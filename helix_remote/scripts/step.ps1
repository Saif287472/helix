# The one step helper every PowerShell gate uses. It exists as its own file so
# the failure behaviour can be tested (scripts/test_step.ps1) instead of
# trusted per copy; a second copy is how the release gate came to report
# failed steps as success (AUD-18-1).

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
