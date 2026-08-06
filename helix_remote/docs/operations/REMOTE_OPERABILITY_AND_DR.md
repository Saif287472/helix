# Helix Remote Operability and Disaster Recovery

Status: Phase 19 repository baseline. This document defines the solo-owner
operating model and production runbooks. It does not claim that production
infrastructure exists; Phase 20 deployment must bind these controls to the
actual host, database, object storage, push provider, TURN provider, and status
page.

## Service-Level Indicators

Track these SLIs from `/api/v1/health/ready`, `/api/v1/ops/metrics`, edge logs,
and provider dashboards:

- API availability: percentage of non-5xx responses for `/api/v1/**`.
- Readiness: percentage of readiness probes reporting `ready`.
- Message enqueue latency: p50/p95/p99 for authenticated message send.
- Mailbox backlog: aggregate message count and newest/oldest message age.
- Push outbox health: counts of `PENDING`, `FAILED`, and `DLQ` outbox rows.
- WebSocket health: connected devices, reconnect rejections, and reconnect rate.
- Attachment storage: object count, total bytes, incomplete upload count.
- TURN health: credential success/error rate and provider reachability.
- Backup health: latest automated backup age and latest restore drill age.
- Cost health: database, object storage, TURN, push, and compute spend.

## Service-Level Objectives

Initial solo-owner SLOs:

- Monthly API/readiness availability: 99.5%.
- API 5xx rate over 5 minutes: less than 2%.
- Message enqueue p95: less than 500 ms under the documented capacity smoke.
- Push outbox `DLQ`: 0 during normal operation.
- WebSocket reconnect rejection rate: less than 5% over 5 minutes.
- TURN credential error rate: less than 2% over 5 minutes.
- Restore drill age: less than or equal to 30 days.

These are product-health objectives, not privacy/security claims.

## Alerts

Page the solo owner when any of these thresholds are crossed:

- Readiness fails for 2 consecutive minutes.
- API 5xx rate exceeds 2% for 5 minutes.
- API 429 rate exceeds 20% for 5 minutes, indicating rate-limit tuning or abuse.
- Push outbox `FAILED + DLQ` exceeds 10 rows.
- WebSocket reconnect rejections exceed 25 in 5 minutes.
- Incomplete attachment objects exceed 100.
- TURN is unconfigured or TURN credential errors exceed 2% in production.
- Latest successful automated backup is older than 24 hours.
- Latest restore drill is older than 30 days.
- Monthly spend reaches 80% and 100% of budget.

## Solo-Owner Incident Process

1. Acknowledge the alert and open an incident note with time, symptom, and scope.
2. Check `/api/v1/health/ready`, `/api/v1/ops/metrics`, edge logs, provider
   dashboards, and recent deploys.
3. Classify severity:
   - SEV1: data loss risk, authentication failure, full outage, security event.
   - SEV2: degraded messaging/files/calls/sync for many users.
   - SEV3: localized degradation, cost alert, or non-urgent restore drill issue.
4. Mitigate first: rollback, disable risky rollout, pause push/TURN integration,
   or raise rate limits only when abuse is ruled out.
5. Communicate on the status page for SEV1/SEV2, using content-free language.
6. Write a short post-incident note with cause, impact window, mitigation, and
   follow-up tests/docs.

## Server Environment Variables

Required and optional environment variables for `backend/bin/server.dart`:

| Variable | Required | Default | Purpose |
| --- | --- | --- | --- |
| `HELIX_REMOTE_JWT_SECRET` | Yes (prod) | n/a | JWT signing secret (≥ 32 bytes). Process exits 78 if absent outside dev mode. |
| `HELIX_REMOTE_DEV_MODE` | No | `0` | Set to `1` to bypass JWT and other production guards. Never use in production. |
| `HELIX_REMOTE_HOST` | No | `127.0.0.1` | Bind address for the HTTP server. |
| `HELIX_REMOTE_PORT` | No | `8080` | TCP port for the HTTP server. |
| `HELIX_REMOTE_DB_PATH` | No | `remote_backend.db` | Path to the SQLite database file. |
| `HELIX_REMOTE_DEPLOYMENT_TOPOLOGY` | No | `single_host` | Production guard: only `single_host` is supported by the SQLite baseline. |
| `HELIX_REMOTE_BACKEND_WORKERS` | No | `1` | Production guard: must be 1-4 while using SQLite. |
| `HELIX_REMOTE_JWT_KEY_RING_JSON` | No | none | JSON map of `kid` to signing secret during a rotation overlap. |
| `HELIX_REMOTE_JWT_ACTIVE_KID` | Conditional | none | Required when a JWT key ring is set; identifies the only key used to sign new tokens. |
| `HELIX_REMOTE_ATTACHMENTS_DIR` | No (warns) | none | Directory for attachment storage. If unset, file uploads/downloads are unavailable and a warning is printed on startup. Directory is created if it does not exist. |
| `HELIX_REMOTE_TURN_URL` | No (warns) | none | TURN server URL (e.g. `turn:turn.example.com:3478`). If unset, relay-only WebRTC calls fail and a warning is printed on startup. |
| `HELIX_REMOTE_TURN_SECRET` | No (warns) | none | TURN shared secret for credential generation. Required alongside `HELIX_REMOTE_TURN_URL`. |

