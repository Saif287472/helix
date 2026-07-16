# ADR 018: External File Export Outside Panic-Wipe Guarantees

Status: accepted  
Date: 2026-06-19  

## Context
When a user chooses to export a received file, save a picture, or share history outside the app sandbox, the file enters the user-controlled operating system storage.

## Decision
We establish that files exported outside the application sandbox are **outside panic-wipe guarantees**:
- The Local panic wipe can only wipe app-private storage, cache directories, and secure key buffers.
- The UI and user documentation must state clearly that exported files, manual media exports, or shared logs cannot be recalled or erased by the app's panic wipe.

## Consequences
- Prevents false security promises regarding external files.
- Informs user behavior clearly via UI notifications.
