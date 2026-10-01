# backup module

Encrypted backups (F2, CRYPTO_V2.md §13). Schema `backup`.

| Table | Holds | Rules |
|---|---|---|
| `history_backups` | the automatic text-history backup, keyed by the AIK | at most 16 MiB; only a higher `version` replaces it; deleted on `onIdentityKeyChanged` (recovery, replacement), because the old key can no longer open it |
| `full_backups` | the user-secret backup envelope (opaque JSON) | only a higher `version` replaces it; refused if any key at any depth is `backup_key`, `passphrase` or `recovery_phrase`; its `media_ids` (backup-kind media) get their 90-day retention restarted |

Account deletion removes both.

Body limits: history 16 MiB of data; a full backup up to
`FullBackup.maxEnvelopeBytes` (64 MiB, fixed by the protocol package), and
before decoding at most 32 levels deep and 100,000 JSON values
(`maxEnvelopeDepth`, `maxEnvelopeValues`; `bad_request` otherwise), so a
body of tiny values cannot expand into gigabytes of objects.
