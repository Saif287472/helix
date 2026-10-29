<#
.SYNOPSIS
Backs up Orbit Home: a pg_dump of the helix database, a copy of the blob
directory, and (optionally) an off-PC copy of the dump.

.DESCRIPTION
Meant to run daily from Task Scheduler: install-backup-task.ps1 copies this
script next to the backups and registers the task. The steps follow
docs/operations/V2_OPERABILITY.md, "Backups":

1. pg_dump --format=custom --no-owner --no-unlogged-table-data into
   <BackupDir>\db\helix-<yyyyMMdd-HHmmss>.dump. The file is written under a
   .partial name and renamed only when pg_dump succeeded.
2. pg_restore --list on the new file, to prove it is a readable archive. A
   dump that fails this is renamed to .unverified and never counted as a
   generation.
3. robocopy /E of the blob directory into <BackupDir>\blobs, after the dump,
   so every finished row in the dump has its object. Deleted objects stay in
   the copy (that costs space only). Never /MIR.
4. Off-PC copy (-OffsiteDir): the new dump, encrypted with age for
   -AgeRecipient, or as it is with -OffsitePlain (only for a destination that
   is encrypted itself, such as a BitLocker drive). -OffsiteBlobs copies the
   blob directory there too.
5. Only after a verified dump: the newest -Keep dumps stay in <BackupDir>\db
   and the newest -OffsiteKeep in -OffsiteDir; older ones are deleted.

Each step appends one line to <BackupDir>\backup.log. The exit code is 0 only
when every step worked, so Task Scheduler's "Last Run Result" shows failures.

The helix password comes from pgpass.conf (install-backup-task.ps1
-WritePgPass writes the entry). pg_dump runs with --no-password, so a missing
entry fails the run instead of waiting for input. This script never reads
server\.env. Back up .env and the Firebase key file yourself, and keep them
apart from the dumps: without HELIX_PHONE_PEPPER a dump cannot be used to test
phone numbers.

.EXAMPLE
./backup-helix.ps1 -BackupDir F:\helix-backups -BlobDir J:\helix\helix_blobs
#>
param(
    [Parameter(Mandatory = $true)][string]$BackupDir,
    [string]$BlobDir,
    [switch]$SkipBlobs,
    [ValidateRange(1, 3650)][int]$Keep = 14,
    [string]$OffsiteDir,
    [string]$AgeRecipient,
    [string]$AgeExe = 'age.exe',
    [switch]$OffsitePlain,
    [switch]$OffsiteBlobs,
    [ValidateRange(1, 3650)][int]$OffsiteKeep = 7,
    [ValidateRange(0, 100000)][int]$MinFreeGB = 2,
    [string]$PgBin = 'C:\Program Files\PostgreSQL\17\bin',
    [string]$DbHost = '127.0.0.1',
    [int]$DbPort = 5432,
    [string]$DbUser = 'helix',
    [string]$DbName = 'helix'
)

$ErrorActionPreference = 'Stop'
$started = Get-Date
$BackupDir = [IO.Path]::GetFullPath($BackupDir)
$dbDir = Join-Path $BackupDir 'db'
$logFile = Join-Path $BackupDir 'backup.log'
$robocopyLog = Join-Path $BackupDir 'robocopy.log'
New-Item -ItemType Directory -Force -Path $dbDir | Out-Null
$script:failed = $false

# Dump names this script writes; nothing else in the folders is ever deleted.
$dumpName = '^helix-\d{8}-\d{6}\.dump(\.age)?$'

function Write-Log([string]$Status, [string]$Message) {
    $line = '{0} {1,-4} {2}' -f (Get-Date -Format 'yyyy-MM-ddTHH:mm:sszzz'), $Status, $Message
    Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8
    Write-Host $line
    if ($Status -eq 'FAIL') { $script:failed = $true }
}

# Windows command-line quoting for one argument (the rules the C runtime
# uses to split a command line back into arguments).
function ConvertTo-Argument([string]$Value) {
    if ($Value.Length -gt 0 -and $Value -notmatch '[\s"]') { return $Value }
    $escaped = $Value -replace '(\\*)"', '$1$1\"'
    $escaped = $escaped -replace '(\\+)$', '$1$1'
    return '"' + $escaped + '"'
}

