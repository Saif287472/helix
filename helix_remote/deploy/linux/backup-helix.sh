#!/usr/bin/env bash
# Nightly backup of Orbit Home: a verified database dump, the blobs, and an
# encrypted copy off this VM. Run by helix-backup.timer as the `helix` user.
#
# Settings (/etc/helix/backup.env, or the environment):
#   HELIX_BACKUP_DIR      local backups (default /var/backups/helix)
#   HELIX_BLOB_DIR        local blobs (default /var/lib/helix/blobs)
#   HELIX_DB_NAME         database (default helix); the helix OS user reaches
#                         it over the local socket with peer authentication
#   HELIX_KEEP            local dump generations (default 14)
#   HELIX_OFFSITE         where the encrypted copy goes: an rclone remote
#                         (`b2:my-bucket/helix`, `s3:bucket/path`) or a folder
#                         that is another machine's disk. REQUIRED unless
#                         HELIX_NO_OFFSITE=1: a backup that lives only on the VM
#                         it protects is lost with it.
#   HELIX_AGE_RECIPIENT   age public key; the copy leaving the VM is encrypted
#                         to it, and the private key lives off the VM
#   HELIX_OFFSITE_KEEP    dumps kept off the VM (default 14)
#   HELIX_OFFSITE_BLOBS   1: also copy the blobs off the VM (never overwriting)
#   HELIX_ALERT_URL / HELIX_HEARTBEAT_URL   see health-check.sh
#
# Never overwrites: blobs are written once under a random id and never change,
# so a file that differs from its copy is damage, and the good copy is kept.
set -euo pipefail
umask 077
# shellcheck source=common.sh
. "$(dirname "$(readlink -f "$0")")/common.sh"

BACKUP_DIR=$(setting HELIX_BACKUP_DIR); BACKUP_DIR=${BACKUP_DIR:-/var/backups/helix}
BLOB_DIR=$(setting HELIX_BLOB_DIR); BLOB_DIR=${BLOB_DIR:-/var/lib/helix/blobs}
DB_NAME=$(setting HELIX_DB_NAME); DB_NAME=${DB_NAME:-helix}
KEEP=$(setting HELIX_KEEP); KEEP=${KEEP:-14}
OFFSITE=$(setting HELIX_OFFSITE)
AGE_RECIPIENT=$(setting HELIX_AGE_RECIPIENT)
OFFSITE_KEEP=$(setting HELIX_OFFSITE_KEEP); OFFSITE_KEEP=${OFFSITE_KEEP:-14}
OFFSITE_BLOBS=$(setting HELIX_OFFSITE_BLOBS)
NO_OFFSITE=$(setting HELIX_NO_OFFSITE)
ALERT_URL=$(setting HELIX_ALERT_URL)

DB_DIR=$BACKUP_DIR/db
LOG=$BACKUP_DIR/backup.log
mkdir -p "$DB_DIR"
failed=0
started=$(date +%s)

log() { # status message
    local line
    line="$(date -Iseconds) $(printf '%-4s' "$1") $2"
    printf '%s\n' "$line" >>"$LOG"
    printf '%s\n' "$line"
    [ "$1" = FAIL ] && failed=1
    return 0
}
finish() {
    local secs=$(( $(date +%s) - started ))
    if [ "$failed" -ne 0 ]; then
        log END "finished WITH ERRORS in ${secs} s"
        notify_post "$ALERT_URL" "Helix backup finished with errors. See $LOG on the VM."
        exit 1
    fi
    log END "finished in ${secs} s"
}

if [ -z "$OFFSITE" ] && [ "$NO_OFFSITE" != 1 ]; then
    log FAIL "HELIX_OFFSITE is not set: a backup only on this VM is lost with it (HELIX_NO_OFFSITE=1 accepts that)"
    finish
fi
if [ -n "$OFFSITE" ] && [ -z "$AGE_RECIPIENT" ]; then
    log FAIL "HELIX_AGE_RECIPIENT is not set: what leaves the VM holds password verifiers and the federation key and must be encrypted"
    finish
fi

log run "start: database $DB_NAME into $BACKUP_DIR"

