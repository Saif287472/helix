$ErrorActionPreference = "Stop"

# The step helper is shared with remote_release_gate.ps1 and tested by
# scripts/test_step.ps1, so a failing native command can never be reported as
# success in either gate (AUD-18-1).
. (Join-Path $PSScriptRoot "step.ps1")

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

if (-not (Test-BuildOnlyEnabled)) {
    # The gate's own failure probe is tested first: if it cannot fail, nothing
    # after it is evidence.
    Invoke-Step "Step helper failure probe" {
        & (Join-Path $PSScriptRoot "test_step.ps1")
    }

    # Generated drift code is committed (ADR-027); fail when it is stale. CI
    # runs this as its own step and sets HELIX_VERIFY_SKIP_CODEGEN=1 here.
    if ($env:HELIX_VERIFY_SKIP_CODEGEN -in @("1", "true", "TRUE", "yes", "YES")) {
        Write-Host ""
        Write-Host "==> Generated drift code (helix_remote_db)"
        Write-Host "Skipped (HELIX_VERIFY_SKIP_CODEGEN=1)."
    } else {
        Invoke-Step "Generated drift code (helix_remote_db)" {
            Push-Location packages/helix_remote_db
            try {
                dart run tool/codegen.dart --check
            } finally {
                Pop-Location
            }
        }
    }

    Invoke-Step "Dart format check" {
        dart format --output=none --set-exit-if-changed app admin server packages tool
    }

    Invoke-Step "Flutter analyze" {
        flutter analyze @FlutterPubArgs
    }

    Invoke-Step "Dart analyze (server and tooling)" {
        dart analyze server tool
    }

    Invoke-Step "Flutter tests (app)" {
        Push-Location app
        try {
            flutter test @FlutterPubArgs
        } finally {
            Pop-Location
        }
    }

    Invoke-Step "Flutter tests (admin)" {
        Push-Location admin
        try {
            flutter test @FlutterPubArgs
        } finally {
            Pop-Location
        }
    }

    # The server. Database tests skip unless HELIX_TEST_DATABASE_URL is set;
    # CI sets HELIX_REQUIRE_TEST_DATABASE=1 on Linux so they cannot silently
    # skip there.
    Invoke-Step "Tests: server" {
        Push-Location server
        try {
            dart test
        } finally {
            Pop-Location
        }
    }

    foreach ($pkg in (Get-ChildItem packages -Directory)) {
        $testDir = Join-Path $pkg.FullName "test"
        # Only real packages: a folder without pubspec.yaml is a leftover
        # build directory of a deleted package.
        if (-not (Test-Path (Join-Path $pkg.FullName "pubspec.yaml"))) { continue }
        if (-not (Test-Path $testDir)) {
            throw "packages/$($pkg.Name) has no test/ directory: every package needs tests."
        }

        Invoke-Step "Tests: packages/$($pkg.Name)" {
            Push-Location $pkg.FullName
            try {
                # Always `flutter test`, even for packages whose own
                # pubspec.yaml has no `sdk: flutter` line - matching
                # verify.sh. It runs pure-Dart package tests correctly too,
                # and a package that gains a Flutter dependency later does
                # not need a new branch here.
                flutter test @FlutterPubArgs
            } finally {
                Pop-Location
            }
        }
    }

    # The gates that guard the guards: tool/ checks the governance docs, the
    # performance budgets and ci.yml, and its own tests are what say those
    # checkers still read the files they claim to read.
    Invoke-Step "Tests: tool" {
        Push-Location tool
        try {
            dart test
        } finally {
            Pop-Location
        }
    }

    Invoke-Step "Governance control evidence" {
        dart run tool/check_governance_controls.dart
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
    Invoke-Step "Debug build: Helix Remote (Windows)" {
        Push-Location app
        try {
            flutter build windows --debug @FlutterPubArgs
        } finally {
            Pop-Location
        }
    }

    Invoke-Step "Debug build: Helix Remote (Android APK)" {
        Push-Location app
        try {
            flutter build apk --debug @FlutterPubArgs
        } finally {
            Pop-Location
        }
    }

    Invoke-Step "Signing credential isolation check" {
        if (-not [Environment]::GetEnvironmentVariable("HELIX_REMOTE_STORE_PASSWORD")) {
            Write-Host "Remote signing env vars are not set; skipping release-signing isolation check."
            return
        }
        Write-Host "Remote signing env var check passed."
    }
} else {
    Write-Host ""
    Write-Host "==> Debug builds"
    Write-Host "Skipped. Set HELIX_VERIFY_BUILD=1 to run platform debug builds."
}
