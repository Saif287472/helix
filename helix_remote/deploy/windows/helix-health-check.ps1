<#
.SYNOPSIS
Checks Helix Global and tells you when something changes: the Windows
Application log (source Helix) and a desktop notification.

.DESCRIPTION
Run every five minutes by the "Helix Health Check" task while you are logged
on (install-helix-tasks.ps1). Each run checks:

- the server answers GET /v1/health/ready with 200,
- the "Helix Server" task is running (when it is installed),
- every drive in -Drives has at least -MinFreePercent free,
- with HELIX_METRICS_TOKEN set in <Dest>\.env (the token is read, never
  printed): no dead jobs (helix_jobs_dead) and a mailbox backlog
  (helix_mailbox_backlog) under -BacklogWarn.

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

# 4. Metrics, when a metrics token is configured.
$token = $null
$envFile = Join-Path $Dest '.env'
if (Test-Path -LiteralPath $envFile) {
    foreach ($line in Get-Content -LiteralPath $envFile) {
        if ($line -match '^\s*HELIX_METRICS_TOKEN\s*=\s*(.+?)\s*$') {
            $token = $Matches[1].Trim('"', "'")
        }
    }
}
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
        Write-HelixEvent "Helix Global health check: $text" 'Error' 2001
        Show-Toast 'Helix Global needs attention' $text
    } else {
        Write-HelixEvent 'Helix Global health check: all clear again.' 'Information' 2000
        Show-Toast 'Helix Global is healthy again' 'Every check passes.'
    }
}
if ($problems.Count -gt 0) { exit 1 }
exit 0
