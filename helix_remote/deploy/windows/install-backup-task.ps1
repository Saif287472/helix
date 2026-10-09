<#
.SYNOPSIS
One-time setup of the daily Helix Global backup: checks, an optional
pgpass.conf entry, a copy of backup-helix.ps1 next to the backups, and a Task
Scheduler task that runs it.

.DESCRIPTION
Run this yourself, in your own PowerShell window (no admin shell needed). It
is safe to run again: it replaces the script copy and the task.

- -BackupDir should be on a different physical disk from the PostgreSQL data
  directory; the script says which disk each folder is on and warns when they
  share one. (On the production PC, C: and D: are the same SSD.)
- The blob directory is the server's HELIX_BLOB_DIR, read the way the server
  reads it: the process environment first, then server\.env (the last line
  wins), relative to helix_remote\server. Only HELIX_BLOB_STORE and
  HELIX_BLOB_DIR are read from .env, and nothing secret is printed. Pass
  -BlobDir to choose it yourself.
- -WritePgPass asks for the helix role's password and writes the
  "127.0.0.1:5432:*:helix" entry of %APPDATA%\postgresql\pgpass.conf, keeping
  other entries. The password is not printed. Without -WritePgPass an
  existing entry must work; the script checks with psql --no-password.
- The task runs backup-helix.ps1 daily at -At while you are signed in to
  Windows (production runs in your session too). If the PC was off at that
  time, the task runs as soon as it can.
- The script is copied to <BackupDir>\backup-helix.ps1, so switching branches
  in the repository does not affect the task. Run this again after
  backup-helix.ps1 changes.

.EXAMPLE
./install-backup-task.ps1 -BackupDir F:\helix-backups -WritePgPass -RunNow

.EXAMPLE
./install-backup-task.ps1 -BackupDir F:\helix-backups -OffsiteDir E:\helix-offsite -OffsitePlain -RunNow
#>
param(
    [Parameter(Mandatory = $true)][string]$BackupDir,
    [string]$At = '03:30',
    [ValidateRange(1, 3650)][int]$Keep = 14,
    [string]$OffsiteDir,
    [string]$AgeRecipient,
    [string]$AgeExe = 'age.exe',
    [switch]$OffsitePlain,
    [switch]$OffsiteBlobs,
    [ValidateRange(1, 3650)][int]$OffsiteKeep = 7,
    [string]$BlobDir,
    [string]$EnvFile,
    [string]$PgBin = 'C:\Program Files\PostgreSQL\17\bin',
    [string]$DbHost = '127.0.0.1',
    [int]$DbPort = 5432,
    [string]$DbUser = 'helix',
    [string]$DbName = 'helix',
    [string]$PostgresService = 'postgresql-x64-17',
    [string]$TaskName = 'Helix Global backup',
    [switch]$WritePgPass,
    [switch]$RunNow
)

$ErrorActionPreference = 'Stop'

$remoteRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$serverDir = Join-Path $remoteRoot 'server'
if (-not $EnvFile) { $EnvFile = Join-Path $serverDir '.env' }
$BackupDir = [IO.Path]::GetFullPath($BackupDir)

# A process environment variable wins, otherwise the last matching line of
# server\.env, as the server reads them (platform/config/env_file.dart).
function Get-Setting([string]$Name) {
    $fromProcess = [Environment]::GetEnvironmentVariable($Name)
    if ($fromProcess) { return $fromProcess.Trim() }
    if (-not (Test-Path -LiteralPath $EnvFile)) { return $null }
    $line = Get-Content -LiteralPath $EnvFile |
        Where-Object { $_ -match "^\s*$([regex]::Escape($Name))\s*=" } |
        Select-Object -Last 1
    if (-not $line) { return $null }
    $value = $line.Substring($line.IndexOf('=') + 1).Trim()
    if ($value.Length -ge 2 -and $value[0] -eq $value[-1] -and "`"'".Contains($value[0])) {
        $value = $value.Substring(1, $value.Length - 2)
    }
    if (-not $value) { return $null }
    return $value
}

function ConvertTo-Argument([string]$Value) {
    if ($Value.Length -gt 0 -and $Value -notmatch '[\s"]') { return $Value }
    $escaped = $Value -replace '(\\*)"', '$1$1\"'
    $escaped = $escaped -replace '(\\+)$', '$1$1'
    return '"' + $escaped + '"'
}

