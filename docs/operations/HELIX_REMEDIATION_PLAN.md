# Helix Remote — Diagnostic Report & Remediation Plan

**Date:** 2026-08-05
**Inputs:** 3 call/attachment screenshots, 3 anomaly logs (`helix_remote_anomaly_log.txt`,
`helix_remote_anomaly_log1.txt`, `DOC20260805WA0000.pdf` — 17 sessions, 2026-08-03 → 08-05).
**Analysed against:** `origin/main` @ `d0f7bd7`.
**Reconciled against:** the structural-upgrade branch (see
[Reconciliation notes](#reconciliation-notes--what-changed-since-d0f7bd7)).
**Status:** findings stand. Remediation status per item:

| # | Status |
|---|---|
| P0-1 | Code hardening **done** (typed setup failures, no silent STUN fallback). **Deploying coturn on the VPS is still open — this is yours; nothing in the repo can fix it.** |
| P0-2 | **Done** — `client_max_body_size 110m`, request buffering off, long `send_timeout`. Needs an nginx reload on the VPS to take effect. |
| P0-3 | **Done** — budget metered per distinct hash (5000/day) rather than per request, 1000-hash batches, dedupe, `full_sync` caching, partial answers with `retry_after_seconds`. |
| P1-1 | Serialisation and within-page backpressure **done** (see below). **The `1002` root cause is still not established** — the 4-step diagnostic procedure needs the live server and is yours. |
| P1-2 | **Done** — limits are env-configurable, published via `/server/info`, and both sides now measure ciphertext. |
| P1-3 | **Done** — call-setup failures are typed and awaited at the UI boundary. |
| P2-1 | Open — vendor-side (IP whitelist / sender ID). Yours. |
| P2-2, P2-3, P3-1 | Open. |

All code paths below are relative to `helix_remote/`.

---

## How to read this

Every claim below is tagged:

- **[CONFIRMED]** — verified by reading the code at the cited line, or stated explicitly in the logs.
- **[HYPOTHESIS]** — consistent with the evidence but not proven; a diagnostic step is given.

I have deliberately **not** guessed at the WebSocket `1002` root cause. It is real and recurring,
but the logs do not contain enough to isolate it, so §P1-1 gives ranked hypotheses and a
decision procedure instead of a fix to apply blind.

---

## Executive summary — prioritized

| # | Issue | Severity | Confidence | Type |
|---|-------|----------|-----------|------|
| **P0-1** | TURN not configured on server → **100% of calls fail** | Critical | CONFIRMED | Infra (+ code hardening) |
| **P0-2** | nginx `client_max_body_size` defaults to **1 MB** → caps every attachment far below the app's own limit | Critical | CONFIRMED | Infra |
| **P0-3** | Contact sync hard-fails >500 hashes; the **5-per-day** cap makes naive chunking fail too | Critical | CONFIRMED | Code (design) |
| **P1-1** | WebSocket closes with `1002` every 1–3 min → reconnect churn | High | CONFIRMED (symptom) / HYPOTHESIS (cause) | Code |
| **P1-2** | Attachment limit is enforced in 4 inconsistent places; raising it naively breaks 3 of them | High | CONFIRMED | Code |
| **P1-3** | Call-setup failures surface as **uncaught** async exceptions + a generic error message | High | CONFIRMED | Code |
| **P2-1** | SMS OTP delivery failing at the vendor (IP not whitelisted, `is_masking` null) | Medium | CONFIRMED | Infra/vendor |
| **P2-2** | X3DH session setup ~2.3 s on first message to a peer | Medium | CONFIRMED | Code (perf) |
| **P2-3** | Rate limiters are in-memory: reset on restart, grow unboundedly | Medium | CONFIRMED | Code |
| **P3-1** | UI crash cascades in the logs are **already fixed** — stale build | Low | CONFIRMED | Ops |

> **Sequencing note.** P0-2 gates P0-1's sibling work and all of §1. There is no point raising
> the attachment limit to 100 MB until nginx is fixed — uploads currently die at ~1 MB regardless
> of what the app says.

---

# P0-1 · Audio & video calls fail — TURN is not configured

## Exact failure point

The logs pin this precisely. From `helix_remote_anomaly_log.txt`:

```
11:04:40.289  [CALL_ENGINE]  engine create_offer begin video=false cid=3f930a34
11:04:40.290  [CALL_ENGINE]  engine state_create begin  video=false cid=3f930a34
11:04:41.727  [CALL_ENGINE]  engine end_call begin cid=3f930a34            ← 1.4 s later
11:04:41.730  [CALL_SCREEN]  state=failed error=The call could not be started…
11:04:41.743  [CALL_ENGINE]  engine end_call ignored reason=missing_state
11:04:43.783  [ERROR] [uncaught] HttpException:
              {"error":"TURN is not configured","turn_configured":false},
              uri = https://hr.agiletechbd.com/api/v1/calls/turn-credentials
              #2 RemoteIceConfigProvider.getIceConfig (…/remote_ice_config_provider.dart:30:22)

# NOTE: that body is the pre-A1 shape. The error format migration moved
# structured context under `details`, so the same failure now returns:
#   {"error":"TURN is not configured",
#    "code":"service_unavailable",
#    "details":{"turn_configured":false}}
# Nothing reads `turn_configured` off this response today, but anything
# written against the old shape must read details.turn_configured.
```

Identical trace for the video attempt at `11:05:11` (`cid=70084e67`). Both screenshots
("Failed" / "Waiting for video") are the UI rendering of exactly this.

**The pipeline breaks at step 2 of 6.** Nothing downstream is implicated:

| Stage | Status | Evidence |
|---|---|---|
| Signaling transport (WS) | ✅ reachable | `WSClient connected generation=2` before each attempt |
| **ICE config fetch** | ❌ **FAILS HERE** | `503 {"turn_configured":false}` |
| WebRTC offer/SDP | ⬜ never reached | `state_create` never completes |
| ICE gathering / STUN / TURN | ⬜ never reached | — |
| Server call endpoints | ⬜ never exercised | — |
| Authentication | ✅ fine | a 503 (not 401/403) means the token was accepted |

So: **auth, signaling, and the call endpoints are all healthy.** This is purely missing TURN config.

## Root cause

`CallsModule._handleTurnCredentials` (`backend/lib/src/modules/calls.dart:264`) throws
`AppError.serviceUnavailable('TURN is not configured').withDetails({'turn_configured': false})`
when `HELIX_REMOTE_TURN_URL` / `HELIX_REMOTE_TURN_SECRET` are empty. They are not set on the VPS.

> You mentioned having configured the server for WebRTC. The server disagrees, and it is the
> authority here — the 503 is emitted only when both env vars are empty at process start.
> Two likely explanations: the values were added to `.env` but the **backend container was never
> recreated** (env is read once at boot — `docker compose restart` is *not* enough, you need
> `up -d`), or they were set somewhere the container does not read. Confirm with the
> **Config screen → "TURN Server Configured"**, or:
> `docker compose exec helix-backend printenv | grep TURN`

## Why this is fatal rather than degraded — and why "just use STUN" is the wrong fix

**[CONFIRMED]** Production ICE config is `iceServers: []` with `ipPrivacy: relayOnly`
(`app/lib/app/remote_config.dart:55-56`). Relay-only is a deliberate **privacy property**: all
media is relayed so peers never learn each other's IP addresses.

This matters for the fix. The tempting "make calls degrade gracefully to STUN when TURN is
missing" would silently convert a privacy guarantee into an IP leak between users — for a
family/personal deployment where the peers are relatives, that trade may be acceptable, but it
must be an **explicit, admin-visible choice**, never a silent fallback triggered by a
misconfiguration. Recommendation below reflects that.

## Fix

### A. Infra — deploy the TURN relay (already in the repo, not yet rolled out)

`deploy/coturn/` was added and verified but never deployed. Full steps are in
`deploy/coturn/README.md`; the short form on the VPS:

1. In `/opt/helix-remote/helix_remote/.env`:
   ```ini
   HELIX_REMOTE_TURN_URL=turn:hr.agiletechbd.com:3478,turns:hr.agiletechbd.com:5349
   HELIX_REMOTE_TURN_SECRET=<openssl rand -hex 32>
   TURN_REALM=hr.agiletechbd.com
   TURN_EXTERNAL_IP=157.250.207.166
   ```
   `HELIX_REMOTE_TURN_SECRET` is **shared** — the backend signs credentials with it and coturn
   verifies them. If they drift, calls fail with a 401 *from the relay* that appears nowhere in
   the backend's logs.
2. Firewall (first ports opened besides 22/80/443 — TURN cannot sit behind nginx):
   ```sh
   ufw allow 3478/tcp; ufw allow 3478/udp
   ufw allow 5349/tcp; ufw allow 5349/udp
   ufw allow 49160:49200/udp
   ```
3. `docker compose up -d helix-turn && docker compose up -d helix-backend`
   — **`up -d`, not `restart`**, or the backend will not pick up the new env.
4. Optional but recommended (`turns:` on 5349, gets through UDP-blocking networks):
   `sudo deploy/coturn/certbot-deploy-hook.sh`, then install it into
   `/etc/letsencrypt/renewal-hooks/deploy/`.

**Verify before retesting the app** — "Config: TURN ENABLED" only proves env vars exist, not that
the relay answers:

```sh
# Should print allocation results, not 401.
EXP=$(( $(date +%s) + 3600 )); U="$EXP:smoketest"
C=$(printf '%s' "$U" | openssl dgst -sha1 -hmac "$HELIX_REMOTE_TURN_SECRET" -binary | base64)
docker compose exec helix-turn turnutils_uclient -T -u "$U" -w "$C" hr.agiletechbd.com
```

The backend↔coturn credential format is pinned by `backend/test/turn_rest_credential_test.dart`
and was verified end-to-end against coturn 4.6.1 (traffic relayed, 0 packet loss), so if the
smoke test fails it is a config/firewall problem, not a format mismatch.

### B. Code — three hardening fixes (all still worth doing after TURN works)

1. **Say what actually went wrong.** `state=failed error=The call could not be started. Check
   server and call connectivity.` is unactionable. Map the 503 to:
   *"This server has no call relay configured. Ask the server admin to set up TURN."*
   Distinguish it from a genuine network failure.

2. **Stop the uncaught exception.** The `HttpException` surfaces **2 seconds after the call
   screen already popped** (`11:04:43.783` vs `11:04:41.730`) — the future is not awaited on the
   failure path, so it lands in the zone error handler. Catch it at the call-setup boundary in
   `remote_ice_config_provider.dart` / the call engine and convert to a typed failure.

3. **Pre-flight the relay, don't fail mid-setup.** Check ICE availability *before*
   `state_create`, so the UI never enters "preparing" for a call that cannot start.

4. **(Policy, needs your decision)** Optionally let the admin opt into `direct_and_relay` from
   the admin console, with copy that states plainly it lets call participants see each other's
   IP addresses. **Default must stay `relayOnly`.** Do not implement this as an automatic
   fallback.

---

# P0-2 · nginx caps every attachment at ~1 MB

**[CONFIRMED]** — and this is the most important finding in §1, because it is invisible in the
app's error messages and would silently defeat the 100 MB change you asked for.

`deploy/nginx/hr.agiletechbd.com.conf` sets **no `client_max_body_size`**. The nginx default is
**1 MB**. The client uploads each attachment as a **single PUT containing the whole ciphertext**
(`app/lib/app/remote_attachment_service.dart:214-222` — `cipherFile.openRead(offset)` at `:222` streams
from `offset` to EOF; the `while` loop is for *resume after failure*, not chunking).

Therefore **every attachment over ~1 MB is rejected by nginx with a 413 before it ever reaches
the backend.**

This is consistent with your screenshot: the 26.3 KB JPG shows `COMPLETED`, and the failure you
saw was a >10 MB file caught by the client-side check first. The 1 MB–10 MB band would fail with
a 413 that the client surfaces as a bare
`Chunk upload failed with status 413` (`remote_attachment_service.dart:228`) — worth testing, as
it may already be biting users without a clear message.

### Fix

In the `location /` block (and anywhere else proxying to the backend):

```nginx
client_max_body_size 110m;      # headroom over the new app limit
proxy_request_buffering off;    # stream to the backend instead of spooling
                                # the whole body to /var/lib/nginx first
proxy_read_timeout 3600s;       # already present — keep
send_timeout 3600s;             # slow uplinks on large uploads
```

`proxy_request_buffering off` matters at 100 MB: with buffering on (the default), nginx writes
the entire body to disk before forwarding, doubling disk I/O and adding the full upload duration
to time-to-first-byte on the backend.

Then `nginx -t && systemctl reload nginx`. **Track this in
`deploy/nginx/hr.agiletechbd.com.conf`**, not by editing the file live on the VPS — the repo copy
is the source of truth and a live edit will conflict on the next `git pull`.

---

# P0-3 · Contact sync fails above 500 contacts

## Why the limit exists — read before changing it

**Do not simply raise 500 to 3000.** `backend/lib/src/modules/contacts.dart:365-370` documents
the reasoning, and it is sound:

> *"even hashed, this is an oracle for 'is phone number X a Helix user' to anyone who can call
> it - auth + a hard per-account daily cap + a batch-size cap are the required mitigations, not
> optional hardening."*

The salt is server-wide, so any authenticated account can hash arbitrary phone numbers and probe
membership. The batch cap and daily cap are what bound that enumeration.

## The trap in the obvious fix

**[CONFIRMED]** There are **two** limits, and everyone notices only the first:

| Constant | Value | Location |
|---|---|---|
| `contactsMatchBatchLimit` | **500** hashes per request | `contacts.dart:17`, enforced `:392` |
| `contactsMatchDailyLimit` | **5** requests per day | `contacts.dart:16`, enforced `:424` |

2,100 contacts ÷ 500 = **5 requests — exactly the entire daily budget.** So naive client-side
chunking "works" once, then leaves **zero** budget for a retry, a second device, or tomorrow's
re-sync. Any chunking implementation that ignores `contactsMatchDailyLimit` will appear to fix
the bug in testing and fail in the field.

The client currently sends everything in one unchunked call
(`app/lib/app/composition_root/contacts_sync.dart:56`), producing the 400 the uncle hit.

## Recommended redesign

**Change what is metered, not how much is allowed.** Meter the thing that actually represents
enumeration exposure — *distinct hashes per day* — rather than *requests* per day. Then chunking
becomes transparent and the privacy property is preserved (arguably tightened, since today
5 × 500 = 2,500 hashes/day is already permitted).

### Server

1. Replace the request-count cap with a **hash-count budget**, e.g. `5,000 distinct hashes /
   account / 24 h`. Return `429` with the remaining budget so the client can report progress
   honestly:
   ```json
   { "error": "…", "hashes_remaining_today": 0, "retry_after_seconds": 43200 }
   ```
2. Keep a per-request batch cap (raise to **1,000**) purely as a request-size guard.
3. **Don't charge for re-syncing an unchanged phone book.** Store a hash of the sorted hash-set
   per account; if it matches the last sync, return the cached result **without** consuming
   budget. This alone removes most repeat cost — phone books change slowly.
4. **Make the limiter durable and bounded.** `_matchAttempts` / `_searchAttempts`
   (`contacts.dart:18,13`) are in-memory `Map`s: they reset on every deploy (so the cap is not
   actually enforced across restarts) and grow without bound (same leak class the
   `RateLimiter` already fixed with idle eviction). Move to a DB table with a periodic sweep.
5. Return `partial: true` + a cursor so a client resuming mid-sync is a first-class case.

### Client (`contacts_sync.dart`)

6. Chunk into batches of ≤1,000, **sequentially** (not `Future.wait` — parallel bursts will trip
   the rate limiter and spike memory).
7. **Persist progress** between chunks and apply matches incrementally, so a sync interrupted at
   chunk 3 of 5 keeps chunks 1–2 and resumes rather than restarting.
8. **Report partial success.** Today one 400 discards the whole sync. Surface
   *"1,500 of 2,100 contacts synced — the rest will sync tomorrow"*, not a hard failure.
9. Respect `retry_after_seconds`; back off rather than hammering.
10. Deduplicate before hashing. Phone books routinely hold the same number under several labels
    and in several formats (`+8801…`, `01…`); dedupe on the normalized E.164 form so the budget
    is spent on distinct people. On a 2,100-entry book this alone often cuts 10–20%.

### Test coverage to add

- 2,100 contacts → all matched across chunks, one pass.
- Budget exhausted mid-sync → partial results kept, clear message, resumable.
- Re-sync with an unchanged phone book → **zero** budget consumed.
- Duplicate numbers in several formats → counted once.

---

# P1-1 · WebSocket closes with `1002` every 1–3 minutes

## Evidence

`close_code=1002` (protocol error) recurs across **both** log files and many sessions:

```
08-05 11:06:43  closed — close_code=1002 reason=none     (2 m 57 s after connect)
08-05 11:06:55  closed — close_code=1002 reason=none     (5 s after connect)
08-05 11:08:38  closed — close_code=1002 reason=none     (1 m 23 s after connect)
08-04 21:25:21 / 21:27:42 / 08-05 11:21:11 …
```

Intervals are irregular (5 s → 3 min), which rules out a fixed proxy idle timeout. Each close
triggers a full reconnect with offline-event replay. **User-visible cost:** dropped call
signaling (a call cannot be set up across a reconnect), delayed message delivery, and repeated
replay work.

## Hypotheses, ranked

**H1 — Unserialised concurrent writers to one socket sink. [strongest]**
The codebase already links flooding to this exact close code
(`backend/lib/src/websocket.dart:122-126`):

> *"Sending everything synchronously in one tight loop overflows the send buffer and causes the
> client to close the connection with code 1002."*

The existing mitigation is incomplete. `_replayOfflineEvents` (`websocket.dart:210-262`) applies
real backpressure (`replay_ack`) only **between 50-event pages**; *within* a page it emits 50
`sink.add` calls with a bare `Future.delayed(Duration.zero)` every 20 — which the code's own
comment acknowledges "does not wait for a slow client (or a full TCP send buffer) to drain."
Worse, `sendToDevice` (`websocket.dart:32-42`) and `trySendToDevice` write to the **same sink
concurrently** with an in-flight replay, from unrelated async contexts, with no serialization.

**Fix regardless of whether it is the cause** — this is a latent correctness bug: route every
write for a device through a single per-connection queue that awaits the sink, and apply
backpressure inside a page, not just between pages.

> **[DONE]** Implemented as a `_DeviceConnection` object per socket. Every write —
> `sendToDevice`, `trySendToDevice`, the `pong` reply, the call-signal ack and replay — now goes
> through `_DeviceConnection.send`, so there is one place that encodes, handles write errors and
> deregisters. That last part fixed a second, separate bug: `sendToDevice` and `trySendToDevice`
> removed the device from the connection map on a failed write **without** the identity check
> `onDone`/`onError` already had, so a late failure on a socket the device had already replaced
> tore down its current, healthy connection. `_replayWaiters` was keyed by `deviceId` for the
> same reason and had the same race; it now lives on the connection object.
>
> Backpressure is now a **credit window of 20 outstanding events, applied per event** rather
> than per 50-event page, released by the `replay_ack` the client already sends. A client that
> stops acking stops receiving after 20 events instead of absorbing a whole page; a client that
> never acks (older builds) trips a 5 s timeout **once**, which latches a yield-based fallback
> for the rest of that replay rather than costing 5 s per window.
>
> **Correction to the recommendation above, worth recording:** "a queue that *awaits the sink*"
> is not achievable in this stack, and it is better to say so than to write an `await` that
> awaits nothing. `shelf_web_socket` hands the server an `IOWebSocketChannel` whose sink is a
> `StreamChannelController(sync: true)` feeding `WebSocket.sendText`, which returns `void` and
> buffers without bound; there is no `bufferedAmount`, and `sink.addStream` completes as fast as
> the source produces. The client's acks are the only real drain signal available, which is why
> the fix is built on them. **This also weakens H1 as an explanation for `1002`:** if the server
> cannot observe its own send buffer, the flood hypothesis is harder to confirm from the server
> side, and step 1 of the procedure below (bypass nginx) becomes the more valuable first move.

**H2 — `permessage-deflate` negotiation mismatch.**
The client uses `WebSocket.connect` (`remote_websocket_client.dart:65`), which offers
compression by default; the server uses `shelf_web_socket`. An RSV-bit / window-bits disagreement
produces exactly `1002`. Cheap to test.

**H3 — Ping/pong interaction.** The client runs **two** keepalives: protocol-level
(`pingInterval = 20 s`, `remote_websocket_client.dart:86`) and application-level JSON ping every
30 s (`:181`). Redundant, and worth ruling out.

## Diagnostic procedure (in order — each step is cheap and eliminates a hypothesis)

1. **Bypass nginx.** Point a test client at `127.0.0.1:8080` directly on the VPS. If 1002
   disappears, it is the proxy; if it persists, it is application-level. *This single step splits
   the search space in half — do it first.*
2. **Disable compression** on the client (`compression: CompressionOptions.compressionOff`) for
   one build. If 1002 disappears → H2.
3. **Correlate with replay.** Log event counts per replay and the socket's buffered amount. If
   1002 clusters with large replays → H1.
4. Now that the admin console's Logs screen works, watch the **server** side during a close —
   the server's view of the disconnect was previously invisible, which is partly why this has
   gone unexplained.

---

# P1-2 · Attachment size limit: enforced in four places, inconsistently

Raising "the limit" means changing **all** of these. Missing one produces confusing partial
failures.

| # | Where | Current | Measures | Note |
|---|---|---|---|---|
| 1 | nginx `client_max_body_size` | **1 MB** (implicit default) | ciphertext | **The real ceiling today.** §P0-2 |
| 2 | Client pre-check `remote_attachment_service.dart:51` | 10 MB | **plaintext** | Source of your error message |
| 3 | Backend `attachments.dart:11` `maxFileSize` | 10 MB | **ciphertext** | Checked at `:53` |
| 4 | Backend `attachments.dart:12` `maxQuota` | **50 MB** | ciphertext, **per account, cumulative** | Checked at `:59` |

### Three defects visible in that table

1. **Quota < proposed file size.** With `maxFileSize` at 100 MB and `maxQuota` still 50 MB,
   *every* file over 50 MB fails with a confusing "quota" error. Raise the quota to something
   coherent (e.g. 2–5 GB) **and** decide a retention/cleanup policy — see below.
2. **Plaintext vs ciphertext mismatch.** #2 measures the plaintext file; #3 measures the
   encrypted file, which is larger: an 18-byte header plus ~40 bytes per 64 KB chunk
   (`_encryptFileToCache`, `remote_attachment_service.dart:515`). A 10 MB plaintext becomes
   ~10 MB + 6.4 KB of ciphertext. **Files in the top ~6 KB band pass the client check and are
   then rejected by the server** — a real, currently-live off-by-overhead bug. Compare like with
   like: check the *ciphertext* length against the limit on both sides, or add explicit headroom.
3. **Limits are hard-coded**, so changing them requires an app release. Make the server the
   source of truth and have the client fetch it (see below).

### Recommended shape

- **Make it configurable, not just bigger.** Add `HELIX_REMOTE_MAX_ATTACHMENT_BYTES` and
  `HELIX_REMOTE_ACCOUNT_QUOTA_BYTES`; expose both via the existing `/api/v1/server/info`
  endpoint; have the client fetch and cache them and validate against the *server's* number.
  An operator then changes a limit in `.env` with no app release, and the client's error message
  can never disagree with the server's.
- **Default to 100 MB file / 5 GB quota** as you asked, with nginx at 110 MB.

### Reliability work that 100 MB makes mandatory

At 10 MB the current single-request upload is survivable. At 100 MB it is not:

- **Real chunking.** Today one PUT carries the entire file; a dropped connection at 95 MB
  restarts from the server's byte offset — better than nothing, but the client re-reads and
  re-sends from that offset in one shot again. Send fixed chunks (4–8 MB) per request so
  progress is durable and any single failure is cheap. The server already supports
  offset-resume (`attachments.dart:262-290`), so this is a client-side change.
- **Memory.** Verify the encrypt→upload path never materialises the whole file; the streaming
  `openRead()` is right, but confirm nothing downstream buffers.
- **Backend hashing.** `sha256.bind(file.openRead()).first` (`attachments.dart:305`) re-hashes
  the entire file on completion — ~100 MB of I/O plus CPU on a small VPS, on the event loop's
  isolate. Move to a worker isolate or hash incrementally during upload.
- **Disk.** 100 MB files × a family's usage on a VPS volume: add a disk-space pre-check before
  accepting an upload, and a retention/cleanup job. **This is currently the largest unbounded
  growth risk on the box** — there is no attachment GC today.
- **Progress UI + cancel.** A 100 MB upload on a phone uplink is minutes long; it needs visible
  progress and a working cancel.
- **Timeouts.** Client request timeout is 15 s in places (`invite_entry_screen.dart:107`);
  ensure the upload path uses a separate, much longer timeout.

---

# P1-3 · Uncaught async exceptions on the call path

`[ERROR] [uncaught] HttpException…` appears in the anomaly log because it reaches the top-level
zone handler — 2 s *after* the UI already gave up. Two distinct problems:

1. The failure path does not await/catch the ICE-config future (§P0-1 B2).
2. Anything reaching `[uncaught]` is, by definition, unhandled — these should be typed failures
   handled at a boundary, not zone-caught crash reports.

Audit other `[uncaught]` entries (9 across the PDF log) for the same shape.

---

# P2-1 · SMS OTP delivery failing at the vendor

Five distinct `[WARN] [auth] OTP request failed` causes across 2026-08-03:

| Time | Vendor response | Meaning | Action |
|---|---|---|---|
| 17:54 | `Failed to send verification SMS. Please try again.` | generic (pre-fix build) | superseded by `2898b95` |
| 21:29, 22:02 | `Bad state: Stream has already been listened to` | **client-side bug** | **already fixed** in `4d60f85` — stale build |
| 22:22 | `1032: Your ip 157.250.207.166 not Whitelisted` | **vendor config** | whitelist the VPS IP in the BulkSMSBD Phonebook portal |
| 22:45 | `1005: Attempt to read property "is_masking" on null` | vendor-side null — almost always an **unregistered/mismatched sender ID** | verify `HELIX_REMOTE_SMS_SENDER_ID` matches an approved masking sender exactly |

Neither remaining issue is a code defect. Two supporting improvements worth making:

- The error text is passed through verbatim (good — `2898b95`), but `1032`/`1005` are
  *operator* problems. Detect these codes and surface an admin-facing hint rather than showing a
  vendor stack to an end user mid-registration.
- Add SMS delivery success/failure counters to `/ops/metrics` so this is visible on the
  dashboard instead of only in a crash log.

---

# P2-2 · X3DH session setup ~2.3 s

From the latency trace at `11:04:40`:

```
x3dh_start → session_cache_miss :  902 ms   ← FLAGGED
session_cache_miss → x3dh_complete: 1405 ms ← FLAGGED
send_attempt → server_ack       :  850 ms   ← FLAGGED
```

~2.3 s before the first message to a new peer even leaves the device. Steady-state is healthy
(receive path 28–67 ms end-to-end), so this is **first-contact only** — but it is the most
visible moment for a new user.

- `session_cache_miss` at 902 ms suggests the miss path itself is slow (a prekey network fetch
  inside the measured window), not just a cold cache. Instrument to separate local lookup from
  the network round trip.
- 1,405 ms for X3DH completion is heavy for the crypto alone — check whether key agreement runs
  on the **main isolate**. `bug_fix.md` already flags "Synchronous Event Loop Starvation" as a
  systemic pattern; this looks like another instance. Move to `compute()`.
- 850 ms `server_ack` on a Bangladesh↔VPS path may just be RTT; compare against a `/health/live`
  ping before optimising.
- Consider prefetching prekey bundles for known contacts after contact sync, so the first
  message to a contact finds a warm session.

---

# P2-3 · In-memory rate limiters

`_matchAttempts`, `_searchAttempts` (`contacts.dart:18,13`) and the global-invite attempt map
are plain in-memory `Map`s keyed by account/IP. Two consequences:

- **Not durable** — every deploy resets every quota. A daily cap that resets on restart is not
  a cap.
- **Unbounded growth** — one entry per account/IP forever. `RateLimiter` already solved this
  with idle eviction (`rate_limiter.dart:56+`); these did not get the same treatment.

Fold this into the P0-3 work, since the contacts limiter has to move to durable storage anyway.

---

# P3-1 · The UI crash cascades in the logs are already fixed

Worth stating clearly so nobody re-debugs them. **196 of the 230 `[ERROR] [flutter]` lines in the
PDF log are one cascade**, not 196 problems:

| Symptom | Count | Status |
|---|---|---|
| `InputDecorator … cannot have an unbounded width` @ 08-03 16:45 | 1 root + ~196 downstream `RenderBox was not laid out` + 16 hit-test | **Fixed** — `4302b24` (CountryCodeSelector width) |
| `No ScaffoldMessenger widget found` @ 08-03 18:52–18:53 | 10 | **Fixed** — `b81902d` (`Builder` for in-MaterialApp context) |
| `RenderFlex overflowed by 400 pixels` @ 08-04 21:26 | 1 | Likely fixed by the keyboard/layout work; **needs confirmation** |

**Action:** these logs come from a build predating those fixes. Rebuild the APK from current
`main` before triaging any UI report — otherwise you will keep re-analysing solved bugs. The
400-pixel overflow is the one to re-verify, since it postdates most of the fixes.

---

# Recommended execution order

**Do these in order — each unblocks the next.**

| Step | Work | Type | Unblocks |
|---|---|---|---|
| 1 | nginx `client_max_body_size` + `proxy_request_buffering off` | Infra, 10 min | All attachment work |
| 2 | Deploy coturn, open firewall, `up -d` backend, run the relay smoke test | Infra, ~30 min | All calls |
| 3 | Rebuild APK from current `main` | Ops | Stops re-triage of P3-1 |
| 4 | Contact-sync redesign (hash budget + chunking + partial results) | Code | 2,100-contact users |
| 5 | Attachment limits: make configurable, align plaintext/ciphertext, raise quota | Code | 100 MB files |
| 6 | Chunked upload + progress + cancel + isolate hashing + disk guard | Code | 100 MB *reliably* |
| 7 | WS `1002`: run the 4-step diagnostic; fix sink serialization regardless | Code | Connection stability |
| 8 | Call-path error handling + specific messages | Code | Diagnosability |
| 9 | SMS vendor: whitelist IP, verify sender ID | Infra/vendor | Registration |
| 10 | X3DH isolate offload; durable rate limiters | Code | Polish |

**Steps 1–3 are configuration and a rebuild — no code changes — and between them they resolve
the two complete outages (calls, large attachments) plus most of the log noise.**

---

## Reconciliation notes — what changed since `d0f7bd7`

This plan was written against `origin/main` @ `d0f7bd7`. The structural upgrade
work (`docs/architecture/EARNMINUTE_STRUCTURAL_UPGRADE_PLAN.md`, items A1–A6)
landed after it, so the findings were re-verified and the references above
updated. **No finding was invalidated** — all of P0-1 … P3-1 still stand. What
moved:

| Change | Effect on this plan |
|---|---|
| **A1 — one error shape.** Every backend error is now `{error, code, details?}` with a `RemoteErrorCode`. | The TURN 503 body changed: `turn_configured` moved from the top level into `details`. P0-1's quoted log line is the pre-A1 shape and is annotated as such. Anything written against the old shape must read `details.turn_configured`. |
| **A3 — `groups.dart` and `calls.dart` split into `part` files.** | `calls.dart:186-192` (the TURN 503) is now `calls.dart:264`. The TURN handler stayed in the shell file, so no path changed — only the line. |
| **A1 line drift** in `attachments.dart` and `contacts.dart`. | All limit/enforcement references retargeted; see the appendix. |
| **A6 — lifecycle transition tables** in `helix_remote_domain/lib/domain/call_room_transitions.dart`. | New, and directly relevant to the call work in P0-1/P1-3: `RemoteCallSessionStatus` is the 1:1 call machine, `RemoteCallRoomStatus` the group-call room. Any new call state belongs in both the service and that table. |
| **CI was not actually running.** The `changes` job failed on every PR (missing `pull-requests: read`), and the format gate failed on every push to `main`, so `flutter analyze` and the package test suites had not run for some time. | Directly relevant to **P3-1**: it is why stale-build issues went unnoticed. Fixed. |

### Findings added while reconciling

Three genuine call-path bugs surfaced once the package test suites ran again.
They are not in the original plan because its inputs were logs, not a test run.
All three are fixed on the structural-upgrade branch:

1. **A connected call could stay stuck on "dialing".** `_isLegalTransition` in
   `remote_call_service.dart` had no `dialing → active` edge. The engine
   reports `checking` and `connected` as separate events but is not obliged to
   emit both, so a fast ICE path reached `connected` first and the transition
   was refused — leaving the call in `dialing` while media flowed, and silently
   disabling everything gated on `active` (adaptive media, reconnect backoff,
   ICE restart). **This compounds P0-1:** once TURN is deployed and calls
   actually connect, this is the next thing that would have broken them.
2. **Adaptive-media recovery was unreachable.** A 15 s cooldown gated the whole
   of `_adaptMediaQuality`, including the counting of good samples. Since
   quality events arrive every second or two, the two consecutive good samples
   required to re-enable video could never accumulate inside the window — video
   dropped on a bad patch and never came back for the rest of the call.
3. **A call that lost connectivity never failed.** `_restartInProgress` was
   cleared only by a later `connected` event, so a restart that never recovered
   blocked every subsequent attempt: the attempt counter stopped growing, the
   max-attempts guard never fired, and the call sat in `reconnecting`
   indefinitely instead of terminating.

---

## Appendix — key references

| Concern | Location |
|---|---|
| Client attachment pre-check (plaintext, 10 MB) | `app/lib/app/remote_attachment_service.dart:51` |
| Single-request upload | `app/lib/app/remote_attachment_service.dart:214-222` |
| Ciphertext framing overhead | `app/lib/app/remote_attachment_service.dart:515` |
| Backend file/quota limits | `backend/lib/src/modules/attachments.dart:11-12`, check at `:53`, quota at `:59` |
| Backend resume-by-offset support | `backend/lib/src/modules/attachments.dart:262-290` |
| Contacts batch + daily caps | `backend/lib/src/modules/contacts.dart:16-17`, enforced `:392`, `:424` |
| Contacts oracle rationale | `backend/lib/src/modules/contacts.dart:365-370` |
| Unchunked client sync call | `app/lib/app/composition_root/contacts_sync.dart:56` |
| ICE fetch that throws | `app/lib/app/remote_ice_config_provider.dart:30` |
| Relay-only production default | `app/lib/app/remote_config.dart:55-56` |
| TURN 503 origin | `backend/lib/src/modules/calls.dart:264` |
| `1002` ↔ sink-flood comment | `backend/lib/src/websocket.dart:122-126` |
| Replay backpressure | `backend/lib/src/websocket.dart:194-262` |
| Concurrent sink writers | `backend/lib/src/websocket.dart:32`, `:44` |
| Client WS keepalives | `app/lib/app/remote_websocket_client.dart:86`, `:181` |
| nginx config (no body-size limit) | `deploy/nginx/hr.agiletechbd.com.conf` |
| TURN deployment guide | `deploy/coturn/README.md` |
