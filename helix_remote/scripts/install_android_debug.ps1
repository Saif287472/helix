param(
  [string[]]$Devices,
  [switch]$Fresh
)

$ErrorActionPreference = "Stop"

function Require-Command($Name) {
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    throw "Required command '$Name' was not found in PATH."
  }
}

Require-Command flutter
Require-Command adb

$ProjectRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $ProjectRoot

Write-Host "Building debug APK..."
flutter build apk --debug

$Apk = Join-Path $ProjectRoot "build\app\outputs\flutter-apk\app-debug.apk"
if (-not (Test-Path $Apk)) {
  throw "Debug APK was not found at $Apk"
}

if (-not $Devices -or $Devices.Count -eq 0) {
  Write-Host "Detecting Android devices..."
  $flutterDevicesJson = flutter devices --machine
  $flutterDevices = $flutterDevicesJson | ConvertFrom-Json
  $Devices = @(
    $flutterDevices |
      Where-Object { $_.targetPlatform -like "android-*" -and $_.emulator -eq $false } |
      Select-Object -ExpandProperty id -Unique
  )
}

if (-not $Devices -or $Devices.Count -eq 0) {
  throw "No Android devices were detected. Check 'adb devices' or pass -Devices explicitly."
}

Write-Host "Installing $Apk to $($Devices.Count) device(s)..."

foreach ($Device in $Devices) {
  Write-Host ""
  Write-Host "Device: $Device"

  if ($Fresh) {
    Write-Host "Uninstalling existing app..."
    adb -s $Device uninstall com.helix.remote | Out-Host
  }

  adb -s $Device install -r -d $Apk | Out-Host
}

Write-Host ""
Write-Host "Done."
