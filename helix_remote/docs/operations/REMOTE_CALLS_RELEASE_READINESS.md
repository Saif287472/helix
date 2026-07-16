# Remote Calls Release Readiness

This runbook is the controlled-release gate for Helix Remote one-to-one calls.
It intentionally records evidence without storing tokens, TURN shared secrets,
raw SDP, raw ICE candidates, private keys, private IPs, or media content.

## Required Service Checks

- API: `GET /api/v1/health/ready` reports `api_ready: true`.
- WebSocket: admin metrics show connected devices and reconnect rejects below
  alert threshold.
- TURN: readiness reports `call_ready: true` and a nonzero TURN URL count.
- Push: admin metrics show the push provider available and no failed/DLQ wake
  notifications.
- Support export: `GET /api/v1/ops/support-diagnostic` contains only redacted
  configuration and aggregate counters.

## Capacity Validation

Run these checks on the planned host connection and record date, network path,
device models, OS versions, backend commit, Coturn commit/config checksum, and
observed metrics.

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

## Deployment Checklist

- Caddy terminates HTTPS/WSS and forwards only to the local Dart backend.
- Coturn uses a DNS-only hostname, restricted relay port range, NAT mapping,
  TLS where enabled, and the runtime `HELIX_REMOTE_TURN_SECRET`.
- Backend environment variables include JWT secret, public base URL, TURN URL,
  TURN secret, database path, admin account IDs, and push provider settings.
- Android build configuration contains no server secrets or TURN shared secret.
- Debug and release builds pass.
- `dart analyze`, `flutter analyze`, focused backend tests, call package tests,
  app widget tests, and Android build gates pass.

## Rollback

1. Disable new call entry points in the Android app if the issue is client-only.
2. If signaling is affected, block `/api/v1/calls/signal` at Caddy and keep
   messaging endpoints online.
3. If TURN is saturated or leaking cost, revoke/rotate `HELIX_REMOTE_TURN_SECRET`
   and restart Coturn plus backend.
4. Restore the previous backend binary and database backup if migrations or
   pending-call state are suspected.
5. Export `/api/v1/ops/support-diagnostic` before and after rollback.

## Release Blockers

- Any raw token, private key, TURN secret, SDP, ICE candidate, private IP, or
  media payload appears in normal logs, diagnostics, notifications, or support
  exports.
- Forced-TURN audio/video fails in the required matrix.
- More than one target device can answer the same call.
- Active calls leak camera, microphone, renderers, streams, or active markers.
- Backend messaging availability depends on TURN availability.
