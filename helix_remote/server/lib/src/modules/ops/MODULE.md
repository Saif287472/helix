# ops module

Health, server info, legal documents, crash telemetry, metrics, app links, the
theme-pack folder, and the operator settings behind them. Schema `ops` (`settings`: key/text
value). Facade: `api.dart` (`OpsApi`; the admin module and, from S6b,
federation use it).

## Routes

| Route | Access | Rate limit |
|---|---|---|
| `GET /v1/health/live` | public | `ops.probe` 120 burst, 2/s per IP |
| `GET /v1/health/ready` | public | `ops.probe` |
| `GET /v1/server` | public | `ops.probe` |
| `GET /v1/server/legal` | public | `ops.probe` |
| `POST /v1/telemetry/crash` | device | `ops.crash` 10/hour per device, 96 KiB |
| `POST /v1/telemetry/anomalies` | device | `ops.anomalies` 120/hour per device, 512 KiB |
| `GET /v1/ops/metrics` | admin, or `HELIX_METRICS_TOKEN` | — |
| `GET /.well-known/assetlinks.json` | public | `ops.probe` |
| `GET /open` | public | `ops.probe` |
| `GET /v1/packs` | public | `packs.list` 60 burst, 1/s per IP |
| `GET /v1/packs/{pack_id}/revisions/{revision}/manifest` | public | `packs.manifest` 120 burst, 2/s per IP |
| `GET /v1/packs/{pack_id}/revisions/{revision}/files/{digest}` | public | `packs.file` 60 burst, 1/s per IP |

`metrics` also accepts `HELIX_METRICS_TOKEN` (constant-time compare; that
token opens nothing else) and refreshes the collected gauges
(`helix_jobs_dead`, `helix_mailbox_backlog`, `helix_storage_used_bytes`)
before rendering.

`ready` runs every check in the `HealthRegistry` (platform: `database`,
`storage`; modules add their own) with a 3-second timeout each and answers
503 if any fails. It reports check names and booleans only.

## Settings

- `server_name` (default `HELIX_SERVER_NAME`), `maintenance`,
  `federation_enabled`, and `flag.<name>` for each allow-listed flag in
  `OpsApi.knownFlags` (`crash_reporting_upload`, `minimal_analytics`, `billing_enabled`,
  `group_calls`; all off by default). Unknown flags cannot be set.
- Cached per node for 30 seconds, and dropped on every node when a change
  is published on the `ops.settings` bus topic after commit, or when the bus
  reports `platform.resync` (its connection came back, hints were missed).
- `HELIX_FEDERATION_ENABLED` (the default of `federation_enabled`) uses the
  shared boolean parser (`1/true/yes`, `0/false/no`).
- `GET /v1/server` lists the flags as `features`. `federation_domain` is
  the public host while federation is on.

## Maintenance mode

The module implements `ProvidesMaintenance`. While it is on, the HTTP
pipeline answers `maintenance` (503, `Retry-After: 300`) to everything
except `/v1/health`, `/v1/ops` and `/v1/admin`.

## Crash reports

Only while `crash_reporting_upload` is on (otherwise `forbidden`). A report
becomes one redacted `client_crash` warning (snake_case keys only, values
capped at 2,000 characters) and a counter. Nothing is stored.

## Anomaly reports

The apps' anomaly logs, in batches of up to 50 (crashes, failed actions,
failed requests, unexpected states). No opt-in and no flag: every build
sends them (the owner's decision, 2026-10-21); a debug build sends whole
messages and stacks, a release build sanitised ones. Each entry becomes one
redacted `client_anomaly` warning (kind, where, device, app version,
platform, time, message, stack, snake_case fields; every value capped) and
a counter, `helix_client_anomalies_total`. Nothing is stored. Watch them
with `dart run tool/anomalies.dart` on the server's log file, or in the
console's output and the admin console's Logs.

## App links

`assetlinks.json` lists the valid `AB:CD:…` fingerprints in
`HELIX_ANDROID_CERT_SHA256` for `com.helix.remote`. `/open` is the
landing page for `https://<host>/open#HLX-(INV|REC|GRP)-…`. The code stays
in the fragment, which browsers never send. The page is served only at
`/open` and `/open/` (the paths the app's link filter claims; nothing below
them), with a strict CSP that includes `frame-ancestors 'none'` plus
`X-Frame-Options: DENY`, so the one-tap page cannot be framed. The pipeline
adds `nosniff`, `no-store` and `no-referrer` to every response.

`/u/<~name>` is the landing page for a share link — the one link a user sends
to somebody who is not in their phone book (`https://<host>/u/<name>`). It is
**one static document for any name**: it never looks the name up, so it cannot
become a way to list the accounts on the server. Whether a `~name` exists is
answered only to a signed-in account, by `GET /v1/people/by-name/{name}`, which
honours "Find me by ~name" and blocking. The name comes from
`location.pathname`, which the browser already has, so the page does not echo
it. Served at `/u/<name>` and `/u/<name>/` and nowhere deeper, with the same
headers as `/open`.

## Theme packs

`HELIX_PACKS_DIR` names a folder of packs devices download and judge for
themselves (`docs/product/THEME_PACK_FORMAT.md`, ADR-033). `pack_host.dart`
reads it, and that is the server's whole knowledge of a pack: it never parses a
manifest, so a hostile or broken folder cannot make it approve anything, and a
device still runs `checkOrbitPack` over the bytes it gets. The layout is what
`dart run tool/theme_pack_tool.dart publish` writes:

    <root>/<pack id>/r<revision>/manifest.json
    <root>/<pack id>/r<revision>/files/<sha256 of that file>

- The list is the folder: id, revision, manifest bytes, total bytes, mtime. One
  walk answers every request for 10 seconds (`PackHost.defaultListLifetime`),
  and requests that arrive during a walk share it; a pack published meanwhile
  appears when the lifetime ends. A folder timestamp is not used instead:
  Windows updates a directory's mtime for a file added to it but not for a
  subdirectory, and only to the second, so it would miss a publish. Manifest
  and file reads always check the disk, so a stale entry can only be a 404,
  never a wrong byte. A revision folder with no manifest is not listed, so an
  interrupted publish advertises nothing. It carries no display name — the name
  a device shows comes from the pack's signed theme document, and an unsigned
  one here could be forged.
- The manifest route streams the file exactly as published. The file route
  selects by lowercase-hex SHA-256 rather than by the manifest's path, so there
  is no path to sanitise, a file in two revisions is stored once, and a client
  cannot ask for bytes no manifest named. A `{revision}` of `01` is revision 1.
- Anything that is not a pack slug, an `r<digits>` revision or a 64-hex digest
  is a 404 before the folder is touched, and every path that is resolved is
  checked to stay inside it. A manifest over 64 KiB or a file over 8 MiB is 413
  — the caps the format itself refuses at, so a pack past one was never
  installable. No folder set: an empty list and 404s, and `ready` stays green.
- These are public routes, rate-limited per client IP, needing no session, so
  they give no account away. The pipeline's `no-store` covers them like
  everything else; a pack revision never changes, so the device's own cache is
  what avoids a repeat download.
