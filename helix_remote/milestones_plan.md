# Helix Remote — Milestones & Phase-by-Phase Plan

> This plan details the 5 Milestones for the development of Helix Remote and Helix Admin, structured sequentially to ensure a robust, E2E-encrypted, private, and federated communication platform.

---

## Milestone 1: Foundation Hardening & Standalone Server MVP
*Goal: Close the gap between "Component-only" and "Verified" status on the single-server app, harden E2EE, and prepare the backend for admin containerization.*

*   **Phase 1.1: Backend Prep & Admin API**
    *   Implement Server Identity (Server ID + public/private keypair) generated at first boot.
    *   Implement an admin authentication layer (admin API key or admin JWT scope).
    *   Expose admin API endpoints for basic stats, logs, config read/write, backup trigger, and user listing.
    *   Write a basic `Dockerfile` and `docker-compose.yml` configured for SQLite and attachments storage volumes.
*   **Phase 1.2: Cryptographic Hardening (E2EE)**
    *   Stabilize the Double Ratchet Protocol implementation in `helix_remote_crypto`.
    *   Add robust DH-ratchet step, out-of-order delivery handling, skipped-message key storage, session resets, and replay protection.
    *   Make key/session updates atomic with outbound/inbound database persistence to avoid out-of-sync states.
*   **Phase 1.3: Core Workflows Cleanup**
    *   Resolve WebSocket manager connection/reconnection edge cases.
    *   Fix account registration identity key consistency.
    *   Ensure the attachment authorization model correctly allows remote recipient downloads while preventing unauthorized third-party access.
*   **Phase 1.4: Calls & Notification Wakeup**
    *   Connect the WebRTC client-side calling UI to the server signaling backend.
    *   Set up FCM/APNs push notification wake behavior so the client is woken up when the process is closed to fetch incoming messages or call alerts.

---

## Milestone 2: Helix Admin v1 (Management Dashboard)
*Goal: Build a minimalist, secure server management panel focused solely on administration, avoiding wizard scope creep.*

*   **Phase 2.1: Admin App Bootstrap**
    *   Initialize the Helix Admin Flutter Web/Desktop application in the monorepo workspace.
    *   Implement secure login/session management using the backend admin API key.
*   **Phase 2.2: Build & Operate Panels**
    *   Create a configuration editor panel (updating environment variables or configuration file).
    *   Build the metrics monitor (displaying CPU/RAM, storage space, SQLite database size, and active client connections).
    *   Implement real-time log output streaming.
*   **Phase 2.3: Maintenance Panel**
    *   Implement a trigger to start automated server-level backups (creating safe database snapshots using SQLite `VACUUM INTO` and packaging attachment directories).
    *   Add an update check/trigger tool to pull the latest Docker images.
*   **Phase 2.4: Self-Hosting Guidance**
    *   Embed a static guide displaying clear instructions on how to purchase VPS hosting, set up standard Docker environments, and use external AI assistants (like Claude, Gemini, ChatGPT) to set up and manage the command-line side of hosting.

---

## Milestone 3: Federation — Discovery & 1-on-1 Messaging
*Goal: Establish secure server-to-server communication for direct communication, utilizing an opt-in directory.*

*   **Phase 3.1: Server-to-Server (S2S) API**
    *   Expose federated endpoints on the backend router for cross-server message proxying.
    *   Implement mutual S2S authentication using Server IDs and signed public-key handshakes.
*   **Phase 3.2: Hosted Federation Directory**
    *   Deploy a lightweight, independent Federation Directory server.
    *   Implement opt-in endpoints: server admins can toggled "Worldwide Mode" to register their server address and user mappings.
*   **Phase 3.3: Client-to-Server Pre-key Fetch Proxying**
    *   Add home-server query routing: client requests key bundle for user `user@domain.com`.
    *   If domain is external, the server queries the directory, locates the remote server, fetches the pre-key bundle, and proxies it back to the client.
*   **Phase 3.4: Federated 1-on-1 Chats**
    *   Enable cross-server message delivery over S2S REST/WebSocket connections.
    *   Support federated text, media, and voice messaging under full E2EE.

---

## Milestone 4: Federation — Groups
*Goal: Expand S2S proxying to support shared chats across multiple servers.*

*   **Phase 4.1: Federated Group Membership**
    *   Route group invites, joins, leaves, and admin updates across S2S boundaries.
    *   Sync group metadata consistently across participating servers.
*   **Phase 4.2: Federated Group Cryptography**
    *   Extend Sender Keys protocol distribution over S2S links.
    *   Ensure group creator and admin signature verification works across server boundaries.
*   **Phase 4.3: Federated Group Messages**
    *   Enable secure message fan-out to all participating server endpoints for active group members.

---

## Milestone 5: Federation — Calls
*Goal: Route WebRTC signaling over federation, leveraging existing STUN/TURN infrastructure for media streams.*

*   **Phase 5.1: Federated WebRTC Signaling**
    *   Map WebRTC signal frames (SDP offer/answer, ICE candidates) to S2S messages.
    *   Route signaling packets between caller's home server and callee's home server.
*   **Phase 5.2: Media Relaying via Local STUN/TURN**
    *   Once signaling is completed, clients attempt direct P2P connections.
    *   If direct connection fails, clients automatically fallback to using the STUN/TURN credentials provided by their respective home servers.
