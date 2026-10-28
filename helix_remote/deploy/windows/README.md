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
| `release-helix.ps1` | Builds a release (`helix-server.exe`, `helix-migrate.exe`, `helix-admin-tool.exe`) from a git tag into the production folder's `releases\`. Touches nothing running. |
| `deploy-helix.ps1` | Switches production to a built release: graceful stop, swap, migrate, start, ready check. |
| `install-helix-tasks.ps1` | One-time, as administrator: the "Helix Server" task (at boot, restarted when it stops), the "Helix Health Check" task, the `Helix` event source; optionally Caddy and coturn tasks. |
| `run-helix-server.ps1` | What the "Helix Server" task runs: starts the server in the production folder and starts it again when it stops, until the stop file appears. |
| `helix-health-check.ps1` | What the health-check task runs: ready, the task, disk space, dead jobs and backlog; the event log and a notification when something changes. |

## Running production

Since review batch 9 (2026-10-14) production is meant to run a compiled
release from `J:\Projects\Servers\helix_server\helix`, started at boot by a
scheduled task, instead of `dart run` in the development checkout (where a
restart could start half-finished work). You do the move once; deploys are
then two commands.

### Move it there, once

1. **Tag the commit to run** (from `J:\Projects\helix`): `git tag server-2026-10-14`.
2. **Build it** (any PowerShell, from this folder):
   `.\release-helix.ps1 -Tag server-2026-10-14`
3. **Give the production folder its own `.env`.** Copy
   `helix_remote\server\.env` to `J:\Projects\Servers\helix_server\helix\.env`,
   then change in the copy (the server now starts in that folder, so
   relative paths would point somewhere new):
   - `HELIX_BLOB_DIR=` the **absolute** path of the blob folder you use today.
     If the line is missing, that is `J:\Projects\helix\helix_remote\server\helix_blobs`:
     add `HELIX_BLOB_DIR=J:\Projects\helix\helix_remote\server\helix_blobs`
     (or move the folder somewhere else first, with the server stopped, and
     point at that). The backup task's `-BlobDir` must name the same folder.
   - `HELIX_FCM_SERVICE_ACCOUNT=` an absolute path, if it is a path.
   - Add `HELIX_LOG_FILE=J:\Projects\Servers\helix_server\helix\logs\helix.log`
     (the task has no console, so this is where the log is).
   - Optional: `HELIX_METRICS_TOKEN=` (32 or more random characters), so the
     health check can see dead jobs and the backlog.
   From then on, `.env` changes go into this copy.
4. **Register the tasks**, in an administrator PowerShell, from this folder:
   `.\install-helix-tasks.ps1`
   (add `-CaddyExe J:\Projects\Servers\helix_server\caddy.exe -Caddyfile J:\Projects\Servers\helix_server\Caddyfile`
   to start Caddy at boot as well, and
   `-TurnScript J:\Projects\helix\helix_remote\deploy\coturn\windows\start-turn.ps1`
   for coturn at log-on). It starts nothing yet.
5. **Switch**: stop the console server (Ctrl+C in its window), then
   `.\deploy-helix.ps1 -Tag server-2026-10-14`. It installs the release,
   migrates and starts the task, and waits for `ready`.
6. Reboot once when convenient and check that Helix Global comes back by
   itself (the event log, source `Helix`, and `logs\wrapper.log` show the
   starts).

### Deploy a new version

```powershell
git tag server-2026-11-02                      # in J:\Projects\helix
.\release-helix.ps1 -Tag server-2026-11-02     # build; production keeps running
.\deploy-helix.ps1  -Tag server-2026-11-02     # stop, swap, migrate, start
```

