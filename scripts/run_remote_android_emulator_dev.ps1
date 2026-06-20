$ErrorActionPreference = "Stop"

param(
    [int]$BackendPort = 8080,
    [string]$DeviceId = "emulator-5554"
)

Push-Location apps\helix_remote
try {
    flutter run -d $DeviceId `
        --dart-define=HELIX_REMOTE_PROFILE=android_emulator `
        --dart-define=HELIX_REMOTE_DEV_MODE=1 `
        --dart-define=HELIX_REMOTE_HOST=10.0.2.2 `
        --dart-define=HELIX_REMOTE_PORT=$BackendPort
} finally {
    Pop-Location
}
