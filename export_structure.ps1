$OutputFile = "codebase_structure.txt"

$excludeDirs = @(
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
    "node_modules",
    "Pods",
    "DerivedData",
    "ephemeral",
    ".plugin_symlinks"
)

$excludeFiles = @(
    $OutputFile,
    "export_structure.ps1",
    ".flutter-plugins-dependencies",
    "local.properties",
    "GeneratedPluginRegistrant.java",
    "dart_plugin_registrant.dart",
    "generated_plugin_registrant.cc",
    "generated_plugin_registrant.h",
    "generated_plugins.cmake"
)

$excludePatterns = @(
    "*.iml",
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
    "*.jar"
)

function Test-ExcludedFile {
    param([System.IO.FileInfo]$File)

    if ($excludeFiles -contains $File.Name) {
        return $true
    }

    foreach ($pattern in $excludePatterns) {
        if ($File.Name -like $pattern) {
            return $true
        }
    }

    return $false
}

function Write-ProjectTree {
    param(
        [string]$Path,
        [string]$Prefix = ""
    )

    $items = @(
        Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue |
        Where-Object {
            if ($_.PSIsContainer) {
                $excludeDirs -notcontains $_.Name
            }
            else {
                -not (Test-ExcludedFile $_)
            }
        } |
        Sort-Object @{ Expression = { -not $_.PSIsContainer } }, Name
    )

    for ($i = 0; $i -lt $items.Count; $i++) {
        $item = $items[$i]
        $isLast = $i -eq ($items.Count - 1)

        $branch = if ($isLast) { "\---" } else { "+---" }
        Add-Content -Path $OutputFile -Value "$Prefix$branch$($item.Name)"

        if ($item.PSIsContainer) {
            $nextPrefix = if ($isLast) {
                "$Prefix    "
            }
            else {
                "$Prefix|   "
            }

            Write-ProjectTree -Path $item.FullName -Prefix $nextPrefix
        }
    }
}

"PROJECT STRUCTURE" | Set-Content -Path $OutputFile -Encoding UTF8
"Root: $(Get-Location)" | Add-Content -Path $OutputFile
"" | Add-Content -Path $OutputFile

Write-ProjectTree -Path (Get-Location).Path

Write-Host "Created: $OutputFile"