<#
.SYNOPSIS
Restore drill: restores a Helix Global dump into a throwaway database
(helix_drill), starts one server node on it on 127.0.0.1, checks
/v1/health/ready, then removes everything again.

.DESCRIPTION
Automates docs/operations/V2_OPERABILITY.md, "Restore drill". Run it
yourself, in your own PowerShell window. It asks for up to two passwords:

- createdb asks for the PostgreSQL superuser's password (the helix role has
  no CREATEDB), unless pgpass.conf has an entry for that user;
- the script asks for the helix role's password, to give the drill node its
  database URL. That URL always names helix_drill, lives only in this
  process's environment, and is never printed.

The drill node cannot reach the real world:
- the database name is fixed (helix_drill), and platform.jobs is emptied
  before the node starts, so no queued push or relay is sent;
- push, SMS, Global mode and federation are off, and the federation and
  maintenance switches are reset inside helix_drill too;
- it listens on 127.0.0.1 on its own port (never the production port), with
  its own node id, an empty blob directory (media.expire deletes objects),
  its own log file and throwaway JWT keys.
Everything else comes from server\.env as usual: the node runs from
helix_remote\server, so a setting that would stop production starting also
fails the drill. The production server is not touched and may keep running.

The result is appended to <BackupDir>\drill.log.

.PARAMETER BackupDir
Restores the newest dump in <BackupDir>\db.

.PARAMETER DumpFile
Restores this file instead: a .dump, or a .dump.age from the off-PC copy
(then pass -AgeIdentity, the key file kept away from the PC).

.PARAMETER Keep
Leaves helix_drill and the drill folder in place for inspection. Drop the
database later with: dropdb -h 127.0.0.1 -U helix --force helix_drill

.EXAMPLE
./restore-drill.ps1 -BackupDir F:\helix-backups
#>
param(
    [string]$BackupDir,
    [string]$DumpFile,
    [string]$AgeIdentity,
    [string]$AgeExe = 'age.exe',
    [string]$PgBin = 'C:\Program Files\PostgreSQL\17\bin',
    [string]$SuperUser = 'postgres',
    [string]$DbHost = '127.0.0.1',
    [int]$DbPort = 5432,
    [ValidateRange(1024, 65535)][int]$Port = 8090,
    [ValidateRange(10, 1800)][int]$ReadySeconds = 180,
    [string]$EnvFile,
    [switch]$Keep
)

$ErrorActionPreference = 'Stop'
$drillDb = 'helix_drill'
$remoteRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$serverDir = Join-Path $remoteRoot 'server'
if (-not $EnvFile) { $EnvFile = Join-Path $serverDir '.env' }

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

function Write-Step([string]$Text) { Write-Host "== $Text" -ForegroundColor Cyan }

function Assert-Exit([string]$What) {
    if ($LASTEXITCODE -ne 0) { throw "$What failed with exit code $LASTEXITCODE." }
}

function Write-DrillLog([string]$Result, [string]$Detail) {
    if (-not $BackupDir) { return }
    $line = '{0} {1} {2}' -f (Get-Date -Format 'yyyy-MM-ddTHH:mm:sszzz'), $Result, $Detail
    Add-Content -LiteralPath (Join-Path $BackupDir 'drill.log') -Value $line -Encoding UTF8
}

# --- Checks ------------------------------------------------------------------

$psql = Join-Path $PgBin 'psql.exe'
$createdb = Join-Path $PgBin 'createdb.exe'
$dropdb = Join-Path $PgBin 'dropdb.exe'
$pgRestore = Join-Path $PgBin 'pg_restore.exe'
foreach ($tool in @($psql, $createdb, $dropdb, $pgRestore)) {
    if (-not (Test-Path -LiteralPath $tool)) { throw "$tool was not found; pass -PgBin." }
}
$dart = Get-Command dart -ErrorAction SilentlyContinue
if (-not $dart) { throw 'dart was not found on PATH.' }