function Get-DiskNumber([string]$Path) {
    try {
        $root = [IO.Path]::GetPathRoot([IO.Path]::GetFullPath($Path))
        if ($root -notmatch '^([A-Za-z]):\\$') { return $null }
        return (Get-Partition -DriveLetter $Matches[1] -ErrorAction Stop).DiskNumber
    } catch {
        return $null
    }
}

# --- Options -----------------------------------------------------------------

$psql = Join-Path $PgBin 'psql.exe'
foreach ($tool in @('pg_dump.exe', 'pg_restore.exe', 'psql.exe')) {
    if (-not (Test-Path -LiteralPath (Join-Path $PgBin $tool))) {
        throw "$tool was not found in '$PgBin'. Pass -PgBin with the PostgreSQL bin folder."
    }
}
if ($OffsiteDir -and -not $AgeRecipient -and -not $OffsitePlain) {
    throw '-OffsiteDir needs -AgeRecipient (encrypt the copy) or -OffsitePlain (the destination is encrypted itself, for example a BitLocker drive).'
}
if ($AgeRecipient -and -not (Get-Command $AgeExe -ErrorAction SilentlyContinue)) {
    throw "$AgeExe was not found. Install age, or pass -AgeExe with its full path."
}

$skipBlobs = $false
if (-not $BlobDir) {
    $store = Get-Setting 'HELIX_BLOB_STORE'
    if ($store -eq 's3') {
        $skipBlobs = $true
        Write-Host 'HELIX_BLOB_STORE is s3: blobs are not copied (use the bucket''s versioning or replication).'
    } else {
        $BlobDir = Get-Setting 'HELIX_BLOB_DIR'
        if (-not $BlobDir) { $BlobDir = 'helix_blobs' }
        if (-not [IO.Path]::IsPathRooted($BlobDir)) { $BlobDir = Join-Path $serverDir $BlobDir }
    }
}
if (-not $skipBlobs) {
    $BlobDir = [IO.Path]::GetFullPath($BlobDir)
    if (Test-Path -LiteralPath $BlobDir -PathType Container) {
        Write-Host "Blob directory: $BlobDir"
    } else {
        Write-Warning "Blob directory $BlobDir does not exist. The server creates it when it starts; if it should exist, check HELIX_BLOB_DIR or pass -BlobDir. Until then the blob step of each backup fails."
    }
}

# --- Disks -------------------------------------------------------------------

$dataDir = $null
$service = Get-CimInstance Win32_Service -Filter "Name='$PostgresService'" -ErrorAction SilentlyContinue
if ($service -and $service.PathName -match '-D\s+"([^"]+)"') { $dataDir = $Matches[1] }
$backupDisk = Get-DiskNumber $BackupDir
if ($dataDir) {
    $dataDisk = Get-DiskNumber $dataDir
    Write-Host "PostgreSQL data: $dataDir (disk $dataDisk); backups: $BackupDir (disk $backupDisk)"
    if ($null -ne $dataDisk -and $dataDisk -eq $backupDisk) {
        Write-Warning 'The backups are on the same physical disk as the database: one disk failure loses both. Choose a drive on another disk, and keep an off-PC copy (-OffsiteDir).'
    }
} else {
    Write-Warning "Could not find the data directory of the $PostgresService service; check yourself that -BackupDir is on another disk."
}
if (-not $skipBlobs) {
    $blobDisk = Get-DiskNumber $BlobDir
    if ($null -ne $blobDisk -and $blobDisk -eq $backupDisk) {
        Write-Warning "The blob copy is on the same physical disk as the blobs (disk $blobDisk). Keep an off-PC copy with -OffsiteDir -OffsiteBlobs."
    }
}
if (-not $OffsiteDir) {
    Write-Warning 'No -OffsiteDir: every copy stays on this PC (fire, theft or a failed power supply can take all of them).'
}

# --- pgpass ------------------------------------------------------------------

