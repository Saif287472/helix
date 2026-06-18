# Threat Model

> **Status:** Finalized — Stage 5 review.

## Protected Assets

| Asset | Sensitivity | Storage |
|---|---|---|
| Identity private key | Critical | Platform secure storage (flutter_secure_storage) |
| Session keys | Critical | RAM only; erased when channel closes |
| Message content | High | RAM only; wiped on thread close or disconnect timer |
| Private media bytes | High | RAM only (50 MB cache, never written to disk) |
| Trust records / fingerprints | High | Platform secure storage |
| Group membership / admin state | Medium | RAM only (session-only by default) |
| Peer discovery metadata | Low | RAM; cached in SQLite peers_cache for favorites only |
| File transfer data (.part files) | Medium | App cache directory; cleaned on completion or cancel |

## Adversary Capabilities

| Adversary | Capabilities | Out of Scope |
|---|---|---|
| Passive LAN observer | Packet capture; traffic-shape analysis | Cannot read encrypted channel content |
| Active LAN attacker | Spoof discovery; inject connection attempts; MITM before trust | Cannot break established TLS; TOFU alerts on fingerprint change |
| Malicious trusted peer | Send any protocol frame; attempt group admin actions | Cannot forge frames from other fingerprints |
| Device-local attacker | Filesystem access; memory dump if device is unlocked | Cannot read platform-secure-storage without user auth |
| Compromised or modified client | Any frame injection, policy bypass, screenshot | Out of scope — copy-prevention is best-effort UI only |

## Current Mitigations

- **Confidentiality in transit:** All peer-to-peer channels use TLS; frames are CBOR-encoded.
- **Identity binding:** Peers are identified by RSA static-key fingerprints, not session IDs or display names.
- **Trust on first use (TOFU):** Users approve fingerprints once; subsequent sessions verify fingerprint continuity.
- **Human verification:** A short derived phrase (from both fingerprints) lets users confirm identity out-of-band.
- **Impersonation detection:** A changed fingerprint for a known display name triggers a warning.
- **Replay / duplicate protection:** Group messages carry `messageId` + `epoch` + `membershipVersion`; duplicates are rejected.
- **Bounded frames:** All protocol frames have explicit size limits; no unbounded reads.
- **Per-thread auto-wipe:** Disconnected secure-chat threads are wiped from RAM after 5 minutes.
- **RAM-only private media:** Ephemeral media bytes are never written to disk; evicted items show a placeholder.
- **Group split-brain prevention:** Host announcements from stale epochs are rejected.

## Non-Goals (Explicit)

- Host-blind group forwarding — the host is a group member and can read group content.
- Protection against malicious trusted peers — trust grants full messaging access.
- Prevention of screenshots or data extraction by a modified client.
- Internet relay, server-side content moderation, or account recovery.
- Guaranteed key zeroization — Dart GC may retain copies (see KEY_LIFECYCLE.md).

## High-Risk Areas (Require Human Review Before Production Claims)

1. **Authenticated key agreement** — the current chain-key design derives material from public identifiers. A DH/ECDH step that produces a shared secret inaccessible to passive observers must be verified before forward-secrecy claims.
2. **TLS certificate / fingerprint binding** — the mapping between the TLS certificate and the RSA static-key fingerprint must be tight; any gap allows MITM.
3. **Protocol frame parsing** — all CBOR decode paths are attack surface; unbounded input or type confusion would be critical.
4. **Group host election and admin actions** — epoch/version logic must be verified exhaustively.
5. **File transfer resume / hash / cancel** — partial-file state must be handled without TOCTOU on the SHA-256 check.
6. **Future WebRTC ICE candidate filtering** — LAN-only candidate filtering must be verified before calls ship.
