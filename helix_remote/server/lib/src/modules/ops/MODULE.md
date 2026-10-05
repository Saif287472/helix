# ops module

Health, server info, legal documents, crash telemetry, metrics, app links,
and the operator settings behind them. Schema `ops` (`settings`: key/text
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
| `GET /v1/ops/metrics` | admin, or `HELIX_METRICS_TOKEN` | — |
| `GET /.well-known/assetlinks.json` | public | `ops.probe` |
| `GET /open` | public | `ops.probe` |

`metrics` also accepts `HELIX_METRICS_TOKEN` (constant-time compare; that
token opens nothing else) and refreshes the collected gauges
(`helix_jobs_dead`, `helix_mailbox_backlog`) before rendering.

`ready` runs every check in the `HealthRegistry` (platform: `database`,
`storage`; modules add their own) with a 3-second timeout each and answers
503 if any fails. It reports check names and booleans only.

## Settings

- `server_name` (default `HELIX_SERVER_NAME`), `maintenance`,
  `federation_enabled`, and `flag.<name>` for each allow-listed flag in
  `OpsApi.knownFlags` (`crash_reporting_upload`, `minimal_analytics`,
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

## App links

`assetlinks.json` lists the valid `AB:CD:…` fingerprints in
`HELIX_ANDROID_CERT_SHA256` for `com.helix.remote`. `/open` is the
landing page for `https://<host>/open#HLX-(INV|REC|GRP)-…`. The code stays
in the fragment, which browsers never send. The page is served only at
`/open` and `/open/` (the paths the app's link filter claims; nothing below
them), with a strict CSP that includes `frame-ancestors 'none'` plus
`X-Frame-Options: DENY`, so the one-tap page cannot be framed. The pipeline
adds `nosniff`, `no-store` and `no-referrer` to every response.
