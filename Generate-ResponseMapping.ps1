[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
    [string]$ProjectPath,

    [string]$OutputPath,

    [ValidateRange(1, 8)]
    [int]$TraceDepth = 4,

    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-NormalizedPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    return [System.IO.Path]::GetFullPath($Path).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
}

function Get-RelativeSourcePath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $normalizedRoot = (Get-NormalizedPath -Path $Root) + [System.IO.Path]::DirectorySeparatorChar
    $normalizedPath = [System.IO.Path]::GetFullPath($Path)
    if ($normalizedPath.StartsWith($normalizedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $normalizedPath.Substring($normalizedRoot.Length).Replace("\", "/")
    }

    return $normalizedPath.Replace("\", "/")
}

function Get-ProjectName {
    param([Parameter(Mandatory = $true)][string]$Root)

    $pomPath = Join-Path $Root "pom.xml"
    if (Test-Path -LiteralPath $pomPath) {
        try {
            [xml]$pom = Get-Content -LiteralPath $pomPath -Raw
            if ($pom.project.artifactId) {
                return [string]$pom.project.artifactId
            }
        }
        catch {
            Write-Verbose "Unable to read artifactId from pom.xml: $($_.Exception.Message)"
        }
    }

    return Split-Path -Leaf $Root
}

function Get-JavaPackage {
    param([Parameter(Mandatory = $true)][string]$Content)

    $match = [regex]::Match($Content, "(?m)^\s*package\s+(?<package>[\w.]+)\s*;")
    if ($match.Success) {
        return $match.Groups["package"].Value
    }

    return ""
}

function Get-JavaTypeName {
    param(
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter(Mandatory = $true)][string]$Fallback
    )

    $match = [regex]::Match(
        $Content,
        "(?m)\b(?:class|interface|record|enum)\s+(?<name>[A-Za-z_]\w*)"
    )
    if ($match.Success) {
        return $match.Groups["name"].Value
    }

    return $Fallback
}

function Get-BalancedBlock {
    param(
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter(Mandatory = $true)][int]$OpenBraceIndex
    )

    $depth = 0
    $inString = $false
    $inCharacter = $false
    $escaped = $false

    for ($index = $OpenBraceIndex; $index -lt $Content.Length; $index++) {
        $character = $Content[$index]

        if ($escaped) {
            $escaped = $false
            continue
        }
        if (($inString -or $inCharacter) -and $character -eq "\") {
            $escaped = $true
            continue
        }
        if (-not $inCharacter -and $character -eq '"') {
            $inString = -not $inString
            continue
        }
        if (-not $inString -and $character -eq "'") {
            $inCharacter = -not $inCharacter
            continue
        }
        if ($inString -or $inCharacter) {
            continue
        }

        if ($character -eq "{") {
            $depth++
        }
        elseif ($character -eq "}") {
            $depth--
            if ($depth -eq 0) {
                return $Content.Substring($OpenBraceIndex + 1, $index - $OpenBraceIndex - 1)
            }
        }
    }

    return ""
}

