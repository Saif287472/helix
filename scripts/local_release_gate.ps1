$ErrorActionPreference = "Stop"

param(
    [switch]$BuildArtifacts,
    [switch]$Android,
    [switch]$Windows
)

function Invoke-Step {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Command
    )

    Write-Host ""
    Write-Host "==> $Name"
    & $Command
    if (-not $?) { throw "Step '$Name' failed." }
}

if (-not $Android -and -not $Windows) {
    $Android = $true
    $Windows = $true
}

Invoke-Step "Full verification" {
    .\scripts\verify.ps1
}

Invoke-Step "Generate Local SBOM" {
    dart run tool/generate_local_sbom.dart --output build/release/helix_local_sbom.json
}

Invoke-Step "Generate Local release provenance" {
    dart run tool/generate_release_provenance.dart --product helix_local --output build/release/helix_local_provenance.json
}

Invoke-Step "Dependency health advisory" {
    flutter pub outdated
}

Invoke-Step "Release signing preflight" {
    $missing = @()
    if (-not (Test-Path ".\apps\helix_local\android\helix_local.keystore")) {
        $missing += "helix_local.keystore"
    }
    foreach ($name in @("HELIX_LOCAL_STORE_PASSWORD", "HELIX_LOCAL_KEY_ALIAS", "HELIX_LOCAL_KEY_PASSWORD")) {
        if (-not [Environment]::GetEnvironmentVariable($name)) {
            $missing += $name
        }
    }
    if ($missing.Count -gt 0) {
        throw "Missing Local release signing material: $($missing -join ', ')"
    }
}

if ($BuildArtifacts) {
    if ($Windows) {
        Invoke-Step "Build Helix Local Windows release" {
            Push-Location apps\helix_local
            try {
                flutter build windows --release
            } finally {
                Pop-Location
            }
        }
    }

    if ($Android) {
        Invoke-Step "Build Helix Local Android release APK" {
            Push-Location apps\helix_local
            try {
                flutter build apk --release
            } finally {
                Pop-Location
            }
        }
    }
} else {
    Write-Host ""
    Write-Host "==> Release artifacts"
    Write-Host "Skipped. Pass -BuildArtifacts after signing material is available."
}
