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
    # PowerShell 5.1 wraps native-command stderr lines in ErrorRecords. With
    # $ErrorActionPreference = "Stop" those would terminate the step before we
    # reach the exit-code check. Switch to Continue so native stderr is printed
    # but does not abort; LASTEXITCODE is the sole failure gate.
    $ErrorActionPreference = "Continue"
    try {
        & $Command
        if ($global:LASTEXITCODE -ne 0) {
            throw "Step '$Name' failed (exit $global:LASTEXITCODE)."
        }
    } finally {
        $timer.Stop()
        Write-Host ("<== {0} completed in {1}" -f $Name, $timer.Elapsed)
    }
}

if (-not (Test-BuildOnlyEnabled)) {
    Invoke-Step "Dart format check" {
        dart format --output=none --set-exit-if-changed app backend packages tool
    }

    Invoke-Step "Flutter analyze" {
        flutter analyze @FlutterPubArgs
    }

    Invoke-Step "Dart analyze (backend and tooling)" {
        dart analyze backend tool
    }

    Invoke-Step "Flutter tests (app)" {
        Push-Location app
        try {
            flutter test @FlutterPubArgs
        } finally {
            Pop-Location
        }
    }

    Invoke-Step "Tests: backend" {
        Push-Location backend
        try {
            dart test
        } finally {
            Pop-Location
        }
    }

    foreach ($pkg in (Get-ChildItem packages -Directory)) {
        $testDir = Join-Path $pkg.FullName "test"
        if (-not (Test-Path $testDir)) { continue }

        Invoke-Step "Tests: packages/$($pkg.Name)" {
            Push-Location $pkg.FullName
            try {
                # Always `flutter test`, even for packages whose own
                # pubspec.yaml has no `sdk: flutter` line - matching
                # verify.sh. A package can still transitively depend on a
                # Flutter-based one (helix_remote_cli -> helix_remote_crypto),
                # and plain `dart test` then fails to resolve `dart:ui`,
                # surfacing as compile errors inside Flutter's own sources
                # (velocity_tracker.dart: "'Offset' isn't a type"). This
                # script used to branch on the pubspec and so hit exactly
                # that on helix_remote_cli, while the bash script - which
                # carries the same fix and a comment explaining it - passed.
                # `flutter test` runs pure-Dart package tests correctly too,
                # so there is no downside to using it unconditionally.
                flutter test @FlutterPubArgs
            } finally {
                Pop-Location
            }
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
