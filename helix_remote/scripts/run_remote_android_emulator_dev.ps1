# Runs the app on an Android emulator. The emulator reaches a server on this
# PC at http://10.0.2.2:<port>; enter that address in the app's hidden
# advanced mode (three taps bottom-right, two seconds apart, a fourth opens it).
$ErrorActionPreference = "Stop"

$DeviceId = if ($args[0]) { $args[0] } else { "emulator-5554" }

Push-Location app
try {
    flutter run -d $DeviceId --no-enable-impeller
} finally {
    Pop-Location
}