# Runs a program and returns its exit code and standard error. Standard
# output is not captured (pg_dump and pg_restore write to files here).
function Invoke-Tool([string]$FilePath, [string[]]$Arguments) {
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $FilePath
    $info.Arguments = ($Arguments | ForEach-Object { ConvertTo-Argument $_ }) -join ' '
    $info.UseShellExecute = $false
    $info.RedirectStandardError = $true
    $info.CreateNoWindow = $true
    $process = [System.Diagnostics.Process]::Start($info)
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    return [pscustomobject]@{ ExitCode = $process.ExitCode; StdErr = $stderr.Trim() }
}

function Get-FirstLine([string]$Text) {
    if (-not $Text) { return 'no error output' }
    return ($Text -split "`r?`n")[0]
}

function Format-Size([long]$Bytes) {
    if ($Bytes -ge 1GB) { return '{0:N1} GB' -f ($Bytes / 1GB) }
    return '{0:N1} MB' -f ($Bytes / 1MB)
}

function Get-Seconds([datetime]$Since) {
    return [int]((Get-Date) - $Since).TotalSeconds
}

function Get-FreeBytes([string]$Path) {
    try {
        return ([IO.DriveInfo]::new([IO.Path]::GetPathRoot($Path))).AvailableFreeSpace
    } catch {
        return $null # A UNC path: no drive to ask.
    }
}

function Copy-Blobs([string]$From, [string]$To, [string]$Label) {
    if (-not (Test-Path -LiteralPath $From -PathType Container)) {
        throw "the blob directory $From does not exist"
    }
    $t = Get-Date
    $robocopy = Join-Path $env:SystemRoot 'System32\robocopy.exe'
    $result = Invoke-Tool $robocopy @(
        # /XC /XN /XO: a file that already exists in the copy is never replaced.
        # Blobs are written once under a random id and never change, so a file
        # that differs from its copy was damaged (ransomware, a bad disk), and
        # the next night's run must not overwrite the good copy with it.
        $From, $To, '/E', '/XC', '/XN', '/XO', '/XJ', '/R:2', '/W:5', '/NP', '/NFL', '/NDL', "/LOG+:$robocopyLog"
    )
    # robocopy: 0 to 7 are success flags (copied, extra, mismatched); 8 and
    # up mean some files could not be copied.
    if ($result.ExitCode -ge 8) {
        throw "robocopy failed with exit code $($result.ExitCode); see $robocopyLog"
    }
    Write-Log 'ok' "$Label copied to $To (robocopy $($result.ExitCode)) in $(Get-Seconds $t) s"
}

function Remove-OldDumps([string]$Dir, [int]$KeepCount, [string]$Label) {
    $dumps = @(Get-ChildItem -LiteralPath $Dir -File |
        Where-Object { $_.Name -match $dumpName } |
        Sort-Object LastWriteTime -Descending)
    $old = @($dumps | Select-Object -Skip $KeepCount)
    foreach ($file in $old) { Remove-Item -LiteralPath $file.FullName -Force }
    if ($old.Count -gt 0) {
        Write-Log 'ok' "$Label`: removed $($old.Count) old dump(s), kept the newest $KeepCount"
    }
}

Write-Log 'run' "start: database $DbName on ${DbHost}:$DbPort into $BackupDir"

