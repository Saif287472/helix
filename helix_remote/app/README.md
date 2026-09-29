# helix_remote (app)

The Helix Remote client: an end-to-end encrypted messenger for Android and
Windows that talks to a Helix Remote backend (`../backend`), either the Helix
Global server or a self-hosted one. Accounts are phone-number based with a
required password; an account can be signed in on several devices at once.
The UI is English-only and light-only.

It is one package of the `helix_remote/` pub workspace. Start with
[`../../AGENTS.md`](../../AGENTS.md) and the docs in [`../docs/`](../docs/).

## Layout

- `lib/main.dart` - entry point.
- `lib/app/` - composition root, runtime, messaging service, REST/sync
  gateways, password vault and history-backup codec.
- `lib/screens/`, `lib/widgets/`, `lib/services/` - UI and platform services.
- Shared logic lives in the workspace packages under `../packages/`
  (`helix_remote_crypto`, `helix_remote_storage`, `helix_remote_sync`,
  `helix_remote_api`, `helix_remote_calls`, `helix_remote_groups`,
  `helix_remote_ui`, ...).

## Checks

From `helix_remote/`:

```powershell
flutter analyze
cd app; flutter test
```

or the full gate (format, analyze, and the app, admin, backend and package
tests): `./scripts/verify.ps1` (Windows) or `./scripts/verify.sh`.

## Running

`../scripts/run_remote_windows_dev.ps1` runs the app on Windows against a local
backend; `../scripts/start_remote_backend_dev.ps1` starts a dev backend.

**Agents: do not build APKs (`flutter build apk`) unless the user asks.** The
user builds and installs them on a physical device; say whether a new APK is
needed instead (see `AGENTS.md`).
