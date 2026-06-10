[CmdletBinding(DefaultParameterSetName = "Json")]
param(
    [Parameter(Mandatory = $true, ParameterSetName = "Json")]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$InputJson,

    [Parameter(Mandatory = $true, ParameterSetName = "Object")]
    [psobject]$InputObject,

    [string]$OutputXlsx = (Join-Path (Get-Location) "response-mapping.xlsx"),

    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$sheetDefinitions = @(
    [pscustomobject]@{
        Key = "scope"
        Name = "Scope"
        Headers = @(
            "Project Or Module", "Packages Scanned", "Generated On",
            "Source Root", "Known Gaps", "Assumptions"
        )
    },
    [pscustomobject]@{
        Key = "endpointSummary"
        Name = "Endpoint Summary"
        Headers = @(
            "HTTP Method", "Path", "Controller Class", "Controller Method",
            "Source File", "Success Status", "Response Type",
            "Collection Or Wrapper", "Error Statuses", "Notes"
        )
    },
    [pscustomobject]@{
        Key = "endToEndFlow"
        Name = "End To End Flow"
        Headers = @(
            "HTTP Method", "Path", "Step Order", "Layer", "Class",
            "Method Or Call", "Input", "Output", "Response Impact",
            "Source File", "Verified", "Notes"
        )
    },
    [pscustomobject]@{
        Key = "detailedMapping"
        Name = "Detailed Mapping"
        Headers = @(
            "HTTP Method", "Path", "Controller Method", "Success Status",
            "Response Type", "Response Body Present", "JSON Field",
            "Source Field", "Java Type", "Required", "Nested Type",
            "Transformation Source", "Repository Or DB Source",
            "Source File", "Notes"
        )
    },
    [pscustomobject]@{
        Key = "dtoFieldCatalog"
        Name = "DTO Field Catalog"
        Headers = @(
            "DTO Name", "JSON Field", "Source Field", "Java Type",
            "Required", "Nullable Evidence", "Enum Values", "Nested Type",
            "Domain Or Entity Source", "Jackson Or Validation Annotations",
            "Source File", "Notes"
        )
    },
    [pscustomobject]@{
        Key = "errorMapping"
        Name = "Error Mapping"
        Headers = @(
            "HTTP Method", "Path", "Status", "Exception Or Failure Source",
            "Handler", "Body Type", "Source File", "Notes"
        )
    },
    [pscustomobject]@{
        Key = "unverifiedItems"
        Name = "Unverified Items"
        Headers = @(
            "Area", "Endpoint Or Type", "Reason", "Source File",
            "Recommended Follow-Up"
        )
    }
)

function Get-FullPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }

    return [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $Path))
}

function ConvertTo-XmlText {
    param([AllowNull()]$Value)

    if ($null -eq $Value) {
        return ""
    }

    if ($Value -is [datetime]) {
        $text = $Value.ToString(
            "yyyy-MM-ddTHH:mm:ssK",
            [System.Globalization.CultureInfo]::InvariantCulture
        )
    }
    elseif ($Value -is [bool]) {
        $text = $Value.ToString().ToLowerInvariant()
    }
    else {
        $text = [string]$Value
    }

    $text = [regex]::Replace($text, "[\x00-\x08\x0B\x0C\x0E-\x1F]", "")
    return [System.Security.SecurityElement]::Escape($text)
}

function Get-ColumnName {
    param([Parameter(Mandatory = $true)][int]$ColumnNumber)

    $name = ""
    $number = $ColumnNumber
    while ($number -gt 0) {
        $number--
        $name = [char](65 + ($number % 26)) + $name
        $number = [math]::Floor($number / 26)
    }

    return $name
}

function Get-PropertyValue {
    param(
        [Parameter(Mandatory = $true)]$Row,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $property = $Row.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return ""
    }

    return $property.Value
}

function Get-SectionRows {
    param(
        [Parameter(Mandatory = $true)]$Document,
        [Parameter(Mandatory = $true)][string]$Key
    )

    $property = $Document.PSObject.Properties[$Key]
    if ($null -eq $property) {
        throw "Mapping data is missing required top-level property '$Key'."
    }

    return @($property.Value | Where-Object { $null -ne $_ })
}

