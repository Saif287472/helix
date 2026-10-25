# compliance module

Data export and account deletion for the signed-in account. It has no
tables.

| Route | Access | Rate limit |
|---|---|---|
| `GET /v1/account/export` | device (also while suspended) | 5 per day per device |
| `DELETE /v1/account` | device (also while suspended) | 5 per hour per device |

- **Export:** one repeatable-read, read-only snapshot. Every module
  implementing `ProvidesAccountExport` contributes a section under its
  name: identity, keys, messaging, people, media, backup and groups. The
  response is sent as an attachment.
- **A section that can grow is capped and says so** (owner ruling Q3): people
  lists the newest 500 reports and blocks (`reports_filed_total`/`_truncated`,
  `blocked_total`/`_truncated`) and media the newest 5,000 objects
  (`{objects, total, truncated}`), so one account cannot make the export as
  big as its history. Identity's security events are capped the same way.
  Sections still count what they omit; they do not stream.
- **What sections hold:** sections hold metadata only, never secrets,
  tokens, ciphertext or other people's numbers. Encrypted things (profile,
  backups, media, undelivered envelopes) appear as versions, sizes, dates
  or counts. Public keys are the account's own.
- **Deletion:** needs `{"confirmation": "DELETE"}` and a proof of
  ownership (`current_auth_key`, `verification_token` or `device_proof`,
  identity's `confirmOwnership`; a session token alone is refused with
  `invalid_credentials`). It runs identity's
  `deleteAccount` in one transaction: every device is revoked, which purges
  keys and mailbox and closes sockets; every `onAccountDeleted` hook runs
  (people, media, backup, groups); then the account row goes. Deletion is
  not a ban: the number can sign up again. Reports about or by the account
  stay as the moderation record (ids only).
- **Wiring:** exporters are collected by `allModules()` as modules are
  created, so adding a module with account data means implementing
  `ProvidesAccountExport`; the compliance module needs no change.
