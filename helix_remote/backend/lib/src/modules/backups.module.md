# Module: backups

Status: current. Follows the template in `messaging.module.md`.

## Purpose

Server-side storage of the client's encrypted backup envelope, plus the
separate large-object store for backup media. The server holds ciphertext
and metadata only; it can never decrypt either.

## Owned files

- `backups.dart` - `BackupsModule` and its router.

## Route table

Mounted at `/api/v1/backups`. All routes require a session.

| Method | Path | Handler | Notes |
|---|---|---|---|
| POST | `/` | `_uploadBackupHandler` | One envelope per account, replaced on each upload. |
| GET | `/` | `_downloadBackupHandler` | 404 when the account has never backed up. |
| POST | `/media` | `_requestMediaUploadHandler` | Reserves an object id. |
| GET | `/media/status/<objectId>` | `_mediaUploadStatusHandler` | Owner only. |
| PUT | `/media/<objectId>` | `_uploadMediaObjectHandler` | `?offset=` resumes. SHA-256 verified. |
| GET | `/media/<objectId>` | `_downloadMediaObjectHandler` | Owner only, COMPLETED only. |
| GET | `/attachments/upload-url` | `_getAttachmentUploadUrlHandler` | Legacy shim; delegates to the same media path. |

## Error codes this module throws

The [`AppError`](../app_error.dart) shape: `.badRequest` for missing or
invalid envelope metadata, `.notFound` for a missing backup or media object,
and `.quotaExceeded` for the media quota.

## Dependencies

- `BackendDatabase` (`../database.dart`).
- A filesystem directory for media objects, same arrangement as
  `attachments`.

## Gotchas

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
