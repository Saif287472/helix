$ErrorActionPreference = "Stop"

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

Invoke-Step "Dart format check" {
    dart format --output=none --set-exit-if-changed apps packages tool
}

Invoke-Step "Flutter analyze" {
    flutter analyze
}

Invoke-Step "Architecture boundary check" {
    dart run tool/check_boundaries.dart
}

Invoke-Step "Forbidden import tests + cycle detection (P4-010/P4-015)" {
    dart test tool/boundary_test.dart
}

Invoke-Step "Dependency graph (P4-014)" {
    dart run tool/dep_graph.dart
}

Invoke-Step "Secret scan" {
    dart run tool/check_secrets.dart
}

Invoke-Step "Flutter tests (helix_local)" {
    Push-Location apps/helix_local
    try {
        flutter test
    } finally {
        Pop-Location
    }
}

Invoke-Step "Flutter tests (helix_remote)" {
    Push-Location apps/helix_remote
    try {
        flutter test
    } finally {
        Pop-Location
    }
}

# Run tests for each package under packages/local/, packages/shared/, packages/remote/
foreach ($scope in @("local", "shared", "remote")) {
    $scopeDir = Join-Path "packages" $scope
    if (-not (Test-Path $scopeDir)) { continue }
    foreach ($pkg in (Get-ChildItem $scopeDir -Directory)) {
        $testDir = Join-Path $pkg.FullName "test"
        if (Test-Path $testDir) {
            Invoke-Step "Tests: packages/$scope/$($pkg.Name)" {
                Push-Location $pkg.FullName
                try {
                    $pubspec = Get-Content (Join-Path $pkg.FullName "pubspec.yaml") -Raw
                    if ($pubspec -match 'sdk: flutter') {
                        flutter test
                    } else {
                        dart test
                    }
                } finally {
                    Pop-Location
                }
            }
        }
    }
}

Invoke-Step "Dependency health advisory" {
    flutter pub outdated
}

if ($env:HELIX_VERIFY_BUILD -eq "1") {
    Invoke-Step "Debug build: helix_local (Windows)" {
        Push-Location apps/helix_local
        try {
            flutter build windows --debug
        } finally {
            Pop-Location
        }
    }

    Invoke-Step "Debug build: helix_local (Android APK)" {
        Push-Location apps/helix_local
        try {
            flutter build apk --debug
        } finally {
            Pop-Location
        }
    }

    Invoke-Step "Debug build: helix_remote (Windows)" {
        Push-Location apps/helix_remote
        try {
            flutter build windows --debug
        } finally {
            Pop-Location
        }
    }

    Invoke-Step "Debug build: helix_remote (Android APK)" {
        Push-Location apps/helix_remote
        try {
            flutter build apk --debug
        } finally {
            Pop-Location
        }
    }

    # Signing credential isolation check — each product must use product-scoped env vars.
    # HELIX_LOCAL_STORE_PASSWORD and HELIX_REMOTE_STORE_PASSWORD must either be absent
    # (non-release CI) or contain distinct values (release CI).
    Invoke-Step "Signing credential isolation check" {
        $localPass  = $env:HELIX_LOCAL_STORE_PASSWORD
        $remotePass = $env:HELIX_REMOTE_STORE_PASSWORD
        if ($localPass -and $remotePass -and ($localPass -eq $remotePass)) {
            throw "HELIX_LOCAL_STORE_PASSWORD and HELIX_REMOTE_STORE_PASSWORD must differ. " +
                  "Do not share signing credentials between products."
        }
        Write-Host "Signing env var check passed (passwords differ or not set)."
    }
} else {
    Write-Host ""
    Write-Host "==> Debug builds"
    Write-Host "Skipped. Set HELIX_VERIFY_BUILD=1 to run all four platform debug builds."
}
