$ErrorActionPreference = "Stop"

param(
    [string]$BackendHost = "127.0.0.1",
    [int]$BackendPort = 8080
)

Push-Location apps\helix_remote
try {
    flutter run -d windows `
        --dart-define=HELIX_REMOTE_PROFILE=local_windows `
        --dart-define=HELIX_REMOTE_DEV_MODE=1 `
        --dart-define=HELIX_REMOTE_HOST=$BackendHost `
        --dart-define=HELIX_REMOTE_PORT=$BackendPort
} finally {
    Pop-Location
}
