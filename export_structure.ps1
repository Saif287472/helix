[CmdletBinding()]
param(
    [Parameter()]
    [string]$OutputFile = "codebase_structure.txt"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Always treat the folder containing this script as the repository root.
# This makes the result independent of the caller's current directory.
$Root = [System.IO.Path]::GetFullPath($PSScriptRoot)

if ([string]::IsNullOrWhiteSpace($Root)) {
    throw "Unable to determine the project root from PSScriptRoot."
}

if ([System.IO.Path]::IsPathRooted($OutputFile)) {
    $OutputPath = [System.IO.Path]::GetFullPath($OutputFile)
}
else {
    $OutputPath = [System.IO.Path]::GetFullPath((Join-Path $Root $OutputFile))
}

$OutputDirectory = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) {
    [void](New-Item -ItemType Directory -Path $OutputDirectory -Force)
}

$CurrentScriptPath = [System.IO.Path]::GetFullPath($PSCommandPath)

# Exclude only generated, dependency, cache, IDE, export, and sensitive folders.
# New project folders are included automatically unless their exact name appears here.
$ExcludedDirectoryNames = @(
    ".git",
    ".dart_tool",
    ".idea",
    ".vscode",
    ".claude",
    ".gradle",
    ".kotlin",
    ".cxx",
    ".pub-cache",
    ".plugin_symlinks",
    ".swiftpm",
    "build",
    "coverage",
    "node_modules",
    "Pods",
    "DerivedData",
    "ephemeral",
    "migrate_working_dir",
    "codebase_review",
    "review_exports",
    "secrets",
    "private"
)

$ExcludedFileNames = @(
    ".flutter-plugins-dependencies",
    "local.properties",
    "key.properties",
    "GeneratedPluginRegistrant.java",
    "dart_plugin_registrant.dart",
    "generated_plugin_registrant.cc",
    "generated_plugin_registrant.h",
    "generated_plugins.cmake",
    "google-services.json",
    "GoogleService-Info.plist",
    "firebase_options.dart"
)

$ExcludedFilePatterns = @(
    "*.iml",
    "*.ipr",
    "*.iws",
    "*.log",
    "*.tmp",
    "*.bak",
    "*.cache",
    "*.dill",
    "*.stamp",
    "*.class",
    "*.dex",
    "*.apk",
    "*.aab",
    "*.dll",
    "*.so",
    "*.exe",
    "*.pdb",
    "*.jar",
    "*.keystore",
    "*.jks",
    "*.p12",
    "*.pfx",
    "*.pem",
    "*.key",
    "*.crt",
    "*.cer",
    "*.csr",
    "service-account*.json",
    "*.db",
    "*.sqlite",
    "*.sqlite3",
    "diagnostics-*.json",
    "audit-export-*.json",
    "app.*.symbols",
    "app.*.map.json"
)

$Stats = [ordered]@{
    IncludedDirectories       = 0
    IncludedFiles             = 0
    ExcludedDirectories       = 0
    ExcludedFiles             = 0
    SkippedSensitiveFiles     = 0
    SkippedReparsePoints      = 0
    UnreadableDirectories     = 0
}

$Warnings = New-Object -TypeName 'System.Collections.Generic.List[string]'
$VisitedDirectories = New-Object -TypeName 'System.Collections.Generic.HashSet[string]' -ArgumentList ([System.StringComparer]::OrdinalIgnoreCase)
$IncludedRelativePaths = New-Object -TypeName 'System.Collections.Generic.HashSet[string]' -ArgumentList ([System.StringComparer]::OrdinalIgnoreCase)

$ExpectedTopLevelDirectories = @(
    "services",
    "contracts",
    "infra",
    "deploy",
    "migrations"
)

function Test-IsReparsePoint {
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileSystemInfo]$Item
    )

    return (($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
}

function Test-IsInsideOutputDirectory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FullName
    )

    $Candidate = [System.IO.Path]::GetFullPath($FullName).TrimEnd([char[]]"\/")
    $OutputBase = $OutputDirectory.TrimEnd([char[]]"\/")

    if ($Candidate.Equals($OutputBase, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }

    $OutputPrefix = $OutputBase + [System.IO.Path]::DirectorySeparatorChar
    return $Candidate.StartsWith($OutputPrefix, [System.StringComparison]::OrdinalIgnoreCase)
}

