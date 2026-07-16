# ADR 008: Remote Deletion Semantics

Status: accepted  
Date: 2026-06-19  

## Context
When a user deletes a message, thread, contact, or account in Helix Remote, the system must ensure that deletion is consistently propagated.

## Decision
Helix Remote deletion flows are modeled as transactional synchronization events:
- **Tombstones**: Deleting a record generates a tombstone with a sequence number.
- **Sync Propagation**: Connected devices pull tombstones and apply deletions locally.
- **Wipe Expiry**: Backend attachments and thumbnails are deleted from S3 storage when reference counts drop to zero.
- **Account Deletion**: Deleting an account erases all user profile fields, device registers, and active mailboxes from the server.

## Consequences
- Guaranteed deletion propagation across offline devices when they reconnect.
- Strict backend data hygiene.
