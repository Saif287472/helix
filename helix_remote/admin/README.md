# helix_admin (admin console)

Helix Admin: the Flutter operator console for a Helix Remote backend
(`../backend`), including the Helix Global server. It signs in with the
server's admin password and uses the backend's `/api/v1/admin/*` and
`/api/v1/ops/*` endpoints for the dashboard, users, invites, reports,
configuration, operations and the live log stream. Light theme only.

It is one package of the `helix_remote/` pub workspace. Start with
[`../../AGENTS.md`](../../AGENTS.md) and the docs in [`../docs/`](../docs/).

## Layout

- `lib/main.dart` - entry point.
- `lib/admin_client.dart` - HTTP client for the backend admin/ops API.
- `lib/screens/` - login, lock screen and the tabs (dashboard, users, invites,
  reports, config, ops, logs).

## Checks

From `helix_remote/`:

```powershell
flutter analyze
cd admin; flutter test
```

or the full gate: `./scripts/verify.ps1` (Windows) or `./scripts/verify.sh`.

**Agents: do not build APKs (`flutter build apk`) unless the user asks.** The
user builds and installs them on a physical device; say whether a new APK is
needed instead (see `AGENTS.md`).
