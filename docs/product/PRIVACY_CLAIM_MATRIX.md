# Privacy Claim Matrix

Comparison of public security claims against validated monorepo mechanisms.

| Claim | Helix Local Status | Helix Local Mechanism | Helix Remote Status | Helix Remote Mechanism |
| :--- | :--- | :--- | :--- | :--- |
| **No Server Dependency** | Implemented | Serverless mDNS discovery; direct P2P TLS channels | N/A (Server Dependent) | N/A |
| **Zero remnants on close** | Implemented | RAM-only threads, messages, and caches | Prohibited | Remote is intentionally persistent; local SQLCipher database-at-rest encryption is implemented by P2-01 |
| **Forward Secrecy** | Planned | Handshake-based ephemeral key agreements | Blocked for strong claim | Full DH/skipped-key ratchet remains blocked pending reviewed implementation |
| **No Metadata tracking** | Implemented | No external signaling server | Partial | Metadata is minimized, inventoried, and audit logs are redacted; server still needs routing/sync metadata |
| **Secure Reset** | Implemented | Clear secure storage, memory tables, WAL buffers | Component-only for server account deletion | Account delete endpoint purges server-side account/device/mailbox data; app-side local cleanup is not wired yet |
| **Panic Wipe** | Implemented | Blocks network, closes files, wipes keys/DBs | Prohibited | N/A (Manual account purge only) |
| **No plaintext push payload** | N/A | Local notifications are product-scoped | Implemented in backend tests | Push outbox rejects plaintext-bearing keys and call/message pushes carry generic metadata only |
| **No sale or behavioral ads** | Implemented | No ad/analytics subsystem | Implemented by policy and code inventory | No ad SDK or address-book upload; policy prohibits sale/behavioral monetization |
| **Production-reviewed cryptography** | Blocked | External review required before strong claim | Blocked | Independent cryptographic review remains externally blocked |
