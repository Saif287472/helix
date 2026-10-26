# Review status — machine review of the remediation commits

**Date:** 2026-10-26. **Scope:** the net change from `3871a15^` to `654483d` in
the highest-risk areas. **Not** the owner's review: the commits still say
"(pending review)", and that stays until the owner has looked at them. This file
records what four independent read-only reviewers (fresh sessions, given the
paths and no conclusions) found, and what was done about it.

## Areas read

| Area | Paths | Result |
|---|---|---|
| Identity, keys, crypto | `helix_remote_crypto`, `modules/identity`, `modules/keys` | No security regression. No signature, transcript or AEAD check was touched; no session minted outside `issueDeviceSession`; device cap race-free; purpose binding only stricter. Two small fixes below. |
| Server modules, platform, every migration | `modules/{people,groups,calls,media,messaging,backup}`, `platform/` | Migrations (platform 3-5, people 5, groups 4-6, media 2, calls 3) all safe on a populated database; none already-run was edited. Three defects below. |
| Local database, backup, transfers | `helix_remote_db`, engine `backup/`, `transfers/`, `media_service`, `maintenance`, `chats_service` | No defect. Claim token, schema 5 step, chunked `IN`, tombstones, `end` record and `recoverInterrupted` all hold. Two narrow edge cases left as designed (below). |
| Wire contract and app glue | `helix_remote_protocol`, `helix_remote_api`, `contracts`, app `core/` (engine, security, notifications, push, platform, diagnostics), CLI | All wire changes additive or unused removals; wipes, app lock and URL policy correct. Three anomaly-log defects and one alert-count gap below. |

## Defects found and fixed

| # | Where | Defect | Fix |
|---|---|---|---|
| 1 | `platform/http/routes.dart` | Buffered bodies had a flat 30 s end-to-end limit, so a 40 MiB full backup on a 1-2 MB/s link timed out on every retry. | The limit is 30 s plus the time a body of the route's cap needs at 128 KiB/s. Test: a 300 ms steady upload to a 64 MiB route succeeds. |
| 2 | `modules/media/module.dart` | Two deleters racing on one object both released its quota. | Release only when the `DELETE` removed the row. Not testable without forcing the race. |
| 3 | `modules/backup` + `media` | A full-backup PUT deleted every unreferenced backup object, including another upload's in-flight media. | Only objects created no later than the replaced backup's `updated_at` expire. Test added. |
| 4 | `identity/application/sign_up.dart` | A gateway timeout (text possibly sent) refunded the per-number and daily limits. | No refund and no challenge deletion for `unreachable`. Test added; fails on the old code. |
| 5 | `identity/data/identity_store.dart` | `last_seen_on` used the database's time zone while the cache counted UTC days. | UTC date in SQL. |
| 6 | app `AnomalyLog` | A runtime opened for another account's server tagged its request failures and wake states with the on-screen server. | Runtimes and the wake pass pass their own server explicitly. Test added. |
| 7 | app `push_background.dart` | "account failed" was recorded with no server and then assigned to the next account's server. | Tagged with the failed account's server. |
| 8 | app `AnomalyLog` | A server that rejected the route was retried every 20 s for ever. | Exponential backoff to one hour; reset on success. Test added. |
| 9 | app `app_storage.dart` | `alert_count.json` survived a destructive reset. | Removed by `wipeLocalFiles`. |
| 10 | app `AnomalyLog.failure` | A debug build kept 2000 characters of an error, which for a database error can include statement parameters. | 300 characters always. |

Also fixed earlier in this pass: `retention_test.dart` filed three identical
reports after the report dedupe (`654483d`).

## Seen, not changed

- **Group roster announcements** (`groups/module.dart`, `_announce`): the 15 s
  dedupe key is written outside the roster transaction, so a rolled-back change
  that is retried within 15 s tells only the accounts it names. Narrow; left.
- **Chat tombstones:** permanent for a chat; a restore drops post-clear messages
  the device does not already hold. Judged by design (live messages are local).
- **Archive `end` frame** can exceed the byte budget by a few hundred bytes in
  the narrowest case; the upload retries with a smaller budget.
- **Idempotency:** if recording a finished response fails, the claim stays
  pending 15 minutes and the retry then repeats the handler.
- **`_report`:** a rare 500 if an open report is closed between the insert and
  the follow-up select.
- **Federation leave:** any status below 500 (including 429) clears an owed
  leave; the code says this is intentional.
- **`ForegroundWakes`** merges a wake-up with a token pass and skips the mailbox
  read for the other accounts until the next wake (stale badge only).
- **`restore()`** deletes unlisted account folders if the keystore list decodes
  to nothing; unlikely.
- **`accountStatus`** reveals whether a number has an account: the recorded
  ADR-032 decision.

## What this review did not cover

Everything outside the paths above (UI, copy, media adapters, notifications UI,
admin console, CLI beyond the URL rule, tests) and anything only a device
shows. Reviewers read code and did not run it; the suites were run by the
author. A reviewer who is also the author's tool is not independent of the
author's blind spots; the owner's pass is still owed.
