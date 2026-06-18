# Privacy Claim Matrix

Comparison of public security claims against validated monorepo mechanisms.

| Claim | Helix Local Status | Helix Local Mechanism | Helix Remote Status | Helix Remote Mechanism |
| :--- | :--- | :--- | :--- | :--- |
| **No Server Dependency** | Implemented | Serverless mDNS discovery; direct P2P TLS channels | N/A (Server Dependent) | N/A |
| **Zero remnants on close** | Implemented | RAM-only threads, messages, and caches | Prohibited | Persistent SQLCipher databases on client |
| **Forward Secrecy** | Planned | Handshake-based ephemeral key agreements | Implemented | Session Double Ratchet protocol |
| **No Metadata tracking** | Implemented | No external signaling server | Implemented | PURGE queues on deliver; logs redacted |
| **Secure Reset** | Implemented | Clear secure storage, memory tables, WAL buffers | Implemented | Account delete purge requests |
| **Panic Wipe** | Implemented | Blocks network, closes files, wipes keys/DBs | Prohibited | N/A (Manual account purge only) |
