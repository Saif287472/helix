# media module

Encrypted media objects (CRYPTO_V2.md §12). Schema `media` (`objects`).
Bytes live in `ObjectStorage` under `<kind>/<id>`.

| Kind | Max size | Quota per account | Objects per account | Kept |
|---|---|---|---|---|
| `attachment` | `HELIX_MAX_ATTACHMENT_BYTES` | 4 GiB | 100,000 | 30 days |
| `persistent` (avatars, group pictures) | 5 MiB | 50 MiB | 100,000 | until deleted |
| `backup` | 100 MiB | 1 GiB | 100,000 | 90 days, refreshed by each full backup |

With plans on (ADR-035, `billing` module) the attachment and backup rows follow
the account's plan, read at `createUpload`: Orbit Premium gets a 16 GiB attachment
quota, files of 4x `HELIX_MAX_ATTACHMENT_BYTES`, attachments kept 90 days, and
backup media of 400 MiB each and 4 GiB in all. An object keeps the retention it was
created with, so a lapsed Premium deletes nothing early. With the flag off the
table above is exact.

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
  the outbox retries it). Both also run in keyset batches of 500 under a
  deadline - `expireBudget` (4 minutes, below the periodic scheduler's
  timeout) for the sweep, `purgeBudget` (45 seconds, below the outbox job
  timeout) for the purge - because each blob delete is an unbounded store
  call: a slow store used to stretch one run past the timeout and get it
  killed mid-sweep (AUD-5-3). A sweep that runs out of budget returns with
  every finished object committed; a purge that does throws, with its
  finished objects committed and the usage row kept, so the retry deletes
  only what is left. A deleted or replaced full backup (backup module) has
  its dropped ids expired in the same transaction, then deleted at once
  under `deleteBudget` (10 seconds), so its ciphertext and quota go now and
  a store that cannot finish leaves the rest to the sweep (AUD-5-2).
  `media.sweep_orphans` (weekly) lists the store
  (`ObjectStorage.list`) and deletes blobs under a kind's prefix whose id has
  no row and that are older than a day (`orphanGrace`). `media.reconcile`
  (weekly, `reconcileBudget` 4 minutes) walks the distinct owners in keyset
  batches and, for an owner `IdentityApi.account` does not know, deletes its
  objects blob-first and drops its usage row: `persistent` objects never
  expire and a dead row keeps its blob from looking like an orphan, so this
  is the backstop for a purge job that dead-lettered (AUD-5-1). It also
  reports `account_usage` rows that disagree with the stored objects
  (`quotaDrift`); it never corrects them silently.
- **What the server never learns:** which message uses an object
  (there is no reference tracking, unlike v1), or what is in it.
