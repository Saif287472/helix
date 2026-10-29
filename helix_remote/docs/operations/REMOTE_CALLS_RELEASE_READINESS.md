# Remote Calls Release Readiness

Status: updated at Phase X for the v2 server (`/v1` routes, `V2_OPERABILITY.md` metrics).

This runbook is the controlled-release gate for Helix Remote one-to-one calls.
It intentionally records evidence without storing tokens, TURN shared secrets,
raw SDP, raw ICE candidates, private keys, private IPs, or media content.

## Required Service Checks

- API: `GET /v1/health/ready` reports `{"ready":true,...}` (database and storage).
- WebSocket: `GET /v1/ops/metrics` (admin token or `HELIX_METRICS_TOKEN`) shows connected
  devices, and upgrade and reconnect rejections stay below the alert threshold.
- TURN: an authenticated `POST /v1/calls/turn` (body: a call id, `role`, `media`) returns credentials with the expected URLs
  (readiness does not check TURN), and `turnutils_uclient` allocates a relay.
- Push: metrics show no dead-letter `messaging.push` or `calls.push` jobs
  (`V2_OPERABILITY.md`, "Jobs").
- Voice relay: with `HELIX_TURN_VOICE_URLS` set, a `media: voice` credential names
  the voice relay and a `media: video` one the video relay (with no voice relay
  configured, both use the main relay and voice minutes are charged but not capped). Allocate on each and
  confirm the voice relay stops near its `max-bps` cap (`deploy/coturn/README.md`).
- Call time (when `billing_enabled` is on): `GET /v1/billing/call-time` shows the
  day's claim, `POST /v1/billing/call-time/claim` grants it once per Dhaka day, and
  a relayed call's credential expires at the end of the reserved time
  (`stale-nonce=30` in coturn cuts the media within about 30 seconds). A call with no
  minutes left is refused with `no_call_time` before the phone rings.
- Voice to video switch: `POST /v1/calls/turn` with the other `media` settles the
  old reservation and reserves from the other pool; the call keeps running if the
  other pool is empty.
- Security signals: `/v1/ops/metrics` carries the auth-event, session-reuse and
  peer-key-change counters; the console dashboard shows the banner when they rise.
- Diagnostics: `V2_OPERABILITY.md` lists the redacted log and metrics that replace the v1
  support export; there is no support-diagnostic route in v2.

## Capacity Validation

Run these checks on the planned host connection and record date, network path,
device models, OS versions, backend commit, Coturn commit/config checksum, and
observed metrics.

- A voice call and a video call each run to the end of their reserved time and are
  cut there (a short account, such as a free one with a few minutes left).
- A voice to video switch and back during a relayed call, on both phones.
- Three simultaneous one-to-one audio calls between six devices/users.
- Three simultaneous 720p video calls with relay-only ICE policy.
- Coturn restart during an active relayed call.
- Backend restart during direct and relayed media.
- Caddy restart while two devices are connected over WSS.
- Router or WAN interruption and recovery.

For each run, capture CPU, RAM, network upload/download, packet loss, RTT,
jitter, selected candidate type, reconnect count, call setup latency, ICE
connection latency, and Coturn allocation count. Store screenshots or logs with
private addresses redacted.

## Real-Device Matrix

- Android Wi-Fi to Android Wi-Fi on different ISPs.
- Wi-Fi to mobile data.
- Mobile data to mobile data.
- Same-LAN direct call.
- Forced TURN-only call.
- TURN UDP blocked with TCP fallback.
- TURN TCP blocked with TLS fallback.
- Wi-Fi-to-mobile and mobile-to-Wi-Fi handoff during a call.
- Caller/callee app foreground, background, locked, and killed.
- Multi-device target account.
- Simultaneous call collision.
- Permission denial and camera/microphone contention.

## Alerts

Configure alerts for:

- API outage or readiness failure for 2 minutes.
- API 5xx rate above 2% for 5 minutes.
- WebSocket reconnect rejections above 25 in 5 minutes.
- Push outbox failed or DLQ count above 10.
- TURN credential error rate above 2% for 5 minutes.
- TURN unconfigured while production mode is enabled.
- TURN reachability checks failing once live reachability is enabled.
- Backup or rollback drill older than 30 days.
- Session-reuse or peer-key-change counters rising fast (a stolen token or a hostile
  peer; `KEY_COMPROMISE_RUNBOOK.md`).
- Coturn voice relay down while the video relay is up (the server hands voice calls
  the voice relay's address whenever it is configured, so they fail to relay; check
  both containers, not one).

## Deployment Checklist

- Caddy terminates HTTPS/WSS and forwards only to the local Dart backend.
- Coturn uses a DNS-only hostname, restricted relay port range, NAT mapping,
  TLS where enabled (optional), and the runtime `HELIX_TURN_SECRET`.
- Server environment variables include the JWT key ring, public base URL, database
  URL, TURN URLs and secret, and the push provider settings (`V2_SERVER_HANDOFF.md`).
- Android build configuration contains no server secrets or TURN shared secret.
- Debug and release builds pass.
- `dart analyze`, `flutter analyze`, the server's call tests, the engine's call tests,
  app widget tests, and Android build gates pass.

## Rollback

1. Disable new call entry points in the Android app if the issue is client-only.
2. If signaling is affected, block `/v1/calls/` at Caddy and keep
   messaging endpoints online.
3. If TURN is saturated or leaking cost, rotate `HELIX_TURN_SECRET` in `server/.env`
   and in Coturn together and restart both.
4. For a bad server release there is no rollback plan for the cutover itself (fix
   forward); for later releases restore the previous server build and, only if a
   migration is suspected, the Postgres backup (`V2_OPERABILITY.md`, "Backups").
5. Capture the redacted log lines and `/v1/ops/metrics` before and after.

## Release Blockers

- Any raw token, private key, TURN secret, SDP, ICE candidate, private IP, or
  media payload appears in normal logs, diagnostics, notifications, or support
  exports.
- Forced-TURN audio/video fails in the required matrix.
- A call outlives its reserved time on the relay, or a refused call (`no_call_time`)
  still rings the callee.
- More than one target device can answer the same call.
- Active calls leak camera, microphone, renderers, streams, or active markers.
- Messaging availability depends on TURN availability.
