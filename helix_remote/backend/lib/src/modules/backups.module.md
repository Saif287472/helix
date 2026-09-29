# Module: backups

Status: current. Follows the template in `messaging.module.md`.

## Purpose

Server-side storage of three things, all ciphertext the server can never
decrypt: the client's encrypted backup envelope (manual, recovery-secret
based), the automatic encrypted text-only chat history backup, and the
separate large-object store for backup media.

## Owned files

- `backups.dart` - `BackupsModule` and its router.

## Route table

Mounted at `/api/v1/backups`. All routes require a session.

| Method | Path | Handler | Notes |
|---|---|---|---|
| POST | `/` | `_uploadBackupHandler` | One envelope per account, replaced on each upload. |
| GET | `/` | `_downloadBackupHandler` | 404 when the account has never backed up. |
| PUT | `/history` | `_uploadHistoryBackupHandler` | Body `{"blob": ...}`. One per account, replaced on each upload; 413 `quotaExceeded` above 16 MB. |
| GET | `/history` | `_downloadHistoryBackupHandler` | Returns `blob` and `updated_at`; 404 when there is none. |
| POST | `/media` | `_requestMediaUploadHandler` | Reserves an object id. |
| GET | `/media/status/<objectId>` | `_mediaUploadStatusHandler` | Owner only. |
| PUT | `/media/<objectId>` | `_uploadMediaObjectHandler` | `?offset=` resumes. SHA-256 verified. |
| GET | `/media/<objectId>` | `_downloadMediaObjectHandler` | Owner only, COMPLETED only. |
| GET | `/attachments/upload-url` | `_getAttachmentUploadUrlHandler` | Legacy shim; delegates to the same media path. |

## Error codes this module throws

The [`AppError`](../app_error.dart) shape: `.badRequest` for missing or
invalid envelope metadata, `.notFound` for a missing backup or media object,
and `.quotaExceeded` for the media quota and for a history backup over
`maxHistoryBackupSize` (16 MB, returned as 413).

## Dependencies

- `BackendDatabase` (`../database.dart`) — `backups` table for the envelope;
  `history_backups` (migration 47, `saveHistoryBackup`/`getHistoryBackup` in
  `../database/passwords_repository.dart`) for the history backup.
- A filesystem directory for media objects, same arrangement as
  `attachments`.

## Gotchas

- **The history backup is opaque to the server.** The app
  (`helix_remote/app/lib/app/history_backup_codec.dart`) derives its key with HKDF from the
  account identity private key (info `helix.remote.history-backup.v1`), gzips
  the text history and seals it with AES-GCM, AAD bound to the identity public
  key. Any device of the account can read it, merge (union by message id, local
  copy wins, capped at 200,000 messages) and re-upload. No media is included.
  The server records `identity_public_key` and `size_bytes` next to the blob;
  when the account identity rotates, `updateAccountIdentityKey` deletes the row
  because nobody can decrypt it any more. Account deletion removes it by
  `ON DELETE CASCADE`.

- **The upload handler rejects any body containing `backup_key`,
  `passphrase` or `recovery_phrase`.** This is server-side enforcement that
  backup keys never leave the device - not a client convention. It is
  checked before anything else in the handler.
- **Object ids are validated against a strict pattern and the hash against
  hex-SHA-256** before any filesystem path is built.
- **Media objects carry a 90-day `retention_until`** set at creation.
- **`requires_reupload` and `deletion_watermark`** let the server tell a
  client its stored backup is stale relative to deletions the account has
  since made, without the server understanding the backup's contents.
- **The media upload's `catch` is guarded by `on AppError { rethrow; }`**
  for the same double-close reason as `attachments`.