function Split-JavaParameters {
    param([AllowEmptyString()][string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return @()
    }

    $parts = New-Object System.Collections.Generic.List[string]
    $start = 0
    $genericDepth = 0
    $parenthesisDepth = 0

    for ($index = 0; $index -lt $Text.Length; $index++) {
        switch ($Text[$index]) {
            "<" { $genericDepth++ }
            ">" { if ($genericDepth -gt 0) { $genericDepth-- } }
            "(" { $parenthesisDepth++ }
            ")" { if ($parenthesisDepth -gt 0) { $parenthesisDepth-- } }
            "," {
                if ($genericDepth -eq 0 -and $parenthesisDepth -eq 0) {
                    $parts.Add($Text.Substring($start, $index - $start).Trim())
                    $start = $index + 1
                }
            }
        }
    }

    $parts.Add($Text.Substring($start).Trim())
    return @($parts.ToArray() | Where-Object { $_ })
}

function Get-QuotedValues {
    param([AllowEmptyString()][string]$Text)

    $values = New-Object System.Collections.Generic.List[string]
    foreach ($match in [regex]::Matches($Text, '"(?<value>(?:\\.|[^"])*)"')) {
        $value = $match.Groups["value"].Value
        if ($value -notmatch "^(application|text|multipart)/") {
            $values.Add($value)
        }
    }
    return $values.ToArray()
}

function Get-MappingPaths {
    param([AllowEmptyString()][string]$Arguments)

    if ([string]::IsNullOrWhiteSpace($Arguments)) {
        return @("")
    }

    $pathAssignment = [regex]::Match(
        $Arguments,
        "(?s)(?:value|path)\s*=\s*(?<value>\{.*?\}|`"[^`"]*`")"
    )
    if ($pathAssignment.Success) {
        $paths = @(Get-QuotedValues -Text $pathAssignment.Groups["value"].Value)
        if ($paths.Count -gt 0) {
            return $paths
        }
    }

    if ($Arguments.TrimStart().StartsWith('"') -or $Arguments.TrimStart().StartsWith("{")) {
        $paths = @(Get-QuotedValues -Text $Arguments)
        if ($paths.Count -gt 0) {
            return $paths
        }
    }

    return @("")
}

function Join-RoutePath {
    param(
        [AllowEmptyString()][string]$BasePath,
        [AllowEmptyString()][string]$MethodPath
    )

    $parts = @($BasePath, $MethodPath) |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        ForEach-Object { $_.Trim("/") }

    if ($parts.Count -eq 0) {
        return "/"
    }

    return "/" + ($parts -join "/")
}

function Get-HttpMethod {
    param(
        [Parameter(Mandatory = $true)][string]$MappingName,
        [AllowEmptyString()][string]$Arguments
    )

    switch ($MappingName) {
        "GetMapping" { return "GET" }
        "PostMapping" { return "POST" }
        "PutMapping" { return "PUT" }
        "PatchMapping" { return "PATCH" }
        "DeleteMapping" { return "DELETE" }
        default {
            $method = [regex]::Match(
                $Arguments,
                "RequestMethod\.(?<method>GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS)"
            )
            if ($method.Success) {
                return $method.Groups["method"].Value
            }
            return "REQUEST"
        }
    }
}

function Get-StatusName {
    param([AllowEmptyString()][string]$Token)

    $statuses = @{
        "OK" = "200 OK"
        "CREATED" = "201 Created"
        "ACCEPTED" = "202 Accepted"
        "NO_CONTENT" = "204 No Content"
        "BAD_REQUEST" = "400 Bad Request"
        "UNAUTHORIZED" = "401 Unauthorized"
        "FORBIDDEN" = "403 Forbidden"
        "NOT_FOUND" = "404 Not Found"
        "CONFLICT" = "409 Conflict"
        "UNPROCESSABLE_ENTITY" = "422 Unprocessable Entity"
        "INTERNAL_SERVER_ERROR" = "500 Internal Server Error"
        "BAD_GATEWAY" = "502 Bad Gateway"
        "SERVICE_UNAVAILABLE" = "503 Service Unavailable"
    }

    if ($statuses.ContainsKey($Token)) {
        return $statuses[$Token]
    }
    if ($Token) {
        return $Token.Replace("_", " ")
    }
    return ""
}

function Get-SuccessStatus {
    param(
        [AllowEmptyString()][string]$Annotations,
        [AllowEmptyString()][string]$Body,
        [Parameter(Mandatory = $true)][string]$HttpMethod
    )

    $responseStatus = [regex]::Match(
        $Annotations,
        "@ResponseStatus\s*\(\s*(?:value\s*=\s*)?(?:HttpStatus\.)?(?<status>[A-Z_]+)"
    )
    if ($responseStatus.Success) {
        return Get-StatusName -Token $responseStatus.Groups["status"].Value
    }

    $explicitStatus = [regex]::Match(
        $Body,
        "ResponseEntity\s*\.\s*status\s*\(\s*(?:HttpStatus\.)?(?<status>[A-Z_]+)"
    )
    if ($explicitStatus.Success) {
        return Get-StatusName -Token $explicitStatus.Groups["status"].Value
    }
    if ($Body -match "ResponseEntity\s*\.\s*created\s*\(") {
        return "201 Created"
    }
    if ($Body -match "ResponseEntity\s*\.\s*noContent\s*\(") {
        return "204 No Content"
    }
    if ($HttpMethod -eq "POST") {
        return "200 OK"
    }
    return "200 OK"
}

function Get-ResponseTypeInfo {
    param([Parameter(Mandatory = $true)][string]$ReturnType)

    $cleanType = ($ReturnType -replace "\s+", " ").Trim()
    $bodyPresent = "Yes"
    $wrapper = ""
    $dtoType = $cleanType

    if ($cleanType -match "^(?:void|Void)$") {
        return [pscustomobject]@{
            Display = $cleanType
            Dto = ""
            Wrapper = ""
            BodyPresent = "No"
        }
    }

    if ($cleanType -match "^ResponseEntity\s*<\s*(?<inner>.+)\s*>$") {
        $wrapper = $cleanType
        $dtoType = $Matches["inner"].Trim()
        if ($dtoType -match "^(?:void|Void)$") {
            $bodyPresent = "No"
            $dtoType = ""
        }
    }

    $collectionMatch = [regex]::Match(
        $dtoType,
        "^(?<wrapper>List|Set|Collection|Page|Slice|Optional|Mono|Flux)\s*<\s*(?<inner>.+)\s*>$"
    )
    if ($collectionMatch.Success) {
        if (-not $wrapper) {
            $wrapper = $dtoType
        }
        $dtoType = $collectionMatch.Groups["inner"].Value.Trim()
    }

    $dtoType = ($dtoType -replace ".*\.", "").Trim()
    return [pscustomobject]@{
        Display = $cleanType
        Dto = $dtoType
        Wrapper = $wrapper
        BodyPresent = $bodyPresent
    }
}

function Get-ClassRequestPath {
    param([Parameter(Mandatory = $true)]$JavaType)

    $classMatch = [regex]::Match(
        $JavaType.Content,
        "(?m)\b(?:class|interface|record|enum)\s+$([regex]::Escape($JavaType.Name))\b"
    )
    if (-not $classMatch.Success) {
        return ""
    }

    $prefixStart = [math]::Max(0, $classMatch.Index - 2000)
    $prefix = $JavaType.Content.Substring($prefixStart, $classMatch.Index - $prefixStart)
    $mappings = [regex]::Matches(
        $prefix,
        "@RequestMapping\s*(?:\((?<args>.*?)\))?",
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )
    if ($mappings.Count -eq 0) {
        return ""
    }

    $paths = @(Get-MappingPaths -Arguments $mappings[$mappings.Count - 1].Groups["args"].Value)
    return $paths[0]
}

function Get-ControllerEndpoints {
    param([Parameter(Mandatory = $true)]$JavaType)

    $basePath = Get-ClassRequestPath -JavaType $JavaType
    $pattern = "(?ms)(?<annotations>(?:^\s*@[^\r\n]+(?:\r?\n|$))+)\s*(?:public|protected|private)\s+(?:static\s+)?(?<return>[\w.$<>, ?\[\]]+?)\s+(?<method>[A-Za-z_]\w*)\s*\((?<params>.*?)\)\s*(?:throws\s+[^{]+)?\{"
    $endpoints = New-Object System.Collections.Generic.List[object]

    foreach ($match in [regex]::Matches($JavaType.Content, $pattern)) {
        $annotations = $match.Groups["annotations"].Value
        $mapping = [regex]::Match(
            $annotations,
            "@(?<name>GetMapping|PostMapping|PutMapping|PatchMapping|DeleteMapping|RequestMapping)\s*(?:\((?<args>.*?)\))?",
            [System.Text.RegularExpressions.RegexOptions]::Singleline
        )
        if (-not $mapping.Success) {
            continue
        }

        $openBraceIndex = $match.Index + $match.Value.LastIndexOf("{")
        $body = Get-BalancedBlock -Content $JavaType.Content -OpenBraceIndex $openBraceIndex
        $httpMethod = Get-HttpMethod `
            -MappingName $mapping.Groups["name"].Value `
            -Arguments $mapping.Groups["args"].Value

        foreach ($methodPath in @(Get-MappingPaths -Arguments $mapping.Groups["args"].Value)) {
            $endpoints.Add([pscustomobject]@{
                HttpMethod = $httpMethod
                Path = Join-RoutePath -BasePath $basePath -MethodPath $methodPath
                Method = $match.Groups["method"].Value
                ReturnType = $match.Groups["return"].Value.Trim()
                Parameters = ($match.Groups["params"].Value -replace "\s+", " ").Trim()
                Annotations = $annotations
                Body = $body
            })
        }
    }

    return $endpoints.ToArray()
}

function Get-JavaFields {
    param([Parameter(Mandatory = $true)]$JavaType)

    $fields = @{}
    $pattern = "(?ms)(?<annotations>(?:^\s*@[^\r\n]+\r?\n)*)^\s*(?:public|protected|private)\s+(?:static\s+)?(?:final\s+)?(?<type>[\w.$<>, ?\[\]]+?)\s+(?<name>[A-Za-z_]\w*)\s*(?:=[^;]*)?;"
    foreach ($match in [regex]::Matches($JavaType.Content, $pattern)) {
        $name = $match.Groups["name"].Value
        if ($name -in @("serialVersionUID", "log", "logger")) {
            continue
        }
        $fields[$name] = [pscustomobject]@{
            Name = $name
            Type = $match.Groups["type"].Value.Trim()
            Annotations = $match.Groups["annotations"].Value
        }
    }
    return $fields
}

function Find-JavaMethod {
    param(
        [Parameter(Mandatory = $true)]$JavaType,
        [Parameter(Mandatory = $true)][string]$MethodName
    )

    $pattern = "(?ms)(?<annotations>(?:^\s*@[^\r\n]+(?:\r?\n|$))*)^\s*(?:public|protected|private)?\s*(?:static\s+)?(?:final\s+)?(?<return>[\w.$<>, ?\[\]]+?)\s+$([regex]::Escape($MethodName))\s*\((?<params>.*?)\)\s*(?:throws\s+[^{]+)?\{"
    $match = [regex]::Match($JavaType.Content, $pattern)
    if (-not $match.Success) {
        $declarationPattern = "(?ms)(?<annotations>(?:^\s*@[^\r\n]+(?:\r?\n|$))*)^\s*(?:public|protected|private)?\s*(?:static\s+)?(?:final\s+)?(?<return>[\w.$<>, ?\[\]]+?)\s+$([regex]::Escape($MethodName))\s*\((?<params>.*?)\)\s*(?:throws\s+[^;]+)?;"
        $declaration = [regex]::Match($JavaType.Content, $declarationPattern)
        if (-not $declaration.Success) {
            return $null
        }

        return [pscustomobject]@{
            Name = $MethodName
            ReturnType = $declaration.Groups["return"].Value.Trim()
            Parameters = ($declaration.Groups["params"].Value -replace "\s+", " ").Trim()
            Annotations = $declaration.Groups["annotations"].Value
            Body = ""
        }
    }

    $openBraceIndex = $match.Index + $match.Value.LastIndexOf("{")
    return [pscustomobject]@{
        Name = $MethodName
        ReturnType = $match.Groups["return"].Value.Trim()
        Parameters = ($match.Groups["params"].Value -replace "\s+", " ").Trim()
        Annotations = $match.Groups["annotations"].Value
        Body = Get-BalancedBlock -Content $JavaType.Content -OpenBraceIndex $openBraceIndex
    }
}

function Get-SimpleTypeName {
    param([AllowEmptyString()][string]$TypeName)

    if (-not $TypeName) {
        return ""
    }
    $withoutGeneric = ($TypeName -replace "<.*", "").Trim()
    return ($withoutGeneric -replace ".*\.", "")
}

function Get-LayerName {
    param([Parameter(Mandatory = $true)][string]$TypeName)

    if ($TypeName -match "(?i)(Repository|Dao)$") { return "Repository" }
    if ($TypeName -match "(?i)(Mapper|Assembler|Converter)$") { return "Mapper" }
    if ($TypeName -match "(?i)(Client|Gateway|Connector|Adapter)$") { return "External Call" }
    if ($TypeName -match "(?i)Service$") { return "Service" }
    return "Component"
}

function Get-ResponseImpact {
    param([Parameter(Mandatory = $true)][string]$Layer)

    switch ($Layer) {
        "Service" { return "Applies business logic that may affect response data or errors" }
        "Mapper" { return "Transforms internal values into the external response shape" }
        "Repository" { return "Reads or writes persistence data used by the response" }
        "External Call" { return "Uses downstream service data or errors in the response flow" }
        default { return "Participates in the endpoint response flow" }
    }
}

function Get-MethodCalls {
    param(
        [Parameter(Mandatory = $true)][string]$Body,
        [Parameter(Mandatory = $true)][hashtable]$Fields
    )

    $calls = New-Object System.Collections.Generic.List[object]
    $seen = @{}
    foreach ($match in [regex]::Matches(
        $Body,
        "(?<![\w.])(?:this\.)?(?<receiver>[A-Za-z_]\w*)\s*\.\s*(?<method>[A-Za-z_]\w*)\s*\("
    )) {
        $receiver = $match.Groups["receiver"].Value
        if (-not $Fields.ContainsKey($receiver)) {
            continue
        }

        $method = $match.Groups["method"].Value
        $key = "$receiver.$method"
        if ($seen.ContainsKey($key)) {
            continue
        }
        $seen[$key] = $true
        $calls.Add([pscustomobject]@{
            Receiver = $receiver
            Method = $method
            Type = Get-SimpleTypeName -TypeName $Fields[$receiver].Type
        })
    }
    return $calls.ToArray()
}

function Add-FlowCalls {
    param(
        [Parameter(Mandatory = $true)][string]$HttpMethod,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$CurrentType,
        [Parameter(Mandatory = $true)][string]$CurrentMethod,
        [Parameter(Mandatory = $true)][string]$Body,
        [Parameter(Mandatory = $true)][hashtable]$TypeIndex,
        [Parameter(Mandatory = $true)][System.Collections.Generic.List[object]]$Rows,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.HashSet[string]]$Visited,
        [Parameter(Mandatory = $true)][ref]$StepOrder,
        [Parameter(Mandatory = $true)][int]$Depth,
        [Parameter(Mandatory = $true)][int]$MaximumDepth
    )

    if ($Depth -gt $MaximumDepth) {
        return
    }

    $currentJavaType = $TypeIndex[$CurrentType]
    if ($null -eq $currentJavaType) {
        return
    }
    $fields = Get-JavaFields -JavaType $currentJavaType

    foreach ($call in @(Get-MethodCalls -Body $Body -Fields $fields)) {
        $visitKey = "$CurrentType.$CurrentMethod->$($call.Type).$($call.Method)"
        if (-not $Visited.Add($visitKey)) {
            continue
        }

        $targetType = $TypeIndex[$call.Type]
        $targetMethod = $null
        $verified = "No"
        $sourceFile = ""
        $inputText = ""
        $outputText = ""
        $notes = "Implementation source was not resolved; call inferred from field type"

        if ($null -ne $targetType) {
            $sourceFile = $targetType.RelativePath
            $targetMethod = Find-JavaMethod -JavaType $targetType -MethodName $call.Method
            if ($null -ne $targetMethod) {
                $verified = "Yes"
                $inputText = $targetMethod.Parameters
                $outputText = $targetMethod.ReturnType
                $notes = ""
            }
            else {
                $notes = "Class resolved, but method implementation was not found"
            }
        }

        $layer = Get-LayerName -TypeName $call.Type
        $StepOrder.Value++
        $Rows.Add([pscustomobject][ordered]@{
            "HTTP Method" = $HttpMethod
            "Path" = $Path
            "Step Order" = [string]$StepOrder.Value
            "Layer" = $layer
            "Class" = $call.Type
            "Method Or Call" = $call.Method
            "Input" = $inputText
            "Output" = $outputText
            "Response Impact" = Get-ResponseImpact -Layer $layer
            "Source File" = $sourceFile
            "Verified" = $verified
            "Notes" = $notes
        })

        if ($null -ne $targetMethod -and -not [string]::IsNullOrWhiteSpace($targetMethod.Body)) {
            Add-FlowCalls `
                -HttpMethod $HttpMethod `
                -Path $Path `
                -CurrentType $call.Type `
                -CurrentMethod $call.Method `
                -Body $targetMethod.Body `
                -TypeIndex $TypeIndex `
                -Rows $Rows `
                -Visited $Visited `
                -StepOrder $StepOrder `
                -Depth ($Depth + 1) `
                -MaximumDepth $MaximumDepth
        }
    }
}

function Get-DtoFields {
    param(
        [Parameter(Mandatory = $true)]$JavaType,
        [Parameter(Mandatory = $true)][hashtable]$TypeIndex
    )

    $fields = New-Object System.Collections.Generic.List[object]
    $recordMatch = [regex]::Match(
        $JavaType.Content,
        "(?s)\brecord\s+$([regex]::Escape($JavaType.Name))\s*\((?<components>.*?)\)\s*(?:implements[^{]+)?\{"
    )

    if ($recordMatch.Success) {
        foreach ($component in @(Split-JavaParameters -Text $recordMatch.Groups["components"].Value)) {
            $clean = ($component -replace "@\w+(?:\([^)]*\))?\s*", "").Trim()
            $match = [regex]::Match($clean, "(?<type>[\w.$<>, ?\[\]]+)\s+(?<name>[A-Za-z_]\w*)$")
            if ($match.Success) {
                $fields.Add([pscustomobject]@{
                    Name = $match.Groups["name"].Value
                    JsonName = $match.Groups["name"].Value
                    Type = $match.Groups["type"].Value.Trim()
                    Annotations = ($component -replace [regex]::Escape($clean), "").Trim()
                })
            }
        }
    }
    else {
        foreach ($field in (Get-JavaFields -JavaType $JavaType).Values) {
            $jsonName = $field.Name
            $jsonProperty = [regex]::Match(
                $field.Annotations,
                "@JsonProperty\s*\(\s*`"(?<name>[^`"]+)`""
            )
            if ($jsonProperty.Success) {
                $jsonName = $jsonProperty.Groups["name"].Value
            }
            if ($field.Annotations -match "@JsonIgnore\b") {
                continue
            }

            $fields.Add([pscustomobject]@{
                Name = $field.Name
                JsonName = $jsonName
                Type = $field.Type
                Annotations = ($field.Annotations -replace "\s+", " ").Trim()
            })
        }
    }

    foreach ($field in $fields) {
        $simpleType = Get-SimpleTypeName -TypeName $field.Type
        $required = if (
            $field.Type -match "^(boolean|byte|short|int|long|float|double|char)$" -or
            $field.Annotations -match "@(?:NotNull|NonNull|NotBlank|NotEmpty)\b"
        ) { "Yes" } else { "Unverified" }

        $nullableEvidence = if ($field.Annotations -match "@Nullable\b") {
            "@Nullable"
        }
        elseif ($field.Annotations -match "@(?:NotNull|NonNull|NotBlank|NotEmpty)\b") {
            ([regex]::Match(
                $field.Annotations,
                "@(?:NotNull|NonNull|NotBlank|NotEmpty)"
            )).Value
        }
        elseif ($field.Type -match "^(boolean|byte|short|int|long|float|double|char)$") {
            "Java primitive"
        }
        else {
            "Unverified"
        }

        $nestedType = ""
        $scalarTypes = @(
            "String", "Boolean", "Byte", "Short", "Integer", "Long", "Float",
            "Double", "Character", "BigDecimal", "BigInteger", "UUID",
            "LocalDate", "LocalDateTime", "OffsetDateTime", "Instant", "Date"
        )
        if ($TypeIndex.ContainsKey($simpleType) -and $simpleType -notin $scalarTypes) {
            $nestedType = $simpleType
        }

        $enumValues = ""
        if ($TypeIndex.ContainsKey($simpleType)) {
            $nestedJavaType = $TypeIndex[$simpleType]
            if ($nestedJavaType.Content -match "\benum\s+$([regex]::Escape($simpleType))\b") {
                $enumBody = [regex]::Match(
                    $nestedJavaType.Content,
                    "(?s)\benum\s+$([regex]::Escape($simpleType))[^{]*\{(?<values>.*?)(?:;|\})"
                )
                if ($enumBody.Success) {
                    $values = [regex]::Matches(
                        $enumBody.Groups["values"].Value,
                        "(?m)(?:^|,)\s*(?<name>[A-Z][A-Z0-9_]*)"
                    ) | ForEach-Object { $_.Groups["name"].Value }
                    $enumValues = ($values -join ", ")
                }
            }
        }

        [pscustomobject]@{
            Name = $field.Name
            JsonName = $field.JsonName
            Type = $field.Type
            Required = $required
            NullableEvidence = $nullableEvidence
            EnumValues = $enumValues
            NestedType = $nestedType
            Annotations = $field.Annotations
        }
    }
}

function Get-ExceptionHandlers {
    param([Parameter(Mandatory = $true)][object[]]$JavaTypes)

    $handlers = @{}
    foreach ($javaType in $JavaTypes) {
        if ($javaType.Content -notmatch "@(?:RestControllerAdvice|ControllerAdvice|ExceptionHandler)\b") {
            continue
        }

        $pattern = "(?ms)(?<annotations>(?:^\s*@[^\r\n]+(?:\r?\n|$))+)\s*(?:public|protected|private)\s+(?<return>[\w.$<>, ?\[\]]+?)\s+(?<method>[A-Za-z_]\w*)\s*\((?<params>.*?)\)\s*(?:throws\s+[^{]+)?\{"
        foreach ($match in [regex]::Matches($javaType.Content, $pattern)) {
            $annotations = $match.Groups["annotations"].Value
            $exceptionHandler = [regex]::Match(
                $annotations,
                "@ExceptionHandler\s*\((?<exceptions>.*?)\)",
                [System.Text.RegularExpressions.RegexOptions]::Singleline
            )
            if (-not $exceptionHandler.Success) {
                continue
            }

            $openBraceIndex = $match.Index + $match.Value.LastIndexOf("{")
            $body = Get-BalancedBlock -Content $javaType.Content -OpenBraceIndex $openBraceIndex
            $status = Get-SuccessStatus `
                -Annotations $annotations `
                -Body $body `
                -HttpMethod "REQUEST"
            if ($status -eq "200 OK") {
                $status = "Unverified"
            }

            $exceptionNames = [regex]::Matches(
                $exceptionHandler.Groups["exceptions"].Value,
                "(?<name>[A-Za-z_]\w*)\s*\.class"
            ) | ForEach-Object { $_.Groups["name"].Value }

            foreach ($exceptionName in $exceptionNames) {
                $handlers[$exceptionName] = [pscustomobject]@{
                    Status = $status
                    Handler = "$($javaType.Name).$($match.Groups["method"].Value)"
                    BodyType = $match.Groups["return"].Value.Trim()
                    SourceFile = $javaType.RelativePath
                }
            }
        }
    }
    return $handlers
}

