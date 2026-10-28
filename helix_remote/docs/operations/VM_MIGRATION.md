# Moving Helix Global from the PC to a Linux VM

Written 2026-10-28 for the day the owner moves production off the Windows PC
(`deploy/windows/`) to one Ubuntu or Debian VPS (`deploy/linux/`). Nothing here
has been run on a real VM yet: do the dry run (section 2) first, and read the
whole page before the cutover. Agents do not touch the live server, `.env` or
the production database: every step is yours.

## What stays the same, and what must not change

The apps and every other server know Helix Global by **its name**
(`helix.agiletechbd.com`), not its address. So:

- **Keep the same domain.** Only the DNS record's IP changes. A different name
  would sign everyone out of Global and break federation, links and the app's
  built-in address.
- **Move the secrets unchanged.** The whole `.env` goes over as it is. Above all
  `HELIX_PHONE_PEPPER` (changing it orphans every account), `HELIX_PHONE_KEY`,
  and the JWT ring (changing it signs everyone out once; harmless but noisy). A
  new `.env` written from scratch is the one way to lose accounts.
- **Move the data in one piece:** the database dump and the blobs from the same
  moment.
- The federation signing key lives **in the database**, so it moves with the dump.

What changes:

| | PC | VM |
|---|---|---|
| Process | scheduled task "Helix Server" | `systemd` unit `helix-server` |
| TLS and proxy | Caddy for Windows | Caddy, certificates automatic (ports 80/443 open) |
| Operator console reach | home LAN (`192.168.0.0/16`) | an allow-list: your fixed IP or a VPN range (`Caddyfile.example`) |
| First-time admin setup | from the LAN | refused from the internet: set `HELIX_ADMIN_PASSWORD` before the first start, or use `helix-admin-tool` |
| coturn | WSL1 + router forwards | Docker, two relays (`docker-compose.yml`), `ufw` ports; set `TURN_EXTERNAL_IP` to the VM's public IPv4, no `TURN_LOCAL_IP` |
| Backups | scheduled task, USB/offsite | `helix-backup.timer`, encrypted off-VM copy (required) |
| Health and alerts | scheduled task | `helix-health.timer`, same alerts |
| Deploys | `release-helix.ps1` + `deploy-helix.ps1` | `release.sh` (a build machine) + `deploy.sh` (the VM) |
| Paths | `J:\Projects\Servers\helix_server\helix` | `/opt/helix`, blobs `/var/lib/helix/blobs`, backups `/var/backups/helix` |

Edit these in the `.env` copied to the VM: `HELIX_BLOB_DIR=/var/lib/helix/blobs`,
`HELIX_LOG_FILE=/opt/helix/logs/server.log`,
`HELIX_DATABASE_URL=postgresql://helix:<new password>@127.0.0.1:5432/helix?sslmode=disable`,
`HELIX_TURN_URLS`/`HELIX_TURN_VOICE_URLS` (same names, same ports),
`HELIX_HOST=127.0.0.1`, and nothing that names a Windows path.

## 1. Before anything: the VM

1. A VPS with at least 2 vCPU, 4 GB RAM, an SSD big enough for the database, the
   blobs (they are encrypted attachments, 30 days by default; your PC's blob
   folder size plus room) and a week of dumps. A static public IPv4. Note the
   provider's snapshot policy: a snapshot on the same account is not an
   off-box backup.
2. Ubuntu 22.04/24.04 or Debian 12. Create a normal sudo user; SSH by key only
   (`PasswordAuthentication no`), root login off.
3. Install PostgreSQL 17 (apt.postgresql.org), Caddy, Docker, `age`, `rclone`,
   `rsync`, `ufw`. Make `listen_addresses = 'localhost'`.
4. `sudo ./install.sh --domain helix.agiletechbd.com` from `deploy/linux/`.
5. Set the `helix` role's password; write `/opt/helix/.env` (copy of the PC's,
   edited as above; mode 600, owner `helix`). Set `HELIX_ADMIN_PASSWORD`.
6. `/etc/helix/backup.env`: `HELIX_OFFSITE`, `HELIX_AGE_RECIPIENT` (generate the
   key pair with `age-keygen` **elsewhere** and keep the private key off the VM),
   `HELIX_ALERT_URL`, `HELIX_HEARTBEAT_URL`.
7. Build a release: on a Linux x86_64 machine with Flutter, `./release.sh
   <tag>`; copy the folder to the VM; `sudo /opt/helix/ops/deploy.sh <tag>
   --skip-backup` (there is no data to back up yet). The server starts against
   an empty database and runs its migrations: that is the dry run's server.

