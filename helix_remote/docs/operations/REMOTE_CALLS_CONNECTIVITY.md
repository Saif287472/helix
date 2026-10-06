# Helix Remote Calls Connectivity Runbook

## Coturn

Status: updated at Phase X for the v2 server. The setup walkthrough, with the exact
steps for the Windows PC and for a VPS, is `deploy/coturn/README.md`.

Run Coturn as a separate service from the Dart server. Use a DNS-only host such
as `turn.example.com` that points at the fixed public IP of the relay host.

Required server environment (`server/.env`):

- `HELIX_TURN_SECRET`: long random shared secret, identical to Coturn
  `static-auth-secret`.
- `HELIX_TURN_URLS`: a comma-separated explicit URL list, each starting with
  `turn:` or `turns:`; there is no base-URL expansion. For example:
  - `turn:host:3478?transport=udp`
  - `turn:host:3478?transport=tcp`
  - `turns:host:5349?transport=tcp` (optional, only once Coturn has a certificate)

Both must be set or neither (one without the other is a startup error).

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

Keep the Dart server bound to localhost (`HELIX_HOST=127.0.0.1`) and proxy HTTPS plus
WSS through Caddy. The bare site block is enough (the full guidance, including the
two-node form, is in `V2_SERVER_HANDOFF.md`, "Caddy"):

```caddyfile
remote.example.com {
  reverse_proxy 127.0.0.1:8080
}
```

The server trusts forwarded client IP headers only when the immediate peer is in
`HELIX_TRUSTED_PROXIES` (default loopback), and takes the rightmost hop that is not a
trusted proxy, so direct clients cannot spoof `X-Forwarded-For`.

Use Caddy transport timeouts that allow long-lived WebSocket sessions. The server pings
every 30 seconds and the client heartbeat is 25 seconds, so avoid idle timeouts shorter
than that.

## Diagnostics

Readiness (`GET /v1/health/ready`) checks only the database and object storage. It does
not check TURN: a missing TURN setting shows up as `GET /v1/calls/turn` answering 503
`unavailable`, and a Coturn that is down shows up only when a relayed call fails. Check the
relay itself with `turnutils_uclient` (see `deploy/coturn/README.md`, "Verifying it
actually relays").

Client call preflight should verify, in order: DNS/TLS, REST authentication,
WSS connection, TURN credential fetch, and relay allocation. A relay-only build
must not place a call when no usable TURN URLs are returned.
