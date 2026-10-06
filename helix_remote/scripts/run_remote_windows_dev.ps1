# Runs the Windows app from source. The app opens on the Helix Global sign-in
# page; to point it at a local server, open the hidden advanced mode (three
# taps bottom-right, two seconds apart, a fourth opens it) and enter the
# server address. A local server is `dart run bin/server.dart` in server/.
$ErrorActionPreference = "Stop"

Push-Location app
try {
    flutter run -d windows
} finally {
    Pop-Location
}
