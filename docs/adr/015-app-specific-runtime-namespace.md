# ADR 015: App-Specific Runtime Namespace Configuration

Status: accepted  
Date: 2026-06-19  

## Context
When both applications are installed on a single OS (Android or Windows), they must not conflict on database files, secure keys, notifications, or method channels.

## Decision
We enforce app-specific identifiers at runtime:
- **Android App IDs**: `com.helix.local` vs `com.helix.remote`.
- **Windows GUIDs**: Separate notification GUIDs.
- **Database Names**: `helix_local.db` vs `helix_remote.db`.
- **Secure Storage Prefix**: Product-prefixed key paths.
- **Method Channels**: Separate channel namespaces (`com.helix.local/foreground` vs `com.helix.remote/foreground`).

Global constants for these values are prohibited; they must be provided dynamically or loaded via composition roots.

## Consequences
- Clean side-by-side installations on target platforms.
- Complete data isolation.
