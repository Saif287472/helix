# media module

Encrypted media objects (CRYPTO_V2.md §12). Schema `media` (`objects`).
Bytes live in `ObjectStorage` under `<kind>/<id>`.

| Kind | Max size | Quota per account | Objects per account | Kept |
|---|---|---|---|---|
| `attachment` | `HELIX_MAX_ATTACHMENT_BYTES` | 4 GiB | 100,000 | 30 days |
| `persistent` (avatars, group pictures) | 5 MiB | 50 MiB | 100,000 | until deleted |
| `backup` | 100 MiB | 1 GiB | 100,000 | 90 days, refreshed by each full backup |

The object cap (`maxObjectsPerKind`) is independent of bytes: the smallest
legal object is one byte, so without it a 4 GiB quota can become millions of
rows that a sweep then deletes one blob at a time (AUD-5-3). Both the bytes
and the row count live in `media.account_usage`, one row per account and
kind, backfilled from `objects` by migration 2. A create reserves both in the
same statement that checks them, so two concurrent creates serialize on the
row instead of both passing a read-then-insert (AUD-5-4); deleting or
expiring an object gives both back.

- **Server-wide budget:** per-account quotas add up on one disk, so with
  `HELIX_STORAGE_BUDGET_BYTES` set, `POST /v1/media` answers
  `quota_exceeded` (`reason: server_storage`) while the database plus the
  stored objects are at or over it (`StorageBudget`, PLATFORM.md). This
  module reports its bytes to that budget as the sum of `objects.size`,
  reserved sizes of unfinished uploads included (review A-03).
- **Upload:** `POST /v1/media` creates a random-id object.
  - Local storage returns the relative path `/v1/media/{id}/content`: a
    resumable `PUT` with `Upload-Offset` (a wrong offset gives 409 with
    the stored offset; a size over the declared one gives 413). Two
    writers never mix into one object: `ObjectStorage.append` takes one
    writer per key and returns the file's real length, so a retry that
    overtakes the request it was retried after resumes at the stored
    offset instead of sealing a corrupt object as complete.
  - S3 returns a presigned PUT URL valid for 15 minutes. It signs
    `content-length` = the declared size, so the store refuses any other
    size (one `PUT` of exactly `size` bytes).
- **Status:** `HEAD …/content` returns `Upload-Offset` and
  `Upload-Length`.
- **Download:** any signed-in device, because ids are random and content
  is encrypted. Local storage serves `Range` (206 or 416); S3 redirects
  302 to a 5-minute presigned GET. Unfinished or expired objects are 404.
- **Housekeeping:** `media.expire` (every 30 minutes) deletes expired
  objects and uploads abandoned for a day. Account deletion enqueues
  `media.purge_account`. Both delete each blob before its row: a blob that
  cannot be deleted keeps its row for the next try (the purge job throws, so
  the outbox retries it). `media.sweep_orphans` (weekly) lists the store
  (`ObjectStorage.list`) and deletes blobs under a kind's prefix whose id has
  no row and that are older than a day (`orphanGrace`).
- **What the server never learns:** which message uses an object
  (there is no reference tracking, unlike v1), or what is in it.
