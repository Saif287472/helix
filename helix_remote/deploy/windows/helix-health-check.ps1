<#
.SYNOPSIS
Checks Orbit Home and tells you when something changes: the Windows
Application log (source Helix) and a desktop notification.

.DESCRIPTION
Run every five minutes by the "Helix Health Check" task, at boot and whether
or not anyone is logged on (install-helix-tasks.ps1). Each run checks:

- the server answers GET /v1/health/ready with 200,
- the "Helix Server" task is running (when it is installed),
- every drive in -Drives has at least -MinFreePercent free,
- with HELIX_METRICS_TOKEN set in <Dest>\.env (the token is read, never
  printed): no dead jobs (helix_jobs_dead) and a mailbox backlog
  (helix_mailbox_backlog) under -BacklogWarn.

Also, from the settings in <Dest>\.env (none of them secret):

- HELIX_BACKUP_DIR: the newest verified dump in <dir>\db is under
  -BackupMaxAgeHours old, the last backup.log run did not end WITH ERRORS, and
  <dir>\drill.log has a PASS in the last -DrillMaxAgeDays days.
- HELIX_PUBLIC_BASE_URL (https): its certificate has more than 14 days left.
- Postgres, Caddy and coturn run (the ones installed), and Postgres does not
  answer on this PC's LAN address.
- HELIX_HEARTBEAT_URL: pinged on every healthy run (healthchecks.io and the
  like: when the pings stop, that service tells you, even when this PC is off).
- HELIX_ALERT_URL: a change (new problems, or all clear) is POSTed there as
  plain text (ntfy.sh, a Telegram or Discord bridge...). Keep the URL private.

Only a change is reported (new problems, or all clear again), so a problem
that lasts an hour does not notify you twelve times. The last result is in
<Dest>\health-state.json. Exit code 0 when healthy, 1 otherwise.

.EXAMPLE
.\helix-health-check.ps1 -Dest J:\Projects\Servers\helix_server\helix -Drives C:,J:
#>
param(
    [string]$Dest = $PSScriptRoot,
    [int]$Port = 8080,
    [string[]]$Drives = @('C:', 'J:'),
    [int]$MinFreePercent = 10,
    [int]$BacklogWarn = 50000,
    [string]$TaskName = 'Helix Server',
    [int]$BackupMaxAgeHours = 36,
    [int]$DrillMaxAgeDays = 45,
    [string]$PostgresService = 'postgresql-x64-17',
    [switch]$NoToast
)

$ErrorActionPreference = 'Stop'
# From a scheduled task (-File) the list arrives as one "C:,J:" string.
$Drives = @($Drives | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim(" '") } | Where-Object { $_ })
$problems = New-Object System.Collections.Generic.List[string]
$base = "http://127.0.0.1:$Port"

# 1. Ready.
try {
    $ready = Invoke-WebRequest -UseBasicParsing -TimeoutSec 10 "$base/v1/health/ready"
    if ($ready.StatusCode -ne 200) { $problems.Add("The server is not ready (HTTP $($ready.StatusCode)).") }
} catch {
    $status = $_.Exception.Response.StatusCode.value__
    if ($status) {
        $problems.Add("The server is not ready (HTTP $status).")
    } else {
        $problems.Add('The server does not answer.')
    }
}

# 2. The task.
$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($task -and $task.State -ne 'Running') {
    $problems.Add("The '$TaskName' task is $($task.State).")
}

# 3. Disk space.
foreach ($drive in $Drives) {
    $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$drive'" -ErrorAction SilentlyContinue
    if (-not $disk -or -not $disk.Size) { continue }
    $free = [Math]::Round(100 * $disk.FreeSpace / $disk.Size, 1)
    if ($free -lt $MinFreePercent) {
        $problems.Add("Drive $drive has $free% free (under $MinFreePercent%).")
    }
}

# Settings from <Dest>\.env (the last matching line wins, as the server reads it).
$settings = @{}
$envFile = Join-Path $Dest '.env'
if (Test-Path -LiteralPath $envFile) {
    foreach ($line in Get-Content -LiteralPath $envFile) {
        if ($line -match '^\s*(HELIX_METRICS_TOKEN|HELIX_BACKUP_DIR|HELIX_PUBLIC_BASE_URL|HELIX_HEARTBEAT_URL|HELIX_ALERT_URL)\s*=\s*(.+?)\s*$') {
            $settings[$Matches[1]] = $Matches[2].Trim('"', "'")
        }
    }
}

