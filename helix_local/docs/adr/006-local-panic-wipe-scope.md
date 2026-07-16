# ADR 006: Local Panic Wipe Scope and Limitations

Status: accepted  
Date: 2026-06-19  

## Context
Helix Local has a security-critical "Panic Wipe" feature that must reliably destroy all traces of app usage instantly.

## Decision
The Local panic-wipe sequence must follow a strict, ordered execution path:
1. Block incoming and outgoing network sockets immediately.
2. Terminate all active calls, camera, and microphone handles.
3. Close open SQLite connection handles.
4. Truncate and delete database, WAL, and SHM files.
5. Recursively delete app-private cache, temp files, and logs.
6. Clear all secure storage namespaces.
7. Cancel all notifications and clear memory buffers.

Panic wipe is strictly local and must **never** make network calls to any remote service, preventing leakage of panic state.

## Consequences
- Guarantees immediate zero-remnant state in the app private directories.
- Wipes the device safely without network dependency.