function Get-WorksheetXml {
    param(
        [Parameter(Mandatory = $true)][string[]]$Headers,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Rows
    )

    $columnCount = $Headers.Count
    $rowCount = $Rows.Count + 1
    $lastColumn = Get-ColumnName -ColumnNumber $columnCount
    $dimension = "A1:$lastColumn$rowCount"

    $columnWidths = New-Object int[] $columnCount
    for ($columnIndex = 0; $columnIndex -lt $columnCount; $columnIndex++) {
        $columnWidths[$columnIndex] = $Headers[$columnIndex].Length
    }

    foreach ($row in $Rows) {
        for ($columnIndex = 0; $columnIndex -lt $columnCount; $columnIndex++) {
            $value = Get-PropertyValue -Row $row -Name $Headers[$columnIndex]
            $length = ([string]$value).Length
            if ($length -gt $columnWidths[$columnIndex]) {
                $columnWidths[$columnIndex] = $length
            }
        }
    }

    $builder = [System.Text.StringBuilder]::new()
    [void]$builder.AppendLine('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
    [void]$builder.AppendLine('<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">')
    [void]$builder.AppendLine("  <dimension ref=`"$dimension`"/>")
    [void]$builder.AppendLine('  <sheetViews>')
    [void]$builder.AppendLine('    <sheetView workbookViewId="0">')
    [void]$builder.AppendLine('      <pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/>')
    [void]$builder.AppendLine('      <selection pane="bottomLeft" activeCell="A2" sqref="A2"/>')
    [void]$builder.AppendLine('    </sheetView>')
    [void]$builder.AppendLine('  </sheetViews>')
    [void]$builder.AppendLine('  <sheetFormatPr defaultRowHeight="15"/>')
    [void]$builder.AppendLine('  <cols>')

    for ($columnIndex = 0; $columnIndex -lt $columnCount; $columnIndex++) {
        $width = [math]::Min(60, [math]::Max(12, $columnWidths[$columnIndex] + 2))
        $columnNumber = $columnIndex + 1
        [void]$builder.AppendLine(
            "    <col min=`"$columnNumber`" max=`"$columnNumber`" width=`"$width`" customWidth=`"1`"/>"
        )
    }

    [void]$builder.AppendLine('  </cols>')
    [void]$builder.AppendLine('  <sheetData>')
    [void]$builder.AppendLine('    <row r="1" ht="30" customHeight="1">')

    for ($columnIndex = 0; $columnIndex -lt $columnCount; $columnIndex++) {
        $cellReference = "$(Get-ColumnName -ColumnNumber ($columnIndex + 1))1"
        $headerText = ConvertTo-XmlText -Value $Headers[$columnIndex]
        [void]$builder.AppendLine(
            "      <c r=`"$cellReference`" s=`"1`" t=`"inlineStr`"><is><t xml:space=`"preserve`">$headerText</t></is></c>"
        )
    }

    [void]$builder.AppendLine('    </row>')

    for ($rowIndex = 0; $rowIndex -lt $Rows.Count; $rowIndex++) {
        $excelRow = $rowIndex + 2
        [void]$builder.AppendLine("    <row r=`"$excelRow`">")

        for ($columnIndex = 0; $columnIndex -lt $columnCount; $columnIndex++) {
            $cellReference = "$(Get-ColumnName -ColumnNumber ($columnIndex + 1))$excelRow"
            $rawValue = Get-PropertyValue -Row $Rows[$rowIndex] -Name $Headers[$columnIndex]
            $cellText = ConvertTo-XmlText -Value $rawValue
            [void]$builder.AppendLine(
                "      <c r=`"$cellReference`" s=`"2`" t=`"inlineStr`"><is><t xml:space=`"preserve`">$cellText</t></is></c>"
            )
        }

        [void]$builder.AppendLine('    </row>')
    }

    [void]$builder.AppendLine('  </sheetData>')
    [void]$builder.AppendLine("  <autoFilter ref=`"A1:$lastColumn$rowCount`"/>")
    [void]$builder.AppendLine('  <pageMargins left="0.3" right="0.3" top="0.5" bottom="0.5" header="0.2" footer="0.2"/>')
    [void]$builder.AppendLine('</worksheet>')
    return $builder.ToString()
}

function Write-ZipEntry {
    param(
        [Parameter(Mandatory = $true)]$Archive,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )

    $entry = $Archive.CreateEntry(
        $Path,
        [System.IO.Compression.CompressionLevel]::Optimal
    )
    $stream = $entry.Open()
    try {
        $writer = [System.IO.StreamWriter]::new(
            $stream,
            [System.Text.UTF8Encoding]::new($false)
        )
        try {
            $writer.Write($Content)
        }
        finally {
            $writer.Dispose()
        }
    }
    finally {
        $stream.Dispose()
    }
}

$outputPath = Get-FullPath -Path $OutputXlsx

if ([System.IO.Path]::GetExtension($outputPath) -ne ".xlsx") {
    throw "OutputXlsx must use the .xlsx extension."
}

if ((Test-Path -LiteralPath $outputPath) -and -not $Force) {
    throw "Output file already exists: $outputPath. Use -Force to replace it."
}

$outputDirectory = Split-Path -Parent $outputPath
if (-not (Test-Path -LiteralPath $outputDirectory)) {
    [void](New-Item -ItemType Directory -Path $outputDirectory -Force)
}

if ($PSCmdlet.ParameterSetName -eq "Object") {
    $document = $InputObject
}
else {
    $inputPath = (Resolve-Path -LiteralPath $InputJson).Path
    try {
        $document = Get-Content -LiteralPath $inputPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        throw "Unable to parse input JSON '$inputPath': $($_.Exception.Message)"
    }
}

$sheetRows = @{}
foreach ($definition in $sheetDefinitions) {
    $sheetRows[$definition.Key] = @(Get-SectionRows -Document $document -Key $definition.Key)
}

$contentTypes = [System.Text.StringBuilder]::new()
[void]$contentTypes.AppendLine('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
[void]$contentTypes.AppendLine('<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">')
[void]$contentTypes.AppendLine('  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>')
[void]$contentTypes.AppendLine('  <Default Extension="xml" ContentType="application/xml"/>')
[void]$contentTypes.AppendLine('  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>')
[void]$contentTypes.AppendLine('  <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>')
for ($sheetIndex = 1; $sheetIndex -le $sheetDefinitions.Count; $sheetIndex++) {
    [void]$contentTypes.AppendLine(
        "  <Override PartName=`"/xl/worksheets/sheet$sheetIndex.xml`" ContentType=`"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml`"/>"
    )
}
[void]$contentTypes.AppendLine('</Types>')

$rootRelationships = @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>
'@

$workbook = [System.Text.StringBuilder]::new()
[void]$workbook.AppendLine('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
[void]$workbook.AppendLine('<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">')
[void]$workbook.AppendLine('  <bookViews><workbookView xWindow="0" yWindow="0" windowWidth="28800" windowHeight="16620"/></bookViews>')
[void]$workbook.AppendLine('  <sheets>')
for ($sheetIndex = 0; $sheetIndex -lt $sheetDefinitions.Count; $sheetIndex++) {
    $sheetId = $sheetIndex + 1
    $sheetName = ConvertTo-XmlText -Value $sheetDefinitions[$sheetIndex].Name
    [void]$workbook.AppendLine(
        "    <sheet name=`"$sheetName`" sheetId=`"$sheetId`" r:id=`"rId$sheetId`"/>"
    )
}
[void]$workbook.AppendLine('  </sheets>')
[void]$workbook.AppendLine('</workbook>')

$workbookRelationships = [System.Text.StringBuilder]::new()
[void]$workbookRelationships.AppendLine('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
[void]$workbookRelationships.AppendLine('<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">')
for ($sheetIndex = 1; $sheetIndex -le $sheetDefinitions.Count; $sheetIndex++) {
    [void]$workbookRelationships.AppendLine(
        "  <Relationship Id=`"rId$sheetIndex`" Type=`"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet`" Target=`"worksheets/sheet$sheetIndex.xml`"/>"
    )
}
$styleRelationshipId = $sheetDefinitions.Count + 1
[void]$workbookRelationships.AppendLine(
    "  <Relationship Id=`"rId$styleRelationshipId`" Type=`"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles`" Target=`"styles.xml`"/>"
)
[void]$workbookRelationships.AppendLine('</Relationships>')

$styles = @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <fonts count="2">
    <font><sz val="11"/><color theme="1"/><name val="Calibri"/><family val="2"/></font>
    <font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/><family val="2"/></font>
  </fonts>
  <fills count="3">
    <fill><patternFill patternType="none"/></fill>
    <fill><patternFill patternType="gray125"/></fill>
    <fill><patternFill patternType="solid"><fgColor rgb="FF176B6B"/><bgColor indexed="64"/></patternFill></fill>
  </fills>
  <borders count="2">
    <border><left/><right/><top/><bottom/><diagonal/></border>
    <border>
      <left style="thin"><color rgb="FFD7E0E5"/></left>
      <right style="thin"><color rgb="FFD7E0E5"/></right>
      <top style="thin"><color rgb="FFD7E0E5"/></top>
      <bottom style="thin"><color rgb="FFD7E0E5"/></bottom>
      <diagonal/>
    </border>
  </borders>
  <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
  <cellXfs count="3">
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
    <xf numFmtId="0" fontId="1" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1">
      <alignment horizontal="center" vertical="center" wrapText="1"/>
    </xf>
    <xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1" applyAlignment="1">
      <alignment vertical="top" wrapText="1"/>
    </xf>
  </cellXfs>
  <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
  <tableStyles count="0" defaultTableStyle="TableStyleMedium2" defaultPivotStyle="PivotStyleLight16"/>
</styleSheet>
'@

$temporaryPath = "$outputPath.$([guid]::NewGuid().ToString('N')).tmp"
$fileStream = $null
$archive = $null
try {
    $fileStream = [System.IO.File]::Open(
        $temporaryPath,
        [System.IO.FileMode]::CreateNew,
        [System.IO.FileAccess]::ReadWrite,
        [System.IO.FileShare]::None
    )
    $archive = [System.IO.Compression.ZipArchive]::new(
        $fileStream,
        [System.IO.Compression.ZipArchiveMode]::Create,
        $false
    )

    Write-ZipEntry -Archive $archive -Path "[Content_Types].xml" -Content $contentTypes.ToString()
    Write-ZipEntry -Archive $archive -Path "_rels/.rels" -Content $rootRelationships
    Write-ZipEntry -Archive $archive -Path "xl/workbook.xml" -Content $workbook.ToString()
    Write-ZipEntry -Archive $archive -Path "xl/_rels/workbook.xml.rels" -Content $workbookRelationships.ToString()
    Write-ZipEntry -Archive $archive -Path "xl/styles.xml" -Content $styles

    for ($sheetIndex = 0; $sheetIndex -lt $sheetDefinitions.Count; $sheetIndex++) {
        $definition = $sheetDefinitions[$sheetIndex]
        $worksheetXml = Get-WorksheetXml `
            -Headers $definition.Headers `
            -Rows @($sheetRows[$definition.Key])
        Write-ZipEntry `
            -Archive $archive `
            -Path "xl/worksheets/sheet$($sheetIndex + 1).xml" `
            -Content $worksheetXml
    }
}
finally {
    if ($null -ne $archive) {
        $archive.Dispose()
    }
    if ($null -ne $fileStream) {
        $fileStream.Dispose()
    }
}

if (Test-Path -LiteralPath $outputPath) {
    Remove-Item -LiteralPath $outputPath -Force
}
Move-Item -LiteralPath $temporaryPath -Destination $outputPath

Write-Host "Created response mapping workbook:"
Write-Host "  $outputPath"
foreach ($definition in $sheetDefinitions) {
    Write-Host ("  {0}: {1} data row(s)" -f $definition.Name, $sheetRows[$definition.Key].Count)
}
