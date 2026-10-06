# media module

Encrypted media objects (CRYPTO_V2.md §12). Schema `media` (`objects`).
Bytes live in `ObjectStorage` under `<kind>/<id>`.

| Kind | Max size | Quota per account | Kept |
|---|---|---|---|
| `attachment` | `HELIX_MAX_ATTACHMENT_BYTES` | 4 GiB | 30 days |
| `persistent` (avatars, group pictures) | 5 MiB | 50 MiB | until deleted |
| `backup` | 100 MiB | 1 GiB | 90 days, refreshed by each full backup |

- **Upload:** `POST /v1/media` creates a random-id object.
  - Local storage returns the relative path `/v1/media/{id}/content`: a
    resumable `PUT` with `Upload-Offset` (a wrong offset gives 409 with
    the stored offset; a size over the declared one gives 413).
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
  `media.purge_account`.
- **What the server never learns:** which message uses an object
  (there is no reference tracking, unlike v1), or what is in it.
