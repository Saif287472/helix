<#
.SYNOPSIS
Runs the Helix Global server and starts it again when it stops, until asked
to stop.

.DESCRIPTION
The "Helix Server" scheduled task (install-helix-tasks.ps1) runs this at boot.
It starts bin\helix-server.exe in the production folder, so the server reads
the .env there, and:

- passes HELIX_STOP_FILE=<Dest>\stop. Creating that file (deploy-helix.ps1
  does) makes the server stop gracefully, and this script then exits instead
  of starting it again. A scheduled task has no console, so Ctrl+C is not an
  option.
- starts the server again after it stops for any other reason (a crash, a
  database that never came back), after 5 s, doubling to 60 s; a run that
  lasted ten minutes resets the wait. Each unexpected stop is written to the
  Windows Application log (source Helix) and to logs\wrapper.log.
- discards the server's stdout (it repeats HELIX_LOG_FILE, so set that in
  .env) and keeps the stderr of the last run in logs\stderr-last-run.log
  (configuration errors land there).

.EXAMPLE
.\run-helix-server.ps1 -Dest J:\Projects\Servers\helix_server\helix
#>
param(
    [string]$Dest = $PSScriptRoot,
    [string]$ServerExe = '',
    [string[]]$ServerArgs = @(),
    [int]$FirstDelaySeconds = 5,
    [int]$MaxDelaySeconds = 60
)

$ErrorActionPreference = 'Stop'
if (-not $ServerExe) { $ServerExe = Join-Path $Dest 'bin\helix-server.exe' }
$stopFile = Join-Path $Dest 'stop'
$logDir = Join-Path $Dest 'logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$wrapperLog = Join-Path $logDir 'wrapper.log'

function Write-Wrapper([string]$Message) {
    "$(Get-Date -Format o) $Message" | Add-Content -Path $wrapperLog -Encoding utf8
}

function Write-HelixEvent([string]$Message, [string]$Type, [int]$Id) {
    # The source exists once install-helix-tasks.ps1 ran (as administrator).
    try {
        Write-EventLog -LogName Application -Source Helix -EventId $Id -EntryType $Type -Message $Message
    } catch {
        Write-Wrapper "event log unavailable: $Message"
    }
}

function Test-StopRequested {
    if (Test-Path -LiteralPath $stopFile) {
        Remove-Item -LiteralPath $stopFile -Force
        return $true
    }
    return $false
}

if (-not (Test-Path -LiteralPath $ServerExe)) {
    Write-HelixEvent "Helix server not found at $ServerExe. Run deploy-helix.ps1 first." 'Error' 1002
    throw "Helix server not found at $ServerExe"
}

# A stop request left over from before this start is not meant for it.
Remove-Item -LiteralPath $stopFile -Force -ErrorAction SilentlyContinue

$delay = $FirstDelaySeconds
while ($true) {
    $started = Get-Date
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $ServerExe
    $info.Arguments = ($ServerArgs -join ' ')
    $info.WorkingDirectory = $Dest
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.EnvironmentVariables['HELIX_STOP_FILE'] = $stopFile
    $process = [System.Diagnostics.Process]::Start($info)
    Write-Wrapper "started pid $($process.Id)"

    $null = $process.StandardOutput.BaseStream.CopyToAsync([System.IO.Stream]::Null)
    $errFile = [System.IO.File]::Create((Join-Path $logDir 'stderr-last-run.log'))
    $errCopy = $process.StandardError.BaseStream.CopyToAsync($errFile)
    $process.WaitForExit()
    try { $null = $errCopy.Wait(5000) } catch { }
    $errFile.Dispose()
    $code = $process.ExitCode

    if (Test-StopRequested) {
        Write-Wrapper "stopped on request (exit $code)"
        exit 0
    }

    $ranMinutes = ((Get-Date) - $started).TotalMinutes
    if ($ranMinutes -ge 10) { $delay = $FirstDelaySeconds }
    $why = if ($code -eq 78) { 'a configuration error (see logs\stderr-last-run.log)' } else { "exit code $code" }
    Write-Wrapper "exited with $code after $([int]$ranMinutes) min; starting again in $delay s"
    Write-HelixEvent "Helix server stopped unexpectedly ($why). Starting it again in $delay seconds." 'Warning' 1001

    $until = (Get-Date).AddSeconds($delay)
    while ((Get-Date) -lt $until) {
        if (Test-StopRequested) {
            Write-Wrapper 'stop requested while waiting to start again'
            exit 0
        }
        Start-Sleep -Seconds 1
    }
    $delay = [Math]::Min($delay * 2, $MaxDelaySeconds)
}