function Get-ThrownExceptions {
    param([AllowEmptyString()][string[]]$Bodies)

    $exceptions = New-Object System.Collections.Generic.HashSet[string]
    foreach ($body in $Bodies) {
        foreach ($match in [regex]::Matches(
            $body,
            "(?:throw\s+)?new\s+(?<name>[A-Za-z_]\w*(?:Exception|Error))\s*\("
        )) {
            [void]$exceptions.Add($match.Groups["name"].Value)
        }
    }
    return @($exceptions | ForEach-Object { $_ })
}

$projectRoot = Get-NormalizedPath -Path (Resolve-Path -LiteralPath $ProjectPath).Path
if (-not $OutputPath) {
    $OutputPath = Join-Path $projectRoot "response-mapping.xlsx"
}
elseif (-not [System.IO.Path]::IsPathRooted($OutputPath)) {
    $OutputPath = Join-Path $projectRoot $OutputPath
}
$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)

$javaFiles = @(
    Get-ChildItem -LiteralPath $projectRoot -Recurse -File -Filter "*.java" |
        Where-Object {
            $_.FullName -notmatch "[\\/](target|build|out|generated|\.git)[\\/]"
        }
)
if ($javaFiles.Count -eq 0) {
    throw "No Java source files were found under '$projectRoot'."
}

