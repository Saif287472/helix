<#
.SYNOPSIS
One-time setup of the scheduled tasks that keep Orbit Home running after a
reboot or a crash (review H-03), plus the health check (H-05).

.DESCRIPTION
Run it once, as administrator (Task Scheduler and the event source need it).
It:

1. creates <Dest> and <Dest>\logs, and copies run-helix-server.ps1 and
   helix-health-check.ps1 there, so the tasks never run from the development
   checkout;
2. registers the Windows event source "Helix" (Application log);
3. registers "Helix Server": at boot (30 s delay), whether or not you are
   logged on, as your account without storing a password (S4U: local access
   only, which is all the server needs), restarted by Task Scheduler if the
   wrapper itself fails; no time limit;
4. registers "Helix Health Check": every 5 minutes while you are logged on
   (so its notifications reach you);
5. optionally "Helix Caddy" (-CaddyExe, -Caddyfile): Caddy at boot, the same
   way as the server; and "Helix TURN" (-TurnScript): coturn in WSL at log-on.

It starts nothing unless you pass -StartNow: stop the server you run by hand
(Ctrl+C in its window) first, or the two fight over the port.

-Uninstall removes the tasks (not the folder, the logs or the event source).

.EXAMPLE
.\install-helix-tasks.ps1
.\install-helix-tasks.ps1 -CaddyExe J:\Projects\Servers\helix_server\caddy.exe -Caddyfile J:\Projects\Servers\helix_server\Caddyfile -StartNow
#>
param(
    [string]$Dest = 'J:\Projects\Servers\helix_server\helix',
    [int]$Port = 8080,
    [string[]]$Drives = @('C:', 'J:'),
    [string]$CaddyExe = '',
    [string]$Caddyfile = '',
    [string]$TurnScript = '',
    [switch]$StartNow,
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'
$names = 'Helix Server', 'Helix Health Check', 'Helix Caddy', 'Helix TURN'

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).
    IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) { throw 'Run this from an administrator PowerShell.' }

if ($Uninstall) {
    foreach ($name in $names) {
        if (Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue) {
            Unregister-ScheduledTask -TaskName $name -Confirm:$false
            Write-Host "Removed $name"
        }
    }
    exit 0
}

# 1. The production folder.
New-Item -ItemType Directory -Force -Path $Dest, (Join-Path $Dest 'logs') | Out-Null
foreach ($script in 'run-helix-server.ps1', 'helix-health-check.ps1') {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $script) -Destination $Dest -Force
}

# 2. The event source.
if (-not [System.Diagnostics.EventLog]::SourceExists('Helix')) {
    New-EventLog -LogName Application -Source Helix
}

$user = "$env:USERDOMAIN\$env:USERNAME"
$powershell = Join-Path $PSHOME 'powershell.exe'

function New-ScriptAction([string]$File, [string]$Arguments) {
    New-ScheduledTaskAction -Execute $powershell -WorkingDirectory $Dest `
        -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$File`" $Arguments"
}

function Register-BootTask([string]$Name, $Action, [string]$Description) {
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $trigger.Delay = 'PT30S'
    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType S4U -RunLevel Limited
    $settings = New-ScheduledTaskSettingsSet -RestartCount 999 `
        -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit ([TimeSpan]::Zero) `
        -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -MultipleInstances IgnoreNew
    Register-ScheduledTask -TaskName $Name -Description $Description -Action $Action `
        -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
    Write-Host "Registered $Name"
}

# 3. The server.
Register-BootTask 'Helix Server' `
    (New-ScriptAction (Join-Path $Dest 'run-helix-server.ps1') "-Dest `"$Dest`"") `
    'Orbit Home: runs bin\helix-server.exe and starts it again when it stops (deploy\windows\README.md).'

# 4. The health check.
$drives = $Drives -join ','
$check = New-ScriptAction (Join-Path $Dest 'helix-health-check.ps1') "-Dest `"$Dest`" -Port $Port -Drives $drives"
$every = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 5)
$boot = New-ScheduledTaskTrigger -AtStartup
$boot.Delay = 'PT1M'
$logon = New-ScheduledTaskTrigger -AtLogOn -User $user
# S4U: runs whether or not anyone is logged on, so a reboot with nobody at the
# PC does not leave the health check (and its off-box alert) silent. A desktop
# toast needs a logged-on session and is skipped then; the Event Log entry and
# the off-box alert (HELIX_HEARTBEAT_URL / HELIX_ALERT_URL in .env) are not.
$s4u = New-ScheduledTaskPrincipal -UserId $user -LogonType S4U -RunLevel Limited
$interactive = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
$checkSettings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 2) `
    -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew
Register-ScheduledTask -TaskName 'Helix Health Check' -Action $check -Trigger @($every, $boot, $logon) `
    -Principal $s4u -Settings $checkSettings -Force `
    -Description 'Orbit Home: ready, disk, dead jobs, backlog, backup and certificate age; Event Log, a notification and an off-box alert on change.' | Out-Null
Write-Host 'Registered Helix Health Check'

# 5. Caddy and coturn, when asked.
if ($CaddyExe) {
    if (-not $Caddyfile) { throw '-CaddyExe needs -Caddyfile.' }
    $caddy = New-ScheduledTaskAction -Execute $CaddyExe -WorkingDirectory (Split-Path $CaddyExe) `
        -Argument "run --config `"$Caddyfile`""
    Register-BootTask 'Helix Caddy' $caddy 'Caddy in front of Orbit Home.'
}
if ($TurnScript) {
    $turn = New-ScheduledTaskAction -Execute $powershell `
        -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$TurnScript`""
    $turnTrigger = New-ScheduledTaskTrigger -AtLogOn -User $user
    Register-ScheduledTask -TaskName 'Helix TURN' -Action $turn -Trigger $turnTrigger `
        -Principal $interactive -Force -Description 'coturn in WSL for Helix calls.' | Out-Null
    Write-Host 'Registered Helix TURN'
}

if ($StartNow) {
    Start-ScheduledTask -TaskName 'Helix Server'
    if ($CaddyExe) { Start-ScheduledTask -TaskName 'Helix Caddy' }
    Write-Host 'Started.'
} else {
    Write-Host ''
    Write-Host "Nothing was started. When the console server is stopped: Start-ScheduledTask 'Helix Server'"
}