To go back, deploy the previous tag (its build stays in `releases\`).
Migrations only ever expand the schema, so an older version runs on it.

### When something is wrong

- **The task**: `Get-ScheduledTask 'Helix Server'`; start or stop with
  `Start-ScheduledTask` / `deploy-helix.ps1`. Stopping it with
  `Stop-ScheduledTask` is a hard stop (in-flight requests are lost); to stop
  gracefully, create the file `stop` in the production folder.
- **Why it stopped**: `logs\stderr-last-run.log` (configuration errors, exit
  78), `logs\wrapper.log`, and the Application event log (source `Helix`).
- **The health check**: `health-state.json` in the production folder holds
  the last result; notifications appear only when the result changes.

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

## Hardening changes of 2026-10-28 (read before the next deploy)

Written from the security survey; **none of this was run on a Windows PC**, so
try each step once while you can watch it.

**Off-box alerts and the new health checks.** The health check now also looks
at backup age, restore-drill age, the certificate, Postgres, Caddy and coturn,
and can tell someone who is not at the PC. Add any of these lines to
`<Dest>\.env` (the server ignores them; none is secret except the two URLs,
which are as good as a password, so keep `.env` private):

```ini
# The folder the backup task writes to: the check then flags a dump older than
# 36 hours, a backup run that ended with errors, and no passing restore drill
# in 45 days.
HELIX_BACKUP_DIR=F:\helix-backups
# A dead-man's switch: create a check at healthchecks.io (or similar), paste its
# ping URL. It is pinged on every healthy run (every 5 minutes); when the pings
# stop for longer than you set there, it emails or messages you - even when this
# PC is off or hung.
HELIX_HEARTBEAT_URL=https://hc-ping.com/<your-uuid>
# A plain-text POST on every change (a problem, or all clear). ntfy.sh works:
# pick a long random topic and install the ntfy app on your phone.
HELIX_ALERT_URL=https://ntfy.sh/<long-random-topic>
```

Then re-run `install-helix-tasks.ps1` once: the health check now also runs at
boot, **whether or not anyone is logged on** (before, it ran only while you
were), and the backup task (`install-backup-task.ps1`) runs the same way. A
desktop toast needs someone logged on, so with nobody at the PC the Event Log
entry and the off-box alert are what you get. The coturn task still starts at
logon (WSL under a service-style task is untested): after a reboot with nobody
logged in, calls do not connect until you log in. The health check now says so
("coturn is not running in WSL"). A backup folder on a network share is not
reachable from a task that runs while you are logged off; use a local or USB
drive, or store the share's credentials with `cmdkey`.

**Backups must leave the PC.** `install-backup-task.ps1` now refuses to
install without `-OffsiteDir` (a USB drive, another PC, a synced folder) unless
you pass `-NoOffsite` on purpose, and it wants `-AgeRecipient` (encrypt the
copy) or `-OffsitePlain`. A thief or ransomware that gets this PC and its
drives otherwise takes the live data and every backup together. Prefer a
destination the server's Windows user cannot delete from (another PC with its
own login, or storage with versions or object lock).
The blob copy no longer overwrites a file that already exists in the copy: blobs
never change, so a different file is damage, and last night's good copy is kept.

**Deploys take a restore point first, and check the build.**
`deploy-helix.ps1` takes a database backup before it changes anything (pass
`-BackupDir`, or set `HELIX_BACKUP_DIR` once as a Windows user variable; a
failed backup stops the deploy; `-SkipBackup` skips it), and refuses
executables whose SHA-256 differs from the one `release-helix.ps1` wrote into
`VERSION`. `release-helix.ps1` refuses a tag that is not on `origin/main`
(`-AllowOffMain` overrides); `-RequireSignedTag` also demands a signed tag
(`git tag -s`, with an SSH signing key: `git config gpg.format ssh`).

**Caddy** (`Caddyfile.example`): security headers, `-Server`, and an access log
with the Authorization header removed, in `logs\access.log` next to the
Caddyfile (20 MiB, ten files kept). Narrow the operator-only range from
`192.168.0.0/16` to this PC's address and your phones' reserved addresses when
you can. **coturn** now also denies IPv4-in-IPv6 peers (`::ffff:`, NAT64,
6to4) and drops root once started (`TURN_KEEP_ROOT=1` in the start script's
environment turns that off if WSL1 refuses it).