$javaTypes = New-Object System.Collections.Generic.List[object]
$typeIndex = @{}
foreach ($file in $javaFiles) {
    $content = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
    $typeName = Get-JavaTypeName -Content $content -Fallback $file.BaseName
    $javaType = [pscustomobject]@{
        Name = $typeName
        Package = Get-JavaPackage -Content $content
        FullPath = $file.FullName
        RelativePath = Get-RelativeSourcePath -Root $projectRoot -Path $file.FullName
        Content = $content
    }
    $javaTypes.Add($javaType)
    if (-not $typeIndex.ContainsKey($typeName)) {
        $typeIndex[$typeName] = $javaType
    }
}

$controllers = @(
    $javaTypes | Where-Object {
        $_.Content -match "@(?:RestController|Controller)\b"
    }
)
if ($controllers.Count -eq 0) {
    throw "No Spring controller classes were found under '$projectRoot'."
}

$handlerIndex = Get-ExceptionHandlers -JavaTypes $javaTypes.ToArray()
$endpointSummary = New-Object System.Collections.Generic.List[object]
$endToEndFlow = New-Object System.Collections.Generic.List[object]
$detailedMapping = New-Object System.Collections.Generic.List[object]
$dtoFieldCatalog = New-Object System.Collections.Generic.List[object]
$errorMapping = New-Object System.Collections.Generic.List[object]
$unverifiedItems = New-Object System.Collections.Generic.List[object]
$cataloguedDtos = @{}

