param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectPath,

    [int]$SinceHours = 72,

    [int]$MaxFiles = 100,

    [switch]$AllFiles,

    [string]$OutputFile
)

$ErrorActionPreference = "Stop"

$skillFile = [System.IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot "..\SKILL.md")
)
$projectRoot = [System.IO.Path]::GetFullPath($ProjectPath)

if (-not (Test-Path -LiteralPath $skillFile -PathType Leaf)) {
    throw "SKILL.md was not found at: $skillFile"
}

if (-not (Test-Path -LiteralPath $projectRoot -PathType Container)) {
    throw "Project folder was not found at: $projectRoot"
}

if ([string]::IsNullOrWhiteSpace($OutputFile)) {
    $OutputFile = Join-Path $projectRoot "KOTLIN_CODE_REVIEW_REQUEST.md"
} elseif (-not [System.IO.Path]::IsPathRooted($OutputFile)) {
    $OutputFile = Join-Path $projectRoot $OutputFile
}

$outputPath = [System.IO.Path]::GetFullPath($OutputFile)
$ignoredSegments = @(
    "\.git\",
    "\.gradle\",
    "\.idea\",
    "\build\",
    "\target\",
    "\out\",
    "\node_modules\"
)
$allowedNames = @(
    "build.gradle",
    "build.gradle.kts",
    "settings.gradle",
    "settings.gradle.kts",
    "pom.xml",
    "application.yml",
    "application.yaml",
    "application.properties"
)
$allowedExtensions = @(
    ".kt",
    ".kts",
    ".java",
    ".sql",
    ".yml",
    ".yaml",
    ".properties"
)

function Test-IgnoredPath {
    param([string]$Path)

    foreach ($segment in $ignoredSegments) {
        if ($Path.IndexOf($segment, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            return $true
        }
    }

    return $false
}

function Get-RelativeProjectPath {
    param([string]$Path)

    $rootUri = [System.Uri]::new($projectRoot.TrimEnd("\") + "\")
    $pathUri = [System.Uri]::new([System.IO.Path]::GetFullPath($Path))
    return [System.Uri]::UnescapeDataString(
        $rootUri.MakeRelativeUri($pathUri).ToString()
    ).Replace("/", "\")
}

$candidates = Get-ChildItem -LiteralPath $projectRoot -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object {
        -not (Test-IgnoredPath $_.FullName) -and
        ($allowedNames -contains $_.Name -or $allowedExtensions -contains $_.Extension.ToLowerInvariant())
    }

if (-not $AllFiles) {
    $cutoff = (Get-Date).AddHours(-1 * [Math]::Abs($SinceHours))
    $recent = @($candidates | Where-Object { $_.LastWriteTime -ge $cutoff })

    if ($recent.Count -gt 0) {
        $candidates = $recent
    }
}

$selectedFiles = @(
    $candidates |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First ([Math]::Max(1, $MaxFiles))
)

$fileLines = if ($selectedFiles.Count -gt 0) {
    $selectedFiles | ForEach-Object {
        $relativePath = Get-RelativeProjectPath $_.FullName
        "- $relativePath (modified $($_.LastWriteTime.ToString("yyyy-MM-dd HH:mm")))"
    }
} else {
    @("- No Kotlin/Spring source, test, configuration, or migration files were discovered.")
}

$prompt = @"
# Kotlin Code Review Request

Read and follow this skill:

$skillFile

Review this project:

$projectRoot

Use Agent mode. Inspect the files listed below and any directly related controllers, services, tests, configuration, security, repositories, DTOs, and migrations needed to understand their behavior.

Return:

1. `Findings`, ordered by severity, with file and line references.
2. `Open questions or assumptions`, only when uncertainty changes the outcome.
3. `Summary`, briefly and only after findings.

Prioritize behavioral regressions, Spring proxy or transaction issues, API and serialization mistakes, security gaps, concurrency risks, configuration drift, Kotlin null-safety hazards, and missing failure-path tests. Do not lead with formatting or naming feedback.

## Candidate Files

$($fileLines -join "`r`n")
"@

$parent = Split-Path -Parent $outputPath
if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
}

[System.IO.File]::WriteAllText($outputPath, $prompt, [System.Text.UTF8Encoding]::new($false))

$clipboardStatus = "Clipboard unavailable"
try {
    Set-Clipboard -Value $prompt
    $clipboardStatus = "Prompt copied to clipboard"
} catch {
    $clipboardStatus = "Prompt file created; clipboard copy failed"
}

Write-Output "Review request: $outputPath"
Write-Output "Files selected: $($selectedFiles.Count)"
Write-Output $clipboardStatus
