# Protocol Security Properties

> **Status:** Finalized — Stage 5 review.

## What the Protocol Guarantees (Current Implementation)

| Property | Status | Notes |
|---|---|---|
| Capability negotiation | ✅ Implemented | Peers exchange bitmask flags on connect; unsupported features are hidden |
| Bounded frames | ✅ Implemented | All protocol frames have explicit size limits |
| Identity fingerprint binding | ✅ Implemented | Trust decisions are keyed on RSA static-key fingerprints |
| TOFU trust | ✅ Implemented | First-use approval; subsequent sessions verify fingerprint continuity |
| Human-verifiable phrase | ✅ Implemented | 6-word phrase derived from both fingerprints; shown in trust UI |
| Duplicate group message rejection | ✅ Implemented | `messageId` deduplication per group session |
| Epoch-based split-brain prevention | ✅ Implemented | Stale host announcements from older epochs are rejected |
| Membership-version gating | ✅ Implemented | Admin and membership changes carry monotone version numbers |
| File transfer integrity | ✅ Implemented | SHA-256 hash verified by receiver before atomically renaming `.part` |
| RAM-only private media | ✅ Implemented | No `localFilePath` ever assigned to received ephemeral frames |
| Per-thread auto-wipe | ✅ Implemented | RAM cleared after 5-minute disconnect timer |

## What the Protocol Does NOT Guarantee

| Property | Status | Notes |
|---|---|---|
| Forward secrecy | ⚠️ Unverified | DH/ECDH step needed; see TRUST_MODEL.md open items |
| Host-blind group forwarding | ✗ Out of scope | Host is a member; can decrypt group content |
| Protection against malicious trusted peers | ✗ Out of scope | Trust grants full protocol access |
| Replay protection across sessions | ⚠️ Partial | Epoch + messageId protect within a session; cross-session replay is not addressed |
| Post-quantum security | ✗ Not planned | RSA + HKDF-SHA256 only |
| Internet relay privacy | ✗ Out of scope | LAN-only; no relay or server infrastructure |

## Handshake Security Summary

1. Peers connect over TLS; the TLS certificate embeds the static RSA public key.
2. Fingerprints are compared against the local trust store.
3. Secret sentence (if required) is verified via Argon2id derivation.
4. A chain key is derived via HKDF-SHA256 for per-message encryption.

**Critical open item:** The chain key derivation must include an authenticated DH/ECDH step so that the session secret is not reproducible by a passive observer who knows both public keys.

## Regression Requirements

Any change to protocol encoding or handshake logic must satisfy:

- [ ] Stage 0 fixture corpus decodes correctly through the updated codec.
- [ ] Round-trip encode/decode passes for all frame types.
- [ ] Capability negotiation behavior is preserved.
- [ ] Stale group host announcements continue to be rejected.
- [ ] File resume offsets continue to be verified by receiver state (not trusted from sender).
- [ ] New frame types are added with `CREATE TABLE IF NOT EXISTS` semantics — never modify existing frame wire formats.

## Future Protocol Envelope

When the versioned envelope is introduced (see ROADMAP §3), it will add:
- `frameId` — unique per-frame identifier for deduplication and correlation.
- `correlationId` — links responses to requests.
- `sequenceNumber` — per-session monotone counter for ordering.
- Dual-codec path: legacy frames and enveloped frames decoded transparently.

Unknown optional frames may be safely ignored with a redacted diagnostic event. Unknown required/critical frames must fail closed with an `UnsupportedFrame` response.
