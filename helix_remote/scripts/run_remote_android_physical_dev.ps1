# `param` must be the first statement in the file, so the preference is set
# just below it rather than above.
param(
    [Parameter(Mandatory = $true)]
    [string]$TrustedHttpsHost,
    [int]$BackendPort = 443,
    [string]$DeviceId = ""
)

$ErrorActionPreference = "Stop"

$deviceArgs = @()
if ($DeviceId -ne "") {
    $deviceArgs = @("-d", $DeviceId)
}

Push-Location app
try {
    flutter run @deviceArgs `
        --dart-define=HELIX_REMOTE_PROFILE=android_physical `
        --dart-define=HELIX_REMOTE_HOST=$TrustedHttpsHost `
        --dart-define=HELIX_REMOTE_PORT=$BackendPort
} finally {
    Pop-Location
}