function Test-IsUnderExcludedDirectory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FullName
    )

    $RelativePath = [System.IO.Path]::GetFullPath($FullName).Substring($Root.Length).TrimStart([char[]]"\/")
    $Parts = $RelativePath -split '[\\/]'
    foreach ($Part in $Parts) {
        if ($ExcludedDirectoryNames -contains $Part) {
            return $true
        }
    }
    return $false
}

function Test-IsSensitiveFileName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if ($Name -ieq ".env.example") {
        return $false
    }

    if ($Name -ieq ".env" -or $Name -like ".env.*") {
        return $true
    }

    if ($Name -ieq "google-services.json" -or
        $Name -ieq "GoogleService-Info.plist" -or
        $Name -ieq "firebase_options.dart" -or
        $Name -like "service-account*.json") {
        return $true
    }

    foreach ($Pattern in @(
        "*.keystore", "*.jks", "*.p12", "*.pfx", "*.pem", "*.key",
        "*.crt", "*.cer", "*.csr", "*.db", "*.sqlite", "*.sqlite3"
    )) {
        if ($Name -like $Pattern) {
            return $true
        }
    }

    return $false
}

function Test-ExcludedFile {
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo]$File
    )

    $FullPath = [System.IO.Path]::GetFullPath($File.FullName)

    if ($FullPath -ieq $OutputPath -or $FullPath -ieq $CurrentScriptPath) {
        $Stats.ExcludedFiles++
        return $true
    }

    if (Test-IsSensitiveFileName -Name $File.Name) {
        $Stats.SkippedSensitiveFiles++
        return $true
    }

    if ($ExcludedFileNames -contains $File.Name) {
        $Stats.ExcludedFiles++
        return $true
    }

    foreach ($Pattern in $ExcludedFilePatterns) {
        if ($File.Name -like $Pattern) {
            $Stats.ExcludedFiles++
            return $true
        }
    }

    return $false
}

function Test-ExcludedDirectory {
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.DirectoryInfo]$Directory
    )

    if (Test-IsReparsePoint -Item $Directory) {
        $Stats.SkippedReparsePoints++
        return $true
    }

    if ($ExcludedDirectoryNames -contains $Directory.Name) {
        $Stats.ExcludedDirectories++
        return $true
    }

    return $false
}

function Get-GitCommit {
    try {
        $Commit = (& git -C $Root rev-parse HEAD 2>$null | Select-Object -First 1)
        if (-not [string]::IsNullOrWhiteSpace($Commit)) {
            return $Commit.Trim()
        }
    }
    catch {
        # Git metadata is optional for this inventory.
    }

    return "Unavailable"
}

function Get-VisibleChildren {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    try {
        $Children = @(Get-ChildItem -LiteralPath $Path -Force -ErrorAction Stop)
    }
    catch {
        $Stats.UnreadableDirectories++
        $Warnings.Add("Unreadable directory: $Path | $($_.Exception.Message)")
        return @()
    }

    $Visible = foreach ($Child in $Children) {
        if ($Child.PSIsContainer) {
            if (-not (Test-ExcludedDirectory -Directory $Child)) {
                $Child
            }
        }
        else {
            if (-not (Test-ExcludedFile -File $Child)) {
                $Child
            }
        }
    }

    return @(
        $Visible |
        Sort-Object @{ Expression = { -not $_.PSIsContainer } }, @{ Expression = { $_.Name }; Ascending = $true }
    )
}