if ($WritePgPass) {
    $secure = Read-Host -AsSecureString "Password of the PostgreSQL role '$DbUser'"
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
    if ([string]::IsNullOrEmpty($plain)) { throw 'The password must not be empty.' }
    try {
        $pgpassDir = Join-Path $env:APPDATA 'postgresql'
        $pgpass = Join-Path $pgpassDir 'pgpass.conf'
        New-Item -ItemType Directory -Force -Path $pgpassDir | Out-Null
        # One entry for this host, port and user, any database (so the restore
        # drill can use helix_drill). Older entries for them are replaced: libpq
        # uses the first line that matches.
        $same = "^$([regex]::Escape($DbHost)):$DbPort`:[^:]*:$([regex]::Escape($DbUser)):"
        $lines = @()
        if (Test-Path -LiteralPath $pgpass) {
            $lines = @(Get-Content -LiteralPath $pgpass | Where-Object { $_ -notmatch $same })
        }
        $lines += "${DbHost}:${DbPort}:*:${DbUser}:" + $plain.Replace('\', '\\').Replace(':', '\:')
        [IO.File]::WriteAllLines($pgpass, [string[]]$lines, (New-Object Text.UTF8Encoding($false)))
        Write-Host "Wrote the $DbUser entry of $pgpass."
    } finally {
        Remove-Variable -Name plain, lines -ErrorAction SilentlyContinue
    }
}

$check = & $psql --no-password -h $DbHost -p $DbPort -U $DbUser -d $DbName -tAc 'SELECT 1'
if ($LASTEXITCODE -ne 0 -or "$check".Trim() -ne '1') {
    throw "psql could not sign in as $DbUser without a password prompt. Run again with -WritePgPass."
}
Write-Host "Signed in to $DbName as $DbUser through pgpass.conf."

# --- Task --------------------------------------------------------------------

New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
$scriptCopy = Join-Path $BackupDir 'backup-helix.ps1'
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'backup-helix.ps1') -Destination $scriptCopy -Force

$taskArgs = @(
    '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden',
    '-File', $scriptCopy,
    '-BackupDir', $BackupDir, '-Keep', "$Keep", '-PgBin', $PgBin,
    '-DbHost', $DbHost, '-DbPort', "$DbPort", '-DbUser', $DbUser, '-DbName', $DbName
)
if ($skipBlobs) { $taskArgs += '-SkipBlobs' } else { $taskArgs += @('-BlobDir', $BlobDir) }
if ($OffsiteDir) {
    $taskArgs += @('-OffsiteDir', [IO.Path]::GetFullPath($OffsiteDir), '-OffsiteKeep', "$OffsiteKeep")
    if ($AgeRecipient) {
        $taskArgs += @('-AgeRecipient', $AgeRecipient, '-AgeExe', (Get-Command $AgeExe).Source)
    } else {
        $taskArgs += '-OffsitePlain'
    }
    if ($OffsiteBlobs) { $taskArgs += '-OffsiteBlobs' }
}

$action = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument (($taskArgs | ForEach-Object { ConvertTo-Argument $_ }) -join ' ') `
    -WorkingDirectory $BackupDir
$trigger = New-ScheduledTaskTrigger -Daily -At $At
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew `
    -ExecutionTimeLimit (New-TimeSpan -Hours 3)
$principal = New-ScheduledTaskPrincipal `
    -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) `
    -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger `
    -Settings $settings -Principal $principal -Force `
    -Description 'Helix Global: pg_dump of the helix database and a copy of the blobs (helix_remote/deploy/windows).' |
    Out-Null
Write-Host "Task '$TaskName' runs daily at $At. Log: $(Join-Path $BackupDir 'backup.log')" -ForegroundColor Green

if ($RunNow) {
    Write-Host 'Running the first backup now...'
    Start-ScheduledTask -TaskName $TaskName
    Start-Sleep -Seconds 2
    while ((Get-ScheduledTask -TaskName $TaskName).State -in @('Running', 'Queued')) {
        Start-Sleep -Seconds 2
    }
    $logFile = Join-Path $BackupDir 'backup.log'
    if (Test-Path -LiteralPath $logFile) { Get-Content -LiteralPath $logFile -Tail 10 }
    $result = (Get-ScheduledTaskInfo -TaskName $TaskName).LastTaskResult
    if ($result -ne 0) {
        Write-Host "The first backup failed (task result $result). See the log above." -ForegroundColor Red
        exit 1
    }
    Write-Host 'The first backup worked.' -ForegroundColor Green
}