$verified = $false
$dump = $null
try {
    if ($OffsiteDir -and -not $AgeRecipient -and -not $OffsitePlain) {
        throw '-OffsiteDir needs -AgeRecipient (encrypt the copy) or -OffsitePlain (the destination is encrypted itself)'
    }
    if (-not $SkipBlobs -and -not $BlobDir) {
        throw 'pass -BlobDir (the server''s HELIX_BLOB_DIR) or -SkipBlobs'
    }
    $pgDump = Join-Path $PgBin 'pg_dump.exe'
    $pgRestore = Join-Path $PgBin 'pg_restore.exe'
    foreach ($tool in @($pgDump, $pgRestore)) {
        if (-not (Test-Path -LiteralPath $tool)) { throw "$tool was not found; pass -PgBin" }
    }
    $free = Get-FreeBytes $BackupDir
    if ($null -ne $free -and $free -lt ([long]$MinFreeGB * 1GB)) {
        throw "only $(Format-Size $free) free on the backup drive (minimum $MinFreeGB GB)"
    }

    # 1. Dump.
    $name = 'helix-{0}.dump' -f (Get-Date -Format 'yyyyMMdd-HHmmss')
    $dump = Join-Path $dbDir $name
    $partial = "$dump.partial"
    $t = Get-Date
    $result = Invoke-Tool $pgDump @(
        '--format=custom', '--no-owner', '--no-unlogged-table-data', '--no-password',
        '-h', $DbHost, '-p', "$DbPort", '-U', $DbUser, '-d', $DbName, '-f', $partial
    )
    if ($result.ExitCode -ne 0) {
        Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue
        $dump = $null
        throw "pg_dump failed with exit code $($result.ExitCode): $(Get-FirstLine $result.StdErr)"
    }
    Move-Item -LiteralPath $partial -Destination $dump
    Write-Log 'ok' "dump $name, $(Format-Size (Get-Item -LiteralPath $dump).Length) in $(Get-Seconds $t) s"

    # 2. Verify.
    $toc = "$dump.toc"
    $result = Invoke-Tool $pgRestore @('--list', '-f', $toc, $dump)
    $entries = 0
    if (Test-Path -LiteralPath $toc) {
        $entries = @(Get-Content -LiteralPath $toc | Where-Object { $_ -and -not $_.StartsWith(';') }).Count
        Remove-Item -LiteralPath $toc -Force
    }
    if ($result.ExitCode -ne 0 -or $entries -eq 0) {
        Move-Item -LiteralPath $dump -Destination "$dump.unverified"
        $dump = $null
        throw "pg_restore --list could not read $name (exit code $($result.ExitCode)): $(Get-FirstLine $result.StdErr)"
    }
    $verified = $true
    Write-Log 'ok' "verify $name`: $entries archive entries"
} catch {
    Write-Log 'FAIL' $_.Exception.Message
}

# 3. Blobs, after the dump.
if ($verified -and -not $SkipBlobs) {
    try {
        Copy-Blobs $BlobDir (Join-Path $BackupDir 'blobs') 'blobs'
    } catch {
        Write-Log 'FAIL' "blobs: $($_.Exception.Message)"
    }
}

# 4. Off the PC.
if ($verified -and $OffsiteDir) {
    try {
        New-Item -ItemType Directory -Force -Path $OffsiteDir | Out-Null
        $source = Get-Item -LiteralPath $dump
        if ($AgeRecipient) {
            $age = Get-Command $AgeExe -ErrorAction SilentlyContinue
            if (-not $age) { throw "$AgeExe was not found; install age or pass -AgeExe" }
            $target = Join-Path $OffsiteDir "$($source.Name).age"
            $result = Invoke-Tool $age.Source @(
                '--encrypt', '--recipient', $AgeRecipient, '--output', "$target.partial", $source.FullName
            )
            if ($result.ExitCode -ne 0) {
                Remove-Item -LiteralPath "$target.partial" -Force -ErrorAction SilentlyContinue
                throw "age failed with exit code $($result.ExitCode): $(Get-FirstLine $result.StdErr)"
            }
        } else {
            $target = Join-Path $OffsiteDir $source.Name
            Copy-Item -LiteralPath $source.FullName -Destination "$target.partial" -Force
        }
        Move-Item -LiteralPath "$target.partial" -Destination $target -Force
        Write-Log 'ok' "offsite $(Split-Path $target -Leaf), $(Format-Size (Get-Item -LiteralPath $target).Length)"
        if ($OffsiteBlobs -and -not $SkipBlobs) {
            Copy-Blobs $BlobDir (Join-Path $OffsiteDir 'blobs') 'offsite blobs'
        }
        Remove-OldDumps $OffsiteDir $OffsiteKeep 'offsite'
    } catch {
        Write-Log 'FAIL' "offsite: $($_.Exception.Message)"
    }
}

# 5. Generations, only after a verified dump.
if ($verified) {
    try {
        Remove-OldDumps $dbDir $Keep 'local'
    } catch {
        Write-Log 'FAIL' "pruning: $($_.Exception.Message)"
    }
}

if ($script:failed) {
    Write-Log 'END' "finished WITH ERRORS in $(Get-Seconds $started) s"
    exit 1
}
Write-Log 'END' "finished in $(Get-Seconds $started) s"
exit 0
