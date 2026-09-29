# Feature Ownership Matrix

Defines which features and behaviors map to Local or Remote.

> Note (2026-09): there is no shared code. Helix Local and Helix Remote are separate workspaces (`helix_local/`, `helix_remote/`) that share no packages, so every "Shared Context: Yes" below means each product has its own copy (Remote theme and UI kit: `helix_remote/packages/helix_remote_ui`; Local: `helix_local/app/lib/ui/app_theme.dart`).

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