## 2. The dry run (a few days before the cutover)

Do it all once with **real data and a different name**, so nothing is a
surprise on the day:

1. On the PC, take a backup (`backup-helix.ps1`) and copy the newest dump and the
   blob folder to the VM (`scp`/`rsync`).
2. On the VM, stop the server; `dropdb helix; createdb -O helix helix`;
   `pg_restore --no-owner -d helix helix-….dump`; copy the blobs into
   `/var/lib/helix/blobs` (owner `helix`); `bin/helix-migrate`; start.
3. Check `curl http://127.0.0.1:8080/v1/health/ready`, the journal
   (`journalctl -u helix-server`), `restore-drill.sh`, and one backup run
   (`sudo -u helix /opt/helix/ops/backup-helix.sh`): the encrypted copy appears
   off the VM, and you can decrypt it with the private key.
4. Try a call over a test client pointed at the VM's IP (TURN reachable from
   mobile data, both relays up). Do not point DNS at it yet.
5. Time the restore and the copy. That is your downtime on the day.

## 3. The cutover (a quiet hour)

Lower the DNS record's TTL to 300 seconds a day before.

1. **Maintenance mode** on the PC (Orbit Console > Settings): people see "try
   again shortly" instead of failed sends. Wait a minute for in-flight work.
2. **Stop the PC server** (`Stop-ScheduledTask 'Helix Server'`), so nothing writes.
3. **Final backup** on the PC (`backup-helix.ps1`), then copy the newest dump and
   the blobs to the VM (the blob copy is incremental if you already did the dry
   run: `rsync -a --ignore-existing`).
4. On the VM: restore as in the dry run (step 2), `helix-migrate`, start,
   check ready. Then `docker compose --env-file server/.env up -d helix-turn
   helix-turn-voice` in the folder with `docker-compose.yml`.
5. **Switch DNS** to the VM's IP. On the PC, remove any `hosts` entry that points
   the name at the LAN, and stop its Caddy and coturn tasks.
6. Watch the journal. Turn maintenance mode off once `ready` is 200 on the new
   address (`curl -s https://helix.agiletechbd.com/v1/health/ready`).
7. Test from a phone on mobile data: sign in, send, receive, a call both ways
   (voice and video), the plan page, a push (the app closed). Open the console from
   an allowed address.

**Rollback** is only clean in the first minutes: before anyone writes on the VM,
point DNS back and start the PC's server again. After people have written on the
VM, the PC's data is stale: do not point back without dumping the VM and
restoring it on the PC first.

## 4. After the move

- Disable the Windows tasks (Helix Server, Caddy, TURN, Health Check, Helix Global
  backup) so two servers never run on one name. Keep the PC's data for a few
  weeks, read-only, as a last resort; then delete the disk contents safely.
- Federation peers cache your signing key (it did not change) and your name (it
  did not change): nothing to tell them. If you ever change the key, see
  `KEY_COMPROMISE_RUNBOOK.md`.
- FCM and BulkSMSBD credentials work from any IP (unless the SMS provider
  whitelists your PC's address: check its panel and add the VM's).
- Re-run the checks in `THREAT_MODEL.md` that mention "this PC": the operator
  console is no longer "behind the home router", so keep the allow-list tight.
- Raise HSTS to a year (`Caddyfile`) after a week.

## 5. What a VM adds, and what it still needs from you

- **Snapshots** are fast restore points. They protect against a bad deploy, not
  against an account takeover or the provider failing; the off-VM encrypted
  backup does. Keep both.
- **Updates:** `unattended-upgrades` for security fixes, a reboot window (the
  `systemd` unit and Postgres come back by themselves, the timers have
  `Persistent=true`), and a monthly look at coturn's image
  (`docker compose pull`).
- **Access:** SSH keys only, `fail2ban` is optional, nothing but 22/80/443/3478/3479
  and the relay range is open. PostgreSQL and port 8080 never are.
- **Scale:** this is still one node. When one VM is not enough:
  `HELIX_TOPOLOGY=cluster`, `HELIX_BLOB_STORE=s3`, a managed PostgreSQL, and
  several nodes behind a load balancer (`V2_SERVER_HANDOFF.md`, "Object
  storage"). There is no tool to move blobs from local disk to S3: copy them with
  `rclone copy /var/lib/helix/blobs s3:bucket --ignore-existing` while the server
  is stopped, keeping the same object keys, then switch the setting.