foreach ($controller in $controllers) {
    foreach ($endpoint in @(Get-ControllerEndpoints -JavaType $controller)) {
        $responseInfo = Get-ResponseTypeInfo -ReturnType $endpoint.ReturnType
        $successStatus = Get-SuccessStatus `
            -Annotations $endpoint.Annotations `
            -Body $endpoint.Body `
            -HttpMethod $endpoint.HttpMethod

        $step = 1
        $endToEndFlow.Add([pscustomobject][ordered]@{
            "HTTP Method" = $endpoint.HttpMethod
            "Path" = $endpoint.Path
            "Step Order" = "1"
            "Layer" = "Controller"
            "Class" = $controller.Name
            "Method Or Call" = $endpoint.Method
            "Input" = $endpoint.Parameters
            "Output" = $endpoint.ReturnType
            "Response Impact" = "Defines the route, request contract, and top-level response"
            "Source File" = $controller.RelativePath
            "Verified" = "Yes"
            "Notes" = ""
        })

        $visited = [System.Collections.Generic.HashSet[string]]::new()
        Add-FlowCalls `
            -HttpMethod $endpoint.HttpMethod `
            -Path $endpoint.Path `
            -CurrentType $controller.Name `
            -CurrentMethod $endpoint.Method `
            -Body $endpoint.Body `
            -TypeIndex $typeIndex `
            -Rows $endToEndFlow `
            -Visited $visited `
            -StepOrder ([ref]$step) `
            -Depth 1 `
            -MaximumDepth $TraceDepth

        $endpointFlow = @(
            $endToEndFlow | Where-Object {
                $_."HTTP Method" -eq $endpoint.HttpMethod -and
                $_.Path -eq $endpoint.Path
            }
        )
        $repositorySources = @(
            $endpointFlow |
                Where-Object { $_.Layer -eq "Repository" } |
                ForEach-Object { "$($_.Class).$($_."Method Or Call")" } |
                Select-Object -Unique
        )
        $mapperSources = @(
            $endpointFlow |
                Where-Object { $_.Layer -eq "Mapper" } |
                ForEach-Object { "$($_.Class).$($_."Method Or Call")" } |
                Select-Object -Unique
        )
        $unresolvedCalls = @($endpointFlow | Where-Object { $_.Verified -eq "No" })

        $allBodies = New-Object System.Collections.Generic.List[string]
        $allBodies.Add($endpoint.Body)
        foreach ($flowRow in $endpointFlow | Where-Object { $_.Layer -ne "Controller" }) {
            if ($typeIndex.ContainsKey($flowRow.Class)) {
                $resolvedMethod = Find-JavaMethod `
                    -JavaType $typeIndex[$flowRow.Class] `
                    -MethodName $flowRow."Method Or Call"
                if ($null -ne $resolvedMethod) {
                    $allBodies.Add($resolvedMethod.Body)
                }
            }
        }

        $endpointErrors = New-Object System.Collections.Generic.List[string]
        foreach ($exceptionName in @(Get-ThrownExceptions -Bodies $allBodies.ToArray())) {
            if ($handlerIndex.ContainsKey($exceptionName)) {
                $handler = $handlerIndex[$exceptionName]
                $endpointErrors.Add($handler.Status)
                $errorMapping.Add([pscustomobject][ordered]@{
                    "HTTP Method" = $endpoint.HttpMethod
                    "Path" = $endpoint.Path
                    "Status" = $handler.Status
                    "Exception Or Failure Source" = $exceptionName
                    "Handler" = $handler.Handler
                    "Body Type" = $handler.BodyType
                    "Source File" = $handler.SourceFile
                    "Notes" = "Exception and handler resolved from source"
                })
            }
            else {
                $endpointErrors.Add("Unverified")
                $unverifiedItems.Add([pscustomobject][ordered]@{
                    "Area" = "Error Mapping"
                    "Endpoint Or Type" = "$($endpoint.HttpMethod) $($endpoint.Path)"
                    "Reason" = "No @ExceptionHandler was resolved for $exceptionName"
                    "Source File" = $controller.RelativePath
                    "Recommended Follow-Up" = "Review controller advice and exception inheritance"
                })
            }
        }

        foreach ($unresolved in $unresolvedCalls) {
            $unverifiedItems.Add([pscustomobject][ordered]@{
                "Area" = "Flow Resolution"
                "Endpoint Or Type" = "$($endpoint.HttpMethod) $($endpoint.Path)"
                "Reason" = "$($unresolved.Class).$($unresolved."Method Or Call") could not be resolved to source"
                "Source File" = $controller.RelativePath
                "Recommended Follow-Up" = "Check interface implementations, generated source, or external dependencies"
            })
        }

        $endpointSummary.Add([pscustomobject][ordered]@{
            "HTTP Method" = $endpoint.HttpMethod
            "Path" = $endpoint.Path
            "Controller Class" = $controller.Name
            "Controller Method" = $endpoint.Method
            "Source File" = $controller.RelativePath
            "Success Status" = $successStatus
            "Response Type" = $responseInfo.Display
            "Collection Or Wrapper" = $responseInfo.Wrapper
            "Error Statuses" = (@($endpointErrors.ToArray() | Select-Object -Unique) -join ", ")
            "Notes" = if ($unresolvedCalls.Count -gt 0) {
                "$($unresolvedCalls.Count) flow call(s) require verification"
            } else { "" }
        })

        if ($responseInfo.BodyPresent -eq "No") {
            $detailedMapping.Add([pscustomobject][ordered]@{
                "HTTP Method" = $endpoint.HttpMethod
                "Path" = $endpoint.Path
                "Controller Method" = "$($controller.Name).$($endpoint.Method)"
                "Success Status" = $successStatus
                "Response Type" = $responseInfo.Display
                "Response Body Present" = "No"
                "JSON Field" = ""
                "Source Field" = ""
                "Java Type" = ""
                "Required" = ""
                "Nested Type" = ""
                "Transformation Source" = ($mapperSources -join ", ")
                "Repository Or DB Source" = ($repositorySources -join ", ")
                "Source File" = $controller.RelativePath
                "Notes" = ""
            })
            continue
        }

        if (-not $responseInfo.Dto -or -not $typeIndex.ContainsKey($responseInfo.Dto)) {
            $detailedMapping.Add([pscustomobject][ordered]@{
                "HTTP Method" = $endpoint.HttpMethod
                "Path" = $endpoint.Path
                "Controller Method" = "$($controller.Name).$($endpoint.Method)"
                "Success Status" = $successStatus
                "Response Type" = $responseInfo.Display
                "Response Body Present" = "Yes"
                "JSON Field" = "Unverified"
                "Source Field" = ""
                "Java Type" = $responseInfo.Dto
                "Required" = "Unverified"
                "Nested Type" = ""
                "Transformation Source" = ($mapperSources -join ", ")
                "Repository Or DB Source" = ($repositorySources -join ", ")
                "Source File" = $controller.RelativePath
                "Notes" = "Response DTO source was not resolved"
            })
            $unverifiedItems.Add([pscustomobject][ordered]@{
                "Area" = "Response DTO"
                "Endpoint Or Type" = "$($endpoint.HttpMethod) $($endpoint.Path)"
                "Reason" = "Source for response type '$($responseInfo.Dto)' was not found"
                "Source File" = $controller.RelativePath
                "Recommended Follow-Up" = "Check dependency modules, generated types, and generic wrappers"
            })
            continue
        }

        $dtoJavaType = $typeIndex[$responseInfo.Dto]
        $dtoFields = @(Get-DtoFields -JavaType $dtoJavaType -TypeIndex $typeIndex)
        if ($dtoFields.Count -eq 0) {
            $unverifiedItems.Add([pscustomobject][ordered]@{
                "Area" = "DTO Fields"
                "Endpoint Or Type" = $responseInfo.Dto
                "Reason" = "No serializable fields or record components were detected"
                "Source File" = $dtoJavaType.RelativePath
                "Recommended Follow-Up" = "Review inherited properties, getters, and custom serializers"
            })
        }

        foreach ($field in $dtoFields) {
            $detailedMapping.Add([pscustomobject][ordered]@{
                "HTTP Method" = $endpoint.HttpMethod
                "Path" = $endpoint.Path
                "Controller Method" = "$($controller.Name).$($endpoint.Method)"
                "Success Status" = $successStatus
                "Response Type" = $responseInfo.Display
                "Response Body Present" = "Yes"
                "JSON Field" = $field.JsonName
                "Source Field" = $field.Name
                "Java Type" = $field.Type
                "Required" = $field.Required
                "Nested Type" = $field.NestedType
                "Transformation Source" = ($mapperSources -join ", ")
                "Repository Or DB Source" = ($repositorySources -join ", ")
                "Source File" = $dtoJavaType.RelativePath
                "Notes" = if ($field.Required -eq "Unverified") { "Nullability is unverified" } else { "" }
            })

            if (-not $cataloguedDtos.ContainsKey("$($responseInfo.Dto).$($field.Name)")) {
                $cataloguedDtos["$($responseInfo.Dto).$($field.Name)"] = $true
                $dtoFieldCatalog.Add([pscustomobject][ordered]@{
                    "DTO Name" = $responseInfo.Dto
                    "JSON Field" = $field.JsonName
                    "Source Field" = $field.Name
                    "Java Type" = $field.Type
                    "Required" = $field.Required
                    "Nullable Evidence" = $field.NullableEvidence
                    "Enum Values" = $field.EnumValues
                    "Nested Type" = $field.NestedType
                    "Domain Or Entity Source" = if ($repositorySources.Count -gt 0) {
                        "Trace through $($repositorySources -join ', ')"
                    } else { "Unverified" }
                    "Jackson Or Validation Annotations" = $field.Annotations
                    "Source File" = $dtoJavaType.RelativePath
                    "Notes" = ""
                })
            }
        }
    }
}

