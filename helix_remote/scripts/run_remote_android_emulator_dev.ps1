$ErrorActionPreference = "Stop"

$BackendPort = if ($args[0]) { $args[0] } else { "8080" }
$DeviceId = if ($args[1]) { $args[1] } else { "emulator-5554" }

Push-Location app
try {
    flutter run -d $DeviceId `
        --no-enable-impeller `
        --dart-define=HELIX_REMOTE_PROFILE=android_emulator `
        --dart-define=HELIX_REMOTE_DEV_MODE=true `
        --dart-define=HELIX_REMOTE_HOST=10.0.2.2 `
        --dart-define=HELIX_REMOTE_PORT=$BackendPort
} finally {
    Pop-Location
}
