param(
    [string]$HostAddress = "127.0.0.1",
    [int]$Port = 8080,
    [string]$DatabasePath = "build\helix_remote_backend_dev.db"
)

$ErrorActionPreference = "Stop"

$env:HELIX_REMOTE_DEV_MODE = "1"
$env:HELIX_REMOTE_HOST = $HostAddress
$env:HELIX_REMOTE_PORT = "$Port"
$env:HELIX_REMOTE_DB_PATH = $DatabasePath

Push-Location backend
try {
    dart run bin/server.dart
} finally {
    Pop-Location
}
