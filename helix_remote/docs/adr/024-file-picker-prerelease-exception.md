# ADR 024: File-picker prerelease dependency exception

Status: accepted (2026-08-07), review at each dependency update.

`file_picker ^12.0.0-beta.5` remains temporarily required because stable 11
depends on `win32 ^5`, while the current `share_plus ^13.1.0` requires
`win32 ^6`; Dart's solver correctly rejects the stable combination. The app
already uses the static API shared by the compatible release line.

This is not a general allowance for prereleases. CI lockfile enforcement, the
OSV scan, and client regression tests remain mandatory. Replace the pin with a
stable version as soon as a stable file-picker release resolves with win32 6;
then run the Android and Windows attachment selection matrix before release.