# Free space: at least the size of the last dump, twice, plus 1 GiB.
last=$(find "$DB_DIR" -maxdepth 1 -name 'helix-*.dump' -printf '%s\n' 2>/dev/null | sort -n | tail -n 1 || true)
need=$(( ${last:-0} * 2 + 1073741824 ))
free=$(df --output=avail -B1 "$BACKUP_DIR" | tail -n 1 | tr -d ' ')
if [ "$free" -lt "$need" ]; then
    log FAIL "only $free bytes free in $BACKUP_DIR (need $need)"
    finish
fi

# 1. The dump: written as .partial, verified, then renamed.
stamp=$(date +%Y%m%d-%H%M%S)
dump=$DB_DIR/helix-$stamp.dump
verified=0
if pg_dump --format=custom --no-owner --file="$dump.partial" "$DB_NAME" 2>>"$LOG"; then
    if pg_restore --list "$dump.partial" >/dev/null 2>>"$LOG"; then
        mv "$dump.partial" "$dump"
        verified=1
        log ok "dump helix-$stamp.dump, $(du -h "$dump" | cut -f1)"
    else
        mv "$dump.partial" "$dump.unverified"
        log FAIL "the dump did not verify (kept as helix-$stamp.dump.unverified)"
    fi
else
    rm -f "$dump.partial"
    log FAIL "pg_dump failed"
fi

# 2. The blobs, never overwriting what is already in the copy.
if [ -d "$BLOB_DIR" ]; then
    if rsync -a --ignore-existing "$BLOB_DIR"/ "$BACKUP_DIR/blobs/" 2>>"$LOG"; then
        log ok "blobs copied to $BACKUP_DIR/blobs"
    else
        log FAIL "blob copy failed"
    fi
fi

# 3. Off the VM, encrypted.
if [ "$verified" = 1 ] && [ -n "$OFFSITE" ]; then
    {
        enc=$DB_DIR/helix-$stamp.dump.age
        age --encrypt --recipient "$AGE_RECIPIENT" --output "$enc.partial" "$dump"
        mv "$enc.partial" "$enc"
        # The secrets (.env) travel too, as a separate encrypted file: losing the
        # pepper orphans every account, and a dump alone must never be enough to
        # use them. Same key, never in the same artifact as the dump.
        if [ -r "$HELIX_ENV_FILE" ]; then
            age --encrypt --recipient "$AGE_RECIPIENT" --output "$BACKUP_DIR/env-latest.age" "$HELIX_ENV_FILE"
        fi
        if [[ $OFFSITE == *:* ]] && command -v rclone >/dev/null 2>&1; then
            rclone copyto "$enc" "$OFFSITE/db/$(basename "$enc")" --immutable
            [ -f "$BACKUP_DIR/env-latest.age" ] && rclone copyto "$BACKUP_DIR/env-latest.age" "$OFFSITE/env/env-$stamp.age" --immutable
            if [ "$OFFSITE_BLOBS" = 1 ] && [ -d "$BLOB_DIR" ]; then
                rclone copy "$BLOB_DIR" "$OFFSITE/blobs" --ignore-existing --immutable
            fi
            # Keep the newest OFFSITE_KEEP dumps off the VM.
            rclone lsf "$OFFSITE/db" 2>/dev/null | sort | head -n -"$OFFSITE_KEEP" | while read -r old; do
                [ -n "$old" ] && rclone deletefile "$OFFSITE/db/$old"
            done
        else
            mkdir -p "$OFFSITE/db" "$OFFSITE/env"
            cp "$enc" "$OFFSITE/db/"
            [ -f "$BACKUP_DIR/env-latest.age" ] && cp "$BACKUP_DIR/env-latest.age" "$OFFSITE/env/env-$stamp.age"
            if [ "$OFFSITE_BLOBS" = 1 ] && [ -d "$BLOB_DIR" ]; then
                rsync -a --ignore-existing "$BLOB_DIR"/ "$OFFSITE/blobs/"
            fi
            find "$OFFSITE/db" -maxdepth 1 -name 'helix-*.dump.age' | sort | head -n -"$OFFSITE_KEEP" | xargs -r rm -f
        fi
        # Only the encrypted copy leaves; the local .age is a duplicate of the dump.
        rm -f "$enc"
    } 2>>"$LOG" && log ok "offsite copy (encrypted) to $OFFSITE" || log FAIL "offsite copy failed"
fi

# 4. Local generations, only after a verified dump.
if [ "$verified" = 1 ]; then
    find "$DB_DIR" -maxdepth 1 -name 'helix-*.dump' | sort | head -n -"$KEEP" | xargs -r rm -f
fi

finish
