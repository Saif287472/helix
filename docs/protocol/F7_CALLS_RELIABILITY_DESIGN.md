# F7 — Reliable Direct Calls and Everyday Call UX

**Date:** 2026-06-25  
**Phase:** F7  
**Status:** Implemented

## Goal

Harden one-to-one calling for production use: process-closed push wake, per-device
push token management, adaptive media quality, exponential reconnect backoff,
Silence Unknown Callers enforcement, missed-call voice message queuing, TURN
credential clock-skew tolerance, call-quality metrics storage, and UX polish
(filter tabs, audio-only fallback, quality indicator).

---

## Architecture decisions

### 1. Push token management

**Problem:** The existing FCM push provider requires a manually supplied long-lived
access token. Client devices have no way to register their own push tokens.

**Solution:** Add a `device_push_tokens` table (backend schema v23). Each device
registers its FCM/APNs push token via `POST /api/v1/calls/push-token` on startup
and token rotation. The backend uses stored tokens when delivering call wake
notifications to offline devices.

- One token per device (UNIQUE on device_id); upserts replace stale tokens.
- Token deregistered on logout via `DELETE /api/v1/calls/push-token`.
- The backend tries stored tokens when an offer is sent to an offline device; if
  the FCM provider returns 404 (expired token), the token is automatically pruned.

### 2. Adaptive media quality

**Problem:** Calls continue at full video bitrate even when packet loss is severe,
degrading audio intelligibility.

**Solution:** `RemoteCallService` watches quality events and applies a two-tier fallback:

```
Tier 0 (normal)     → audio + video at engine default
Tier 1 (degraded)   → video disabled if packet_loss > 15% or RTT > 400ms
Tier 2 (poor)       → audio only (already at tier 1 with explicit disable)
```

Recovery hysteresis: two consecutive good samples (packet_loss < 5%, RTT < 200ms)
are required before re-enabling video to avoid rapid toggling.

Cooldown: 15 s between adaptation decisions.

### 3. Reconnect backoff

**Problem:** `restartIce()` is called immediately after `disconnectedGrace` expires
with no backoff between retries.

**Solution:** Add `_reconnectAttempt` counter and exponential delays:

| Attempt | Delay |
|---------|-------|
| 1       | 2 s   |
| 2       | 4 s   |
| 3       | 8 s   |
| 4       | 16 s  |
| ≥ 5     | 30 s  |

After 5 failed restarts without reaching `active` state, the call transitions to
`failed`. The attempt counter resets to 0 when the connection reaches `active`.

### 4. Silence Unknown Callers (F3 integration)

The `_shouldSilenceUnknownOffer` check was already wired; it now reliably reads the
DB setting and silences (records as missed) any offer from a non-contact when enabled.

### 5. Missed-call action

When a call completes with outcome `missed`, the service enqueues an outbound
operation (type `call.missed_action`) into `pending_operations` so the
`CallsTabScreen` can surface a "Call back" shortcut.

### 6. TURN credential improvements

- Added `clock_skew_tolerance_ms = 30000` (30 s) to HMAC-SHA1 TURN credential
  validation window on the backend.
- Added `X-Helix-Turn-Refresh-In` response header so clients know when to
  proactively refresh.
- Backend rate-limit window unchanged (10 requests / hour per account+device).

### 7. Privacy-safe call metrics

At call end, metrics are recorded in `call_metrics` (backend schema v23):

- `connection_type`: relay | direct | unknown
- `setup_time_ms`: time from `startOutgoingCall` to `active` state
- `reconnect_count`: number of successful ICE restarts
- `packet_loss_percent`: last sampled value
- `peer_rtt_ms`: last sampled round-trip time
- `call_outcome`: completed | missed | declined | failed | busy
- `duration_seconds`

No content, SDP, or identifiers beyond the call's own `call_id` are stored.

---

## Schema changes

### Backend v23

```sql
CREATE TABLE device_push_tokens (
  token_id     TEXT PRIMARY KEY,
  account_id   TEXT NOT NULL REFERENCES accounts(account_id) ON DELETE CASCADE,
  device_id    TEXT NOT NULL REFERENCES devices(device_id) ON DELETE CASCADE,
  push_token   TEXT NOT NULL,
  token_type   TEXT NOT NULL DEFAULT 'FCM',
  created_at   INTEGER NOT NULL,
  updated_at   INTEGER NOT NULL,
  UNIQUE(device_id)
);

CREATE TABLE call_metrics (
  metric_id            TEXT PRIMARY KEY,
  call_id              TEXT NOT NULL,
  account_id           TEXT NOT NULL,
  device_id            TEXT NOT NULL,
  connection_type      TEXT,
  setup_time_ms        INTEGER,
  reconnect_count      INTEGER NOT NULL DEFAULT 0,
  packet_loss_percent  REAL,
  peer_rtt_ms          REAL,
  call_outcome         TEXT,
  duration_seconds     INTEGER NOT NULL DEFAULT 0,
  recorded_at          INTEGER NOT NULL
);
CREATE INDEX idx_call_metrics_account ON call_metrics(account_id, recorded_at DESC);
```

---

## New REST endpoints

| Method | Path | Auth | Purpose |
|--------|------|------|---------|
| POST | `/api/v1/calls/push-token` | JWT | Register/rotate push token |
| DELETE | `/api/v1/calls/push-token` | JWT | Deregister token on logout |
| POST | `/api/v1/calls/metrics` | JWT | Upload call metrics at end |

---

## New capabilities

| Constant | String |
|----------|--------|
| `callsReliabilityV1` | `helix.remote.calls-reliability.v1` |
| `callPushWakeV1` | `helix.remote.call-push-wake.v1` |
| `backendSchemaV23` | `helix.remote.backend-schema.v23` |

---

## Test coverage

- `backend/test/calls_f7_test.dart`: push token CRUD, offline call wake, TURN
  credential issuance, multi-device ring + answered-elsewhere, call metrics upload
- `packages/helix_remote_calls/test/call_service_f7_test.dart`: adaptive media
  (video disable / re-enable), reconnect backoff, silence unknown callers, missed-call
  action queuing, call history with push token outcome
