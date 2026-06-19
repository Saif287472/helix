$ErrorActionPreference = "Stop"

function Invoke-Step {
    param([string]$Name, [scriptblock]$Command)
    Write-Host "`n==> $Name"
    $global:LASTEXITCODE = 0
    try { & $Command } catch { throw "Step '$Name' threw: $_" }
    if ($global:LASTEXITCODE -ne 0) { throw "Step '$Name' failed (exit $global:LASTEXITCODE)." }
}

function Invoke-Step-NoErr {
    param([string]$Name, [scriptblock]$Command)
    $saved = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    Write-Host "`n==> $Name"
    $global:LASTEXITCODE = 0
    & $Command 2>&1
    $ErrorActionPreference = $saved
    if ($global:LASTEXITCODE -ne 0) { throw "Step '$Name' failed (exit $global:LASTEXITCODE)." }
}

Invoke-Step "Dart format check" {
    dart format --output=none --set-exit-if-changed apps packages tool
}

Invoke-Step "Flutter analyze" {
    flutter analyze --no-pub
}

Invoke-Step-NoErr "Architecture boundary check" {
    dart run tool/check_boundaries.dart
}

Invoke-Step "Boundary tests + cycle detection" {
    dart test tool/boundary_test.dart
}

Invoke-Step-NoErr "Secret scan" {
    dart run tool/check_secrets.dart
}

Invoke-Step "Remote app tests" {
    flutter test --no-pub apps/helix_remote/test/
}

Invoke-Step "Remote crypto tests" {
    flutter test --no-pub packages/remote/helix_remote_crypto/test/
}

Invoke-Step "Remote calls tests" {
    flutter test --no-pub packages/remote/helix_remote_calls/test/
}

Invoke-Step "Remote groups tests" {
    flutter test --no-pub packages/remote/helix_remote_groups/test/
}

Invoke-Step "Remote storage tests" {
    flutter test --no-pub packages/remote/helix_remote_storage/test/
}

Invoke-Step "Remote sync tests" {
    flutter test --no-pub packages/remote/helix_remote_sync/test/
}

Invoke-Step "Remote API tests" {
    flutter test --no-pub packages/remote/helix_remote_api/test/
}

Invoke-Step "Remote backend tests" {
    dart test services/helix_remote_backend/test/
}

Invoke-Step "Local app tests" {
    Push-Location apps/helix_local; flutter test --no-pub test/; Pop-Location
}

Write-Host "`nAll student validation checks passed."
