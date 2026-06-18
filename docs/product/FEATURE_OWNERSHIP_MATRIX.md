# Feature Ownership Matrix

Defines which features and behaviors map to Local, Remote, or Shared contexts.

| Feature / Behavior | Local Shell | Remote Shell | Shared Context |
| :--- | :---: | :---: | :---: |
| **mDNS LAN Discovery** | Yes | No | No |
| **P2P Socket Handshakes** | Yes | No | No |
| **E2EE Messaging Loop** | No | Yes | No |
| **Account Creation / Login** | No | Yes | No |
| **SQLite Content Persist** | No | Yes | No |
| **Panic Wipe Orchestrator** | Yes | No | No |
| **Theme / Design Tokens** | No | No | Yes |
| **Generic UI Kit Buttons** | No | No | Yes |
| **Platform Notification GUIDs** | Yes (Local) | Yes (Remote) | No |
| **STUN/TURN signaling** | No | Yes | No |
| **WebRTC Audio/Video** | Yes (LAN-only) | Yes (relayed) | No |
