# backup module

Encrypted backups (F2, CRYPTO_V2.md §13). Schema `backup`.

| Table | Holds | Rules |
|---|---|---|
| `history_backups` | the automatic text-history backup, keyed by the AIK | at most 16 MiB; only a higher `version` replaces it; deleted on `onIdentityKeyChanged` (recovery, replacement), because the old key can no longer open it |
| `full_backups` | the user-secret backup envelope (opaque JSON) | only a higher `version` replaces it; refused if any key at any depth is `backup_key`, `passphrase` or `recovery_phrase`; its `media_ids` (backup-kind media) get their 90-day retention restarted |

Account deletion removes both. While the server is over its storage budget
(`HELIX_STORAGE_BUDGET_BYTES`), both `PUT`s answer `quota_exceeded`
(`reason: server_storage`); the stored backup stays as it was.

`GET /v1/backups/full/meta` answers only `full_backups.updated_at` - whether
the account has a recovery backup and when it was made - so any device can
show that without a `GET /v1/backups/full` download. "None" is a 200 with
`exists: false`, never a 404, so a client can tell it apart from a server that
does not know the route. It reads only this module's table, for the caller's
own account.

Body limits: history 16 MiB of data; a full backup up to
`FullBackup.maxEnvelopeBytes` (64 MiB, fixed by the protocol package), and
before decoding at most 32 levels deep and 100,000 JSON values
(`maxEnvelopeDepth`, `maxEnvelopeValues`; `bad_request` otherwise), so a
body of tiny values cannot expand into gigabytes of objects.

Both `PUT`s are rate-limited per account - 6 a minute for a full backup, 12
for the history - and answer `rate_limited` beyond that. Each request scans,
decodes and re-encodes its body, so without a limit one account could keep a
node parsing JSON continuously (AUD-5-6). Backups are occasional (a device
start or a settings change), so the allowance is headroom, not a schedule.
