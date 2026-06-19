param(
    [string]$OutputDirectory = "review_exports",
    [int]$MaxFileSizeKB = 2048,
    [switch]$NoRedaction
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Root = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = (Get-Location).Path
}

$OutputRoot = if ([System.IO.Path]::IsPathRooted($OutputDirectory)) {
    [System.IO.Path]::GetFullPath($OutputDirectory)
}
else {
    [System.IO.Path]::GetFullPath((Join-Path $Root $OutputDirectory))
}

New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null

$ExportDefinitions = [ordered]@{
    architecture = [PSCustomObject]@{
        FileName    = "01_architecture_and_plans.txt"
        Title       = "ARCHITECTURE, PLANS, PRODUCT CONTRACTS, AND ROOT CONFIGURATION"
        Description = "Root configuration, ADRs, architecture documents, product contracts, security documents, and workflows."
    }
    localPackages = [PSCustomObject]@{
        FileName    = "02_local_and_shared_packages.txt"
        Title       = "LOCAL AND SHARED PACKAGES"
        Description = "Helix Local package source plus product-neutral shared package source. Tests are exported separately."
    }
    localApp = [PSCustomObject]@{
        FileName    = "03_local_app.txt"
        Title       = "HELIX LOCAL APPLICATION"
        Description = "Helix Local Flutter app, platform code, configuration, and app-specific source. Tests are exported separately."
    }
    remoteClient = [PSCustomObject]@{
        FileName    = "04_remote_client_and_packages.txt"
        Title       = "HELIX REMOTE CLIENT AND REMOTE PACKAGES"
        Description = "Helix Remote Flutter app and Remote client packages. Tests are exported separately."
    }
    remoteBackend = [PSCustomObject]@{
        FileName    = "05_remote_backend_and_contracts.txt"
        Title       = "REMOTE BACKEND, CONTRACTS, AND INFRASTRUCTURE"
        Description = "Remote backend services, API contracts, compatibility fixtures, deployment definitions, and infrastructure source. Tests are exported separately."
    }
    verification = [PSCustomObject]@{
        FileName    = "06_tests_and_verification.txt"
        Title       = "TESTS, CI, VERIFICATION, AND REPOSITORY TOOLING"
        Description = "All tests regardless of location, CI workflows, verification scripts, architecture checks, release gates, and repository tooling."
    }
}

$IncludedTopDirectories = @(
    "apps",
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
    ".github",
    "services",
    "contracts",
    "infra",
    "assets"
)

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
    "DerivedData",
    ".pub-cache",
    ".pub",
    "dist",
    "out",
    "target",
    "vendor"
)

$AllowedExtensions = @(
    ".dart", ".yaml", ".yml", ".json", ".md", ".txt",
    ".ps1", ".psm1", ".sh", ".bat", ".cmd", ".py",
    ".kt", ".kts", ".java", ".xml", ".gradle", ".properties",
    ".c", ".cc", ".cpp", ".cxx", ".h", ".hpp", ".cmake",
    ".html", ".css", ".scss", ".js", ".mjs", ".cjs", ".ts", ".tsx", ".jsx",
    ".sql", ".toml", ".ini", ".conf", ".config", ".graphql", ".proto"
)

$SpecialTextFileNames = @(
    ".env.example",
    ".gitignore",
    ".gitattributes",
    ".metadata",
    "Dockerfile",
    "Containerfile",
    "Makefile",
    "gradlew",
    "LICENSE",
    "LICENSE.md",
    "CHANGELOG",
    "CHANGELOG.md"
)

$SensitiveFileNames = @(
    ".env",
    "local.properties",
    "key.properties",
    "keystore.properties",
    "google-services.json",
    "GoogleService-Info.plist",
    "credentials.json",
    "secrets.json"
)

$SensitiveExtensions = @(
    ".jks", ".keystore", ".p12", ".pfx", ".pem", ".key",
    ".der", ".p7b", ".p7c", ".mobileprovision"
)

$GeneratedPatterns = @(
    "*.g.dart",
    "*.freezed.dart",
    "*.mocks.dart",
    "*.gr.dart",
    "*.gen.dart",
    "*.generated.dart"
)

$ExplicitlyExcludedFileNames = @(
    ".flutter-plugins-dependencies",
    "pubspec.lock",
    "package-lock.json",
    "yarn.lock",
    "pnpm-lock.yaml",
    "Podfile.lock",
    "gradle.lockfile",
    "GeneratedPluginRegistrant.java",
    "dart_plugin_registrant.dart",
    "generated_plugin_registrant.cc",
    "generated_plugin_registrant.h",
    "generated_plugins.cmake"
)

