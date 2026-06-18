$ErrorActionPreference = "Stop"

function Invoke-Step {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Command
    )

    Write-Host ""
    Write-Host "==> $Name"
    & $Command
}

Invoke-Step "Dart format check" {
    dart format --output=none --set-exit-if-changed apps packages tool
}

Invoke-Step "Flutter analyze" {
    flutter analyze
}

Invoke-Step "Architecture boundary check" {
    dart run tool/check_boundaries.dart
}

Invoke-Step "Secret scan" {
    dart run tool/check_secrets.dart
}

Invoke-Step "Flutter tests (Local)" {
    Push-Location apps/helix_local
    try {
        flutter test
    } finally {
        Pop-Location
    }
}

Invoke-Step "Flutter tests (Remote)" {
    Push-Location apps/helix_remote
    try {
        flutter test
    } finally {
        Pop-Location
    }
}

Invoke-Step "Dependency health advisory" {
    flutter pub outdated
}

if ($env:HELIX_VERIFY_BUILD -eq "1") {
    Invoke-Step "Debug build (Local)" {
        Push-Location apps/helix_local
        try {
            flutter build windows --debug
        } finally {
            Pop-Location
        }
    }
} else {
    Write-Host ""
    Write-Host "==> Debug build"
    Write-Host "Skipped. Set HELIX_VERIFY_BUILD=1 to run flutter build windows --debug."
}