### Start / stop server

```sh
# Minimum production start
export HELIX_REMOTE_JWT_SECRET="$(openssl rand -hex 32)"
export HELIX_REMOTE_ATTACHMENTS_DIR=/var/lib/helix-remote/attachments
export HELIX_REMOTE_TURN_URL=turn:turn.example.com:3478
export HELIX_REMOTE_TURN_SECRET=<shared_secret>
dart run backend/bin/server.dart

# Graceful stop: send SIGINT or SIGTERM
kill -SIGINT <pid>
```

### Rotate JWT key ring without forced logout

1. Add a new high-entropy secret to `HELIX_REMOTE_JWT_KEY_RING_JSON` and set
   `HELIX_REMOTE_JWT_ACTIVE_KID` to the new `kid`.
2. Restart each process while keeping the retiring key in the ring.
3. Wait longer than the longest issued access and refresh token lifetime.
4. Remove the retiring key in a subsequent deploy. Do not remove it early:
   that deliberately invalidates live sessions.

### Legacy single-key rotation (forces logout)

1. Generate a new secret: `openssl rand -hex 32`
2. Update the environment variable on the host/secret manager.
3. Restart the server process — all existing sessions become invalid and clients will re-authenticate on next request.

### Inspect health

```sh
curl https://<host>/api/v1/health/ready
curl https://<host>/api/v1/ops/metrics   # requires admin auth
```

### Clear dev data

Dev-mode only — never run against production data:
```sh
rm remote_backend.db
# Restart server to reinitialize schema
```

### Collect safe logs

The backend uses `RedactedLogger` which strips tokens, secrets, and message content. To export logs, collect stdout/stderr from the server process. The app's on-device `AppLogger` writes to a file that the user can export via Settings → Anomaly Log.

## Automated Backups

Production must configure automated backups before launch:

- Database: continuous WAL archiving or managed point-in-time recovery, plus a
  daily full logical backup retained for at least 30 days.
- Object storage: provider versioning, lifecycle protection, and cross-zone or
  equivalent durability.
- Configuration: versioned infrastructure config without secrets.
- Application backups: user backup envelopes remain opaque ciphertext; the
  server never receives backup keys or recovery phrases.

Backup jobs must emit a success/failure metric and alert when no successful run
has completed in 24 hours.

## Restore Drills and PITR

Run a restore drill at least every 30 days:

1. Restore the latest database backup into an isolated non-production database.
2. Restore object metadata and a small sample of opaque attachment objects.
3. Run migration and compatibility checks against the restored copy.
4. Verify account/device/message/attachment counts match expected backup
   metadata without reading plaintext user content.
5. Record restore point, duration, verification result, and gaps.

Database point-in-time recovery must document the requested timestamp, restored
schema version, compatible app/backend versions, and whether any writes after
the recovery point are intentionally discarded.

## Object Storage Recovery

Object storage must enable versioning or equivalent durability. Recovery order:

1. Stop object lifecycle deletion jobs.
2. Restore missing object versions or provider snapshot.
3. Compare aggregate object count and bytes against database attachment rows.
4. Re-run orphan cleanup only after the database/object set is consistent.

Never inspect or log private media bytes.

## Redis Loss

Redis is not a source of truth. If introduced later, it may cache rate-limit,
presence, queue, or session hints only. On Redis loss:

- Continue serving from the database where possible.
- Treat all Redis-backed state as rebuildable.
- Recreate rate-limit buckets conservatively.
- Do not store message ciphertext, keys, account deletion state, or trust state
  only in Redis.

