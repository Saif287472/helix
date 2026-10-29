# Runs the app on a connected Android phone. It opens on the Orbit Home
# sign-in page; a personal server is entered in the hidden advanced mode
# (three taps bottom-right, two seconds apart, a fourth opens it).
param(
    [string]$DeviceId = ""
)

$ErrorActionPreference = "Stop"

$deviceArgs = @()
if ($DeviceId -ne "") {
    $deviceArgs = @("-d", $DeviceId)
}

Push-Location app
try {
    flutter run @deviceArgs
} finally {
    Pop-Location
}
