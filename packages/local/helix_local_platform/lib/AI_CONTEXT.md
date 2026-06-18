# Platform Context

## Responsibility

Platform owns OS integration adapters for Android foreground service behavior,
Windows tray integration, diagnostics gateway plumbing, and local notification
bridges.

## Public Entry Points

- `platform/android_foreground.dart`
- `platform/windows_tray.dart`
- `infrastructure/platform/*`

## Dependencies

Platform may depend on Flutter plugins, method channels, and domain/application
gateway contracts. It must not own protocol semantics, trust decisions, message
storage, cryptography, or transport frame parsing.

## Invariants

- Platform adapters must not log message contents, keys, private media bytes, or
  full fingerprints.
- Foreground service state must reflect active connections/calls accurately.
- Notification text must remain privacy-preserving.
- Windows tray lifecycle must not outlive disposed app services.

## Required Tests

- Provider/app bootstrap smoke tests where platform adapters are wired through
  fakes or no-op gateways.

## High-Risk Areas

Android service lifecycle, notification privacy, Windows tray disposal, plugin
availability on unsupported platforms, and permission-sensitive call behavior.
