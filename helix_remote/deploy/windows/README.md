# Helix Global on the Windows PC: backups and the Caddy site

Operator scripts and config for the PC that runs Helix Global
(`docs/operations/V2_SERVER_HANDOFF.md` describes the PC,
`docs/operations/V2_OPERABILITY.md` the day-to-day work). **You install and
run them.** Agents write and test them, but never run them against
production, never handle the PostgreSQL passwords and never edit the live
Caddyfile.

| File | What it is |
|---|---|
| `backup-helix.ps1` | The daily backup: `pg_dump`, a readability check, the blob copy, an optional off-PC copy, and a fixed number of generations. |
| `install-backup-task.ps1` | One-time setup: the `pgpass.conf` entry, disk checks, the Task Scheduler task, and a first run. |
| `restore-drill.ps1` | The restore drill: restores a dump into `helix_drill`, starts a node on it, checks `ready`, and cleans up. |
| `Caddyfile.example` | The site block with HSTS and the operator-route restriction. |

## Backups

### 1. Choose where they go

The database lives in `C:\Program Files\PostgreSQL\17\data`, on the SSD (disk
1, drives C: and D:). The HDD (disk 0) holds F: to J:, including this
repository. A backup on the same disk as the data does not survive that
disk failing, so put `-BackupDir` on the HDD, for example `F:\helix-backups`.
The installer prints the disk of each folder and warns when they share one.

Also keep a copy **off the PC** (`-OffsiteDir`): a USB drive you unplug, or a
synced cloud folder. A dump holds password verifier hashes, undelivered
ciphertext, the federation signing key and every account's metadata (see
"Backups" in `V2_OPERABILITY.md`), so an off-PC copy must be encrypted:

- **A BitLocker drive** (a USB drive with BitLocker To Go): pass
  `-OffsitePlain`. The drive already encrypts everything on it.
- **Anywhere else** (a cloud folder, an unencrypted drive): pass
  `-AgeRecipient age1...` and install [age](https://github.com/FiloSottile/age).
  Make a key once with `age-keygen -o helix-backup-key.txt`, put the
  `age1...` public key in the command, and keep `helix-backup-key.txt` **off
  this PC** (on paper, or a USB drive in a drawer). This PC can then
  encrypt dumps, but cannot decrypt them.

Turn on BitLocker for the backup drive on the PC too, if you can.

### 2. Install

From `helix_remote\deploy\windows`, in your own PowerShell window (no admin
shell needed):

```powershell
.\install-backup-task.ps1 -BackupDir F:\helix-backups -WritePgPass -RunNow
```

With an off-PC copy on a BitLocker USB drive E: (add `-OffsiteBlobs` to copy
the blobs there too):

```powershell
.\install-backup-task.ps1 -BackupDir F:\helix-backups -OffsiteDir E:\helix-offsite -OffsitePlain -WritePgPass -RunNow
```

What it does:

- `-WritePgPass` asks for the `helix` role's password (the one in
  `HELIX_DATABASE_URL`) and writes the `127.0.0.1:5432:*:helix` line of
  `%APPDATA%\postgresql\pgpass.conf`. PostgreSQL tools read the password
  there, so it never appears on a command line. The file is in your Windows
  profile and holds the password in plain text, as `server\.env` does. Leave
  the flag out on later runs.
- Finds the blob directory from `HELIX_BLOB_DIR` (the process environment,
  then `server\.env`; only the two blob settings are read). Pass `-BlobDir`
  to choose it yourself.
- Copies `backup-helix.ps1` to `F:\helix-backups\backup-helix.ps1` and
  registers the task **Helix Global backup**: daily at 03:30 (`-At`), while
  you are signed in to Windows. If the PC was off at 03:30, it runs as soon
  as it can. Run the installer again after `backup-helix.ps1` changes.
- `-RunNow` runs the task once and shows the log.

Defaults: 14 dumps kept on the PC (`-Keep`), 7 off it (`-OffsiteKeep`).

### 3. Back up the secrets, once, apart from the dumps

The scripts never copy `server\.env`. Copy it and the Firebase service-account
key file yourself, once now and after every change, to somewhere that is
**not** next to the dumps (a password manager, or a second USB drive).
`HELIX_PHONE_PEPPER` cannot be recovered if lost, and a dump stored next to it
lets whoever holds both test phone numbers.

### 4. Check it keeps working

- `F:\helix-backups\backup.log` gets one line per step. A bad run ends with
  `END  finished WITH ERRORS`.
- Task Scheduler shows **Last Run Result** `0x0` after a good run and `0x1`
  after a bad one.
- `F:\helix-backups\db` has one `helix-<date>-<time>.dump` per run. A dump
  that `pg_restore --list` cannot read is renamed `.unverified` and never
  replaces a good one.

## Restore drill

Do this once now, then monthly (and after any PostgreSQL upgrade):

```powershell
.\restore-drill.ps1 -BackupDir F:\helix-backups
```

It restores the newest dump into a throwaway database, `helix_drill`, then
migrates and starts one server node on it at `127.0.0.1:8090`. It waits for
`/v1/health/ready`, then stops the node and drops `helix_drill`.
`createdb` asks for the PostgreSQL superuser password; the script asks for the
`helix` password, which it uses for the drill node's database URL. The result
goes to `F:\helix-backups\drill.log`.

The drill node cannot reach the real world. `platform.jobs` is emptied first,
push, SMS, Global mode and federation are off, it never uses the production
port, and it gets its own blob folder, log file and JWT keys. The production
server can keep running.

To drill the off-PC copy, pass the file and the key:
`-DumpFile E:\helix-offsite\helix-....dump.age -AgeIdentity <key file>`.
`-Keep` leaves `helix_drill` in place for a look around.

Not covered yet: phones whose mailbox cursor is ahead of a restored database
(`V2_OPERABILITY.md`, "Restore"). Decide that before a real restore.

## Caddy

`Caddyfile.example` is the live site block plus two things:

- **HSTS**, starting at one day. After a week without trouble, raise it to
  `max-age=31536000`.
- **The operator routes answer only to the PC and the home LAN.**
  `/v1/admin...` and `/v1/ops/metrics` get a plain 404 from anywhere else.

Install:

```powershell
cd J:\Projects\Servers\helix_server
copy Caddyfile Caddyfile.before-hardening
copy J:\Projects\helix\helix_remote\deploy\windows\Caddyfile.example Caddyfile
.\caddy.exe validate --config Caddyfile
.\caddy.exe reload --config Caddyfile
```

`reload` needs Caddy running. If it is not, start it as usual
(`.\caddy.exe run`). The Helix server is not restarted.

Check:

```powershell
curl.exe -sI https://helix.agiletechbd.com/v1/server
curl.exe -s https://helix.agiletechbd.com/v1/admin/setup
```

- **On the PC:** the first command shows `Strict-Transport-Security`. The
  second answers `{"configured":...}`; this PC reaches the site through its
  LAN address, because of the `hosts` entry.
- **On a phone using mobile data (Wi-Fi off):** open
  `https://helix.agiletechbd.com/v1/admin/setup` in a browser. It must
  answer 404 with an empty page. The Helix app keeps working.
- **The admin console on a phone using home Wi-Fi:** try signing in. The
  phone looks up the public address, so the router loops the connection
  back (NAT loopback). If the router keeps the phone's LAN address, sign-in
  works. If it gets "That item no longer exists.", the router replaced it
  with the public address. Then use the console on the PC.
- **The admin console off the home network** now gets "That item no longer
  exists." That is the block working.

To undo, copy `Caddyfile.before-hardening` back and reload.
