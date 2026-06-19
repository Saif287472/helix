$ErrorActionPreference = "Stop"

param(
    [switch]$BuildArtifacts,
    [switch]$Android,
    [switch]$Windows,
    [switch]$StagingE2E
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

Invoke-Step "Remote client tests" {
    Push-Location apps\helix_remote
    try {
        flutter test --no-pub
    } finally {
        Pop-Location
    }
}

Invoke-Step "Remote backend tests" {
    Push-Location services\helix_remote_backend
    try {
        dart test
    } finally {
        Pop-Location
    }
}

Invoke-Step "Remote API compatibility tests" {
    Push-Location packages\remote\helix_remote_api
    try {
        dart test
    } finally {
        Pop-Location
    }
}

Invoke-Step "Security gates" {
    dart run tool\check_boundaries.dart
    dart run tool\check_secrets.dart
    dart run tool\check_release_hardening.dart
    dart test tool\phase20_release_governance_test.dart
}

Invoke-Step "Remote release signing preflight" {
    $missing = @()
    if (-not (Test-Path ".\apps\helix_remote\android\helix_remote.keystore")) {
        $missing += "helix_remote.keystore"
    }
    foreach ($name in @("HELIX_REMOTE_STORE_PASSWORD", "HELIX_REMOTE_KEY_ALIAS", "HELIX_REMOTE_KEY_PASSWORD")) {
        if (-not [Environment]::GetEnvironmentVariable($name)) {
            $missing += $name
        }
    }
    if ($missing.Count -gt 0) {
        throw "Missing Remote release signing material: $($missing -join ', ')"
    }
}

if ($StagingE2E) {
    Invoke-Step "Remote staging E2E preflight" {
        $missing = @()
        foreach ($name in @("HELIX_REMOTE_STAGING_BASE_URL", "HELIX_REMOTE_STAGING_ACCOUNT", "HELIX_REMOTE_STAGING_DEVICE")) {
            if (-not [Environment]::GetEnvironmentVariable($name)) {
                $missing += $name
            }
        }
        if ($missing.Count -gt 0) {
            throw "Missing Remote staging E2E configuration: $($missing -join ', ')"
        }
        Write-Host "Staging configuration present. Run the environment-specific E2E suite from docs/release/REMOTE_RELEASE_CHECKLIST.md."
    }
} else {
    Write-Host ""
    Write-Host "==> Remote staging E2E"
    Write-Host "Skipped. Pass -StagingE2E only after real staging infrastructure and credentials exist."
}

if ($BuildArtifacts) {
    if ($Windows) {
        Invoke-Step "Build Helix Remote Windows release" {
            Push-Location apps\helix_remote
            try {
                flutter build windows --release
            } finally {
                Pop-Location
            }
        }
    }

    if ($Android) {
        Invoke-Step "Build Helix Remote Android release APK" {
            Push-Location apps\helix_remote
            try {
                flutter build apk --release
            } finally {
                Pop-Location
            }
        }
    }
} else {
    Write-Host ""
    Write-Host "==> Remote release artifacts"
    Write-Host "Skipped. Pass -BuildArtifacts after signing material is available."
}
