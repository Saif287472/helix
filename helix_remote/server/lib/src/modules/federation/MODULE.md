# federation module

Server-to-server federation. Schema `federation`: `settings` holds this
server's Ed25519 seed (created on first start); `peers` is the cache of
other servers' identity documents. It provides the S2S half of
authentication (`ProvidesAuthentication.server`) and installs relays in
messaging (`MessageRelay`), keys (`RemoteKeySource`) and calls
(`CallRelay`).

## Addresses

An account on another server is `<uuid>@<domain>`. The domain is the
authority of that server's `HELIX_PUBLIC_BASE_URL` (`host` or
`host:port`), lowercase. Local accounts are bare UUIDs to their own
clients, and an address qualified with this server's own domain is
treated as local. Stored foreign senders, blockees and callers are kept
qualified: `mailbox.sender_account`, `people.blocks.blocked` and
`calls.pending_calls.caller_account` are `text` since migration 2 of each
module.

## Switch and policy

- **On or off:** the ops setting `federation_enabled` (default
  `HELIX_FEDERATION_ENABLED`, false). While it is off, outbound relays
  answer `federation_unavailable` and inbound S2S requests are not
  authenticated (401).
- **Allow list:** `HELIX_FEDERATION_ALLOW` (comma-separated domains). When
  set, it is the only set of peers.
- **Addresses refused:** link-local and unspecified addresses are always
  refused (cloud metadata). Loopback and private ranges are refused unless
  `HELIX_FEDERATION_ALLOW_PRIVATE=true`. Domains in addresses are user
  input, so this is the SSRF guard. It is checked for the identity
  document and for every API call.
- **Scheme:** `https`. `HELIX_FEDERATION_HTTP=true` uses `http`, in dev
  mode only (tests).

## Trust

A peer's key is whatever `https://<domain>/.well-known/helix-server`
serves. TLS authenticates the domain, so the trust root is the domain's
certificate.

- **The document:** it must name the domain as `server_id`, carry a 32-byte
  key, and keep `api_base` on the same scheme and authority. Documents are
  cached for 24 hours.
- **Re-fetching:** a signature that fails is re-fetched once, at most every
  10 minutes per domain, for key rotation. A changed key is logged
  (`peer_key_changed`).
- **Failed lookups:** a failed lookup with nothing cached is not retried for
  a minute (`fed:down:`), so forged headers cannot make this server hammer
  a domain.

## Signatures

Every S2S request carries `x-helix-s2s-server`, `x-helix-s2s-timestamp` (ms)
and `x-helix-s2s-signature`: Ed25519 over `s2sSigningInput`, which is
`helix-s2s-v1|server|timestamp|METHOD|path?query|base64url(sha256(body))`.

- **Clock skew:** at most ±5 minutes.
- **Replay:** each signature is accepted once. The ephemeral store remembers
  its hash for twice the skew.
- **Principal:** `ServerPrincipal(serverId: domain)`. Per-server rate limits
  apply after verification.

## Relays

| Direction | Route | Behaviour |
|---|---|---|
| Out: messages | `POST /v1/s2s/messages` | Synchronous. Stale lists come back with accounts qualified; `not_found` passes through. Unreachable (network, timeout, 5xx): queued as `federation.relay`, retried up to 12 times with backoff, deduped per (domain, message id). Ephemeral sends are dropped. A retry the peer refuses is logged and dropped: the sender was already told it was accepted. |
| In: messages | same | `MessagingApi.receive`. The sender must be qualified with the calling domain (`forbidden` otherwise). Same device-list, block, quota and idempotency rules as a local send. |
| Out/In: keys | `GET /v1/s2s/keys/{account}` | Consumes one-time prekeys on the home server. Inbound: 600 per minute per server, 30 per minute per (server, account). |
| Out/In: call signals | `POST /v1/s2s/calls/{call_id}/signals` | Synchronous, no queue (calls are live). Unreachable is `federation_unavailable`. Offers to offline remote devices become pending calls on their server. |
| Groups | `/v1/s2s/groups/{id}`, `…/actions`, `…/sync`, `…/messages` | Carried for the groups module (see its MODULE.md): member actions to the home (always answered 200 with the operation's own status and body inside), snapshots and fan-out from the home. Unreachable peers raise `RelayUnavailable` so queued group work retries. |

## Not covered

- Remote profiles and presence (no S2S route in the catalog): clients show
  the address until profile exchange is designed (review item).