# 4. Metrics, when a metrics token is configured.
$token = $settings['HELIX_METRICS_TOKEN']
if ($token) {
    try {
        $metrics = Invoke-WebRequest -UseBasicParsing -TimeoutSec 10 `
            -Headers @{ Authorization = "Bearer $token" } "$base/v1/ops/metrics"
        $values = @{}
        foreach ($line in ($metrics.Content -split "`n")) {
            if ($line -match '^(helix_jobs_dead|helix_mailbox_backlog)(\{[^}]*\})?\s+([0-9.eE+-]+)') {
                $values[$Matches[1]] = [double]$Matches[3] + [double]($values[$Matches[1]])
            }
        }
        if ($values['helix_jobs_dead'] -gt 0) {
            $problems.Add("$($values['helix_jobs_dead']) background jobs failed for good (dead letters; V2_OPERABILITY.md, 'Jobs').")
        }
        if ($values['helix_mailbox_backlog'] -gt $BacklogWarn) {
            $problems.Add("$($values['helix_mailbox_backlog']) undelivered envelopes wait in mailboxes.")
        }
    } catch {
        # The ready check already reports a server that does not answer.
    }
}
$token = $null

# 5. Backups: fresh, not failing, and a restore drill that has been run.
$backupDir = $settings['HELIX_BACKUP_DIR']
if ($backupDir -and (Test-Path -LiteralPath $backupDir)) {
    $newest = Get-ChildItem -LiteralPath (Join-Path $backupDir 'db') -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^helix-\d{8}-\d{6}\.dump(\.age)?$' } |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $newest) {
        $problems.Add("There is no verified database backup in $backupDir.")
    } elseif ($newest.LastWriteTime -lt (Get-Date).AddHours(-$BackupMaxAgeHours)) {
        $problems.Add("The newest database backup is from $($newest.LastWriteTime.ToString('yyyy-MM-dd HH:mm')) (older than $BackupMaxAgeHours h).")
    }
    $backupLog = Join-Path $backupDir 'backup.log'
    if (Test-Path -LiteralPath $backupLog) {
        $lastEnd = Get-Content -LiteralPath $backupLog -Tail 40 | Where-Object { $_ -match '\sEND\s' } | Select-Object -Last 1
        if ($lastEnd -match 'WITH ERRORS') { $problems.Add('The last backup run ended with errors (backup.log).') }
    }
    $drillLog = Join-Path $backupDir 'drill.log'
    $lastPass = $null
    if (Test-Path -LiteralPath $drillLog) {
        $lastPass = Get-Content -LiteralPath $drillLog | Where-Object { $_ -match '^\S+\s+PASS\s' } | Select-Object -Last 1
    }
    if ($DrillMaxAgeDays -gt 0) {
        $drilled = $null
        if ($lastPass -match '^(\S+)') { try { $drilled = [datetime]::Parse($Matches[1]) } catch { } }
        if (-not $drilled) {
            $problems.Add('No restore drill has passed yet (restore-drill.ps1).')
        } elseif ($drilled -lt (Get-Date).AddDays(-$DrillMaxAgeDays)) {
            $problems.Add("The last passing restore drill was on $($drilled.ToString('yyyy-MM-dd')) (older than $DrillMaxAgeDays days).")
        }
    }
} elseif ($backupDir) {
    $problems.Add("The backup folder $backupDir cannot be reached.")
}

# 6. The certificate people connect with.
$publicUrl = $settings['HELIX_PUBLIC_BASE_URL']
if ($publicUrl -match '^https://([^/:]+)') {
    $publicHost = $Matches[1]
    if ($publicHost -ne 'localhost' -and $publicHost -notmatch '^[0-9.]+$') {
        try {
            $client = New-Object System.Net.Sockets.TcpClient
            $pending = $client.BeginConnect($publicHost, 443, $null, $null)
            if ($pending.AsyncWaitHandle.WaitOne(4000) -and $client.Connected) {
                $client.EndConnect($pending)
                $ssl = New-Object System.Net.Security.SslStream($client.GetStream(), $false, { $true })
                $ssl.AuthenticateAsClient($publicHost)
                $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($ssl.RemoteCertificate)
                $daysLeft = [int]($cert.NotAfter - (Get-Date)).TotalDays
                if ($daysLeft -lt 14) { $problems.Add("The certificate for $publicHost expires in $daysLeft days.") }
                $ssl.Dispose()
            }
            $client.Close()
        } catch {
            # This PC may not reach its own public name; the ready check and the
            # off-box heartbeat tell the rest.
        }
    }
}

