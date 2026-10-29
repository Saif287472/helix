# Go-live checklist

One page to tick through on launch day, and again for each later release. It adds nothing new: each line points at
the document that has the detail. Windows commands are in `deploy/windows/README.md`, Linux in `deploy/linux/README.md`.
Never hand-edit the production database; `.env` lines are added by you, from the lists in the handoff.

## 1. A week before

- [ ] Gate green on the commit you will tag: `scripts/verify.ps1` (or `.sh`), server on Postgres 17.
- [ ] `docs/legal/DRAFT_terms_plans_and_call_time.md` reviewed, approved and applied (needed before plans are on).
- [ ] Restore drill passed in the last 30 days (`restore-drill`), and a real backup restored once by you.
- [ ] Backup is off the machine and encrypted; you can decrypt it with the key kept elsewhere.
- [ ] Alerts reach your phone: stop the server for a minute on the dry run and see the message arrive.
- [ ] `docs/operations/REMOTE_CALLS_RELEASE_READINESS.md`: the real-device matrix done and recorded.
- [ ] Both coturn relays up; the UDP range open on the router and the firewall; `HELIX_TURN_SECRET` and
      `HELIX_TURN_VOICE_SECRET` differ.
- [ ] Release APK built from the tag with the real signing key, installed on two phones.

## 2. The day, in order

- [ ] Tell people if downtime is expected; pick a quiet hour.
- [ ] Tag the commit. Build it (`release-helix` / `release.sh`).
- [ ] Add the new `.env` lines (the change report names them) to the **production** `.env`.
- [ ] Back up now. Check the file exists.
- [ ] Deploy (`deploy-helix` / `deploy.sh`): graceful stop, swap, migrate, start, ready check.
- [ ] `GET /v1/health/ready` is true through the public address, over HTTPS.
- [ ] Sign in on a phone; send a message each way; make a voice call and a video call; switch one.
- [ ] Orbit Console: log in, the dashboard shows no security banner, plan counts load.
- [ ] Metrics: no dead-letter jobs, no 5xx, WebSocket devices connected.
- [ ] Plans stay off (`billing_enabled` false) until you have tested a payment request end to end with your own
      account: submit, see it in the console queue, confirm, plan changes on the phone.

## 3. Rollback (decide before you start)

- Client-only fault: leave the server, pull the APK.
- Server fault, no migration in the release: redeploy the previous tag.
- Migration ran and is wrong: stop, restore the backup taken in step 2, redeploy the previous tag. Messages sent in
  between are lost (`V2_OPERABILITY.md`, "Backups"). The deploy script rolls back by itself if the migration fails.

## 4. The first week

- [ ] Each morning: the health message arrived, last backup under 26 hours old, disk below 80%.
- [ ] Watch the security counters (session reuse, key changes) and the crash and anomaly lines in the log.
- [ ] After a quiet week, switch plans on in the console, then claim and spend call time on a test account.
