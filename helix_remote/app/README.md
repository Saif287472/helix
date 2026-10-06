# helix_remote (app)

The Helix Remote client: an end-to-end encrypted messenger for Android and
Windows that talks to a Helix Remote server (`../server`), either the Helix
Global server or a self-hosted one. Accounts are phone-number based; an account
can be signed in on several devices at once. The UI is English-only and
light-only.

It is one package of the `helix_remote/` pub workspace. Start with
[`../../AGENTS.md`](../../AGENTS.md), [`MODULE.md`](MODULE.md) (the layout, the
import rules and every decision in it) and the docs in [`../docs/`](../docs/).

## Layout

- `lib/main.dart` - entry point: zones, error reporting, the FCM background
  handler, the one `MaterialApp.router`.
- `lib/core/` - wiring only: the engine runtime, router and deep links,
  platform adapters, lifecycle, app lock, notifications, push.
- `lib/features/<feature>/` - `application/` (Riverpod state) and
  `presentation/` (widgets) for sign-in, home, chats, conversation, people,
  calls, groups, settings, devices, backup and profile.
- `lib/shared/widgets/` - cross-feature widgets.
- The messaging logic lives in the workspace packages under `../packages/`
  (`helix_remote_engine`, `helix_remote_db`, `helix_remote_api`,
  `helix_remote_crypto`, `helix_remote_protocol`, `helix_remote_calls`,
  `helix_remote_ui`).

## Checks

From `helix_remote/`:

```powershell
flutter analyze
cd app; flutter test
```

or the full gate (format, codegen, analyze, and the app, admin, server and
package tests): `./scripts/verify.ps1` (Windows) or `./scripts/verify.sh`.

## Running

`../scripts/run_remote_windows_dev.ps1` runs the app on Windows from source; the
other `run_remote_*` scripts run it on an emulator or a phone. Point it at a
local server (`dart run bin/server.dart` in `../server`) in the hidden advanced
mode: three taps in the bottom-right corner of the sign-in page, then a fourth.

TLS pinning for Helix Global is off unless a build passes
`--dart-define=HELIX_GLOBAL_PINS=...` (see `MODULE.md`, "Pinning").

**Agents: do not build APKs (`flutter build apk`) unless the user asks.** The
user builds and installs them on a physical device; say whether a new APK is
needed instead (see `AGENTS.md`).
