# Module: attachments

Status: current. Follows the template in `messaging.module.md`.

## Purpose

Resumable upload and range-capable download of end-to-end-encrypted message
attachments, plus the reference-counting that decides when a stored blob can
be deleted.

## Owned files

- `attachments.dart` - `AttachmentsModule`, its router, and the retention
  sweeps (`cleanupOrphans`, `runLifecycleRules`,
  `cleanAttachmentReferences`).

## Route table

Mounted at `/api/v1/attachments`. All routes require a session.

| Method | Path | Handler | Notes |
|---|---|---|---|
| POST | `/upload` | `_requestUploadHandler` | Reserves a file id. Max 10 MB/file, 50 MB/account. |
| GET | `/upload/status/<fileId>` | `_uploadStatusHandler` | Owner only. Re-syncs DB progress from what is on disk. |
| PUT | `/upload/file/<fileId>` | `_uploadFileHandler` | Owner only. `?offset=` resumes. Verifies SHA-256 on completion. |
| GET | `/download/<fileId>` | `_requestDownloadHandler` | Returns a download URL. Requires a grant. |
| GET | `/download/file/<fileId>` | `_downloadFileHandler` | The bytes. Honours `Range`. |
| POST | `/register-reference` | `_registerReferenceHandler` | Links a file to a message and grants access to that conversation's members. |

## Error codes this module throws

The [`AppError`](../app_error.dart) shape. `.badRequest` for size, hash and
resume-offset problems, `.notFound` for an unknown file or one missing on
disk, `.forbidden` for access-control failures, and `.quotaExceeded` for the
50 MB account limit. The range handler throws a bare `AppError` with status
416 and a `Content-Range` header - the one place `AppError.headers` is used,
because a 416 without it does not tell the client the real object size.

## Dependencies

- `BackendDatabase` (`../database.dart`) - attachment rows, reference
  counts, access grants.
- `storageDir` - a plain filesystem directory, created on construction.
  Set from `HELIX_REMOTE_ATTACHMENTS_DIR`; on the Docker deployment this is
  a volume, not container-local disk.
- `crypto` for SHA-256, `path` for basename sanitization.

## Gotchas

- **File ids are content-addressed**: `file_id` *is* the client-supplied
  SHA-256. Two users uploading identical ciphertext therefore collide by
  design, which is why access is grant-based rather than owner-based on
  download.
- **`p.basename(fileId)` is applied on every filesystem path.** That is the
  path-traversal guard - a file id is attacker-controlled input.
- **Upload authorization and download authorization differ deliberately.**
  Upload/status/resume check `attachment.account_id == caller`. Download
  checks `db.canAccessAttachment`, so a remote recipient who was granted
  access can fetch it while an unrelated third party cannot.
- **A failed hash check deletes the file and marks the row FAILED**, rather
  than leaving a partial object that a resume would append to.
- **The upload handler's `catch` closes the write sink and is guarded by
  `on AppError { rethrow; }`.** Every AppError there is thrown after the
  sink is already closed; falling into the generic branch would close it
  twice.
- **Cleanup is reference-counted, not time-based**, except for
  `cleanupOrphans` (uploads that never completed) and `runLifecycleRules`
  (completed but unreferenced past a retention window).
