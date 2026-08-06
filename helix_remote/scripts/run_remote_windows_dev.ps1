# `param` must be the first statement in the file, so the preference is set
# just below it rather than above.
param(
    [string]$BackendHost = "127.0.0.1",
    [int]$BackendPort = 8080
)

$ErrorActionPreference = "Stop"

Push-Location app
try {
    flutter run -d windows `
        --dart-define=HELIX_REMOTE_PROFILE=local_windows `
        --dart-define=HELIX_REMOTE_DEV_MODE=true `
        --dart-define=HELIX_REMOTE_HOST=$BackendHost `
        --dart-define=HELIX_REMOTE_PORT=$BackendPort
} finally {
    Pop-Location
}