$packages = @(
    $javaTypes |
        ForEach-Object { $_.Package } |
        Where-Object { $_ } |
        Sort-Object -Unique
)
$knownGaps = @(
    $unverifiedItems |
        ForEach-Object { $_.Area } |
        Sort-Object -Unique
) -join ", "

$mappingData = [pscustomobject]@{
    scope = @(
        [pscustomobject][ordered]@{
            "Project Or Module" = Get-ProjectName -Root $projectRoot
            "Packages Scanned" = ($packages -join ", ")
            "Generated On" = (Get-Date).ToString("yyyy-MM-dd")
            "Source Root" = $projectRoot.Replace("\", "/")
            "Known Gaps" = $knownGaps
            "Assumptions" = "PowerShell static analysis; runtime wiring, reflection, and generated code may require verification"
        }
    )
    endpointSummary = $endpointSummary.ToArray()
    endToEndFlow = $endToEndFlow.ToArray()
    detailedMapping = $detailedMapping.ToArray()
    dtoFieldCatalog = $dtoFieldCatalog.ToArray()
    errorMapping = $errorMapping.ToArray()
    unverifiedItems = $unverifiedItems.ToArray()
}

$writerPath = Join-Path $PSScriptRoot "New-ResponseMappingWorkbook.ps1"
if (-not (Test-Path -LiteralPath $writerPath -PathType Leaf)) {
    throw "Workbook writer was not found: $writerPath"
}

& $writerPath -InputObject $mappingData -OutputXlsx $OutputPath -Force:$Force

Write-Host ""
Write-Host "Static analysis summary:"
Write-Host "  Java files: $($javaFiles.Count)"
Write-Host "  Controllers: $($controllers.Count)"
Write-Host "  Endpoints: $($endpointSummary.Count)"
Write-Host "  Unverified items: $($unverifiedItems.Count)"
