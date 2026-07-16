# Helix Remote Calls Connectivity Runbook

## Coturn

Run Coturn as a separate service from the Dart backend. Use a DNS-only host such
as `turn.example.com` that points at the fixed public IP of the relay host.

Required backend environment:

- `HELIX_REMOTE_TURN_SECRET`: long random shared secret, identical to Coturn
  `static-auth-secret`.
- `HELIX_REMOTE_TURN_URL`: either a comma-separated explicit URL list or a base
  `turn:host:3478` URL. A base URL expands to:
  - `turn:host:3478?transport=udp`
  - `turn:host:3478?transport=tcp`
  - `turns:host:5349?transport=tcp`

Coturn configuration checklist:

- `lt-cred-mech`
- `use-auth-secret`
- `static-auth-secret=<same value as HELIX_REMOTE_TURN_SECRET>`
- `realm=<turn hostname>`
- `external-ip=<public-ip>/<lan-ip>` when the relay host is behind NAT
- `listening-port=3478`
- `tls-listening-port=5349` when `turns:` is enabled
- `min-port` and `max-port` restricted to the planned UDP relay range
- `no-multicast-peers` and denied unsafe peer ranges
- TLS certificate/key configured for `turns:`

Open and forward UDP/TCP 3478, TCP 5349 when TLS TURN is enabled, and the
restricted UDP relay range. On Windows, create inbound firewall rules for those
ports and configure Coturn to start as a service after boot.

## Caddy

Keep the Dart backend bound to localhost and proxy HTTPS plus WSS through Caddy.

Example shape:

```caddyfile
remote.example.com {
  reverse_proxy 127.0.0.1:8080 {
    header_up X-Forwarded-For {remote_host}
    header_up X-Forwarded-Proto {scheme}
  }
}
```

The backend trusts forwarded client IP headers only when the immediate peer is a
configured local proxy address. Direct clients cannot spoof `X-Forwarded-For`.

Use Caddy transport timeouts that allow long-lived WebSocket sessions. The
client and backend also use ping/pong keepalive traffic, so avoid idle timeouts
shorter than the ping interval.

## Diagnostics

Readiness exposes API and call readiness separately:

- `/api/v1/health/ready` `api_ready`: database and API availability.
- `/api/v1/health/ready` `call_ready`: TURN secret and usable TURN URLs.
- `/api/v1/health/ready` `turn.live_reachability`: placeholder for live TURN
  allocation checks; currently reports `not_checked`.

Client call preflight should verify, in order: DNS/TLS, REST authentication,
WSS connection, TURN credential fetch, and relay allocation. A relay-only build
must not place a call when no usable TURN URLs are returned.
