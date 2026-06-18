# Helix Local Privacy Verification Checklist

## Identity And Trust

- Identity reset rotates the fingerprint.
- Trusted nickname with a changed fingerprint shows an impersonation warning.
- Secret sentence plaintext is not stored after setup.
- Full fingerprints are visible for audit but are not logged.

## Local-Only Networking

- App remains usable with internet disconnected.
- No Remote API endpoint is called during Local use.
- Discovery and messaging stay on LAN transports.
- Firewall or client-isolation diagnostics are visible when discovery fails.

## Retention And Wipe

- Chat messages do not survive restart.
- Panic wipe clears Local secure storage keys only.
- Panic wipe deletes Local database, WAL, SHM, cache, temp, logs, and `.part`
  files.
- Panic wipe during calls releases microphone and camera.
- Panic wipe during transfer deletes partial transfer files.
- Export warnings state that externally exported files cannot be recalled.

## Platform

- Android foreground service notification is product-scoped to Helix Local.
- Android camera and microphone permissions are used only for QR/calls.
- Windows executable name and metadata identify Helix Local.
- Windows tray/close behavior does not leak message contents.
