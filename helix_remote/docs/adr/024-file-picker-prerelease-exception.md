# ADR 024: File-picker prerelease dependency exception

Status: superseded (2026-09-26) by the stable `file_picker ^13.1.0` bump.

`file_picker ^12.0.0-beta.5` remains temporarily required because stable 11
depends on `win32 ^5`, while the current `share_plus ^13.1.0` requires
`win32 ^6`; Dart's solver correctly rejects the stable combination. The app
already uses the static API shared by the compatible release line.

This is not a general allowance for prereleases. CI lockfile enforcement, the
OSV scan, and client regression tests remain mandatory. Replace the pin with a
stable version as soon as a stable file-picker release resolves with win32 6;
then run the Android and Windows attachment selection matrix before release.

## Amendment (2026-08-07): pinned exactly, not by caret

The declaration was `^12.0.0-beta.5`, which is a range, not a pin. A caret on a
prerelease admits every later prerelease of the same major — and that drift had
already happened: `beta.5` was declared and `beta.7` resolved, which is the
observation MED-7 was recorded from.

The lockfile pins what CI builds, but `pubspec.yaml` is what a fresh
`pub upgrade` obeys, so the two were saying different things. The declaration is
now `file_picker: 12.0.0-beta.7` — the same version already locked, so nothing
resolves differently, and the range that permitted the drift is gone.

When the win32 conflict clears, this becomes an ordinary version bump: change
the pin, re-lock, run the attachment matrix, and retire this ADR.

## Retired (2026-09-26)

Stable `file_picker` 13.1.0 resolves with `share_plus ^13.1.0`, so the
declaration is now the ordinary range `file_picker: ^13.1.0` and this exception
no longer applies. 13.0 removed `lockParentWindow` from the top-level calls
(now `WindowsOptions.lockParentWindow`) and `saveFile` returns a `Uri` instead
of a path. The Android and Windows attachment pick/export matrix still needs a
manual pass on a device.