if ($BackupDir) { $BackupDir = [IO.Path]::GetFullPath($BackupDir) }
if (-not $DumpFile) {
    if (-not $BackupDir) { throw 'Pass -BackupDir (newest dump) or -DumpFile.' }
    $newest = Get-ChildItem -LiteralPath (Join-Path $BackupDir 'db') -File |
        Where-Object { $_.Name -match '^helix-\d{8}-\d{6}\.dump$' } |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $newest) { throw "No dump found in $(Join-Path $BackupDir 'db')." }
    $DumpFile = $newest.FullName
}
$DumpFile = [IO.Path]::GetFullPath($DumpFile)
if (-not (Test-Path -LiteralPath $DumpFile -PathType Leaf)) { throw "$DumpFile does not exist." }
$dumpLabel = Split-Path $DumpFile -Leaf

# Never the production port: Caddy forwards public traffic there.
$productionPort = 8080
$configured = Get-Setting 'HELIX_PORT'
if ($configured) { $productionPort = [int]$configured }
if ($Port -in @($productionPort, 8080, 8081)) {
    throw "Port $Port is (or may be) a production node's port. Use another -Port."
}
if (Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue) {
    throw "Something already listens on port $Port. Use another -Port."
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$work = Join-Path $env:TEMP "helix-drill-$stamp"
New-Item -ItemType Directory -Force -Path (Join-Path $work 'blobs') | Out-Null

$node = $null
$saved = @{}
$passed = $false
$detail = ''
try {
    # --- Dump --------------------------------------------------------------
    if ($DumpFile.EndsWith('.age')) {
        if (-not $AgeIdentity) { throw 'A .age dump needs -AgeIdentity (the age key file).' }
        $age = Get-Command $AgeExe -ErrorAction SilentlyContinue
        if (-not $age) { throw "$AgeExe was not found; install age or pass -AgeExe." }
        Write-Step "Decrypting $dumpLabel"
        $plainDump = Join-Path $work 'drill.dump'
        & $age.Source --decrypt --identity $AgeIdentity --output $plainDump $DumpFile
        Assert-Exit 'age'
        $DumpFile = $plainDump
    }

    # --- Database ----------------------------------------------------------
    $exists = & $psql --no-password -h $DbHost -p $DbPort -U helix -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname = '$drillDb'"
    Assert-Exit 'psql (looking for an old drill database)'
    if ("$exists".Trim() -eq '1') {
        Write-Step "Dropping the $drillDb left over from an earlier drill"
        & $dropdb --no-password --force -h $DbHost -p $DbPort -U helix $drillDb
        Assert-Exit 'dropdb'
    }

    Write-Step "Creating $drillDb (as $SuperUser; enter its password if asked)"
    & $createdb -h $DbHost -p $DbPort -U $SuperUser -O helix $drillDb
    Assert-Exit 'createdb'

    Write-Step "Restoring $dumpLabel into $drillDb"
    & $pgRestore --no-owner --no-password -h $DbHost -p $DbPort -U helix -d $drillDb $DumpFile
    Assert-Exit 'pg_restore'

    Write-Step 'Emptying platform.jobs and turning federation and maintenance off'
    $sql = @"
TRUNCATE platform.jobs;
INSERT INTO ops.settings (key, value) VALUES ('federation_enabled', 'false'), ('maintenance', 'false')
  ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = now();
SELECT 'accounts: ' || count(*) FROM identity.accounts;
SELECT 'devices: ' || count(*) FROM identity.devices;
SELECT 'applied migrations: ' || count(*) FROM platform.schema_migrations;
"@
    $sql | & $psql --no-password -h $DbHost -p $DbPort -U helix -d $drillDb -v ON_ERROR_STOP=1 -q -tA -f -
    Assert-Exit 'psql (preparing the drill database)'

    # --- Node --------------------------------------------------------------
    $secure = Read-Host -AsSecureString 'Password of the PostgreSQL role helix (for the drill node)'
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
    $encoded = [Uri]::EscapeDataString($plain)
    Remove-Variable -Name plain

    $keyBytes = New-Object byte[] 32
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($keyBytes)
    $drillKey = [Convert]::ToBase64String($keyBytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')

    $overrides = [ordered]@{
        HELIX_DATABASE_URL       = "postgresql://helix:$encoded@${DbHost}:$DbPort/$drillDb`?sslmode=disable"
        HELIX_HOST               = '127.0.0.1'
        HELIX_PORT               = "$Port"
        HELIX_PUBLIC_BASE_URL    = "http://127.0.0.1:$Port"
        HELIX_NODE_ID            = "restore-drill-$stamp"
        HELIX_TOPOLOGY           = 'single_host'
        HELIX_BLOB_STORE         = 'local'
        HELIX_BLOB_DIR           = (Join-Path $work 'blobs')
        HELIX_LOG_FILE           = (Join-Path $work 'server.log')
        HELIX_DB_POOL_SIZE       = '4'
        HELIX_JWT_KEYS           = "{`"drill`":`"$drillKey`"}"
        HELIX_JWT_ACTIVE_KID     = 'drill'
        HELIX_PUSH_PROVIDER      = 'none'
        HELIX_SMS_PROVIDER       = 'none'
        HELIX_GLOBAL_MODE        = 'false'
        HELIX_FEDERATION_ENABLED = 'false'
    }
    Remove-Variable -Name encoded
    foreach ($key in $overrides.Keys) {
        $saved[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
        [Environment]::SetEnvironmentVariable($key, $overrides[$key], 'Process')
    }
    $overrides = $null

    Write-Step "Migrating $drillDb with this checkout's code"
    Push-Location $serverDir
    try {
        & $dart.Source run bin/migrate.dart
        Assert-Exit 'bin/migrate.dart'
    } finally {
        Pop-Location
    }

    Write-Step "Starting a drill node on 127.0.0.1:$Port"
    $node = Start-Process -FilePath $dart.Source -ArgumentList @('run', 'bin/server.dart') `
        -WorkingDirectory $serverDir -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput (Join-Path $work 'stdout.log') `
        -RedirectStandardError (Join-Path $work 'stderr.log')

    $deadline = (Get-Date).AddSeconds($ReadySeconds)
    while ((Get-Date) -lt $deadline -and -not $node.HasExited) {
        try {
            $response = Invoke-WebRequest -UseBasicParsing -TimeoutSec 5 `
                -Uri "http://127.0.0.1:$Port/v1/health/ready"
            if ($response.StatusCode -eq 200) {
                $passed = $true
                $detail = "ready: $($response.Content)"
                break
            }
        } catch {
            # Not listening yet, or 503 while a check fails: keep waiting.
        }
        Start-Sleep -Seconds 2
    }
    if (-not $passed) {
        $detail = if ($node.HasExited) { 'the drill node exited' } else { "not ready within $ReadySeconds s" }
        Write-Host 'Last lines of the drill node output:' -ForegroundColor Yellow
        foreach ($log in @('stdout.log', 'stderr.log')) {
            $path = Join-Path $work $log
            if (Test-Path -LiteralPath $path) { Get-Content -LiteralPath $path -Tail 15 }
        }
    }
} catch {
    $detail = $_.Exception.Message
} finally {
    if ($node -and -not $node.HasExited) {
        # The whole tree: dart may run the server in a child process.
        & taskkill.exe /PID $node.Id /T /F | Out-Null
    }
    foreach ($key in $saved.Keys) {
        [Environment]::SetEnvironmentVariable($key, $saved[$key], 'Process')
    }
    if (-not $Keep) {
        Start-Sleep -Seconds 1
        & $dropdb --no-password --if-exists --force -h $DbHost -p $DbPort -U helix $drillDb
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Could not drop $drillDb. Drop it yourself: dropdb -h $DbHost -U helix --force $drillDb"
        }
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    } else {
        Write-Host "Kept $drillDb and $work for inspection."
    }
}

if ($passed) {
    Write-DrillLog 'PASS' "$dumpLabel $detail"
    Write-Host "Drill passed: $dumpLabel restored, migrated and served /v1/health/ready ($detail)." -ForegroundColor Green
    exit 0
}
Write-DrillLog 'FAIL' "$dumpLabel $detail"
Write-Host "Drill FAILED: $detail" -ForegroundColor Red
exit 1
