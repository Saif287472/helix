# Trust Model

> **Status:** Finalized — Stage 5 review.

## Model Summary

Helix uses **Trust on First Use (TOFU)** with optional human out-of-band verification.

- Cryptographic identity is a RSA static-key fingerprint (32-byte hash, displayed as hex).
- Secret sentences are used for peer discovery and pairing; they do not prove identity by themselves.
- Human verification uses a short phrase derived deterministically from both peers' fingerprints.

## Trust States

| State | Meaning | Transition Trigger |
|---|---|---|
| `Unknown` | Peer is visible but no trust decision made | Peer discovered via mDNS / UDP |
| `Pending` | Peer has requested a connection | `ConnectionRequest` received |
| `Trusted` | User explicitly approved the peer fingerprint | User approves request or manually trusts |
| `Changed` | A previously trusted fingerprint has changed | New TLS fingerprint on reconnect |
| `Revoked` | User removed trust for the peer | User blocks or removes peer |

## Invariants

1. A fingerprint mismatch between a stored trust record and a new connection must **never** be silently trusted.
2. `Changed` state must surface a visible warning to the user before any messages are exchanged.
3. Verification phrases are derived from **both** peer fingerprints — changing either peer's fingerprint changes the phrase.
4. Session IDs are ephemeral and never substitute for fingerprint identity checks.
5. Trust decisions are auditable: events contain truncated or pseudonymous identifiers, never full private-key material or decrypted content.

## Verification Flow

1. Peer connects and presents a TLS certificate.
2. The certificate's public-key fingerprint is extracted.
3. If the fingerprint is **not** in the trust store → show request UI with the peer's display name and device suffix.
4. User reviews the displayed fingerprint phrase (6 words derived from fingerprints).
5. User confirms out-of-band (e.g., by voice) that the phrase matches the peer's display.
6. On approval, fingerprint is stored in platform secure storage.
7. Future connections from the same fingerprint are auto-trusted; any other fingerprint triggers `Changed`.

## Revocation

- Revocation removes the fingerprint from the trust store and must close or block all active and future sessions from that fingerprint.
- Revoked peers remain visible in discovery (they can re-request) but will not be auto-trusted.

## Handshake Inputs (Public vs. Secret)

| Input | Public / Secret | Used For |
|---|---|---|
| RSA static public key | Public | Fingerprint derivation, TLS certificate embedding |
| RSA static private key | Secret | TLS certificate signing; must never leave secure storage |
| Secret sentence (passphrase) | Secret at pairing time | Argon2id derivation; shared with intended peer only |
| Argon2id-derived key | Secret | Session pairing gate; verified but not stored |
| Session ID | Ephemeral public | Peer routing; not a security identifier |
| Device suffix | Public | Human-readable device disambiguation |

## Open Items (Must Be Resolved Before Production Security Claims)

- **Authenticated key agreement:** The current handshake must include a DH or ECDH step so that the session key is secret even to a passive observer. Deriving keys from public identifiers alone does not create a shared secret.
- **TLS binding:** The TLS certificate must cryptographically commit to the RSA static public key; verify that no gap exists where an active attacker could present a different certificate.
- **Independent review:** The full handshake must be reviewed by an independent cryptographer before forward-secrecy or confidentiality claims are made.
