$ErrorActionPreference = "Stop"

param(
    [Parameter(Mandatory = $true)]
    [string]$TrustedHttpsHost,
    [int]$BackendPort = 443,
    [string]$DeviceId = ""
)

$deviceArgs = @()
if ($DeviceId -ne "") {
    $deviceArgs = @("-d", $DeviceId)
}

Push-Location apps\helix_remote
try {
    flutter run @deviceArgs `
        --dart-define=HELIX_REMOTE_PROFILE=android_physical `
        --dart-define=HELIX_REMOTE_HOST=$TrustedHttpsHost `
        --dart-define=HELIX_REMOTE_PORT=$BackendPort
} finally {
    Pop-Location
}