$SelectedByExport = @{}
$AssetsByExport = @{}
$SkippedSensitiveByExport = @{}
$SkippedGeneratedByExport = @{}
$SkippedLargeByExport = @{}
$SkippedUnreadableByExport = @{}

foreach ($Key in $ExportDefinitions.Keys) {
    $SelectedByExport[$Key] = New-Object System.Collections.ArrayList
    $AssetsByExport[$Key] = New-Object System.Collections.ArrayList
    $SkippedSensitiveByExport[$Key] = New-Object System.Collections.ArrayList
    $SkippedGeneratedByExport[$Key] = New-Object System.Collections.ArrayList
    $SkippedLargeByExport[$Key] = New-Object System.Collections.ArrayList
    $SkippedUnreadableByExport[$Key] = New-Object System.Collections.ArrayList
}

function Get-RelativePath([string]$FullName) {
    $FullPath = [System.IO.Path]::GetFullPath($FullName)
    $RootPath = [System.IO.Path]::GetFullPath($Root).TrimEnd([char[]]"\/")

    if (-not $FullPath.StartsWith($RootPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Path is outside the project root: $FullPath"
    }

    return $FullPath.Substring($RootPath.Length).TrimStart([char[]]"\/").Replace("\", "/")
}

function Test-IsInsideOutputDirectory([string]$FullName) {
    $Candidate = [System.IO.Path]::GetFullPath($FullName).TrimEnd([char[]]"\/")
    $OutputBase = $OutputRoot.TrimEnd([char[]]"\/")

    if ($Candidate.Equals($OutputBase, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }

    $OutputPrefix = $OutputBase + [System.IO.Path]::DirectorySeparatorChar
    return $Candidate.StartsWith($OutputPrefix, [System.StringComparison]::OrdinalIgnoreCase)
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
    if ($SpecialTextFileNames -contains $File.Name) {
        return $true
    }

    if ($File.Name -like "README*") {
        return $true
    }

    return $AllowedExtensions -contains $File.Extension.ToLowerInvariant()
}

function Test-IsAssetPath([string]$RelativePath) {
    $Path = $RelativePath.Replace("\", "/")
    return $Path -match '(^|/)assets(/|$)'
}

function Test-IsTestPath([string]$RelativePath) {
    $Path = $RelativePath.Replace("\", "/")
    $Name = [System.IO.Path]::GetFileName($Path)

    return ($Path -match '(^|/)test(/|$)') -or
           ($Path -match '(^|/)tests(/|$)') -or
           ($Path -match '(^|/)integration_test(/|$)') -or
           ($Name -match '(_test|\.spec|\.test)\.[^.]+$')
}

function Get-ExportKey([string]$RelativePath) {
    $Path = $RelativePath.Replace("\", "/")
    $Extension = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()

    # Tests and verification tooling are routed first so exports do not overlap.
    if (Test-IsTestPath $Path) { return "verification" }
    if ($Path -like ".github/*") { return "verification" }
    if ($Path -like "scripts/*") { return "verification" }
    if ($Path -like "tool/*") { return "verification" }
    if (($Path -notmatch "/") -and ($Extension -in @(".ps1", ".psm1", ".sh", ".bat", ".cmd", ".py"))) {
        return "verification"
    }

    if ($Path -like "apps/helix_local/*") { return "localApp" }
    if ($Path -like "apps/helix_remote/*") { return "remoteClient" }
    if ($Path -like "packages/remote/*") { return "remoteClient" }
    if (($Path -like "packages/local/*") -or ($Path -like "packages/shared/*")) { return "localPackages" }

    # Legacy single-app/package layout fallback.
    if (($Path -like "lib/*") -or ($Path -like "android/*") -or ($Path -like "windows/*") -or
        ($Path -like "linux/*") -or ($Path -like "macos/*") -or ($Path -like "ios/*") -or
        ($Path -like "web/*") -or ($Path -like "assets/*")) {
        return "localApp"
    }
    if (($Path -like "packages/*") -and -not ($Path -like "packages/remote/*")) {
        return "localPackages"
    }

    if (($Path -like "services/*") -or ($Path -like "contracts/*") -or ($Path -like "infra/*")) {
        return "remoteBackend"
    }

    if (($Path -like "docs/*") -or ($Path -notmatch "/")) {
        return "architecture"
    }

    # Unknown project-authored text defaults to architecture so nothing silently disappears.
    return "architecture"
}

function Get-LanguageLabel([string]$RelativePath) {
    $Name = [System.IO.Path]::GetFileName($RelativePath)
    $Extension = [System.IO.Path]::GetExtension($RelativePath).ToLowerInvariant()

    if ($Name -eq "Dockerfile" -or $Name -eq "Containerfile") { return "Container Build File" }
    if ($Name -eq "Makefile") { return "Makefile" }
    if ($Name -eq "gradlew") { return "Shell" }

    switch ($Extension) {
        ".dart"       { return "Dart" }
        ".yaml"       { return "YAML" }
        ".yml"        { return "YAML" }
        ".json"       { return "JSON" }
        ".md"         { return "Markdown" }
        ".txt"        { return "Text" }
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
        ".mjs"        { return "JavaScript Module" }
        ".cjs"        { return "CommonJS" }
        ".ts"         { return "TypeScript" }
        ".tsx"        { return "TypeScript JSX" }
        ".jsx"        { return "JavaScript JSX" }
        ".sql"        { return "SQL" }
        ".toml"       { return "TOML" }
        ".ini"        { return "INI" }
        ".conf"       { return "Configuration" }
        ".config"     { return "Configuration" }
        ".graphql"    { return "GraphQL" }
        ".proto"      { return "Protocol Buffers" }
        default       { return "Text" }
    }
}

function Protect-LikelySecrets([string]$Text) {
    if ($NoRedaction) {
        return $Text
    }

    # Deliberately avoids generic "secret" names because Helix contains legitimate
    # secret-code and secret-sentence product logic. This targets credential-style assignments.
    $AssignmentPattern = '(?im)^(\s*(?:(?:const|final|var|late|String)\s+)?(?:api[_-]?key|apiKey|access[_-]?token|accessToken|auth[_-]?token|authToken|refresh[_-]?token|refreshToken|client[_-]?secret|clientSecret|password|passwd|private[_-]?key|privateKey|database[_-]?url|databaseUrl)\s*[:=]\s*)(.+?)([;,]?\s*)$'
    $Protected = [System.Text.RegularExpressions.Regex]::Replace(
        $Text,
        $AssignmentPattern,
        '$1<REDACTED_FOR_REVIEW>$3'
    )

    $EnvPattern = '(?im)^(\s*(?:API_KEY|ACCESS_TOKEN|AUTH_TOKEN|REFRESH_TOKEN|CLIENT_SECRET|PASSWORD|PASSWD|PRIVATE_KEY|DATABASE_URL)\s*=\s*)(.+?)\s*$'
    return [System.Text.RegularExpressions.Regex]::Replace(
        $Protected,
        $EnvPattern,
        '$1<REDACTED_FOR_REVIEW>'
    )
}

function Add-ProjectFile([System.IO.FileInfo]$File) {
    if (Test-IsInsideOutputDirectory $File.FullName) {
        return
    }

    $RelativePath = Get-RelativePath $File.FullName
    $ExportKey = Get-ExportKey $RelativePath
    $Name = $File.Name
    $Extension = $File.Extension.ToLowerInvariant()

    if ($ExplicitlyExcludedFileNames -contains $Name) {
        return
    }

    if (($SensitiveFileNames -contains $Name) -or ($SensitiveExtensions -contains $Extension)) {
        [void]$SkippedSensitiveByExport[$ExportKey].Add($RelativePath)
        return
    }

    if (Test-IsGenerated $Name) {
        [void]$SkippedGeneratedByExport[$ExportKey].Add($RelativePath)
        return
    }

    # Asset contents are intentionally omitted even when they are text files.
    # Their names, sizes, and hashes remain available in the asset inventory,
    # regardless of the source-file size limit.
    if (Test-IsAssetPath $RelativePath) {
        [void]$AssetsByExport[$ExportKey].Add([PSCustomObject]@{
            FullName     = $File.FullName
            RelativePath = $RelativePath
            Length       = $File.Length
        })
        return
    }

    if ($File.Length -gt ($MaxFileSizeKB * 1KB)) {
        [void]$SkippedLargeByExport[$ExportKey].Add($RelativePath)
        return
    }

    if (-not (Test-IsAllowedTextFile $File)) {
        [void]$AssetsByExport[$ExportKey].Add([PSCustomObject]@{
            FullName     = $File.FullName
            RelativePath = $RelativePath
            Length       = $File.Length
        })
        return
    }

    [void]$SelectedByExport[$ExportKey].Add([PSCustomObject]@{
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

            if (Test-IsInsideOutputDirectory $Item.FullName) {
                continue
            }

            if ($IsRoot -and -not ($IncludedTopDirectories -contains $Item.Name)) {
                continue
            }

            Visit-Directory -Directory $Item.FullName -IsRoot $false
            continue
        }

        try {
            Add-ProjectFile $Item
        }
        catch {
            $RelativePath = try { Get-RelativePath $Item.FullName } catch { $Item.FullName }
            $ExportKey = try { Get-ExportKey $RelativePath } catch { "architecture" }
            [void]$SkippedUnreadableByExport[$ExportKey].Add("$RelativePath :: $($_.Exception.Message)")
        }
    }
}

function Get-GitCommit {
    try {
        $Commit = (& git -C $Root rev-parse HEAD 2>$null | Select-Object -First 1)
        if ([string]::IsNullOrWhiteSpace($Commit)) {
            return "UNKNOWN"
        }
        return $Commit.Trim()
    }
    catch {
        return "UNKNOWN"
    }
}

function Write-StringListSection(
    [System.IO.StreamWriter]$Writer,
    [string]$Heading,
    [System.Collections.IEnumerable]$Items
) {
    $Writer.WriteLine("")
    $Writer.WriteLine("## $Heading")

    $SortedItems = @($Items | Sort-Object -Unique)
    if ($SortedItems.Count -eq 0) {
        $Writer.WriteLine("(None.)")
        return
    }

    foreach ($Item in $SortedItems) {
        $Writer.WriteLine([string]$Item)
    }
}

function Write-Export([string]$ExportKey, [string]$GitCommit) {
    $Definition = $ExportDefinitions[$ExportKey]
    $OutputPath = Join-Path $OutputRoot $Definition.FileName

    $OrderedFiles = @($SelectedByExport[$ExportKey] | Sort-Object RelativePath)
    $OrderedAssets = @($AssetsByExport[$ExportKey] | Sort-Object RelativePath)

    $TotalBytes = 0L
    if ($OrderedFiles.Count -gt 0) {
        $Measured = ($OrderedFiles | Measure-Object -Property Length -Sum).Sum
        if ($null -ne $Measured) {
            $TotalBytes = [int64]$Measured
        }
    }

    $Encoding = New-Object System.Text.UTF8Encoding($false)
    $Writer = [System.IO.StreamWriter]::new($OutputPath, $false, $Encoding)

    try {
        $Writer.WriteLine("HELIX FOCUSED CODEBASE REVIEW EXPORT")
        $Writer.WriteLine("Export: $($Definition.Title)")
        $Writer.WriteLine("Description: $($Definition.Description)")
        $Writer.WriteLine(("Generated UTC: {0}" -f (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd HH:mm:ss'Z'")))
        $Writer.WriteLine("Project root: $Root")
        $Writer.WriteLine("Git commit: $GitCommit")
        $Writer.WriteLine(("Included text files: {0}" -f $OrderedFiles.Count))
        $Writer.WriteLine(("Included source size: {0:N0} bytes" -f $TotalBytes))
        $Writer.WriteLine(("Asset inventory entries: {0}" -f $OrderedAssets.Count))
        $Writer.WriteLine(("Maximum individual file size: {0:N0} KB" -f $MaxFileSizeKB))
        $Writer.WriteLine(("Credential-assignment redaction: {0}" -f $(if ($NoRedaction) { "OFF" } else { "ON" })))
        $Writer.WriteLine("")
        $Writer.WriteLine("Exports are intentionally non-overlapping. All tests are routed to 06_tests_and_verification.txt.")
        $Writer.WriteLine("Asset contents are omitted; names, sizes, and hashes are listed in the asset inventory.")

        $Writer.WriteLine("")
        $Writer.WriteLine("################################################################################")
        $Writer.WriteLine("# PROJECT FILE INDEX")
        $Writer.WriteLine("################################################################################")

        if ($OrderedFiles.Count -eq 0) {
            $Writer.WriteLine("(No text files matched this export.)")
        }
        else {
            $Index = 1
            foreach ($Entry in $OrderedFiles) {
                $Writer.WriteLine(("{0:D4}. {1} [{2:N0} bytes]" -f $Index, $Entry.RelativePath, $Entry.Length))
                $Index++
            }
        }

        $Writer.WriteLine("")
        $Writer.WriteLine("################################################################################")
        $Writer.WriteLine("# ASSET INVENTORY — NAMES, SIZES, AND HASHES ONLY")
        $Writer.WriteLine("################################################################################")

        if ($OrderedAssets.Count -eq 0) {
            $Writer.WriteLine("(No assets or non-text project files found.)")
        }
        else {
            foreach ($Asset in $OrderedAssets) {
                try {
                    $Hash = (Get-FileHash -LiteralPath $Asset.FullName -Algorithm SHA256).Hash
                    $Writer.WriteLine(("{0} [{1:N0} bytes] [SHA256: {2}]" -f $Asset.RelativePath, $Asset.Length, $Hash))
                }
                catch {
                    $Writer.WriteLine(("{0} [{1:N0} bytes] [HASH ERROR: {2}]" -f $Asset.RelativePath, $Asset.Length, $_.Exception.Message))
                }
            }
        }

        $Writer.WriteLine("")
        $Writer.WriteLine("################################################################################")
        $Writer.WriteLine("# SKIPPED FILES")
        $Writer.WriteLine("################################################################################")

        Write-StringListSection $Writer "Sensitive or machine-local files" $SkippedSensitiveByExport[$ExportKey]
        Write-StringListSection $Writer "Generated source files" $SkippedGeneratedByExport[$ExportKey]
        Write-StringListSection $Writer "Files larger than the configured limit" $SkippedLargeByExport[$ExportKey]
        Write-StringListSection $Writer "Unreadable files" $SkippedUnreadableByExport[$ExportKey]

        $Writer.WriteLine("")
        $Writer.WriteLine("################################################################################")
        $Writer.WriteLine("# FILE CONTENTS")
        $Writer.WriteLine("################################################################################")

        $Index = 1
        foreach ($Entry in $OrderedFiles) {
            try {
                $RawContent = [System.IO.File]::ReadAllText($Entry.FullName)
                $Content = Protect-LikelySecrets $RawContent
                $LineCount = if ($Content.Length -eq 0) { 0 } else { ($Content -split "`r?`n").Count }
                $Hash = (Get-FileHash -LiteralPath $Entry.FullName -Algorithm SHA256).Hash
                $Language = Get-LanguageLabel $Entry.RelativePath

                $Writer.WriteLine("")
                $Writer.WriteLine("================================================================================")
                $Writer.WriteLine(("FILE {0:D4} OF {1:D4}" -f $Index, $OrderedFiles.Count))
                $Writer.WriteLine("PATH: $($Entry.RelativePath)")
                $Writer.WriteLine("EXPORT: $($Definition.Title)")
                $Writer.WriteLine("LANGUAGE: $Language")
                $Writer.WriteLine(("SIZE: {0:N0} bytes" -f $Entry.Length))
                $Writer.WriteLine(("LINES: {0:N0}" -f $LineCount))
                $Writer.WriteLine("SHA256: $Hash")
                $Writer.WriteLine("--------------------------------------------------------------------------------")
                $Writer.Write($Content)

                if (-not $Content.EndsWith("`n")) {
                    $Writer.WriteLine("")
                }

                $Writer.WriteLine("--------------------------------------------------------------------------------")
                $Writer.WriteLine("END FILE: $($Entry.RelativePath)")
                $Writer.WriteLine("================================================================================")
                $Index++
            }
            catch {
                $Writer.WriteLine("")
                $Writer.WriteLine("================================================================================")
                $Writer.WriteLine("FAILED TO READ: $($Entry.RelativePath)")
                $Writer.WriteLine("ERROR: $($_.Exception.Message)")
                $Writer.WriteLine("================================================================================")
            }
        }
    }
    finally {
        $Writer.Dispose()
    }

    return [PSCustomObject]@{
        FileName = $Definition.FileName
        Path     = $OutputPath
        Files    = $OrderedFiles.Count
        Assets   = $OrderedAssets.Count
        Bytes    = (Get-Item -LiteralPath $OutputPath).Length
    }
}

Write-Host ""
Write-Host "Scanning Helix project..." -ForegroundColor Cyan
Write-Host "Root: $Root"
Write-Host "Output: $OutputRoot"

Visit-Directory -Directory $Root -IsRoot $true

$GitCommit = Get-GitCommit
$Results = New-Object System.Collections.ArrayList

foreach ($Key in $ExportDefinitions.Keys) {
    [void]$Results.Add((Write-Export -ExportKey $Key -GitCommit $GitCommit))
}

Write-Host ""
Write-Host "Created six focused review exports:" -ForegroundColor Green
foreach ($Result in $Results) {
    Write-Host (("  {0}  |  {1} files  |  {2} assets  |  {3:N2} MB" -f `
        $Result.FileName,
        $Result.Files,
        $Result.Assets,
        ($Result.Bytes / 1MB)))
}

Write-Host ""
Write-Host "Output directory:" -ForegroundColor Cyan
Write-Host $OutputRoot
Write-Host ""
