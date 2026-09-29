# Privacy Claim Matrix

Comparison of public security claims against validated monorepo mechanisms.

> The authoritative Remote matrix is `helix_remote/docs/product/PRIVACY_CLAIM_MATRIX.md`; the Remote columns here are a summary (updated 2026-09).

| Claim | Helix Local Status | Helix Local Mechanism | Helix Remote Status | Helix Remote Mechanism |
| :--- | :--- | :--- | :--- | :--- |
| **No Server Dependency** | Implemented | Serverless mDNS discovery; direct P2P TLS channels | N/A (Server Dependent) | N/A |
| **Zero remnants on close** | Implemented | RAM-only threads, messages, and caches | Prohibited | Remote is intentionally persistent; local SQLCipher database-at-rest encryption is implemented by P2-01 |
| **Forward Secrecy** | Planned | Handshake-based ephemeral key agreements | Implemented; strong claim blocked | X3DH plus a Double Ratchet with DH ratchet steps and skipped-key handling (`helix_remote/packages/helix_remote_crypto/lib/src/double_ratchet.dart`, used by `helix_remote/app/lib/app/remote_messaging_service/message_crypto.dart`); no public claim until external review |
| **No Metadata tracking** | Implemented | No external signaling server | Partial | Metadata is minimized, inventoried, and audit logs are redacted; server still needs routing/sync metadata |
| **Secure Reset** | Implemented | Clear secure storage, memory tables, WAL buffers | Implemented | `DELETE /api/v1/account/delete` purges server-side account data (cascading to devices, mailbox, password and history backup); the app then runs `purgeAfterAccountDeletion` (`helix_remote/app/lib/app/composition_root/runtime.dart`), deleting tokens, the local database and the attachment cache |
| **Panic Wipe** | Implemented | Blocks network, closes files, wipes keys/DBs | Prohibited | N/A (Manual account purge only) |
| **No plaintext push payload** | N/A | Local notifications are product-scoped | Implemented in backend tests | Push outbox rejects plaintext-bearing keys and call/message pushes carry generic metadata only |
| **No sale or behavioral ads** | Implemented | No ad/analytics subsystem | Implemented by policy and code inventory | No ad SDK or address-book upload; policy prohibits sale/behavioral monetization |
| **Production-reviewed cryptography** | Blocked | External review required before strong claim | Blocked | Independent cryptographic review remains externally blocked |
