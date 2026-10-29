<#
.SYNOPSIS
Switches Orbit Home to a release built by release-helix.ps1: graceful stop,
swap, migrate, start, check.

.DESCRIPTION
Run it yourself when you decide to deploy; it stops production for the length
of the swap (usually under a minute). Steps:

1. Checks <Dest>\releases\<Tag> has the three executables, that they are the
   ones release-helix.ps1 built (the SHA-256 in VERSION), and <Dest>\.env
   exists. Then takes a database backup (backup-helix.ps1 into -BackupDir or
   %HELIX_BACKUP_DIR%) so a bad migration or release has a restore point from
   minutes ago; a failed backup stops the deploy before anything changes. Pass
   -SkipBackup to deploy without one.
2. Asks the running server to stop gracefully by creating <Dest>\stop (the
   "Helix Server" task's wrapper then exits), and waits for the task to
   stop. With -Force it ends the task if it has not stopped in time.
3. Keeps the current bin\ as bin-previous\ and copies the release into bin\.
4. Runs helix-migrate.exe in <Dest> (it reads <Dest>\.env). If that fails, it
   puts bin-previous\ back and starts the old version.
5. Starts the task and waits for /v1/health/ready.

Without the scheduled task (-NoTask), it stops at step 4 and tells you how to
start the server by hand.

.EXAMPLE
.\deploy-helix.ps1 -Tag server-2026-10-14
#>
param(
    [Parameter(Mandatory = $true)][string]$Tag,
    [string]$Dest = 'J:\Projects\Servers\helix_server\helix',
    [string]$TaskName = 'Helix Server',
    [int]$Port = 8080,
    [int]$StopTimeoutSeconds = 60,
    [int]$ReadyTimeoutSeconds = 120,
    [string]$BackupDir = $env:HELIX_BACKUP_DIR,
    [switch]$SkipBackup,
    [switch]$Force,
    [switch]$NoTask
)

$ErrorActionPreference = 'Stop'
$release = Join-Path $Dest "releases\$Tag"
$exes = 'helix-server.exe', 'helix-migrate.exe', 'helix-admin-tool.exe'
foreach ($exe in $exes) {
    if (-not (Test-Path -LiteralPath (Join-Path $release $exe))) {
        throw "$release has no $exe. Build it with release-helix.ps1 -Tag $Tag."
    }
}
# The executables are the ones release-helix.ps1 built: their hashes were
# written to VERSION when they were built.
$versionFile = Join-Path $release 'VERSION'
if (Test-Path -LiteralPath $versionFile) {
    $recorded = @{}
    foreach ($line in Get-Content -LiteralPath $versionFile) {
        if ($line -match '^sha256-(\S+?)=([0-9a-f]{64})$') { $recorded[$Matches[1]] = $Matches[2] }
    }
    foreach ($exe in $exes) {
        $want = $recorded[$exe]
        if (-not $want) { throw "$versionFile has no hash for $exe. Build the release again with release-helix.ps1." }
        $have = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $release $exe)).Hash.ToLowerInvariant()
        if ($have -ne $want) { throw "$exe in $release is not the file that was built (hash differs). Nothing was changed." }
    }
} else {
    throw "$release has no VERSION file. Build it with release-helix.ps1 -Tag $Tag."
}
if (-not (Test-Path -LiteralPath (Join-Path $Dest '.env'))) {
    throw "No .env in $Dest. Copy server\.env there first (README, 'Moving production')."
}

$bin = Join-Path $Dest 'bin'
$previous = Join-Path $Dest 'bin-previous'
$stopFile = Join-Path $Dest 'stop'

function Wait-TaskStopped {
    $deadline = (Get-Date).AddSeconds($StopTimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if ((Get-ScheduledTask -TaskName $TaskName).State -ne 'Running') { return $true }
        Start-Sleep -Seconds 1
    }
    return $false
}

