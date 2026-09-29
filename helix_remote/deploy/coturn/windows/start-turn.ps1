<#
.SYNOPSIS
Runs the Helix TURN relay (coturn) in WSL on a Windows PC behind a home router.

.DESCRIPTION
Uses the same template and entrypoint as the Docker deployment
(deploy/coturn/turnserver.conf, deploy/coturn/entrypoint.sh), so the two
never drift. coturn has no native Windows build; WSL1 is used because it
shares Windows' network stack, so coturn binds the PC's real LAN address.

Settings are read the way the backend reads them - a process environment
variable wins, otherwise backend/.env - so coturn and the backend are always
handed the same shared secret:

  HELIX_REMOTE_TURN_SECRET  required; must match what the backend uses
  TURN_REALM                optional; defaults to the host in HELIX_REMOTE_TURN_URL

The secret is never put on a command line. It reaches WSL through WSLENV
(inherited environment), and the rendered config lives in a root-only file
under /run inside WSL.

Prerequisites (one-time, see deploy/coturn/README.md "Windows home PC"):
router port forwards and Windows Firewall rules for UDP/TCP 3478 and UDP
49160-49200, and `apt install coturn` in the WSL distro.

.PARAMETER PublicIp
The router's public IPv4. Detected automatically when omitted.

.PARAMETER LanIp
This PC's LAN IPv4 (the router forwards to it). Detected from the default
route when omitted.
#>
param(
    [string]$Distro = 'Ubuntu',
    [string]$PublicIp,
    [string]$LanIp
)

$ErrorActionPreference = 'Stop'

$coturnDir = Split-Path $PSScriptRoot -Parent
$repoRoot = Split-Path (Split-Path $coturnDir -Parent) -Parent
$envFile = Join-Path $repoRoot 'backend\.env'

function Get-Setting([string]$Name) {
    $fromProcess = [Environment]::GetEnvironmentVariable($Name)
    if ($fromProcess) { return $fromProcess }
    if (-not (Test-Path $envFile)) { return $null }
    $line = Get-Content $envFile |
        Where-Object { $_ -match "^\s*$([regex]::Escape($Name))\s*=" } |
        Select-Object -First 1
    if (-not $line) { return $null }
    $value = $line.Substring($line.IndexOf('=') + 1).Trim()
    if ($value.Length -ge 2 -and $value[0] -eq $value[-1] -and "`"'".Contains($value[0])) {
        $value = $value.Substring(1, $value.Length - 2)
    }
    return $value
}

$secret = Get-Setting 'HELIX_REMOTE_TURN_SECRET'
if (-not $secret) {
    throw "HELIX_REMOTE_TURN_SECRET is not set in the environment or $envFile."
}

$realm = Get-Setting 'TURN_REALM'
if (-not $realm) {
    $turnUrl = Get-Setting 'HELIX_REMOTE_TURN_URL'
    if ($turnUrl -match '^turns?:([^:?,]+)') { $realm = $Matches[1] }
}
if (-not $realm) {
    throw 'Set TURN_REALM (or HELIX_REMOTE_TURN_URL) in backend/.env.'
}

if (-not $LanIp) {
    $route = Get-NetRoute -DestinationPrefix '0.0.0.0/0' |
        Sort-Object RouteMetric, InterfaceMetric | Select-Object -First 1
    $LanIp = (Get-NetIPAddress -InterfaceIndex $route.InterfaceIndex -AddressFamily IPv4 |
        Select-Object -First 1).IPAddress
}
if (-not $PublicIp) {
    $PublicIp = (Invoke-RestMethod -Uri 'https://api.ipify.org' -TimeoutSec 10).Trim()
}

function ConvertTo-WslPath([string]$WindowsPath) {
    (& wsl.exe -d $Distro -- wslpath -a ($WindowsPath -replace '\\', '/')).Trim()
}

# The checkout has CRLF line endings on Windows (core.autocrlf), which sh
# cannot run, so LF copies are staged inside WSL rather than used in place.
$stage = '/run/helix-turn'
foreach ($file in @('entrypoint.sh', 'turnserver.conf')) {
    $wslSource = ConvertTo-WslPath (Join-Path $coturnDir $file)
    & wsl.exe -d $Distro -u root -- sh -c "mkdir -p $stage && chmod 700 $stage && tr -d '\r' < '$wslSource' > $stage/$file"
    if ($LASTEXITCODE -ne 0) { throw "Could not stage $file into WSL." }
}

& wsl.exe -d $Distro -u root -- sh -c 'pkill -x turnserver; sleep 1; true'

$env:HELIX_REMOTE_TURN_SECRET = $secret
$env:TURN_REALM = $realm
$env:TURN_EXTERNAL_IP = $PublicIp
$env:TURN_LOCAL_IP = $LanIp
$env:TURN_TEMPLATE = "$stage/turnserver.conf"
$env:TURN_RENDERED = "$stage/turnserver.rendered.conf"
# No certificate directory: plain turn: on 3478 only (see entrypoint.sh).
$env:TURN_CERT_DIR = "$stage/certs"
$env:WSLENV = 'HELIX_REMOTE_TURN_SECRET/u:TURN_REALM/u:TURN_EXTERNAL_IP/u:TURN_LOCAL_IP/u:TURN_TEMPLATE/u:TURN_RENDERED/u:TURN_CERT_DIR/u'

Start-Process -FilePath 'wsl.exe' -WindowStyle Hidden -ArgumentList @(
    '-d', $Distro, '-u', 'root', '--',
    'sh', '-c', "`"exec sh $stage/entrypoint.sh >> /var/log/helix-turn.log 2>&1`""
)

Start-Sleep -Seconds 3
$running = (& wsl.exe -d $Distro -u root -- sh -c 'pgrep -x turnserver >/dev/null && echo yes || echo no').Trim()
if ($running -ne 'yes') {
    Write-Host 'coturn did not start. Last log lines:' -ForegroundColor Red
    & wsl.exe -d $Distro -u root -- tail -n 20 /var/log/helix-turn.log
    exit 1
}

Write-Host "TURN relay running: realm $realm, public $PublicIp -> LAN $LanIp" -ForegroundColor Green
Write-Host 'Log: wsl -d Ubuntu -u root -- tail -f /var/log/helix-turn.log'
