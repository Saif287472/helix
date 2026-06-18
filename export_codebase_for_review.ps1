param(
    [string]$OutputFile = "helix_codebase_review.txt",
    [int]$MaxFileSizeKB = 2048,
    [switch]$NoRedaction
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$OutputPath = Join-Path $Root $OutputFile

# Project-authored areas to inspect.
$IncludedTopDirectories = @(
    "lib",
    "packages",
    "docs",
    "test",
    "integration_test",
    "tool",
    "scripts",
    "android",
    "windows",
    "linux",
    "macos",
    "ios",
    "web",
    ".github"
)

# Never descend into generated, cached, dependency, or IDE folders.
$ExcludedDirectoryNames = @(
    ".git",
    ".dart_tool",
    ".idea",
    ".vscode",
    ".claude",
    ".gradle",
    ".kotlin",
    ".cxx",
    "build",
    "coverage",
    "ephemeral",
    ".plugin_symlinks",
    "node_modules",
    "Pods",
    "DerivedData"
)

$AllowedExtensions = @(
    ".dart", ".yaml", ".yml", ".json", ".md", ".txt",
    ".ps1", ".psm1", ".sh", ".bat", ".cmd", ".py",
    ".kt", ".kts", ".java", ".xml", ".gradle", ".properties",
    ".c", ".cc", ".cpp", ".cxx", ".h", ".hpp", ".cmake",
    ".html", ".css", ".scss", ".js", ".ts", ".sql"
)

$SpecialTextFileNames = @(
    ".env.example",
    ".gitignore",
    ".gitattributes",
    "Dockerfile",
    "LICENSE",
    "LICENSE.md",
    "CHANGELOG",
    "CHANGELOG.md"
)

# These files may contain machine-local paths, credentials, or signing material.
$SensitiveFileNames = @(
    ".env",
    "local.properties",
    "key.properties",
    "keystore.properties",
    "google-services.json",
    "GoogleService-Info.plist"
)

$SensitiveExtensions = @(
    ".jks", ".keystore", ".p12", ".pfx", ".pem", ".key"
)

$ExplicitlyExcludedFileNames = @(
    $OutputFile,
    "codebase_structure.txt",
    ".flutter-plugins-dependencies",
    "GeneratedPluginRegistrant.java",
    "generated_plugin_registrant.cc",
    "generated_plugin_registrant.h",
    "generated_plugins.cmake"
)

$GeneratedPatterns = @(
    "*.g.dart",
    "*.freezed.dart",
    "*.mocks.dart"
)

$SelectedFiles = New-Object System.Collections.ArrayList
$SkippedSensitive = New-Object System.Collections.ArrayList
$SkippedLarge = New-Object System.Collections.ArrayList
$SkippedGenerated = New-Object System.Collections.ArrayList

function Get-RelativePath([string]$FullName) {
    return $FullName.Substring($Root.Length).TrimStart([char[]]"\/").Replace("\", "/")
}

function Test-IsGenerated([string]$Name) {
    foreach ($Pattern in $GeneratedPatterns) {
        if ($Name -like $Pattern) {
            return $true
        }
    }
    return $false
}

function Test-IsAllowedTextFile([System.IO.FileInfo]$File) {
    $Name = $File.Name
    $Extension = $File.Extension.ToLowerInvariant()

    if ($SpecialTextFileNames -contains $Name) {
        return $true
    }

    if ($Name -like "README*") {
        return $true
    }

    return $AllowedExtensions -contains $Extension
}

function Add-ProjectFile([System.IO.FileInfo]$File) {
    $RelativePath = Get-RelativePath $File.FullName
    $Name = $File.Name
    $Extension = $File.Extension.ToLowerInvariant()

    if ($File.FullName -eq $OutputPath) {
        return
    }

    if ($ExplicitlyExcludedFileNames -contains $Name) {
        return
    }

    if (($SensitiveFileNames -contains $Name) -or ($SensitiveExtensions -contains $Extension)) {
        [void]$SkippedSensitive.Add($RelativePath)
        return
    }

    if (Test-IsGenerated $Name) {
        [void]$SkippedGenerated.Add($RelativePath)
        return
    }

    if (-not (Test-IsAllowedTextFile $File)) {
        return
    }

    if ($File.Length -gt ($MaxFileSizeKB * 1KB)) {
        [void]$SkippedLarge.Add($RelativePath)
        return
    }

    [void]$SelectedFiles.Add([PSCustomObject]@{
        FullName     = $File.FullName
        RelativePath = $RelativePath
        Length       = $File.Length
    })
}

function Visit-Directory([string]$Directory, [bool]$IsRoot) {
    foreach ($Item in Get-ChildItem -LiteralPath $Directory -Force -ErrorAction SilentlyContinue) {
        if ($Item.PSIsContainer) {
            if (($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                continue
            }

            if ($ExcludedDirectoryNames -contains $Item.Name) {
                continue
            }

            if ($IsRoot -and -not ($IncludedTopDirectories -contains $Item.Name)) {
                continue
            }

            Visit-Directory -Directory $Item.FullName -IsRoot $false
            continue
        }

        Add-ProjectFile $Item
    }
}

function Get-CategoryOrder([string]$RelativePath) {
    $Path = $RelativePath.Replace("\", "/")

    if ($Path -notmatch "/") { return 0 }
    if ($Path -like "docs/*") { return 10 }
    if ($Path -like "lib/*") { return 20 }
    if ($Path -like "packages/*") { return 30 }
    if (($Path -like "test/*") -or ($Path -like "integration_test/*")) { return 40 }
    if (($Path -like "tool/*") -or ($Path -like "scripts/*")) { return 50 }
    if ($Path -like "android/*") { return 60 }
    if ($Path -like "windows/*") { return 70 }
    if (($Path -like "linux/*") -or ($Path -like "macos/*") -or
        ($Path -like "ios/*") -or ($Path -like "web/*")) { return 80 }
    if ($Path -like ".github/*") { return 90 }

    return 99
}

function Get-CategoryLabel([string]$RelativePath) {
    switch (Get-CategoryOrder $RelativePath) {
        0  { return "ROOT CONFIGURATION" }
        10 { return "DOCUMENTATION" }
        20 { return "APPLICATION SOURCE" }
        30 { return "LOCAL PACKAGES" }
        40 { return "TESTS" }
        50 { return "TOOLS AND SCRIPTS" }
        60 { return "ANDROID PLATFORM CODE" }
        70 { return "WINDOWS PLATFORM CODE" }
        80 { return "OTHER PLATFORM CODE" }
        90 { return "CI/CD" }
        default { return "OTHER PROJECT TEXT" }
    }
}

function Get-LanguageLabel([string]$RelativePath) {
    $Extension = [System.IO.Path]::GetExtension($RelativePath).ToLowerInvariant()

    switch ($Extension) {
        ".dart"       { return "Dart" }
        ".yaml"       { return "YAML" }
        ".yml"        { return "YAML" }
        ".json"       { return "JSON" }
        ".md"         { return "Markdown" }
        ".ps1"        { return "PowerShell" }
        ".psm1"       { return "PowerShell" }
        ".sh"         { return "Shell" }
        ".bat"        { return "Batch" }
        ".cmd"        { return "Batch" }
        ".py"         { return "Python" }
        ".kt"         { return "Kotlin" }
        ".kts"        { return "Kotlin Script" }
        ".java"       { return "Java" }
        ".xml"        { return "XML" }
        ".gradle"     { return "Gradle" }
        ".properties" { return "Properties" }
        ".c"          { return "C" }
        ".cc"         { return "C++" }
        ".cpp"        { return "C++" }
        ".cxx"        { return "C++" }
        ".h"          { return "C/C++ Header" }
        ".hpp"        { return "C++ Header" }
        ".cmake"      { return "CMake" }
        ".html"       { return "HTML" }
        ".css"        { return "CSS" }
        ".scss"       { return "SCSS" }
        ".js"         { return "JavaScript" }
        ".ts"         { return "TypeScript" }
        ".sql"        { return "SQL" }
        default       { return "Text" }
    }
}

function Protect-LikelySecrets([string]$Text) {
    if ($NoRedaction) {
        return $Text
    }

    # Avoid redacting Helix's legitimate "secret sentence/code" logic.
    # Only redact common credential-style assignments.
    $Pattern = '(?im)^(\s*(?:(?:const|final|var|late|String)\s+)?(?:api[_-]?key|apiKey|access[_-]?token|accessToken|auth[_-]?token|authToken|client[_-]?secret|clientSecret|password|passwd|private[_-]?key|privateKey)\s*[:=]\s*)(.+?)([;,]?\s*)$'
    return [System.Text.RegularExpressions.Regex]::Replace(
        $Text,
        $Pattern,
        '$1<REDACTED_FOR_REVIEW>$3'
    )
}

# Traverse only project-authored top-level areas.
Visit-Directory -Directory $Root -IsRoot $true

$OrderedFiles = @(
    $SelectedFiles |
    Sort-Object `
        @{ Expression = { Get-CategoryOrder $_.RelativePath } }, `
        @{ Expression = { $_.RelativePath } }
)

# Asset names are useful for UI review, but binary/audio/image contents are not.
$AssetInventory = @()
$AssetsPath = Join-Path $Root "assets"
if (Test-Path -LiteralPath $AssetsPath) {
    $AssetInventory = @(
        Get-ChildItem -LiteralPath $AssetsPath -File -Recurse -Force -ErrorAction SilentlyContinue |
        Sort-Object FullName |
        ForEach-Object {
            [PSCustomObject]@{
                RelativePath = Get-RelativePath $_.FullName
                Length       = $_.Length
            }
        }
    )
}

$TotalBytes = 0
if ($OrderedFiles.Count -gt 0) {
    $MeasuredBytes = ($OrderedFiles | Measure-Object -Property Length -Sum).Sum
    if ($null -ne $MeasuredBytes) {
        $TotalBytes = [int64]$MeasuredBytes
    }
}

$Encoding = New-Object System.Text.UTF8Encoding($false)
$Writer = [System.IO.StreamWriter]::new($OutputPath, $false, $Encoding)

try {
    $Writer.WriteLine("HELIX CODEBASE REVIEW EXPORT")
    $Writer.WriteLine(("Generated: {0:u}" -f (Get-Date)))
    $Writer.WriteLine(("Project root: {0}" -f $Root))
    $Writer.WriteLine(("Included text files: {0}" -f $OrderedFiles.Count))
    $Writer.WriteLine(("Included source size: {0:N0} bytes" -f $TotalBytes))
    $Writer.WriteLine(("Maximum individual file size: {0:N0} KB" -f $MaxFileSizeKB))
    $Writer.WriteLine(("Credential-assignment redaction: {0}" -f $(if ($NoRedaction) { "OFF" } else { "ON" })))
    $Writer.WriteLine("")
    $Writer.WriteLine("Excluded: build output, caches, dependencies, IDE metadata, generated plugin code,")
    $Writer.WriteLine("platform ephemeral folders, binaries, signing material, and machine-local secrets.")
    $Writer.WriteLine("")

    $Writer.WriteLine("################################################################################")
    $Writer.WriteLine("# PROJECT FILE INDEX")
    $Writer.WriteLine("################################################################################")

    $CurrentCategory = ""
    $Index = 1

    foreach ($Entry in $OrderedFiles) {
        $Category = Get-CategoryLabel $Entry.RelativePath

        if ($Category -ne $CurrentCategory) {
            $Writer.WriteLine("")
            $Writer.WriteLine(("## {0}" -f $Category))
            $CurrentCategory = $Category
        }

        $Writer.WriteLine(("{0:D4}. {1} [{2:N0} bytes]" -f $Index, $Entry.RelativePath, $Entry.Length))
        $Index++
    }

    $Writer.WriteLine("")
    $Writer.WriteLine("################################################################################")
    $Writer.WriteLine("# ASSET INVENTORY (NAMES AND SIZES ONLY)")
    $Writer.WriteLine("################################################################################")

    if ($AssetInventory.Count -eq 0) {
        $Writer.WriteLine("(No assets found.)")
    }
    else {
        foreach ($Asset in $AssetInventory) {
            $Writer.WriteLine(("{0} [{1:N0} bytes]" -f $Asset.RelativePath, $Asset.Length))
        }
    }

    $Writer.WriteLine("")
    $Writer.WriteLine("################################################################################")
    $Writer.WriteLine("# SKIPPED FILES")
    $Writer.WriteLine("################################################################################")

    $Writer.WriteLine("")
    $Writer.WriteLine("## Sensitive or machine-local files")
    if ($SkippedSensitive.Count -eq 0) {
        $Writer.WriteLine("(None detected.)")
    }
    else {
        foreach ($Path in ($SkippedSensitive | Sort-Object)) {
            $Writer.WriteLine($Path)
        }
    }

    $Writer.WriteLine("")
    $Writer.WriteLine("## Generated source files")
    if ($SkippedGenerated.Count -eq 0) {
        $Writer.WriteLine("(None detected.)")
    }
    else {
        foreach ($Path in ($SkippedGenerated | Sort-Object)) {
            $Writer.WriteLine($Path)
        }
    }

    $Writer.WriteLine("")
    $Writer.WriteLine("## Files larger than the configured limit")
    if ($SkippedLarge.Count -eq 0) {
        $Writer.WriteLine("(None detected.)")
    }
    else {
        foreach ($Path in ($SkippedLarge | Sort-Object)) {
            $Writer.WriteLine($Path)
        }
    }

    $Writer.WriteLine("")
    $Writer.WriteLine("################################################################################")
    $Writer.WriteLine("# FILE CONTENTS")
    $Writer.WriteLine("################################################################################")

    $Index = 1

    foreach ($Entry in $OrderedFiles) {
        try {
            $RawContent = [System.IO.File]::ReadAllText($Entry.FullName)
            $Content = Protect-LikelySecrets $RawContent
            $LineCount = 0

            if ($Content.Length -gt 0) {
                $LineCount = ($Content -split "`r?`n").Count
            }

            $Hash = (Get-FileHash -LiteralPath $Entry.FullName -Algorithm SHA256).Hash
            $Category = Get-CategoryLabel $Entry.RelativePath
            $Language = Get-LanguageLabel $Entry.RelativePath

            $Writer.WriteLine("")
            $Writer.WriteLine("================================================================================")
            $Writer.WriteLine(("FILE {0:D4} OF {1:D4}" -f $Index, $OrderedFiles.Count))
            $Writer.WriteLine(("PATH: {0}" -f $Entry.RelativePath))
            $Writer.WriteLine(("CATEGORY: {0}" -f $Category))
            $Writer.WriteLine(("LANGUAGE: {0}" -f $Language))
            $Writer.WriteLine(("SIZE: {0:N0} bytes" -f $Entry.Length))
            $Writer.WriteLine(("LINES: {0:N0}" -f $LineCount))
            $Writer.WriteLine(("SHA256: {0}" -f $Hash))
            $Writer.WriteLine("--------------------------------------------------------------------------------")
            $Writer.Write($Content)

            if (-not $Content.EndsWith("`n")) {
                $Writer.WriteLine("")
            }

            $Writer.WriteLine(("--------------------------------------------------------------------------------"))
            $Writer.WriteLine(("END FILE: {0}" -f $Entry.RelativePath))
            $Writer.WriteLine("================================================================================")

            $Index++
        }
        catch {
            $Writer.WriteLine("")
            $Writer.WriteLine("================================================================================")
            $Writer.WriteLine(("FAILED TO READ: {0}" -f $Entry.RelativePath))
            $Writer.WriteLine(("ERROR: {0}" -f $_.Exception.Message))
            $Writer.WriteLine("================================================================================")
        }
    }
}
finally {
    $Writer.Dispose()
}

Write-Host ""
Write-Host "Codebase export created successfully:" -ForegroundColor Green
Write-Host $OutputPath -ForegroundColor Cyan
Write-Host ""
Write-Host ("Included files: {0}" -f $OrderedFiles.Count)
Write-Host ("Output size: {0:N2} MB" -f ((Get-Item -LiteralPath $OutputPath).Length / 1MB))
Write-Host ""
Write-Host "Review the SKIPPED FILES section, then upload the TXT file."
