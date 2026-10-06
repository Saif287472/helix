# ADR 008: Remote Deletion Semantics

Status: accepted  

> Status note (Phase X): the tombstone and sequence mechanism describes v1. In v2 the server keeps no history, deletes are encrypted content applied by each device, and account deletion is an event every module handles (ADR-028, `docs/product/RETENTION_AND_DELETION.md`).
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
