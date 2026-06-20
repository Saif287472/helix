$ErrorActionPreference = "Stop"

function Test-DependencyAdvisoryEnabled {
    $flag = $env:HELIX_DEPENDENCY_ADVISORY
    if ($flag -in @("1", "true", "TRUE", "yes", "YES")) { return $true }

    $ci = $env:CI
    return $ci -in @("1", "true", "TRUE", "yes", "YES")
}

function Test-BuildOnlyEnabled {
    $flag = $env:HELIX_VERIFY_BUILD_ONLY
    return $flag -in @("1", "true", "TRUE", "yes", "YES")
}

$FlutterPubArgs = @()
if (-not (Test-DependencyAdvisoryEnabled)) {
    $FlutterPubArgs = @("--no-pub")
}

function Invoke-Step {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Command
    )

    Write-Host ""
    Write-Host "==> $Name"
    $global:LASTEXITCODE = 0
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        & $Command
        if ((-not $?) -or ($global:LASTEXITCODE -ne 0)) {
            throw "Step '$Name' failed."
        }
    } finally {
        $timer.Stop()
        Write-Host ("<== {0} completed in {1}" -f $Name, $timer.Elapsed)
    }
}

if (-not (Test-BuildOnlyEnabled)) {
    Invoke-Step "Dart format check" {
        dart format --output=none --set-exit-if-changed apps packages services tool
    }

    Invoke-Step "Flutter analyze" {
        flutter analyze @FlutterPubArgs
    }

    Invoke-Step "Dart analyze (backend and tooling)" {
        dart analyze services/helix_remote_backend tool
    }

    Invoke-Step "Architecture boundary check" {
        dart run tool/check_boundaries.dart
    }

    Invoke-Step "Forbidden import tests + cycle detection (P4-010/P4-015)" {
        dart test tool/boundary_test.dart
    }

    Invoke-Step "Phase 0 guardrail tests" {
        dart test tool/secret_scan_test.dart tool/dependency_policy_test.dart tool/documentation_consistency_test.dart tool/risk_coverage_test.dart
    }

    Invoke-Step "Phase 11 release assurance audit" {
        dart test tool/fuzz_seed_corpus_test.dart tool/phase11_release_assurance_test.dart
    }

    Invoke-Step "Phase 20 release/governance audit" {
        dart test tool/phase20_release_governance_test.dart
    }

    Invoke-Step "Dependency graph (P4-014)" {
        dart run tool/dep_graph.dart
    }

    Invoke-Step "Secret scan" {
        dart run tool/check_secrets.dart
    }

    Invoke-Step "Release hardening checks (P7)" {
        dart run tool/check_release_hardening.dart
    }

    Invoke-Step "SBOM/license inventory check (P7)" {
        dart run tool/generate_local_sbom.dart --check-only
    }

    Invoke-Step "Flutter tests (helix_local)" {
        Push-Location apps/helix_local
        try {
            flutter test @FlutterPubArgs
        } finally {
            Pop-Location
        }
    }

    Invoke-Step "Flutter tests (helix_remote)" {
        Push-Location apps/helix_remote
        try {
            flutter test @FlutterPubArgs
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
                            flutter test @FlutterPubArgs
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

    Invoke-Step "Tests: services/helix_remote_backend" {
        Push-Location services/helix_remote_backend
        try {
            dart test
        } finally {
            Pop-Location
        }
    }

    Invoke-Step "Dependency health advisory" {
        if (Test-DependencyAdvisoryEnabled) {
            flutter pub outdated
        } else {
            Write-Host "Skipped for local verification. Set HELIX_DEPENDENCY_ADVISORY=1 to run flutter pub outdated."
        }
    }
} else {
    Write-Host ""
    Write-Host "==> Build-only verification"
    Write-Host "Skipping format, analyze, dependency, and test gates because HELIX_VERIFY_BUILD_ONLY=1."
}

if ($env:HELIX_VERIFY_BUILD -eq "1") {
    Invoke-Step "Debug build: helix_local (Windows)" {
        Push-Location apps/helix_local
        try {
            flutter build windows --debug @FlutterPubArgs
        } finally {
            Pop-Location
        }
    }

    Invoke-Step "Debug build: helix_local (Android APK)" {
        Push-Location apps/helix_local
        try {
            flutter build apk --debug @FlutterPubArgs
        } finally {
            Pop-Location
        }
    }

    Invoke-Step "Debug build: helix_remote (Windows)" {
        Push-Location apps/helix_remote
        try {
            flutter build windows --debug @FlutterPubArgs
        } finally {
            Pop-Location
        }
    }

    Invoke-Step "Debug build: helix_remote (Android APK)" {
        Push-Location apps/helix_remote
        try {
            flutter build apk --debug @FlutterPubArgs
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
