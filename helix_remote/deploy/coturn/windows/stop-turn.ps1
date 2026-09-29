<#
.SYNOPSIS
Stops the Helix TURN relay started by start-turn.ps1 and removes its
rendered config (which holds the shared secret).
#>
param([string]$Distro = 'Ubuntu')

& wsl.exe -d $Distro -u root -- sh -c 'pkill -x turnserver; rm -f /run/helix-turn/turnserver.rendered.conf; true'
Write-Host 'TURN relay stopped.'
