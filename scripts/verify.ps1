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
    dart format --output=none --set-exit-if-changed lib test tool packages
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

Invoke-Step "Flutter tests" {
    flutter test
}

Invoke-Step "Dependency health advisory" {
    flutter pub outdated
}

if ($env:HELIX_VERIFY_BUILD -eq "1") {
    Invoke-Step "Debug build" {
        flutter build windows --debug
    }
} else {
    Write-Host ""
    Write-Host "==> Debug build"
    Write-Host "Skipped. Set HELIX_VERIFY_BUILD=1 to run flutter build windows --debug."
}
