<#
.SYNOPSIS
Rotates the backend's JWT signing secret and the TURN shared secret in
backend/.env, without printing either.

.DESCRIPTION
Run it on the PC that hosts the backend, then restart coturn and the backend:

    .\scripts\rotate_secrets.ps1
    .\deploy\coturn\windows\stop-turn.ps1
    .\deploy\coturn\windows\start-turn.ps1
    # then restart `dart run bin/server.dart` in backend/

What changes:
- HELIX_REMOTE_JWT_SECRET gets a new random value. Every session token issued
  with the old secret stops working at once. Devices notice on their next
  request and sign in again with their own device key - no SMS code, nothing
  for users to do. Admin console sessions have to sign in again.
- HELIX_REMOTE_JWT_KEY_RING_JSON / HELIX_REMOTE_JWT_ACTIVE_KID are removed if
  present, so no old key keeps verifying tokens.
- HELIX_REMOTE_TURN_SECRET gets a new random value. start-turn.ps1 reads it
  from the same file, so coturn and the backend stay in step once both are
  restarted. Calls in progress during the restart drop.

The previous file is kept as backend/.env.bak-<timestamp> (ignored by git).
Delete it once the backend and coturn are running on the new secrets.
#>
[CmdletBinding()]
param(
    [string]$EnvFile = (Join-Path (Split-Path $PSScriptRoot -Parent) 'backend\.env')
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $EnvFile)) {
    throw "No .env file at $EnvFile."
}

function New-Secret {
    $bytes = New-Object byte[] 48
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    return [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

$rotate = [ordered]@{
    'HELIX_REMOTE_JWT_SECRET'  = New-Secret
    'HELIX_REMOTE_TURN_SECRET' = New-Secret
}
$remove = @('HELIX_REMOTE_JWT_KEY_RING_JSON', 'HELIX_REMOTE_JWT_ACTIVE_KID')

# A value set in the environment wins over .env for both the backend and
# start-turn.ps1, which would silently keep the old secret in use.
foreach ($name in @($rotate.Keys) + $remove) {
    foreach ($scope in 'Process', 'User', 'Machine') {
        if ([Environment]::GetEnvironmentVariable($name, $scope)) {
            Write-Warning "$name is also set as a $scope environment variable, which overrides .env. Remove it there too."
        }
    }
}

$raw = [IO.File]::ReadAllText($EnvFile)
$newline = if ($raw.Contains("`r`n")) { "`r`n" } else { "`n" }
$lines = $raw -split "\r?\n"
if ($lines.Length -gt 0 -and $lines[-1] -eq '') { $lines = $lines[0..($lines.Length - 2)] }

$seen = @{}
$out = New-Object System.Collections.Generic.List[string]
foreach ($line in $lines) {
    $match = [regex]::Match($line, '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=')
    if ($match.Success) {
        $name = $match.Groups[1].Value
        if ($remove -contains $name) { continue }
        if ($rotate.Contains($name)) {
            if (-not $seen.ContainsKey($name)) {
                $out.Add("$name=$($rotate[$name])")
                $seen[$name] = $true
            }
            continue
        }
    }
    $out.Add($line)
}
foreach ($name in $rotate.Keys) {
    if (-not $seen.ContainsKey($name)) { $out.Add("$name=$($rotate[$name])") }
}

$backup = "$EnvFile.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
Copy-Item $EnvFile $backup
[IO.File]::WriteAllText($EnvFile, (($out -join $newline) + $newline), (New-Object System.Text.UTF8Encoding($false)))

Write-Host "Rotated HELIX_REMOTE_JWT_SECRET and HELIX_REMOTE_TURN_SECRET in $EnvFile."
Write-Host "Old file kept at $backup - delete it once everything runs on the new secrets."
Write-Host 'Next: restart coturn (stop-turn.ps1, start-turn.ps1), then the backend.'
