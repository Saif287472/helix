# Proves the shared step helper fails a step whose native command exits
# non-zero, including the shape every gate step uses (the scriptblock ends in
# Pop-Location). AUD-18-1: the release gate checked `$?` after that cleanup, so
# a failing flutter test or release build was reported as success.
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "step.ps1")

$failures = [System.Collections.Generic.List[string]]::new()

# A step that succeeds must not throw.
try {
    Invoke-Step "exit 0" { cmd /c "exit 0" }
} catch {
    $failures.Add("a successful step threw: $($_.Exception.Message)")
}

# The measured defect: a scriptblock ending in Pop-Location hides the exit
# code from `$?`, so the old helper returned as if the step had passed.
$threw = $false
try {
    Invoke-Step "exit 7" {
        Push-Location (Join-Path $PSScriptRoot "..")
        try {
            cmd /c "exit 7"
        } finally {
            Pop-Location
        }
    }
} catch {
    $threw = $true
}
if (-not $threw) {
    $failures.Add("a step whose command exited 7 was reported as success")
}

# The gate's own failure probe must ride on this helper, not a local copy.
foreach ($script in @("verify.ps1", "remote_release_gate.ps1")) {
    $path = Join-Path $PSScriptRoot $script
    $text = Get-Content -Raw $path
    if ($text -notmatch 'step\.ps1') {
        $failures.Add("$script does not source the shared step helper")
    }
    if ($text -match 'function Invoke-Step') {
        $failures.Add("$script defines its own Invoke-Step")
    }
}

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) {
        Write-Host "FAIL: $failure" -ForegroundColor Red
    }
    throw "Step helper verification failed ($($failures.Count))."
}

# The deliberate exit-7 case leaves $global:LASTEXITCODE behind, and a caller
# that runs this file as a step checks exactly that variable - so a green run
# has to clear it or it would be reported as a failed step.
$global:LASTEXITCODE = 0
Write-Host "Step helper verification passed."