function Wait-Ready {
    $deadline = (Get-Date).AddSeconds($ReadyTimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        try {
            $r = Invoke-WebRequest -UseBasicParsing -TimeoutSec 5 "http://127.0.0.1:$Port/v1/health/ready"
            if ($r.StatusCode -eq 200) { return $true }
        } catch { }
        Start-Sleep -Seconds 2
    }
    return $false
}

# 1b. A restore point from minutes ago, before anything changes.
if (-not $SkipBackup) {
    if (-not $BackupDir) {
        throw 'Pass -BackupDir (or set HELIX_BACKUP_DIR) so a backup is taken before the migration, or -SkipBackup to deploy without one.'
    }
    $backup = Join-Path $PSScriptRoot 'backup-helix.ps1'
    if (-not (Test-Path -LiteralPath $backup)) { $backup = Join-Path $Dest 'backup-helix.ps1' }
    if (-not (Test-Path -LiteralPath $backup)) { throw "backup-helix.ps1 was not found next to this script or in $Dest." }
    Write-Host 'Taking a backup before the deploy...'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $backup -BackupDir $BackupDir -SkipBlobs
    if ($LASTEXITCODE -ne 0) { throw "The backup failed (exit $LASTEXITCODE). Nothing was changed; fix it, or deploy with -SkipBackup." }
}

# 1-2. Stop the running server gracefully.
$task = $null
if (-not $NoTask) {
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if (-not $task) { throw "No scheduled task '$TaskName'. Run install-helix-tasks.ps1, or pass -NoTask." }
    if ($task.State -eq 'Running') {
        Write-Host 'Asking the server to stop...'
        New-Item -ItemType File -Force -Path $stopFile | Out-Null
        if (-not (Wait-TaskStopped)) {
            if (-not $Force) {
                throw "The server did not stop within $StopTimeoutSeconds s. Nothing was changed. Run again with -Force to end it."
            }
            Write-Warning 'Ending the task (in-flight requests are cut off).'
            Stop-ScheduledTask -TaskName $TaskName
            $null = Wait-TaskStopped
        }
        Remove-Item -LiteralPath $stopFile -Force -ErrorAction SilentlyContinue
    }
}

# 3. Swap, keeping the old version.
if (Test-Path -LiteralPath $bin) {
    if (Test-Path -LiteralPath $previous) { Remove-Item -LiteralPath $previous -Recurse -Force }
    Move-Item -LiteralPath $bin -Destination $previous
}
New-Item -ItemType Directory -Force -Path $bin | Out-Null
Copy-Item -Path (Join-Path $release '*') -Destination $bin -Force

# 4. Migrate (expand-only: the old version still runs on the new schema).
Push-Location $Dest
try {
    & (Join-Path $bin 'helix-migrate.exe')
    $migrated = $LASTEXITCODE
} finally {
    Pop-Location
}
if ($migrated -ne 0) {
    Write-Warning "Migration failed (exit $migrated); putting the previous version back."
    if (Test-Path -LiteralPath $previous) {
        Remove-Item -LiteralPath $bin -Recurse -Force
        Move-Item -LiteralPath $previous -Destination $bin
    }
    if ($task) { Start-ScheduledTask -TaskName $TaskName }
    throw 'Deploy failed at the migration; the previous version is running again.'
}

if ($NoTask) {
    Write-Host "Deployed $Tag. Start it with: cd $Dest; .\bin\helix-server.exe"
    exit 0
}

# 5. Start and check.
Start-ScheduledTask -TaskName $TaskName
if (Wait-Ready) {
    Write-Host "Orbit Home is running $Tag and ready."
} else {
    Write-Warning "Not ready after $ReadyTimeoutSeconds s. Look at $Dest\logs (stderr-last-run.log, wrapper.log) and the Application event log."
    Write-Warning "To go back: .\deploy-helix.ps1 -Tag <previous tag>"
    exit 1
}
