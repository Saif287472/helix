# Product Differences: Local vs. Remote

A side-by-side comparison of the architectural and persistence models.

| Feature Area | Helix Local | Helix Remote |
| :--- | :--- | :--- |
| **Network Boundary** | LAN/Hotspot only | Public Internet + WAN |
| **Infrastructure** | Serverless / mDNS multicast | Modular Monolith Backend (PostgreSQL, S3) |
| **Identity Model** | Long-lived install-scoped keypair | Registered account, prekeys on server directory |
| **Conversation Storage** | RAM only (zero-remnant on restart) | Encrypted SQLite (SQLCipher) persistent database |
| **Group Authority** | Ephemeral P2P election | Server-assisted membership & distribution |
| **File Attachments** | Ephemeral stream to disk; RAM cache | Encrypted S3 bucket; persistent cache |
| **Panic Wipe** | Deep local wipe (all keys, databases, WAL) | Not applicable (local logout/purge only) |
| **Multi-Device Support** | No (single device only) | Yes (sync queue, cursors, fan-out) |
| **Push Notifications** | No | Yes (silent ciphertext push signaling) |
