# ops module

Schema: `ops` (no tables yet).

## Routes

| Route | Access | Rate limit |
|---|---|---|
| `GET /v1/health/live` | public | `ops.probe` 120 burst, 2/s per IP |
| `GET /v1/health/ready` | public | `ops.probe` |

`ready` runs every check in the `HealthRegistry` (platform: `database`,
`storage`; modules add their own) with a 3-second timeout each and answers
503 if any fails. It reports check names and booleans only.

## Later (Phase S6)

`GET /v1/server`, `GET /v1/server/legal`, `POST /v1/telemetry/crash`,
`GET /v1/ops/metrics`, maintenance mode, `/.well-known/assetlinks.json`,
`/open`.