## WebSocket Reconnect Storms

The backend rejects excessive per-device reconnect attempts and reports
aggregate reconnect stats in admin metrics. During a storm:

- Confirm whether the trigger is a deploy, mobile network issue, or provider
  outage.
- Prefer client backoff and rollout pause over raising limits.
- Alert if rejection counts exceed the Phase 19 threshold.

## Push Provider Outage

Push notifications are best-effort wake hints and must not include plaintext.
When the provider is unavailable, outbox processing retries and moves exhausted
items to `DLQ`. During outage:

- Confirm messages are still stored/synced through the mailbox path.
- Watch `FAILED` and `DLQ` counts.
- Resume the provider, then replay pending safe notification hints only.
- Do not insert message bodies, filenames, SDP, tokens, or backup secrets into
  push payloads.

## TURN Outage and Regional Fallback

TURN is required for some Remote calls but does not carry message content in the
backend database. During outage:

- Fail credential issuance closed when the provider secret/config is invalid.
- Prefer a configured secondary region/provider.
- Communicate call degradation while keeping messaging/files/sync status
  separate.
- Track TURN credential errors and usage cost.

## Rate-Limit Tuning

Default rate limits are conservative for a solo-operated service. Tune only with
metrics:

- Raise limits for legitimate 429s only after checking abuse reports and edge
  logs.
- Lower limits for abuse without affecting deletion/export/security endpoints.
- Preserve per-feature quotas for TURN and group operations.

## Capacity Tests

Capacity smoke coverage must exercise:

- Messages: direct and multi-device message enqueue/sync.
- Files: upload reservation, object accounting, orphan lifecycle.
- Calls: TURN credential issuance and signaling outbox behavior.
- Sync: reconnect and cursor/backlog behavior.

The repository test suite includes a Phase 19 capacity smoke that validates
aggregate counters without reading plaintext user content. Full production load
tests should be added once Phase 20 staging infrastructure exists.

## Scaling Strategy

Do not extract brokers or partition/archive data prematurely.

- Database partitioning/archive is allowed only when metrics show table growth,
  query latency, or backup/restore windows exceeding SLOs.
- Broker extraction is allowed only when the modular monolith proves a concrete
  bottleneck such as outbox latency or WebSocket fan-out pressure.
- Any extraction requires an ADR, compatibility plan, and rollback plan.

## Zero-Downtime Migrations

Use expand/contract migrations:

1. Expand schema with backward-compatible nullable/default columns or new tables.
2. Deploy code that writes both old and new shapes when needed.
3. Backfill in bounded batches.
4. Flip reads after verification.
5. Contract old schema only after all supported clients and backend versions no
   longer need it.

Migrations must preserve encrypted payloads, deletion state, trust state, and
account/device identity.

## Rolling Compatibility

During rolling upgrades:

- Keep `/api/v1/` backward compatible.
- Preserve realtime envelope graceful degradation for unknown event types and
  higher schema versions.
- Keep old clients able to sync/delete/export account data.
- Add compatibility fixtures before changing request/response shapes.

## Emergency Rollback

Follow `docs/workflows/RELEASE_ROLLBACK.md`:

- Roll back the binary/container first if the schema is backward compatible.
- If a migration is not backward compatible, use the documented restore/PITR
  path and communicate possible write loss after the restore point.
- Never roll back by deleting user data or weakening crypto/auth checks.

## Status Page and User Communication

Status updates must be short, factual, and content-free:

- Name the affected capability: messaging, files, calls, sync, account access,
  exports/deletion, or backups.
- Give start time, current status, and next update time.
- Do not mention user identifiers, message content, private media, or provider
  secrets.

## Top Failure-Mode Runbooks

- Database down or corrupt: fail readiness, stop writes if necessary, restore
  from backup/PITR, verify aggregate counts, then reopen traffic.
- Object storage unavailable: pause uploads/downloads, preserve message sync,
  recover object versions, verify aggregate counts.
- Push outage: retry safe wake hints, monitor DLQ, keep mailbox sync available.
- TURN outage: route to fallback region/provider or declare call degradation.
- Reconnect storm: pause rollout, verify client backoff, watch rejection stats.
- Rate-limit incident: distinguish abuse from legitimate traffic, tune narrowly.
- Bad deploy: rollback binary, preserve compatibility, run verification before
  redeploy.
- Account deletion/export incident: stop affected path, preserve audit evidence,
  repair without exposing plaintext or private media.
