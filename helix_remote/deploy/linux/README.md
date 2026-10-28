# Helix Global on a Linux VM

The Linux twin of `deploy/windows/`, for the day production moves off the PC
(`docs/operations/VM_MIGRATION.md`). One Ubuntu 22.04+/Debian 12 VPS: the server
under `systemd`, PostgreSQL 17, Caddy, coturn in Docker (two relays), nightly
encrypted backups, a health check, a monthly restore drill. **None of this has
been run on a real VM yet.**

| File | What it is |
|---|---|
| `install.sh` | one-time setup (user, folders, units, the PostgreSQL role, `ufw`, timers) |
| `helix-server.service` | the server, hardened (no new privileges, read-only system, its own folders) |
| `backup-helix.sh` + `helix-backup.{service,timer}` | nightly dump (verified), blobs (never overwritten), encrypted off-VM copy, which is **required** |
| `health-check.sh` + `helix-health.{service,timer}` | every 5 minutes: ready, services, disk, backups, drill, certificate, Postgres exposure; off-box heartbeat and alerts |
| `restore-drill.sh` + `helix-drill.{service,timer}` | restores the newest dump into a throwaway database and serves `ready` from it |
| `release.sh`, `deploy.sh` | build from a tag (on a build machine) and switch to it on the VM, with a hash check, a backup first, and a rollback if the migration fails |
| `Caddyfile.example` | TLS, headers, an access log without credentials, the operator routes only for named addresses |
| `backup.env.example` | the backup and alert settings (`/etc/helix/backup.env`) |
| `../../docker-compose.yml` | coturn: `helix-turn` (main) and `helix-turn-voice` (capped) |

Settings you add to `/etc/helix/backup.env` or `/opt/helix/.env` are read by the
ops scripts, never by the server. The server's own settings are in
`docs/operations/V2_SERVER_HANDOFF.md`.

Commands you will use:

```sh
sudo systemctl status helix-server            # state
journalctl -u helix-server -f                 # the log
sudo /opt/helix/ops/deploy.sh <tag>           # deploy (backs up first)
sudo -u helix /opt/helix/ops/backup-helix.sh  # a backup now
sudo systemctl start helix-drill              # a restore drill now
systemctl list-timers 'helix-*'               # when things run next
```

First-time admin setup is refused from the internet by design: set
`HELIX_ADMIN_PASSWORD` in `/opt/helix/.env` before the first start (it never
replaces an existing password; remove it afterwards), or run
`/opt/helix/bin/helix-admin-tool reset-password`.