function Write-ProjectTree {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [System.IO.StreamWriter]$Writer,

        [string]$Prefix = ""
    )

    $CanonicalPath = [System.IO.Path]::GetFullPath($Path)
    if (-not $VisitedDirectories.Add($CanonicalPath)) {
        $Warnings.Add("Duplicate directory traversal prevented: $CanonicalPath")
        return
    }

    $Items = @(Get-VisibleChildren -Path $CanonicalPath)

    for ($Index = 0; $Index -lt $Items.Count; $Index++) {
        $Item = $Items[$Index]
        $IsLast = ($Index -eq ($Items.Count - 1))
        $Branch = if ($IsLast) { "\---" } else { "+---" }

        $Writer.WriteLine("$Prefix$Branch$($Item.Name)")

        if ($Item.PSIsContainer) {
            $Stats.IncludedDirectories++
            [void]$IncludedRelativePaths.Add($Item.FullName.Substring($Root.Length).TrimStart([char[]]"\/").Replace("\", "/"))
            $NextPrefix = if ($IsLast) { "$Prefix    " } else { "$Prefix|   " }
            Write-ProjectTree -Path $Item.FullName -Writer $Writer -Prefix $NextPrefix
        }
        else {
            $Stats.IncludedFiles++
            [void]$IncludedRelativePaths.Add($Item.FullName.Substring($Root.Length).TrimStart([char[]]"\/").Replace("\", "/"))
        }
    }
}

function Assert-ExpectedExportCoverage {
    $Missing = New-Object -TypeName 'System.Collections.Generic.List[string]'

    foreach ($DirectoryName in $ExpectedTopLevelDirectories) {
        $DirectoryPath = Join-Path $Root $DirectoryName
        if ((Test-Path -LiteralPath $DirectoryPath -PathType Container) -and
            (-not $IncludedRelativePaths.Contains($DirectoryName))) {
            $Missing.Add("$DirectoryName/")
        }
    }

    $Dockerfiles = @(
        Get-ChildItem -LiteralPath $Root -Recurse -Force -File -Filter "Dockerfile*" |
        Where-Object {
            -not (Test-IsInsideOutputDirectory -FullName $_.FullName) -and
            -not (Test-IsUnderExcludedDirectory -FullName $_.FullName) -and
            -not (Test-IsSensitiveFileName -Name $_.Name)
        }
    )

    foreach ($Dockerfile in $Dockerfiles) {
        $RelativePath = $Dockerfile.FullName.Substring($Root.Length).TrimStart([char[]]"\/").Replace("\", "/")
        if (-not $IncludedRelativePaths.Contains($RelativePath)) {
            $Missing.Add($RelativePath)
        }
    }

    if ($Missing.Count -gt 0) {
        throw "Export self-check failed. Expected project areas were absent from $OutputPath`: $($Missing -join ', ')"
    }
}

$GeneratedUtc = [DateTime]::UtcNow.ToString("yyyy-MM-dd HH:mm:ss'Z'")
$GitCommit = Get-GitCommit
$Utf8WithBom = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $true
$Writer = New-Object -TypeName System.IO.StreamWriter -ArgumentList $OutputPath, $false, $Utf8WithBom

try {
    $Writer.WriteLine("PROJECT STRUCTURE")
    $Writer.WriteLine("Generated UTC: $GeneratedUtc")
    $Writer.WriteLine("Root: $Root")
    $Writer.WriteLine("Git commit: $GitCommit")
    $Writer.WriteLine("")

    Write-ProjectTree -Path $Root -Writer $Writer
    Assert-ExpectedExportCoverage

    $Writer.WriteLine("")
    $Writer.WriteLine("SUMMARY")
    $Writer.WriteLine("Included directories: $($Stats.IncludedDirectories)")
    $Writer.WriteLine("Included files: $($Stats.IncludedFiles)")
    $Writer.WriteLine("Excluded directories: $($Stats.ExcludedDirectories)")
    $Writer.WriteLine("Excluded files: $($Stats.ExcludedFiles)")
    $Writer.WriteLine("Skipped sensitive files: $($Stats.SkippedSensitiveFiles)")
    $Writer.WriteLine("Skipped reparse points: $($Stats.SkippedReparsePoints)")
    $Writer.WriteLine("Unreadable directories: $($Stats.UnreadableDirectories)")

    if ($Warnings.Count -gt 0) {
        $Writer.WriteLine("")
        $Writer.WriteLine("WARNINGS")
        foreach ($Warning in $Warnings) {
            $Writer.WriteLine("- $Warning")
        }
    }
}
finally {
    $Writer.Dispose()
}

Write-Host ""
Write-Host "Project tree created successfully:" -ForegroundColor Green
Write-Host $OutputPath -ForegroundColor Cyan
Write-Host ""
Write-Host "Included directories: $($Stats.IncludedDirectories)"
Write-Host "Included files: $($Stats.IncludedFiles)"
Write-Host "Skipped sensitive files: $($Stats.SkippedSensitiveFiles)"
Write-Host "Skipped reparse points: $($Stats.SkippedReparsePoints)"
Write-Host ""