# 7. The things around the server.
$pg = Get-Service -Name $PostgresService -ErrorAction SilentlyContinue
if ($pg -and $pg.Status -ne 'Running') { $problems.Add("The PostgreSQL service ($PostgresService) is $($pg.Status).") }
if ((Get-ScheduledTask -TaskName 'Helix Caddy' -ErrorAction SilentlyContinue) -and -not (Get-Process -Name caddy -ErrorAction SilentlyContinue)) {
    $problems.Add('Caddy is not running (nothing reaches the server from outside).')
}
if (Get-ScheduledTask -TaskName 'Helix TURN' -ErrorAction SilentlyContinue) {
    # Calls need the relay; it lives in WSL, so ask WSL, with a short timeout.
    try {
        $probe = Start-Process -FilePath 'wsl.exe' -ArgumentList '-u', 'root', '--', 'pgrep', '-x', 'turnserver' `
            -NoNewWindow -PassThru -RedirectStandardOutput ([IO.Path]::GetTempFileName())
        if (-not $probe.WaitForExit(8000)) {
            $probe.Kill()
        } elseif ($probe.ExitCode -ne 0) {
            $problems.Add('coturn is not running in WSL (calls cannot connect).')
        }
    } catch { }
}
# PostgreSQL must listen on this PC only: nothing else on the network may reach it.
try {
    $route = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction Stop | Sort-Object RouteMetric | Select-Object -First 1
    $lan = (Get-NetIPAddress -InterfaceIndex $route.InterfaceIndex -AddressFamily IPv4 -ErrorAction Stop | Select-Object -First 1).IPAddress
    if ($lan -and $lan -ne '127.0.0.1') {
        $probe = New-Object System.Net.Sockets.TcpClient
        $pending = $probe.BeginConnect($lan, 5432, $null, $null)
        if ($pending.AsyncWaitHandle.WaitOne(1500) -and $probe.Connected) {
            $problems.Add("PostgreSQL answers on the LAN address $lan (listen_addresses and the firewall should keep it to this PC).")
        }
        $probe.Close()
    }
} catch { }

# Report a change only.
$stateFile = Join-Path $Dest 'health-state.json'
$previous = @()
if (Test-Path -LiteralPath $stateFile) {
    try { $previous = @((Get-Content -Raw -LiteralPath $stateFile | ConvertFrom-Json).problems) } catch { }
}
$changed = (($previous | Sort-Object) -join "`n") -ne (($problems | Sort-Object) -join "`n")
@{ checked = (Get-Date -Format o); problems = @($problems) } |
    ConvertTo-Json | Set-Content -LiteralPath $stateFile -Encoding utf8

function Show-Toast([string]$Title, [string]$Text) {
    if ($NoToast) { return }
    try {
        $null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
        $null = [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]
        $escape = { param($s) [System.Security.SecurityElement]::Escape($s) }
        $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
        $xml.LoadXml("<toast><visual><binding template='ToastGeneric'><text>$(& $escape $Title)</text><text>$(& $escape $Text)</text></binding></visual></toast>")
        $app = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($app).Show(
            [Windows.UI.Notifications.ToastNotification]::new($xml))
    } catch { }
}

function Write-HelixEvent([string]$Message, [string]$Type, [int]$Id) {
    try {
        Write-EventLog -LogName Application -Source Helix -EventId $Id -EntryType $Type -Message $Message
    } catch { }
}

if ($changed) {
    if ($problems.Count -gt 0) {
        $text = $problems -join ' '
        Write-HelixEvent "Orbit Home health check: $text" 'Error' 2001
        Show-Toast 'Orbit Home needs attention' $text
    } else {
        Write-HelixEvent 'Orbit Home health check: all clear again.' 'Information' 2000
        Show-Toast 'Orbit Home is healthy again' 'Every check passes.'
    }
}
# Off-box: a heartbeat on every healthy run (a dead-man's switch: when the pings
# stop, the service you chose tells you, even if this PC is off), and a plain
# text alert on a change.
function Send-OffBox([string]$Url, [string]$Method, [string]$Body) {
    try {
        if ($Method -eq 'Post') {
            $null = Invoke-WebRequest -UseBasicParsing -TimeoutSec 10 -Method Post -Uri $Url -Body $Body `
                -ContentType 'text/plain; charset=utf-8'
        } else {
            $null = Invoke-WebRequest -UseBasicParsing -TimeoutSec 10 -Uri $Url
        }
    } catch { }
}
$alertUrl = $settings['HELIX_ALERT_URL']
if ($changed -and $alertUrl) {
    $message = if ($problems.Count -gt 0) { 'Orbit Home needs attention: ' + ($problems -join ' ') } else { 'Orbit Home is healthy again.' }
    Send-OffBox $alertUrl 'Post' $message
}
$heartbeatUrl = $settings['HELIX_HEARTBEAT_URL']
if ($heartbeatUrl -and $problems.Count -eq 0) { Send-OffBox $heartbeatUrl 'Get' '' }
$settings.Clear()

if ($problems.Count -gt 0) { exit 1 }
exit 0
