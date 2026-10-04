# backup

History backup, restore and device-to-device transfer (Phase A3b), on the
engine's `BackupService`.

- `/backup` Settings > Backup: automatic backup switch, "use mobile data",
  last backup, Back up now (progress, errors), links to the pages below,
  delete the server backup.
- `/backup/restore` and `/restore` (the step after signing in on a new device,
  with Skip). Adds what is missing, never replaces; safe to run twice. Errors:
  no backup, wrong key, damaged, newer format, rolled back, offline.
- `/backup/transfer` both sides of a device transfer: send (progress, cancel),
  and offers from other devices (accept, decline, pause, resume).
- `/backup/recovery` a second backup sealed under a secret only the person
  holds. The secret is generated in the app (24 characters, no lookalikes) or
  typed, shown once, never stored, sent, copied or logged, and never
  recoverable by Helix.

## Decisions

- **Offers wait for the person** (`autoAcceptTransfers: false` in
  `HelixRuntime.open`), so Pause means pause and a new device asks before
  downloading. The restore step lists them.
- **Mobile data** is enforced at the one place a backup leaves the phone:
  `PolicyBackupRemote` (core) refuses an *upload* on mobile data unless allowed;
  the engine records it and retries after its normal interval. Restores and
  the manual recovery backup are never blocked.
- **Schedule and media** are the engine's: once a day, text history with
  references to media (not the files). The page says so instead of offering a
  choice.
- `HelixRuntime.open` passes `dart:io`'s gzip to the engine, which fits more
  history into the server's 16 MiB.

## Wiring into sign-in

`core/engine/post_sign_in.dart` holds the step. The password sign-in (and
linking) ask for `offerRestore` before the engine signs in; the router
redirects to `/restore` once, and `RestoreStep.finish()` clears it.
