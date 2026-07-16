# Helix Remote Wire Compatibility Policy

This document defines the policies and technical design principles governing backward and forward compatibility for the Helix Remote wire protocols (REST API and WebSocket realtime events), addressing tasks P8-040 through P8-044.

---

## 1. Protocol Isolation (P8-044)
*   **Rule**: The Helix Remote protocol and APIs are developed and versioned completely independently from the Helix Local LAN wire protocol.
*   **Rationale**: Helix Local uses a binary CBOR frame structure over raw sockets designed for instant LAN delivery with session-only parameters. Helix Remote utilizes JSON over REST and WebSockets designed for persistent, multi-device synchronization, client caching, and server routing. They must never share protocol codecs or version numbers.

## 2. Unknown-Event Behavior (P8-042)
*   To enable rolling updates and new feature rollouts without crashing older clients, the client and server follow a **graceful degradation / ignore-unknown-type** model.
*   **Base Envelope Parsing**: The client must always attempt to parse the outer event envelope (`event_id`, `request_id`, `server_sequence`, `timestamp`, `type`, `schema_version`).
*   **Handling Unknown Types**: If the client receives a message containing an unknown `type` or a `schema_version` higher than the client supports:
    1.  The client updates its local `server_sequence` cursor to acknowledge receipt of the event (preventing the event from blocking the sync queue).
    2.  The client ignores the unrecognized payload entirely.
    3.  The client logs an advisory notice (excluding sensitive ciphertext).
    4.  No app crashes, and no protocol sync loops are broken.

## 3. Strict Semantics (P8-043)
*   **Rule**: Once an endpoint or a WebSocket event payload schema is published, its wire semantics must never be silently changed.
*   **Fields**:
    *   Existing fields must never be renamed or have their semantic meaning changed.
    *   Required fields in requests must never be added in patch/minor versions.
    *   Required fields in responses must never be removed in patch/minor versions.
*   **Format**: Any semantic change requires a new endpoint version (e.g. `/api/v2/...`) or a new WebSocket schema version.

## 4. Deprecation Windows and Versioning (P8-041, P8-040)
*   **Versioning Schema**:
    *   **REST API**: Scoped via path variables (e.g., `/api/v1/auth/login`).
    *   **WebSocket Envelope**: Tracked via `schema_version` (integer).
*   **Deprecation Flow**:
    1.  **Announcement**: When a version is deprecated, the server starts returning a `Warning: 299 - "Deprecated: Use v2 by [date]"` HTTP header.
    2.  **Grace Period**: The deprecated version must remain active and functional for a minimum deprecation window:
        *   **Minor/Patch deprecation**: 90 days.
        *   **Major version deprecation (e.g., v1 -> v2)**: 180 days.
    3.  **Decommission**: After the window expires, the server drops the deprecated endpoint and returns `410 Gone`.
