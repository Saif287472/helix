# Helix Remote: review and remediation plan (2026-10-09)

Status: review only. No source, test, migration, config or generated file was
changed. Batches in section 4 wait for the user's approval.

Scope: everything under `helix_remote/` (server, app, admin, packages, deploy,
scripts, tool, docs) and the cross-product docs in `docs/` that describe Remote.
`helix_local/` was not read. Files in `docs/security/FORBIDDEN_FILES.md` (for
example `server/.env`) were not read, so anything that depends on the live
`.env` values is marked as such.

Rules applied as review criteria: `AGENTS.md` (product rules, security
invariants, verification expectations) and
`docs/architecture/ARCHITECTURE_V2_PLAN.md` (plan of record). Deliberate product
decisions in `AGENTS.md` (SMS sign-in on Helix Global, screenshots allowed, TLS
pinning off by default, light theme only, no contact requests) are not reported
as defects.

Paths: section 3 uses short paths. `identity/…`, `messaging/…` and the other
module names are under `helix_remote/server/lib/src/modules/`; `platform/…` and
`kernel/…` under `helix_remote/server/lib/src/`; `packages/…`, `app/…`,
`admin/…`, `server/…` and `docs/…` (Remote docs) under `helix_remote/`. The
dependency register and `FORBIDDEN_FILES.md` are in the repository root's
`docs/`. The table in section 2 gives paths from the repository root.

---

## 1. Summary

**Overall health.** The v2 codebase is in good shape for its age: the server's
security core (single session mint point, device certificates, exact device
lists, revocation, redacting logs, credentials before bodies, typed config) is
carefully built and tested, the Double Ratchet and Sender Keys code reads as
textbook, analysis is clean and every suite passes except one load-sensitive
server test. The real risks are elsewhere: **availability under ordinary use
and abuse** (one idle device can stall every conversation with its owner; one
member of a large group can flood the PC's disk), **the notification path on
Android** (two independent gaps mean users can miss messages and calls), and
**operations on a single home PC** (no proven backup, production running from
the development checkout, no automatic restart, an admin API open to the
internet behind one password).

**Top 5 risks**

1. **A-01** (High): an unused but never-revoked device whose mailbox reaches
   10,000 envelopes makes every send to that account, and every group it is in,
   fail; the phone keeps retrying and the whole conversation stalls.
2. **E-01 + E-02** (High): no notification while the app is in the background
   but alive (only the FCM isolate notifies, and it stands down while the app
   runs); and the push token is registered only at app launch, so a new sign-up
   gets no pushes or call rings until the app is restarted.
3. **A-02 + A-03** (High/Medium): group sends have no rate limit and each one is
   copied to every member device's mailbox; with per-account quotas only, a few
   accounts can fill the PC's disk and take the service down.
4. **H-01, H-02, H-03** (High/Medium): no backup of the only production database
   is set up or proven in the repository, production runs `dart run` from the
   working tree agents edit, and nothing restarts the service after a reboot.
5. **B-02 + H-04** (Medium): `/v1/admin/*` is reachable from the internet with a
   single password, 12-hour tokens and no server-side sign-out; the live
   Caddyfile has no restriction and no HSTS.

Also worth reading early: **C-01** (two engines on one database can reuse an
AES-GCM key and nonce) and **A-06** (the password routes tell anyone which
phone numbers have Helix accounts, contradicting THREAT_MODEL T-7).

**Counts by severity:** Critical 0, High 5, Medium 13, Low 26, Info 3 (47 in all).

**Verified vs not.** Every finding was read in the code. Fully confirmed: 41.
Confirmed in code but not observed on a device: E-01, C-01. Depends on things
outside the repository or the forbidden `.env`: H-01 (whether a scheduled
backup exists), A-07 (whether the live database URL sets a query timeout).
Unverified: D-01 (UI stalls need a measurement on a phone). B-09 matters only if
macOS is a target.

**Checks run for this review** (from `helix_remote/`, on 2026-10-09):

| Check | Result |
|---|---|
| `flutter analyze` (workspace) | No issues |
| `dart analyze server tool` | No issues |
| `flutter test` protocol / crypto / rules / db / api / engine / cli / calls | 83 / 73 / 20 / 131 / 190 / 292 / 13 / 5, all passed |
| `flutter test` ui | 183 passed, 5 skipped (goldens; see F-02) |
| `flutter test` admin / app | 185 / 799, all passed (AGENTS.md records admin 181) |
| `flutter test` domain | No `test/` directory (F-05) |
| Server: `HELIX_REQUIRE_TEST_DATABASE=1 dart test --concurrency=3` on Postgres | 338 passed, 1 failed: `test/client/engine/devices_test.dart` (pool-lock timeout after the test completed). The file alone: 10/10 passed. Not one of the two known timing-sensitive tests: recorded as F-04, no other new failure |
| `dart run tool/check_governance_controls.dart` | Passed (26 controls) |
| `dart run tool/check_performance_budgets.dart` | Contract verified |
| `dart run tool/codegen.dart --check` (helix_remote_db) | Generated code up to date |

The test runs' `flutter pub get` rewrote the seven generated plugin-registrant
files (`app/windows/flutter/…`, `admin/{linux,macos,windows}/…`); they were
restored with `git checkout --` as AGENTS.md says, so the working tree has only
this file as a change.

## 2. Findings table

| ID | Severity | Area | Title | File:line | Status |
|---|---|---|---|---|---|
| A-01 | High | Server | One idle device's full mailbox blocks every send to its account | `helix_remote/server/lib/src/modules/messaging/data/mailbox_store.dart:19-39` | confirmed; fixed in Batch 2 (trim; inactivity revoke behind an off-by-default setting) |
| A-02 | High | Server | Group sends have no rate limit and are copied to every member device | `helix_remote/server/lib/src/modules/groups/module.dart:177-182` | confirmed; fixed in Batch 2 |
| E-01 | High | App | No message notification while the app is backgrounded but running | `helix_remote/app/lib/core/push/push_background.dart:110-113` | confirmed (code); fixed in Batch 3 (device check pending) |
| E-02 | High | App | Push token registered only at app launch | `helix_remote/app/lib/main.dart:111-138` | confirmed, worse than recorded (Firebase was never initialised in the UI isolate); fixed in Batch 3 (device check pending) |
| H-01 | High | Ops | No backup of the production database set up or proven | `helix_remote/docs/operations/V2_OPERABILITY.md:298-427` | confirmed (no task, no backup folder, 2026-10-09); Batch 1 scripts written, user installs |
| A-03 | Medium | Server | No global storage guard; per-account quotas fill one disk | `helix_remote/server/lib/src/modules/media/module.dart:27-31` | confirmed; fixed in Batch 2 (budget off until `HELIX_STORAGE_BUDGET_BYTES` is set) |
| A-04 | Medium | Server | One hung job stalls every background job on the node | `helix_remote/server/lib/src/platform/jobs/jobs.dart:159-170` | confirmed |
| A-05 | Medium | Server | No global SMS budget or country allow-list | `helix_remote/server/lib/src/modules/identity/application/sign_up.dart:18-48` | confirmed |
| A-06 | Medium | Server | Password routes are an unauthenticated account oracle; lockout DoS | `helix_remote/server/lib/src/modules/identity/application/sign_in.dart:35-60` | confirmed |
| B-01 | Medium | Admin | Android console App lock locks the operator out | `helix_remote/admin/android/app/src/main/kotlin/com/helix/helix_admin/MainActivity.kt:5` | confirmed |
| B-02 | Medium | Admin | Admin API public behind one password, no server sign-out | `helix_remote/server/lib/src/modules/admin/module.dart:121-153` | confirmed; exposure half: Batch 1 Caddyfile written, user installs |
| C-01 | Medium | Security | Two engines can write the same ratchet state (key/nonce reuse) | `helix_remote/packages/helix_remote_engine/lib/src/crypto/db_stores.dart:29-44` | confirmed (code); fixed in Batch 4 (group sender keys left open) |
| E-03 | Medium | App | Windows app raises no notifications | `helix_remote/app/lib/core/notifications/local_notifications.dart:61-65` | confirmed |
| F-01 | Medium | Tests | Platform glue (FCM, notifications, local_auth) untested | `.github/workflows/ci.yml:143-157` | confirmed; push and notification logic tested in Batch 3, device checklist added |
| G-01 | Medium | Deps | Dependency risk register no longer matches the lockfile | `docs/dependencies/DEPENDENCY_RISK_REGISTER.md:65-70` | confirmed |
| H-02 | Medium | Ops | Production runs from the development working tree | `helix_remote/docs/operations/V2_SERVER_HANDOFF.md:74-90` | confirmed |
| H-03 | Medium | Ops | Nothing restarts the service after reboot or crash | `helix_remote/server/lib/src/platform/db/postgres_db.dart:21-24` | confirmed |
| H-04 | Medium | Ops | Caddy site has no HSTS and no admin restriction | `J:\Projects\Servers\helix_server\Caddyfile` | confirmed; Batch 1 Caddyfile written, user installs |
| A-07 | Low | Server | No statement or lock timeout on the pool | `helix_remote/server/lib/src/platform/db/postgres_db.dart:14-19` | confirmed (code) |
| A-08 | Low | Server | A failing after-commit action becomes a request error | `helix_remote/server/lib/src/platform/db/postgres_db.dart:82-84` | confirmed |
| A-09 | Low | Server | Device lists checked outside the send transaction | `helix_remote/server/lib/src/modules/messaging/module.dart:308-352` | confirmed; fixed in Batch 2 |
| A-10 | Low | Server | Media rows deleted before blobs; failures leak files | `helix_remote/server/lib/src/modules/media/module.dart:349-372` | confirmed |
| A-11 | Low | Server | Presence and profile reads have no per-account limit | `helix_remote/server/lib/src/modules/people/module.dart:326-359` | confirmed |
| A-12 | Low | Server | Per-target bundle limit can be exhausted | `helix_remote/server/lib/src/modules/keys/module.dart:32-43` | confirmed |
| B-03 | Low | Admin | Live log WebSocket outlives the admin session | `helix_remote/server/lib/src/modules/admin/module.dart:615-630` | confirmed |
| B-04 | Low | Admin | Some audits outside their transaction; no audit retention | `helix_remote/server/lib/src/modules/admin/module.dart:450-478` | confirmed |
| B-05 | Low | Admin | Ban confirmed more lightly than delete | `helix_remote/admin/lib/src/features/accounts/account_detail_screen.dart:95-114` | confirmed |
| B-06 | Low | Admin | Console App lock asked only at launch | `helix_remote/admin/lib/src/session/admin_session_controller.dart:105-113` | confirmed |
| B-07 | Low | Admin | No way to reset a forgotten admin password | `helix_remote/server/lib/src/modules/admin/module.dart:156-178` | confirmed |
| B-08 | Low | Admin | Distributed attacker can keep admin sign-in locked | `helix_remote/server/lib/src/modules/admin/module.dart:70-73` | confirmed |
| B-09 | Low | Admin | macOS console lacks the network-client entitlement | `helix_remote/admin/macos/Runner/Release.entitlements` | confirmed |
| C-02 | Low | Privacy | Reports kept forever (docs: until resolved) | `helix_remote/server/lib/src/modules/people/module.dart:575-592` | confirmed |
| C-03 | Low | Privacy | Privacy and crypto documents slightly wrong | `helix_remote/docs/protocol/v2/CRYPTO_V2.md` (§11, §14) | confirmed |
| D-01 | Low | Engine | Heavy crypto runs on the UI isolate | `helix_remote/packages/helix_remote_crypto/lib/src/v2/password.dart:54-63` | unverified |
| E-04 | Low | App | Documented gaps against v1 (return-to-call bar, group calls…) | `helix_remote/app/lib/features/calls/FEATURE.md:93-96` | known |
| F-02 | Low | Tests | Four of five UI golden tests check nothing, even on CI | `helix_remote/packages/helix_remote_ui/test/chat_components_golden_test.dart:27-36` | confirmed |
| F-03 | Low | Tests | Golden failure images committed | `helix_remote/packages/helix_remote_ui/test/failures/` | confirmed |
| F-04 | Low | Tests | A third load-sensitive server test | `helix_remote/server/test/client/engine/devices_test.dart` | confirmed |
| F-05 | Low | Tests | Small gaps (domain tests, fake lock, stale registrants) | `helix_remote/scripts/verify.ps1:107-110` | confirmed |
| G-02 | Low | Architecture | Stated rules (SQL only in `data/`) not followed or tested | `helix_remote/server/test/architecture_test.dart` | confirmed |
| G-03 | Low | Docs | Ten documents that contradict the code | `helix_remote/docs/architecture/ARCHITECTURE_V2_PLAN.md:3-6` | confirmed |
| G-04 | Low | Architecture | Very large files | `helix_remote/server/lib/src/modules/groups/module.dart` | confirmed |
| H-05 | Low | Ops | No monitoring, no log rotation | `helix_remote/server/lib/src/platform/observability/log.dart:93-115` | confirmed |
| H-06 | Low | Ops | PC off more than three days fails queued sends | `helix_remote/packages/helix_remote_engine/lib/src/config.dart:15` | confirmed |
| C-04 | Info | Security | What an external crypto reviewer should focus on | — | — |
| D-02 | Info | Engine | Items already tracked as open | `helix_remote/docs/protocol/v2/CRYPTO_V2.md` §14 | known |
| G-05 | Info | Repo | Local v1 leftovers (untracked) | `helix_remote/packages/helix_remote_storage/` | confirmed |

Pre-existing and known items: AGENTS.md lists no pre-existing test failures
and two timing-sensitive server tests; neither failed here. Items the tracker or
module docs already record as open are marked "known" (E-04, D-02) or say so in
their text (B-04's retention, H-01's restore cursor, B-07, the CRYPTO_V2 §14
items in C-04). Everything else is new to the tracker.

---

## 3. Findings in detail

Severity: **Critical** = exploitable now for data loss, key compromise or full
account takeover; **High** = a realistic failure or attack that breaks messaging
or the server for many users; **Medium** = a real defect with limited reach or a
clear precondition; **Low** = hardening, correctness at the edges, or drift.

Status: **confirmed** = read in the code (and, where possible, in tests);
**unverified** = plausible from the code but not proven (for example it depends on
the live `.env` or a device).

### Area A: Server (`helix_remote/server`)

#### A-01 (High, confirmed): one idle device's full mailbox blocks every send to its account

- **What is wrong.** `MailboxStore.allocate` throws `quota_exceeded` for the
  whole send as soon as *any* recipient device has more than 10,000 undelivered
  envelopes (`server/lib/src/modules/messaging/data/mailbox_store.dart:13`,
  `:19-39`). A sender must address every active device of the recipient account
  or get `device_list_stale` (`messaging/module.dart:606-645`), so it cannot leave
  the full device out. Nothing ever retires an unused device: `last_seen_on` is
  only displayed (`identity/data/identity_store.dart:307-313`; no other use in
  `server/lib`).
- **Failure scenario.** Bob installs Helix on a Windows PC, then stops opening
  it without signing out. Alice and Bob chat on their phones. Every message,
  receipt, reaction and edit is one mailbox row for the PC; rows expire after 30
  days (`mailbox_store.dart:14`), so a steady ~340 rows a day (about 110 messages
  a day with their delivered/read receipts) keeps the PC above 10,000. From then
  on every send to Bob fails. The engine treats `quota_exceeded` as retryable
  (`packages/helix_remote_engine/lib/src/messaging/outbox.dart:230-234`) and sends
  one op at a time per conversation (`outbox.dart:241-243`), so the whole
  conversation stalls until the age limit fails the messages. The same applies
  to every group that contains Bob (`groups/module.dart:1130-1150` delivers to all
  member devices in one call).
- **Suggested fix.** (1) Never fail a send for one device: skip or trim the
  over-quota device (drop its oldest rows, or stop delivering to it and send the
  account a signal). (2) Expire devices that have not authenticated for N days
  (WhatsApp unlinks companions after ~30 days): revoke through the normal hooks
  so peers see a device-list change. (3) Show "inactive since" in Devices. Tests:
  a messaging test with one device at quota; an identity job test for inactivity
  revocation.

#### A-02 (High, confirmed): group sends have no per-device or per-account limit, and each send is copied to every member device

- **What is wrong.** `POST /v1/groups/{id}/messages` is registered with only a
  body cap (`groups/module.dart:177-182`); `_send` never calls the rate limiter
  (`:1014-1154`). Direct sends have `messaging.send` (5/s per device) and
  `messaging.send_account` (10/s per account) (`messaging/module.dart:58-67`,
  `:113-134`). The only limit left is the global per-IP bucket (600 burst, 10/s;
  `platform/http/pipeline.dart:23-27`). `_send` stores the same payload (up to
  256 KiB) once per member device (`:1102`, `:1136`).
- **Attack scenario.** Any account may create 20 groups a day and add up to 1,023
  accounts each (`group_add` defaults to `everyone`,
  `people/module.dart:66-71`). One 256 KiB group message to ~2,000 member devices
  writes ~500 MiB into Postgres; ten a second from one address is several GiB a
  second. The live PC's disk and Postgres saturate (denial of service for all
  users), and every member gets spam pushes. Even without malice, a client bug
  retry loop in a large group has no brake.
- **Suggested fix.** Apply `sendPerDevice` and `sendPerAccount` to group sends,
  plus a per-group budget weighted by member-device count; cap the stored payload
  for group fan-out (sender-key ciphertext does not need 256 KiB; attachments go
  through media). Add a test that a burst of group sends is refused with
  `rate_limited`.

#### A-03 (Medium, confirmed): no global storage guard; per-account quotas multiply on one PC disk

- **What is wrong.** Each limit is per device or per account: mailbox 10,000 rows
  of up to 256 KiB per device (`mailbox_store.dart:13`;
  `SendMessageRequest.maxPayloadBytes`), media 4 GiB attachments + 1 GiB backup
  + 50 MiB persistent per account (`media/module.dart:27-31`), a 64 MiB backup
  envelope and a 16 MiB history backup per account in Postgres
  (`backup/module.dart:103-121`). Nothing checks free disk space or a server-wide
  total, and attachments are stored on the PC's local disk next to Postgres.
- **Failure scenario.** A handful of accounts (Helix Global needs one SMS-verified
  number each) upload ~5 GiB of media each and send 256 KiB envelopes to offline
  devices at the allowed 5/s (about 4.5 GiB per hour per sending device). The
  disk fills; Postgres stops accepting writes and the whole service fails, not
  just the abuser's account.
- **Suggested fix.** A server-wide budget (`HELIX_STORAGE_BUDGET_BYTES` or a
  free-space floor checked by a periodic job) that switches uploads and large
  sends to `quota_exceeded` before the disk is full; an admin dashboard gauge for
  media bytes and database size; a lower per-envelope cap for 1:1 sends.
  Monitoring alone (see H-03) is the minimum.

#### A-04 (Medium, confirmed): one hung job stalls every background job on the node

- **What is wrong.** `JobRunner._drain` awaits every job of a batch
  (`platform/jobs/jobs.dart:159-170`) and later ticks join the pass in flight
  (`:148-157`), with no timeout per job. `PeriodicScheduler._tick` runs jobs one
  after another, also without a timeout (`:312-346`). The FCM provider's OAuth
  refresh has no timeout (`platform/push/push.dart:125-137`), and
  `await _accessToken()` runs before the `.timeout(15 s)` that guards only the
  POST (`push.dart:157-169`).
- **Failure scenario.** Google's token endpoint stalls (or the PC's network
  half-drops) during a refresh. That push job never completes, so no other job
  runs on this node: no pushes, no media purges, no group syncs, no relays. The
  lease expires after 2 minutes and another tick would retry, but the in-flight
  pass never finishes, so nothing else is claimed until the process restarts.
- **Suggested fix.** Wrap each handler in `Future.timeout` (shorter than the
  lease) and treat a timeout as a failure with backoff; give `_refresh` its own
  timeout; run periodic jobs with a timeout too. Test with a handler that never
  completes.

#### A-05 (Medium, confirmed): SMS sending has no global budget or country allow-list

- **What is wrong.** Phone challenges are limited to 10 per hour per IP
  (`identity/http/identity_routes.dart:12-16`), 5 per hour per number and a
  resend gap (`identity/application/sign_up.dart:18-48`). Any E.164 number is
  accepted (`identity/domain/secrets.dart:28-42`). There is no daily or global cap
  and no list of allowed country codes.
- **Attack scenario.** SMS pumping: a script rotating through proxies requests
  codes for thousands of (premium or international) numbers. Each request costs
  money on the BulkSMSBD balance; when the balance runs out, real sign-ups fail
  with `sms_unavailable`.
- **Suggested fix.** A cluster-wide daily SMS budget (`HELIX_SMS_DAILY_LIMIT`), an
  allow-list of country codes (`HELIX_SMS_COUNTRIES`, default `880`), and an
  admin gauge of codes sent today. New `.env` lines would be optional with safe
  defaults.

#### A-06 (Medium, confirmed): the password routes are an unauthenticated account oracle, and anyone can lock a victim's password sign-in

- **What is wrong.** Three independent tells, all on public routes:
  1. **Salt length.** `POST /v1/auth/password/params` answers decoys with a
     16-byte salt (`identity/application/sign_in.dart:35-41`, `.sublist(0, 16)`),
     but every real account has a 32-byte salt: the engine always calls
     `PasswordKeys.newSalt` (`packages/helix_remote_engine/lib/src/account/account_service.dart:125`),
     which is 32 bytes (`packages/helix_remote_crypto/lib/src/v2/password.dart:25`).
     One request tells a number with a Helix account and a password from one
     without.
  2. **Lockout.** After five wrong attempts a real account answers
     `password_locked` with `locked_until` (`application/context.dart:220-254`);
     an unknown number never does.
  3. **Timing.** An unknown number costs one HMAC; a real one a transaction
     with `SELECT … FOR UPDATE` and an `UPDATE` (`sign_in.dart:47-60`). The
     comment "Same work as a real check, so timing does not tell the two apart"
     (`sign_in.dart:51`) is not true.

  THREAT_MODEL T-7 says password sign-in "answers decoy parameters for unknown
  numbers, so it is not a number oracle" (`docs/product/THREAT_MODEL.md:100-101`).
- **Attack scenario.** Without an account, an attacker tests phone numbers at 30
  per hour per address (unlimited with rotating addresses) and learns which ones
  use Helix, which T-5 limits to 5,000 a day for authenticated accounts. The same
  route lets anyone keep a known user's password sign-in locked for up to 24
  hours.
- **Suggested fix.** Decoy salts of the real length (32 bytes, derived as now);
  a decoy failure counter (ephemeral store, keyed by the phone hash) so unknown
  numbers lock the same way; a dummy transaction of the same shape; correct the
  comment and T-7. A server test that the decoy and real responses have the same
  shape.

#### A-07 (Low, confirmed in code): no statement or lock timeout on the Postgres pool

- **What is wrong.** `PostgresDb.open` sets only `max_connection_count`
  (`platform/db/postgres_db.dart:14-19`). `package:postgres` 3.5.17 defaults to a
  5-minute query timeout and a 15-second connect timeout. Nothing sets
  `statement_timeout` or `lock_timeout`. (Whether the live `HELIX_DATABASE_URL`
  adds `query_timeout` could not be checked: `.env` is a forbidden file.)
- **Failure scenario.** A long lock (for example a group row held `FOR UPDATE`
  while a big fan-out runs, or a manual `VACUUM FULL`) makes requests queue for
  minutes on pool connections, then every other request waits 15 s for a
  connection and fails. The node looks hung rather than failing fast.
- **Suggested fix.** Set `statement_timeout` (for example 15 s) and
  `lock_timeout` (5 s) per connection (pool `onOpen` or URL parameters), and a
  shorter driver query timeout; longer limits only for migrations and purges.

#### A-08 (Low, confirmed): a failing after-commit action turns a committed write into an error

- **What is wrong.** `PostgresDb.tx` runs after-commit actions in order after the
  commit and lets the first exception escape (`postgres_db.dart:82-84`); later
  actions are skipped.
- **Failure scenario.** A NOTIFY fails during a database blip right after
  `revokeAll` commits: the client gets a 500 for an account change that
  happened, and the remaining `device.revoked` publishes are skipped (sockets
  close only at the next 25 s refresh).
- **Suggested fix.** Run every after-commit action, log failures, and never
  rethrow (the bus is best-effort by design, `bus/event_bus.dart:6-9`).

#### A-09 (Low, confirmed): device lists are checked outside the send transaction

- **What is wrong.** Direct sends check device lists with `context.db`
  (`messaging/module.dart:308-315`) before the transaction that stores rows
  (`:342-352`); group sends read the roster and devices outside any transaction
  (`groups/module.dart:1032-1078`).
- **Failure scenario.** A device revoked between the check and the insert gets
  mailbox rows after its revoke hook already purged the mailbox. It can never
  fetch them (revoked devices do not authenticate), but the rows and its
  `device_seq` row stay until the 30-day expiry. "Revoked devices get nothing"
  holds for delivery, not for storage.
- **Suggested fix.** Repeat the active-device check inside the transaction
  (`activeDevicesOf(tx, …)` with `FOR SHARE` on the device rows), or have the
  insert skip devices that are not active.

#### A-10 (Low, confirmed): media rows are deleted before their blobs, so a failed delete leaks the file

- **What is wrong.** `media.expire` and `media.purge_account` delete the rows
  first and the blobs afterwards (`media/module.dart:349-372`). If a blob delete
  throws, the job fails but the rows are gone, so the retry finds nothing; there
  is no sweep for files without a row.
- **Failure scenario.** A locked file on Windows (antivirus scan) makes
  `File.delete` throw; the encrypted blob stays on disk forever, unaccounted for
  by any quota.
- **Suggested fix.** Delete blobs first and rows after (or mark rows
  `deleting` and remove them when the blob is gone), plus a weekly orphan sweep
  of the blob directory.

#### A-11 (Low, confirmed): presence and profile reads have no per-account limit

- **What is wrong.** `GET /v1/people/{account}/presence` and the profile route
  have no route limit (`people/module.dart:103-117`, `:326-359`); presence
  audiences default to `everyone` (`people/module.dart:66-71`).
- **Failure scenario.** Any signed-in account can poll the online status and last
  seen of thousands of accounts (ids come from discovery) at the global 10/s per
  address, building activity timelines. The default audience is a product
  choice; the missing limit is the defect.
- **Suggested fix.** A per-account limit on presence reads (for example 120 per
  minute) and on distinct targets per day.

#### A-12 (Low, confirmed): the per-target bundle limit can be exhausted to block new sessions to a victim

- **What is wrong.** Bundle fetches are limited per requester (120/h) and per
  target (600/h) (`keys/module.dart:32-43`, `:206-214`); every fetch consumes a
  one-time prekey (`:277`).
- **Attack scenario.** Five accounts fetching one victim's bundle 120 times an
  hour each keep the victim's per-target bucket empty and its one-time prekeys
  drained: nobody new can start a session with the victim (and the victim's own
  new devices cannot be reached by contacts' stale-list rebuilds) while it lasts.
- **Suggested fix.** Count the per-target limit per (requester account, target)
  and keep a separate global cap; stop handing out one-time prekeys to a
  requester that already received one for the same device recently.

### Area B: Admin console (`helix_remote/admin`) and the admin API

What holds: every admin route is behind `RouteAccess.admin`, checked on the
server (`platform/http/routes.dart:399-432`), with audience- and type-separated
tokens (`kernel/jwt.dart`, `modules/admin/module.dart:189-219`); sign-in counts
the attempt before the Argon2id check and locks per address
(`admin/data/admin_store.dart:146-192`); the operator sees the last four phone
digits only; the dashboard's integration status is yes/no plus a provider name,
never a key (`admin/module.dart:536-555`); the console refuses plain `http://`
except for loopback (`admin/lib/src/api/server_address.dart:42-47`) and keeps
the token in secure storage (`admin/lib/src/services/token_vault.dart`).
Destructive actions have confirmations (B-05 is the one gap).

#### B-01 (Medium, confirmed): turning on App lock in the Android console locks the operator out

- **What is wrong.** The console's `MainActivity` extends `FlutterActivity`
  (`admin/android/app/src/main/kotlin/com/helix/helix_admin/MainActivity.kt:5`).
  `local_auth_android` 2.2.0 (the locked version) refuses to authenticate unless
  the activity is a `FragmentActivity` (`LocalAuthPlugin.kt:95-98` in the pub
  cache: `NOT_FRAGMENT_ACTIVITY`), while `isDeviceSupported()` still answers true.
  `LocalAuthDeviceLock.authenticate` turns the failure into `false`
  (`admin/lib/src/services/device_lock.dart:33-43`). The user app uses
  `FlutterFragmentActivity` correctly
  (`app/android/app/src/main/kotlin/com/helix/remote/MainActivity.kt:15`).
- **Failure scenario.** The operator enables App lock (the toggle succeeds),
  closes the console, and on the next launch every unlock attempt shows "The
  device was not unlocked." The only way back in is clearing the app's data.
  Admin tests use a fake `DeviceLock`, so they cannot see this.
- **Suggested fix.** `class MainActivity : FlutterFragmentActivity()` (and an
  AppCompat-based `NormalTheme` if BiometricPrompt needs it); a rule test that
  the activity is a fragment activity. Needs a new admin APK.

#### B-02 (Medium, confirmed): the admin API is on the public origin behind a single password

- **What is wrong.** `/v1/admin/*` is served by the same process and origin as
  the device API. Admin sign-in is password only (no second factor), tokens last
  12 hours, and there is no server-side sign-out: the console's "Sign out" only
  forgets the token locally
  (`admin/lib/src/session/admin_session_controller.dart:341-343`). The live
  Caddyfile (`J:\Projects\Servers\helix_server\Caddyfile`, outside the
  repository; checked with a search for route matchers only) is three lines with
  no path or address restriction, so the admin API and the metrics route are
  reachable from the internet (see also H-04).
- **Attack scenario.** A leaked or phished admin password, or a token copied from
  the operator's PC, gives anyone on the internet the power to delete or ban any
  account, issue recovery codes (which on a server without SMS reset an account,
  THREAT_MODEL T-8) and read the server log, for up to 12 hours, with no way to
  revoke it short of changing the password.
- **Suggested fix.** Restrict `/v1/admin/*` (and `/v1/ops/metrics`) to loopback
  and the LAN in Caddy; add a server-side admin sign-out (sets
  `tokens_valid_after`); consider TOTP as a second factor and a shorter token
  lifetime with refresh.

#### B-03 (Low, confirmed): the live log WebSocket outlives the admin session and has no frame cap

- **What is wrong.** `_logStream` checks the token once at upgrade and then
  streams forever (`admin/module.dart:615-630`). It is not closed on token
  expiry or password change (device sockets are, `realtime/module.dart:348-363`),
  and it does not use `limitWebSocketFrames`
  (`platform/http/websocket_limits.dart`).
- **Failure scenario.** After a password change meant to cut off a stolen token,
  an already open log stream keeps receiving every log line.
- **Suggested fix.** Re-verify the token every 60 s and close on failure; wrap
  the upgrade in `limitWebSocketFrames`.

#### B-04 (Low, confirmed): some admin actions are audited outside their transaction, and the audit log never ages out

- **What is wrong.** MODULE.md says every mutating action writes its audit row
  "in the same transaction", but recovery-code issue, invite create and cancel,
  purge and sign-in write it afterwards as a separate statement
  (`admin/module.dart:450-456`, `:465-478`, `:632-644`, `:289-290`). The `audit`
  table has no retention job and no partitioning
  (`admin/data/admin_store.dart:41-48`), although the plan of record says audit
  tables are range-partitioned by month with retention
  (`ARCHITECTURE_V2_PLAN.md` section 4.3). Audit rows keep account ids after the
  account is deleted.
- **Failure scenario.** A database error between the two statements leaves a
  recovery code issued with no audit record; years of audit rows keep the ids of
  deleted accounts.
- **Suggested fix.** Move those audits into the action's transaction (identity's
  admin facade can take a `Tx`); add an audit retention (for example two years)
  and document it in `RETENTION_AND_DELETION.md`.

#### B-05 (Low, confirmed): ban is confirmed more lightly than delete

- **What is wrong.** Delete requires typing `DELETE`
  (`admin/lib/src/features/accounts/account_detail_screen.dart:116-127`); ban,
  which also deletes the account and in addition bans the number, needs only a
  reason dialog (`:95-114`).
- **Suggested fix.** Use the typed confirmation for ban too.

#### B-06 (Low, confirmed): App lock is asked only at launch

- **What is wrong.** The lock is checked in `AdminSessionController.start()` only
  (`admin_session_controller.dart:105-113`); nothing in `admin/lib` observes the
  app lifecycle.
- **Failure scenario.** On a phone the console stays alive in the background;
  whoever picks the phone up returns to the signed-in console without unlocking.
- **Suggested fix.** Re-lock after a few minutes in the background (a lifecycle
  observer), as the user app does.

#### B-07 (Low, confirmed): no way to reset a forgotten admin password

- **What is wrong.** The plan of record lists `bin/admin_tool.dart` ("reset admin
  password etc.", `ARCHITECTURE_V2_PLAN.md` section 4.1); it does not exist.
  `HELIX_ADMIN_PASSWORD` only seeds the first admin and never replaces a password
  (`admin/module.dart:156-178`).
- **Failure scenario.** The operator forgets the password. The only way back is
  deleting the `admin.admins` row by hand in the production database. A
  `HELIX_ADMIN_PASSWORD` left in `.env` is a stale plaintext secret.
- **Suggested fix.** `dart run bin/admin_tool.dart reset-password` (reads the new
  password from stdin, sets `tokens_valid_after`, writes an audit row); tell the
  operator to remove `HELIX_ADMIN_PASSWORD` from `.env` after the first start.

#### B-08 (Low, confirmed): a distributed attacker can keep admin sign-in locked

- **What is wrong.** Besides the per-address lock, 100 failures from anywhere
  lock sign-in for everyone for 15 minutes (`admin/module.dart:70-73`,
  `admin_store.dart:183-190`). MODULE.md says the per-address design means "an
  attacker elsewhere cannot lock the operator out"; the global cap allows
  exactly that (about 100 requests from 10 addresses every 15 minutes).
- **Suggested fix.** Exempt loopback and LAN addresses from the global cap (once
  B-02 restricts the route this matters less) and correct MODULE.md.

#### B-09 (Low, confirmed; only if macOS is a target): the macOS console cannot reach a server

- **What is wrong.** Both macOS entitlement files enable the App Sandbox but not
  `com.apple.security.network.client`
  (`admin/macos/Runner/DebugProfile.entitlements`, `Release.entitlements`). A
  sandboxed macOS app without it cannot open outgoing connections.
- **Suggested fix.** Add the entitlement (plus a keychain entitlement if
  `flutter_secure_storage` needs it), or drop the macOS folder if the console is
  not meant to ship there.

### Area C: Security and privacy across the stack

What holds, checked in the code:

- **The password never leaves the device.** `PasswordKeys.derive` runs Argon2id
  and HKDF on the device (`packages/helix_remote_crypto/lib/src/v2/password.dart:41-79`);
  the wire DTOs carry only `auth_key`; the server stores
  `HMAC(verifier_salt, label ‖ auth_key)` and compares in constant time
  (`server/lib/src/modules/identity/application/context.dart:206-248`). The
  admin password is the documented exception (sent over TLS, Argon2id on the
  server).
- **Double Ratchet.** Textbook DH and symmetric steps, `MAX_SKIP` 1,000 per
  chain, 2,000 stored keys, 30-day expiry, decrypt-before-commit (state is
  returned only after the tag verifies), retired ratchet keys remembered
  (`packages/helix_remote_crypto/lib/src/v2/ratchet.dart`). Low-order X25519
  outputs are refused (`primitives.dart:262-285`). Group-state and profile blobs
  use a random nonce (the §9 spec flaw is fixed, CRYPTO_V2.md §14).
- **Sessions are minted in one place** (`identity/application/sessions.dart:32-64`;
  architecture test `server/test/architecture_test.dart:99-115`); stale device
  lists answer 409 `device_list_stale` (`messaging/module.dart:606-645`); revoked
  devices cannot authenticate (`identity/application/sessions.dart:157-170`) and
  their sockets close (`realtime/module.dart:113-124`).
- **Privacy claims** in `PRIVACY_CLAIM_MATRIX.md` and `METADATA_INVENTORY.md`
  match the code in substance (data-only push, no conversation graph, random
  media ids, pepper-keyed discovery index, export without secrets,
  relay-only calls in `packages/helix_remote_calls/lib/src/web_rtc_call_engine.dart:14`).
  The gaps are in C-02 and C-03, and A-06 contradicts THREAT_MODEL T-7.
- **HTTPS is enforced in the app** for every server outside a debug build's
  development hosts (`app/lib/core/engine/server_policy.dart:36-53`).

#### C-01 (Medium, confirmed in code; device behaviour unverified): two engines can write the same ratchet state, which can reuse a message key

- **What is wrong.** The engine stores pairwise sessions with plain
  last-writer-wins saves (`packages/helix_remote_engine/lib/src/crypto/db_stores.dart:29-44`);
  there is no version or compare-and-set. The only thing that keeps the app
  engine and the FCM background engine apart is the file lease, and its
  heartbeat rewrites the lease file every 5 s without checking who owns it
  (`app/lib/core/platform/engine_lease.dart:113-116`, `:143-164`). The lease's own
  comment calls it "a best-effort advisory claim, not a mutex" (`:47-50`).
- **Failure scenario.** Android freezes the backgrounded app; after 20 s its lease
  is stale. A push wakes the process: the FCM isolate takes the lease and runs
  `syncOnce`; the unfrozen UI isolate's heartbeat then writes its own owner over
  it and its realtime client reconnects. Both engines load the same session row,
  both decrypt or send (a receipt, a `decryption_error`, a queued message) from
  the same state, and both commit. A lost update corrupts the ratchet (later
  messages fail and trigger §13a resets); two sends from the same sending chain
  state encrypt two plaintexts under the same AES-GCM key and nonce, which
  leaks their XOR and the GHASH key for that message key.
- **Suggested fix.** Make the session save a compare-and-set on a version column
  (refuse and retry when the stored version moved), and make the heartbeat check
  ownership before writing (stop the engine if it lost the lease). Crypto test
  vectors are unaffected; add an engine test with two engines on one database
  file. Needs a db schema step (a version column on `sessions`), regenerated
  drift code and a note in `remote_cryptographic_design_review.md`.

#### C-02 (Low, confirmed): reports are kept forever, although the inventory says "until resolved"

- **What is wrong.** `METADATA_INVENTORY.md` (Reports row) says a report
  "survives account deletion as the moderation record until resolved". Nothing
  deletes reports: `people` has no periodic job and resolving only changes the
  status (`server/lib/src/modules/people/module.dart:575-592`). Reports carry the
  reporter, the subject and free text typed by the reporter.
- **Suggested fix.** Purge resolved and dismissed reports after a stated period
  (for example 180 days) and say so in the inventory and in
  `RETENTION_AND_DELETION.md`.

#### C-03 (Low, confirmed): privacy documents that are slightly wrong

- `METADATA_V2.md` says there is "no IP in the database except rate-limit
  buckets"; `admin.sign_in_failures` stores client addresses for up to two days
  (`server/lib/src/modules/admin/data/admin_store.dart:17-25`, `:205-209`).
- `METADATA_INVENTORY.md` (minimization rules) says the raw number is sent "once
  per code request". It is also sent with every password-params and password
  sign-in request (`PasswordParamsRequest`, `PasswordSignInRequest`) and when
  turning discovery back on (`PrivacySettings.phone_number`). It is not stored
  in any of these cases.
- `CRYPTO_V2.md` §11 says the server stores "a hash of `auth_key` (Argon2id with a
  server-side salt)"; the server stores an HMAC-SHA256 verifier
  (`identity/application/context.dart:206-209`). The HMAC is adequate because the
  auth key is already Argon2id output, but the spec and THREAT_MODEL T-7 should
  say the same thing.
- `CRYPTO_V2.md` §14 still lists "No HTTPS enforcement" as open; the app enforces
  HTTPS (`app/lib/core/engine/server_policy.dart`), so the item should move to
  "closed" with the test that pins it.
- `METADATA_INVENTORY.md` lists `messaging.sends` as "sending device, message id";
  since messaging migration 3 it also stores the sender account
  (`messaging/data/mailbox_store.dart:267-273`).

#### C-04 (Info): what an external cryptographic reviewer should focus on

The crypto has had no external review, and the documents say so. A reviewer's
time is best spent on, in order:

1. **State commit discipline** across the engine: every encrypt is committed
   before the ciphertext leaves; per-device and per-group serialisation; the
   two-engine case in C-01; behaviour after a crash between commit and send.
2. **Prekey message handling**: the sender-identity resolution through
   `GET /v1/keys` (which consumes a one-time prekey, CRYPTO_V2.md §14 "Open"),
   retired base keys (uncapped list), the no-OPK X3DH replay defence.
3. **§13a resets and re-send authorisation** (`decryption_error`,
   `resend_request`): what a hostile peer or server can force.
4. **Sender Keys**: signature-before-derivation, distribution tracking, rotation
   on removal and on device changes, and the open "group key planting" and
   unsigned membership changes (CRYPTO_V2.md §14).
5. **Backup envelope v3 and the history backup** (AAD binding, KDF floors,
   recovery-secret generator) and the password-wrapped AIK (no Unicode
   normalisation; the 16-byte/32-byte salt issue in A-06).
6. **Primitives**: `package:cryptography`'s pure-Dart AES-GCM, X25519 and Ed25519
   (no constant-time guarantee; Ed25519 verification strictness and
   malleability); HKDF hand-rolled in `primitives.dart:123-140`.
7. **Attachment STREAM** framing (`attachments.dart`): chunk boundaries,
   last-chunk flag, header authentication.

### Area D: Engine, API client, local database, CLI

What holds: the inbound pipeline is one serial queue fed by the socket and the
REST mailbox, acks only after the apply transaction commits, de-duplicates
through `processed_envelopes` and quarantines an envelope after three
non-transient failures so nothing blocks the stream
(`packages/helix_remote_engine/lib/src/messaging/inbound_runner.dart:113-172`).
The outbox has one wake-up path, per-conversation ordering, backoff with an age
limit and a clear error classification (`messaging/outbox.dart:203-239`,
`:426-458`). The API transport refreshes tokens single-flight and falls back to
device-key sign-in when the refresh token is refused, so a refresh race ends in
a re-authentication, not a wipe (`packages/helix_remote_api/lib/src/v2/transport/auth.dart:126-164`,
`engine.dart:335-336`). The realtime client follows the close-code policy
(`realtime/realtime_client.dart:131-136`). The local database is schema 2 with a
real step migration (`packages/helix_remote_db/lib/src/database.dart:94-119`),
fails closed on a wrong key, and `wipeAll` covers every table and vacuums
(`:133-170`). The CLI masks phone numbers and reads its key from the environment
or a key file. The sharpest risk in this area is the two-engine case, recorded
as C-01.

#### D-01 (Low, unverified on a device): heavy crypto runs on the UI isolate

- **What is wrong.** The engine runs on the app's main isolate, and its crypto is
  pure Dart: the password KDF (Argon2id 19 MiB, t = 2, at sign-in, password
  change and account deletion: `helix_remote_crypto/lib/src/v2/password.dart:54-63`),
  backup KDFs, the 5,200-round safety number, and attachment STREAM
  encryption of up to 100 MiB. Only the app's image work uses `Isolate.run`
  (`app/lib/core/platform/media_sanitizer.dart:90`, `thumbnail_encoder.dart:35-40`).
- **Failure scenario.** On a low-end Android phone the sign-in screen freezes for
  seconds while Argon2id runs (an ANR dialog if it passes 5 s), and sending a
  large video stutters the UI.
- **Suggested fix.** Measure on the user's slowest phone first. If it is slow,
  run `PasswordKeys.derive`, backup KDFs and attachment sealing through
  `Isolate.run` (they are pure functions), or adopt `cryptography_flutter` for
  native AES-GCM and Argon2id. Add a performance-budget test for the KDF.

#### D-02 (Info, known): items already tracked as open

- Drift watch streams do not cross isolates; the app reconciles on resume
  (plan change log, 2026-10-02 A1).
- Looking up an unknown sender's identity consumes a one-time prekey; retired
  base keys are uncapped (CRYPTO_V2.md §14).
- Group invite links and bans are remembered only on the device that made them
  (tracker A3 notes).

### Area E: Flutter app (`helix_remote/app`)

What holds: the product rules are pinned by `test/product_rules_test.dart` and
`test/accessibility_test.dart` (both pass); spot checks found no `Color(0x…)` or
`Colors.x` in `app/lib`, no `FLAG_SECURE` or display affinity, no dark theme and
no localization layer. HTTPS is enforced (`core/engine/server_policy.dart`), TLS
pinning is opt-in (`core/platform/tls_pinning.dart`), the app lock has a real
grace period and lets only a live call through (`app/MODULE.md`, "Security
review pass"), and "My contacts" is deliberately not offered as an audience
because no contact list is uploaded (`features/settings/application/privacy_providers.dart:151-157`).

#### E-01 (High, confirmed in code; device behaviour unverified): no message notification while the app is in the background but still running

- **What is wrong.** Message notifications are raised in exactly one place: the
  FCM background handler (`app/lib/core/push/push_background.dart:56-83`;
  `LocalNotifications.showMessages` has no other caller). That handler gives up
  with `EngineAlreadyRunning` whenever the app's own engine holds a fresh lease
  (`push_background.dart:110-113`, `core/platform/engine_lease.dart:89-94`). The
  app's engine keeps the lease and its socket while backgrounded (nothing in
  `core/lifecycle/app_lifecycle_host.dart:37-47` stops it on pause), and the app
  never listens to the engine's message events for notifications (`grep` finds
  only the calls feature using `EngineEvent`). The server, meanwhile, sends no
  push to a device whose socket is open (`messaging/module.dart:547-551`,
  `:428-431`).
- **Failure scenario.** Alice switches to another app. For as long as Android
  keeps Helix's process alive (minutes to hours on many phones; until the
  process is frozen on others), messages arrive over the still-open socket or
  the push is swallowed by the lease, and **no notification appears**. She sees
  them only when she opens Helix. Calls are not affected (the running app's
  call host rings).
- **Suggested fix.** In the running app, show the same grouped notification for
  `IncomingNotice`-style engine events when the app is not in the foreground
  (and clear it on resume); or release the lease and stop the socket on
  `paused` so the server pushes and the FCM path handles it. A widget test with
  a fake engine event in the paused state. Needs a new APK.

#### E-02 (High, confirmed): the push token is registered only at app launch

- **What is wrong.** `PushTokenSource().start(onToken: runtime.engine.push.register)`
  runs once, from `_restoreServer` after the first frame (`app/lib/main.dart:111-138`).
  On a fresh install the runtime is signed out at that moment: `register` throws
  `SignedOutException`, the `try` in `PushTokenSource.start` swallows it, and the
  `onTokenRefresh` listener after it is never attached
  (`core/push/push_token_source.dart:47-66`). Nothing registers the token after
  sign-in, registration, password sign-in, linking or a server change (the only
  call site is `main.dart:133`; the engine's `PushService.register` is a bare
  API call, `packages/helix_remote_engine/lib/src/features/push_service.dart:15-20`).
  After a server change the listener, if attached, still points at the closed
  runtime's engine.
- **Failure scenario.** A new user installs Helix, signs up and closes the app.
  The server has no push token for the device, so nothing wakes it: no message
  notifications and no ringing for incoming calls until the user happens to
  cold-start the app again. The same after re-registering a number or switching
  to a personal server.
- **Suggested fix.** Register (and re-subscribe to `onTokenRefresh`) whenever the
  runtime's engine reaches `EngineStatus.running`, from a provider that follows
  `runtimeProvider`; keep the last token and re-send it after sign-in. Test: a
  fake token source registers once after a sign-in completes.
- **Found while fixing it (Batch 3).** It was worse: the UI isolate never called
  `Firebase.initializeApp()` (only the background handler does, in its own
  isolate), so `FirebaseMessaging.instance` threw inside `PushTokenSource()`'s
  constructor, the `try` in `_startPush` swallowed it, and no launch ever
  registered a token, signed in or not. Pushes could only reach a device whose
  token had been registered by some earlier build.

#### E-03 (Medium, confirmed): the Windows app raises no notifications at all

- **What is wrong.** `LocalNotifications.init` returns early on every platform but
  Android (`core/notifications/local_notifications.dart:61-65`), and the push
  token source is Android-only (`push_token_source.dart:32`). On Windows there is
  no message notification and no incoming-call notification; an incoming call
  shows only if the Helix window is visible.
- **Failure scenario.** A Windows user minimises Helix: messages and calls go
  unnoticed until they bring the window back.
- **Suggested fix.** If Windows is a supported client (AGENTS.md says "Android,
  Windows"), initialise the plugin's Windows settings (the crash fixed in
  `2a7eda4` was the missing settings) and raise notifications from the running
  engine (as in E-01); otherwise document Windows as "open to receive".

#### E-04 (Low, known open items): documented gaps against v1

- No minimised "return to call" bar; Back is ignored during a call
  (`features/calls/FEATURE.md:93-94`).
- Group calls, call links and scheduled calls are not built (deferred, plan
  section 13); v1 had `group_call_screen`, `call_link_sheet` and
  `scheduled_calls_screen` (tag `v1-final`).
- The group member picker is its own list rather than the people panel
  (`app/MODULE.md:354-356`).
- Proximity/earpiece playback for voice notes is not done, and the proximity and
  audio-routing Android code has not been exercised on a device (`app/MODULE.md:348-352`,
  tracker A3).
- v1's diagnostics settings page has no v2 equivalent beyond "Advanced"; this
  needs the user's view of what they still want back (section 5).

### Area F: Tests and quality gates

Results of this review's run are in section 1. The gates themselves are good:
`scripts/verify.ps1`/`.sh` run the codegen check, format, both analyzers, every
package's tests, the server, the governance check; CI adds a Postgres 17
service with `HELIX_REQUIRE_TEST_DATABASE=1`, `--enforce-lockfile`, a coverage
ratchet, performance budgets, an SBOM and a vulnerability scan
(`.github/workflows/ci.yml`). What they cannot see is the platform glue, which is
where the High findings of area E sit.

#### F-01 (Medium, confirmed): the riskiest platform glue has no test at all

- **What is wrong.** No device or emulator test runs anywhere (CI says so,
  `.github/workflows/ci.yml:143-157`). The FCM background handler
  (`app/lib/core/push/push_background.dart`), `PushTokenSource`, the
  notification plugin wrapper, `LocalAuthDeviceLock` in the console, the
  Android foreground service, proximity and audio routing are either faked in
  tests or untested, and the server's FCM provider has no automated test
  (`DEPENDENCY_RISK_REGISTER.md`, "Deferred major upgrades"). E-01, E-02 and B-01
  all live in this gap.
- **Suggested fix.** Unit tests with fakes for the parts that are logic (when to
  register the token, when to notify, which activity class the console uses);
  a short manual device checklist per release in
  `docs/release/REMOTE_RELEASE_CHECKLIST.md` (push after first sign-up,
  notification with the app backgrounded, App lock in the console, a call from a
  locked phone); later an Android emulator job.

#### F-02 (Low, confirmed): four of the five UI golden tests check nothing, even on Linux CI

- **What is wrong.** `chat_components_golden_test.dart` skips a golden whose
  baseline file is missing (`packages/helix_remote_ui/test/chat_components_golden_test.dart:27-36`),
  and none of its four baselines exist; only
  `test/goldens/component_gallery_light.png` is committed. AGENTS.md describes
  them as "5 golden tests skipped off Linux", which suggests they run on Linux;
  four of them do not run anywhere.
- **Suggested fix.** Generate the four baselines on Linux
  (`flutter test test/chat_components_golden_test.dart --update-goldens`),
  review and commit them; make a missing baseline fail on CI.

#### F-03 (Low, confirmed): golden failure images are committed

- **What is wrong.** `packages/helix_remote_ui/test/failures/*.png` (four files
  from a failed golden run) are tracked in git. AGENTS.md: do not commit
  unexplained binary assets.
- **Suggested fix.** Delete them and add `test/failures/` to the package's
  `.gitignore`.

#### F-04 (Low, confirmed in this run): a third load-sensitive server test

- **What is wrong.** In the full parallel run (`--concurrency=3`, with the live
  server running on the same PC), `test/client/engine/devices_test.dart`
  "changing the password needs the current one, and the new one signs in on
  another device" failed with `TimeoutException: Failed to acquire pool lock`,
  raised in `IdentityStore.touchLastSeen` from a request that was still running
  after the test had completed. Run alone, the file passes (10/10). It is not
  one of the two timing-sensitive tests listed in AGENTS.md.
- **Suggested fix.** Make the client tests await or cancel the engine's
  background work before tearing down the server (the request outlived the
  test); until then, add it to AGENTS.md's known timing-sensitive list with
  today's date.

#### F-05 (Low, confirmed): small test gaps

- `packages/helix_remote_domain` has no `test/` directory; both verify scripts
  skip it silently (`scripts/verify.ps1:107-110`).
- The admin console's tests pass with a fake `DeviceLock`, so the Android
  activity problem (B-01) is invisible to them.
- `git diff` after `flutter pub get` shows that the committed admin plugin
  registrants still register `share_plus` and `url_launcher`, which the console
  no longer depends on (`admin/{linux,macos,windows}/flutter/...`). AGENTS.md
  tells agents to revert these files after `pub get`, so the stale version keeps
  coming back. Commit the regenerated admin registrants once.

### Area G: Architecture, dependencies, docs

#### G-01 (Medium, confirmed): the dependency risk register no longer matches the lockfile

- **What is wrong.** `docs/dependencies/DEPENDENCY_RISK_REGISTER.md` says these
  are "deliberately not upgraded" because each needs a device matrix:
  `flutter_local_notifications ^18.0.0`, `flutter_secure_storage ^10.3.1`,
  `flutter_contacts ^1.1.9+2`, `connectivity_plus ^6.1.3`. The app now declares
  `^22.3.1`, `^11.2.0`, `^2.5.0` and `^7.3.1` (`app/pubspec.yaml:42-59`) and the
  lockfile resolves those. The register's `file_picker` row is
  `12.0.0-beta.7` under ADR-024's prerelease exception; the app declares and
  resolves `13.1.0` (stable). `firebase_core`, `firebase_messaging`,
  `local_auth` and `shared_preferences` are not in the register at all. AGENTS.md
  says CI enforces the register; the governance check only verifies that
  `file_picker` is declared, not its version.
- **Why it matters.** The register's own warning ("a messaging app ships a build
  that cannot notify, cannot unlock") describes E-01, E-03 and B-01. The major
  bumps it said needed a device matrix were taken without one being recorded.
- **Suggested fix.** Rewrite the register from the current pubspecs and lockfile;
  retire ADR-024's exception (or record why it stays); record the device checks
  done for the notification, secure-storage, contacts and connectivity majors;
  extend `tool/check_governance_controls.dart` to compare the register's versions
  with the lockfile.

#### G-02 (Low, confirmed): stated architecture rules that the code does not follow and no test enforces

- AGENTS.md: "no SQL lives outside `data/`" and every module has `http/`,
  `application/`, `domain/`, `data/`. SQL is in `module.dart` of `people`,
  `calls`, `backup`, `media`, `ops`, `keys`, `messaging` and `groups`; only
  `identity` has the full layout; `realtime` has no `api.dart`. The server's
  `test/architecture_test.dart` has no SQL-placement rule.
- Plan of record §8.1: "No SQL outside `data/`" is listed as an architecture-test
  rule; it was never written.
- **Suggested fix.** Either move the SQL into `data/` stores when a module is next
  touched and add the rule, or (cheaper) change AGENTS.md and the plan to the
  rule that is actually kept (SQL only in a module's own files, never in
  `api.dart`) and test that.

#### G-03 (Low, confirmed): documents that contradict the code

1. `ARCHITECTURE_V2_PLAN.md` header: "Status: cutover in progress" and
   "Authoritative copy: this file on branch `architecture-v2` (worktree
   `J:\hx2`). The copy on `main` is a snapshot from before Phase 0." Both are
   stale since the merge.
2. Plan §4.1 lists `bin/admin_tool.dart`; it does not exist (B-07).
3. Plan §4.3: audit and metrics tables range-partitioned by month with
   retention; not built (B-04; `V2_OPERABILITY.md` already says so).
4. `V2_OPERABILITY.md`, "Disaster recovery": after Postgres restarts, "restart
   every server node (the bus connection is not re-opened)"; the same document's
   troubleshooting section and `postgres_db.dart:163-185` say the `LISTEN`
   connection reopens and no restart is needed.
5. `V2_OPERABILITY.md` close-code table lists `1001` for shutdown and says `4001`,
   `4004` and `4029` are not emitted; the server sends `4503`, `4001`, `4004` and
   `4029` (`realtime/module.dart`, `REALTIME_V2.md`; the document's own review
   items say this was resolved). `V2_SERVER_HANDOFF.md` "Start and stop" also
   says WebSockets close with 1001.
6. `THREAT_MODEL.md` T-10: rate limits "hold across nodes and restarts"; the
   buckets are an UNLOGGED table that Postgres empties after a crash or power
   loss (`platform/platform_migrations.dart:20-26`).
7. `THREAT_MODEL.md` T-7 and `CRYPTO_V2.md` §11, §14: see A-06 and C-03.
8. `admin/MODULE.md`: audit "in the same transaction" (B-04) and "an attacker
   elsewhere cannot lock the operator out" (B-08).
9. `METADATA_V2.md`, `METADATA_INVENTORY.md`: see C-02 and C-03.
10. AGENTS.md "Known pre-existing test failures" records admin 181 tests; this
    run has 185 (not a failure, but the line is stale).

#### G-04 (Low, confirmed): very large files

`server/lib/src/modules/groups/module.dart` (1,196 lines, plus the 607-line
`federation.dart` part of the same library), `packages/helix_remote_engine/lib/src/calls/calls_service.dart`
(1,049), `backup/snapshot.dart` (885), `messaging/apply.dart` (852),
`admin/lib/src/widgets/console_kit.dart` (906). They are tested, but A-02 and
A-09 sit in the groups file. Split the groups route handlers from the
operations and the federation part when that module is next changed.

#### G-05 (Info): local leftovers from v1

Untracked folders `helix_remote/packages/helix_remote_{groups,storage,sync}`
(only `.dart_tool/` and `build/`) and empty, ignored `attachments_storage/` and
`backup_media_storage/` folders at `helix_remote/` and `helix_remote/app/`. Not in
git; the user can delete them.

### Area H: Operations (the user's PC)

#### H-01 (High, unverified): no backup of the only production database is set up or proven

- **What is wrong.** `V2_OPERABILITY.md` ("Backups") describes a daily
  `pg_dump`, a blob copy after it and a monthly restore drill, to be scheduled by
  the user; nothing in the repository sets it up, and this review could not see
  whether the user has (Task Scheduler and the backup drive are outside the
  repository). The restore procedure has an open, untested step: phones whose
  mailbox cursor is ahead of a restored `device_seq` may skip new messages
  (`V2_OPERABILITY.md:387-400`).
- **Failure scenario.** The PC's disk fails or Postgres is corrupted by a power
  cut. Without a recent dump every account, device registration, key bundle,
  group roster and encrypted backup on Helix Global is gone; every user must
  register again and every contact sees a safety-number change. With a dump but
  no verified cursor handling, some messages after the restore are silently
  skipped.
- **Suggested fix.** A scheduled task that runs the documented `pg_dump`
  (`--no-unlogged-table-data`) and blob copy daily to a second disk, keeps
  generations, and copies one off the PC; one restore drill now; then fix the
  cursor problem in code (the server can tell the phone to reset its cursor when
  `lastSeq` is below it in the `hello` frame) and document it.

#### H-02 (Medium, confirmed): production runs from the development working tree

- **What is wrong.** Production is `dart run bin/server.dart` in
  `J:\Projects\helix\helix_remote\server` (`V2_SERVER_HANDOFF.md:74-90`), the same
  checkout agents and the user edit, test, `pub get` and switch branches in.
  `dart run` compiles from source at each start.
- **Failure scenario.** The user restarts the server while a branch with
  half-finished work (or an uncommitted edit, or a `pub get` that moved a
  dependency) is checked out: production starts running it, possibly with a
  migration that can never be undone (expand-only, but applied).
- **Suggested fix.** Build a release from a tagged commit
  (`dart compile exe bin/server.dart -o J:\Projects\Servers\helix_server\helix-server.exe`
  plus `bin/migrate.dart`), run it from that folder with its own `.env`, and
  document "deploy = build exe from tag, stop, migrate, start".

#### H-03 (Medium, confirmed): nothing restarts the service after a reboot or a crash

- **What is wrong.** Start-up is four manual steps in order (Postgres, coturn,
  Caddy, server; `V2_SERVER_HANDOFF.md:74-90`). If Postgres is not ready the
  server exits with `database is not reachable` (`platform/db/postgres_db.dart:21-24`)
  rather than waiting. On Windows only Ctrl+C stops it gracefully; closing the
  console window is a hard stop (`bin/server.dart:64-65`).
- **Failure scenario.** A power cut or Windows Update reboot at night: Helix
  Global stays down until the user notices and starts everything by hand.
- **Suggested fix.** Run the server (and Caddy) as Windows services (WinSW or
  NSSM) or at-startup scheduled tasks with restart-on-failure and a dependency on
  `postgresql-x64-17`; retry the database connection at start for a minute
  before exiting; start coturn from a scheduled task at log-on.

#### H-04 (Medium, confirmed): the Caddy site has no edge hardening

- **What is wrong.** The live Caddyfile is the bare three-line site block: no
  `Strict-Transport-Security` (the handoff recommends it, `V2_SERVER_HANDOFF.md:227-236`)
  and no restriction of `/v1/admin/*` or `/v1/ops/metrics` (B-02).
- **Suggested fix.** Add HSTS (short `max-age` first) and a matcher that answers
  404 for `/v1/admin*` and `/v1/ops/metrics` unless the client address is
  loopback or the LAN. This is a Caddyfile change the user makes; no server
  restart is needed for the Helix process (`caddy.exe reload`).

#### H-05 (Low, confirmed): no monitoring or log rotation

- **What is wrong.** `/v1/ops/metrics` exists, but nothing scrapes it; nothing
  alerts on Postgres down, disk space, dead jobs or mailbox backlog. Logs go to
  the console window, and `HELIX_LOG_FILE` is appended forever
  (`platform/observability/log.dart:93-115`).
- **Suggested fix.** A small scheduled PowerShell check (ready endpoint, free
  disk, `helix_jobs_dead`, `helix_mailbox_backlog`) that writes a Windows event
  or sends a push/email to the operator; rotate the log file daily (copy and
  truncate, as `log.dart` suggests).

#### H-06 (Low, confirmed): a PC that stays off for more than three days fails queued sends

- **What is wrong.** Phones give up on a queued message three days after it was
  written (`packages/helix_remote_engine/lib/src/config.dart:15`,
  `outboxMaxAge`; `messaging/outbox.dart:441-444`). The server is a PC that is
  not always on.
- **Failure scenario.** The PC is off over a long weekend: messages written on
  phones meanwhile turn "failed" and must be retried by hand one by one.
- **Suggested fix.** Do not count time during which the server was unreachable
  toward the age limit (count attempts that reached the server instead), or
  raise the limit to match the 30-day mailbox retention.

---

## 4. Remediation plan

Ordered by risk, then dependency, then effort. Each batch is one change set
(one commit, per the user's commit preference) and follows the `helix-feature`
and `helix-verify` skills. "Sonnet 5.5" marks well-scoped work with clear
tests; "Opus 5.5" marks batches that change cross-module behaviour, protocol,
concurrency or crypto-adjacent code. Nothing here starts until the user approves
the batch.

### Batch 1: Operator safety net (no Helix code)

- **Goal.** Stop the worst operational losses today, with no code change.
- **Closes.** H-01 (scheduling and a drill; the code part is in Batch 9), H-04,
  the exposure half of B-02.
- **Touches.** The user's PC only: a Task Scheduler job for the documented
  `pg_dump` and blob copy (`V2_OPERABILITY.md`, "Backups"), a second disk and an
  off-PC copy, one restore drill into `helix_drill`; the Caddyfile (HSTS with a
  short `max-age`; 404 for `/v1/admin*` and `/v1/ops/metrics` unless loopback or
  LAN). An agent may write the scripts and the Caddyfile snippet into
  `helix_remote/deploy/windows/` and update `V2_OPERABILITY.md`; the user installs
  them.
- **Rules.** Agents never handle Postgres passwords (pgpass is the user's step);
  never edit live state; never restart the server.
- **Regression risk.** Low. A wrong Caddy matcher could block the admin console
  from the LAN: test from the console before relying on it.
- **Verify.** A dump file appears daily; the drill's `/v1/health/ready` is 200;
  `curl https://helix.agiletechbd.com/v1/admin/setup` from outside the LAN gets
  404; HSTS header present.
- **APK / restart.** No APK. `caddy.exe reload` only; the Helix server is not
  restarted.
- **Model.** Sonnet 5.5.
- **Status (2026-10-09).** Written: `helix_remote/deploy/windows/`
  (`backup-helix.ps1`, `install-backup-task.ps1`, `restore-drill.ps1`,
  `Caddyfile.example`, `README.md`). `V2_OPERABILITY.md` and
  `V2_SERVER_HANDOFF.md` were updated to match. Tested: the backup script
  against fake `pg_dump`/`pg_restore` tools (24 checks: generations, failure
  paths, off-PC copy, paths with spaces), and against the real `pg_dump` on a
  closed port (fails fast, no prompt). Also the task's command line as Task
  Scheduler launches it, that the installer stops before registering anything
  when `psql` cannot sign in, and the drill's refusal of production ports.
  The Caddy block passed `caddy validate`; on a throwaway local Caddy its path
  rule blocked 16 path variants from outside the LAN and allowed them on it.
  **Pending (the user):** install the task (`-WritePgPass -RunNow`), set up
  an encrypted off-PC copy, run the first drill, back up `.env` apart from the
  dumps, and install and check the Caddyfile.

### Batch 2: Messaging availability on the server

- **Goal.** No idle device or abusive member can stop delivery or fill the disk.
- **Closes.** A-01, A-02, A-03, A-09.
- **Touches.** `messaging/data/mailbox_store.dart` (an over-quota device is
  skipped or trimmed instead of failing the send), `messaging/module.dart`,
  `groups/module.dart` (per-device and per-account limits on group sends, a
  per-group budget, a smaller stored-payload cap), `identity` (a periodic job
  that revokes devices not seen for N days through the normal hooks),
  `media/module.dart` and `platform/config/server_config.dart` (a server-wide
  storage budget, optional `HELIX_STORAGE_BUDGET_BYTES`), the device check moved
  inside the send transaction. If the response must tell the sender which
  devices were skipped, that is an additive field in `helix_remote_protocol`
  (`SendMessageResponse`) with a golden fixture update
  (`HELIX_UPDATE_FIXTURES=1`), `REST_V2.md`, and an engine change to show it.
- **Rules and tests.** A new messaging/identity migration only if an index on
  `devices(last_seen_on)` is added (new migration, never edit an applied one);
  messaging, groups and identity module tests; the two-node e2e suite; the
  public-route snapshot is unaffected (no new public route); MODULE.md for each
  module touched; `V2_SERVER_HANDOFF.md` env table if a variable is added.
- **Regression risk.** Medium: delivery semantics change. Skipping a device must
  never skip the account's only active device; inactivity revocation needs a
  generous default (see section 5).
- **Verify.** New tests: a device at quota does not fail sends to its account;
  a group-send burst gets `rate_limited`; the storage budget refuses uploads;
  full server suite on Postgres.
- **APK / restart.** Server restart (plus `bin/migrate.dart` if a migration is
  added; any new `.env` line is optional with a default). A new APK only if the
  protocol gains the skipped-devices field and the app shows it.
- **Model.** Opus 5.5.
- **Status (2026-10-09).** Done, server only, no migration, no protocol change,
  no APK.
  - **A-01:** a device over 10,000 undelivered envelopes loses its oldest
    ones in the send's transaction (`MailboxStore.trim`,
    `helix_mailbox_trimmed_total`) instead of failing the send. That makes the
    skipped-devices protocol field unnecessary. Inactivity revocation exists
    (`identity.revoke_inactive`, never an account's newest device) but is off
    until `HELIX_DEVICE_INACTIVE_DAYS` is set (section 5, item 1).
  - **A-02:** group sends are limited per device (`groups.send`). Stored sends,
    direct and group, draw on one weighted per-account budget
    (`messaging.stored_account`, one unit per started 16 KiB per recipient
    device), and group sends also on a per-group budget (`groups.fan_out`).
    `RateLimiter.hit` gained a `cost`. There is no smaller group payload
    cap: texts may be 65,536 characters, so content up to 256 KiB is
    legitimate.
  - **A-03:** a platform `StorageBudget` covers the database size plus media
    bytes, with the gauge `helix_storage_used_bytes`. While over
    `HELIX_STORAGE_BUDGET_BYTES` (off until set; section 5, item 7), media
    uploads, backups and payloads over 16 KiB get `quota_exceeded`.
  - **A-09:** `deliver` locks the active devices (`FOR SHARE`, id order) in
    its transaction and skips the others. `allocate` locks in id order too.
  - **Tests:** `server/test/modules/availability_test.dart`, plus weighted
    rate-limit and config tests.
  - **Not done:** an admin dashboard tile for storage (admin APK, Batch 6) and
    "inactive since" in the app's device list (APK, later).

### Batch 3: Android notifications and push registration

- **Goal.** Every incoming message and call notifies, from the first sign-up on.
- **Closes.** E-01, E-02, part of F-01; E-03 if the user wants Windows
  notifications (section 5).
- **Touches.** `app/lib/main.dart` (`_startPush`), `core/push/push_token_source.dart`,
  a provider that registers the token whenever the engine reaches `running`
  and re-subscribes `onTokenRefresh`; a notifier that raises the grouped message
  notification from engine events while the app is not resumed and clears it on
  resume (`core/notifications/local_notifications.dart`,
  `core/lifecycle/app_lifecycle_host.dart`); for Windows, the plugin's Windows
  settings.
- **Rules and tests.** Notifications stay wake-up only (no content unless
  previews are on); English literals; `product_rules_test` and
  `accessibility_test` unchanged; new unit tests with a fake token source and a
  fake engine event stream (paused state notifies, resumed does not; sign-in
  registers once).
- **Regression risk.** Medium: duplicate notifications (FCM isolate and app
  both) if the lease logic and the new notifier disagree; test both paths.
- **Verify.** App suite; then on the user's phone: install fresh, sign up,
  close the app, receive a message and a call; background the app (not
  killed), receive a message.
- **APK / restart.** New app APK (the user builds it). No server restart.
- **Model.** Opus 5.5 (Android lifecycle, the lease and two notification paths).
- **Status (2026-10-09).** Done in code; the device checks are pending (they
  need an APK).
  - **E-02:** `core/push/push_registration.dart`. `PushRegistration`, kept alive
    by the app root, sends the token every time `authStateProvider` reaches
    `ready`; a rotated token goes to the engine running at that moment.
    `PushTokenSource` now initialises Firebase in the UI isolate (the deeper
    cause, above) and sits behind a `PushTokens` interface.
    `main.dart`'s `_startPush` is gone.
  - **E-01:** `core/notifications/message_alerts.dart`. `RunningAppAlerts`
    raises the grouped notification from the engine's `IncomingMessageEvent`
    while the app is paused or hidden; `AppLifecycleHost` clears it on resume.
    `MessageAlerts` (mute and settings rules, previews) is shared with the push
    isolate. Both paths use notification id 0, so one replaces the other.
  - **F-01 (part):** `app/test/push_and_alerts_test.dart`, 12 tests, and the
    device checks in `docs/release/REMOTE_RELEASE_CHECKLIST.md`.
  - **E-03 (Windows) not done:** section 5, item 5.
  - **Residual:** a backgrounded app whose network Android has cut (Doze)
    keeps the lease while unable to fetch, so the push isolate still stands
    down until the app is frozen past the lease's 20 seconds. That is the
    lease's to fix (Batch 4).

### Batch 4: One engine per database, and safe session commits

- **Goal.** No two engines can commit the same ratchet state.
- **Closes.** C-01.
- **Touches.** `packages/helix_remote_db` (a `version` column on `sessions`,
  compare-and-set save), `packages/helix_remote_engine/lib/src/crypto/db_stores.dart`
  and `pairwise_crypto.dart` (retry on a lost race),
  `app/lib/core/platform/engine_lease.dart` (heartbeat checks ownership; an
  engine that lost the lease stops).
- **Rules and tests.** Local database schema 2 → 3: a `from2To3` step migration,
  `dart run tool/codegen.dart` (schema dump v3, generated helpers, committed
  generated code; CI runs `--check`), and the migration test; db and engine
  tests including two engines on one database file; a note in
  `docs/security/remote_cryptographic_design_review.md` (state commit
  discipline); no change to crypto test vectors.
- **Regression risk.** Medium: a wrong compare-and-set loses sessions and
  triggers §13a resets. Keep the retry inside the engine's per-device lock.
- **Verify.** db, engine, app and server client suites; codegen `--check`.
- **APK / restart.** New app APK. No server restart.
- **Model.** Opus 5.5.
- **Status (2026-10-09).** Done; the device check needs the APK.
  - **Schema 3:** `sessions.version`, one column, `from2To3` as an
    `ALTER TABLE ... ADD COLUMN` (the step-by-step helpers only create
    entities). Existing rows start at 0. Schema dump v3 and the helpers are
    generated and committed.
  - **The compare-and-set:** `CryptoDao.saveSessions` takes
    `expectedVersion`, writes only while the stored revision is still that one
    and stores `expectedVersion + 1`; it returns **false** and changes nothing
    otherwise. `DbSessionStore.load` stamps the record with the revision it
    read, `save` raises `StaleSessionState` when the write is refused, and
    every read-then-write goes through `PairwiseCrypto.locked` (or
    `encryptFor`'s own loop), which reloads and retries up to `staleAttempts`
    (3) - always from the stored state, never from a record loaded earlier.
    A cleared record is written as an empty one-slot record rather than deleted,
    so the revision survives and the next write is still comparable.
  - **`PRAGMA busy_timeout = 5000`** on every connection (`busyTimeout` in
    `opening.dart`). This was necessary, not cosmetic: with SQLite's default of
    zero the second writer fails at once, and the compare-and-set is never
    reached. Found by the two-engine test.
  - **App:** the heartbeat reads the lease file before rewriting it. Another
    engine's claim ends this one (`lostEvents`, `lost`), stops the engine
    (`HelixRuntime._onLeaseLost`) and makes `runtimeProvider` open a new
    runtime that takes the lease back. A lost lease no longer deletes the
    file, which is the other engine's now. `HelixRuntime.open` gained
    `leaseHeartbeat` for the tests.
  - **Crypto:** `DeviceSessions` carries a `version`, propagated through
    `withNewActive`, `withUpdated`, `cleared` and a new `atVersion`, and **not**
    part of the encoded state, so no test vector changed.
  - **Tests:** db `sync_test.dart` (the CAS, the refusal, the ArgumentError) and
    `drift/helix/migration_test.dart` ("2 to 3 keeps every session row and
    gives it revision 0"); crypto `session_test.dart` (the revision travels,
    and is not stored state); engine `util_test.dart` and a new
    `two_engines_test.dart` (two engines on one database file: both sends
    arrive, the revision rises once per committed send, a stale write is
    refused, a locked block retries); app `local_data_test.dart` (the
    heartbeat's ownership check, and that a lost lease leaves the new owner's
    file alone) and `hard_wipe_test.dart` (the engine stops on the loss and the
    app reopens).
  - **Not done, deliberately:** `sender_keys` keeps its last-writer-wins save,
    so two engines could still send a group message from the same sender-key
    iteration. The user chose sessions only for this batch; the gap is recorded
    in CRYPTO_V2 §14 and in the design-review note. The Doze residual from
    Batch 3 is now *safe* (the overlap can no longer corrupt state) but not
    *removed*: the user chose to keep the lease timing.

### Batch 5: Server hardening

- **Goal.** Close the remaining server weaknesses that need no protocol change.
- **Closes.** A-04, A-05, A-06, A-07, A-08, A-11, A-12.
- **Touches.** `platform/jobs/jobs.dart` (per-job and periodic timeouts),
  `platform/push/push.dart` (timeout on the token refresh),
  `identity/application/sign_up.dart` and `identity/config.dart` (daily SMS
  budget, country allow-list), `identity/application/sign_in.dart` and
  `context.dart` (32-byte decoy salts, decoy lockout counter, same-shape
  transaction), `platform/db/postgres_db.dart` (statement and lock timeouts;
  after-commit actions that never throw), `people/module.dart` (presence and
  profile limits), `keys/module.dart` (per-requester-and-target limit).
- **Rules and tests.** The public-route snapshot must stay unchanged (no new
  public route); every new limit is a named `RateLimitPolicy`; the
  log-redaction test still passes; identity, platform, people and keys tests;
  update THREAT_MODEL T-7 and the env table in `V2_SERVER_HANDOFF.md`.
- **Regression risk.** Low to medium: a too-short statement timeout breaks
  purges and migrations (give those their own limit).
- **Verify.** New tests: a hung job does not block others; decoy and real
  password params have the same shape; SMS budget refuses the next code;
  full server suite on Postgres.
- **APK / restart.** Server restart. New optional `.env` lines:
  `HELIX_SMS_DAILY_LIMIT`, `HELIX_SMS_COUNTRIES` (both with safe defaults). No
  migration. No APK.
- **Model.** Sonnet 5.5.

### Batch 6: Admin console and admin API

- **Goal.** A console the operator cannot lock themselves out of, sessions that
  can be ended, a complete audit trail.
- **Closes.** B-01, the code half of B-02, B-03, B-04, B-05, B-06, B-07, B-08,
  B-09 (or drop macOS).
- **Touches.** `admin/android/.../MainActivity.kt` (`FlutterFragmentActivity`),
  `admin/lib/...` (typed confirm for ban, re-lock after background),
  `server/lib/src/modules/admin/` (server-side sign-out route, log-stream
  re-check and frame cap, audits inside the transaction, an audit retention job,
  global-cap exemption for LAN addresses), `server/bin/admin_tool.dart`
  (reset-password), `packages/helix_remote_protocol` route catalog and
  `REST_V2.md` for the new admin route, `packages/helix_remote_api`
  `AdminClient` (route-parity test).
- **Rules and tests.** The new route is admin-access, not public (the
  public-route snapshot is unchanged); route-parity and catalog tests; admin
  console tests plus a rule test for the activity class; admin module tests and
  `test/client/admin_console_v2_test.dart`; AGENTS.md test count update.
- **Regression risk.** Low.
- **Verify.** Admin suite, server suite; on the phone: turn App lock on, restart,
  unlock.
- **APK / restart.** New admin APK; server restart (no migration unless the
  audit retention needs an index).
- **Model.** Sonnet 5.5.

### Batch 7: Retention and hygiene

- **Goal.** What the documents say is deleted, is deleted.
- **Closes.** A-10, C-02, H-06 (and B-04's retention if not done in Batch 6).
- **Touches.** `media/module.dart` (blob before row, orphan sweep),
  `people/module.dart` (report retention job), `RETENTION_AND_DELETION.md` and
  `METADATA_INVENTORY.md`; the engine's outbox age rule
  (`packages/helix_remote_engine/lib/src/config.dart`, `messaging/outbox.dart`).
- **Rules and tests.** Media and people module tests; engine outbox tests.
- **Regression risk.** Low.
- **Verify.** Server and engine suites.
- **APK / restart.** Server restart; new app APK for the outbox change.
- **Model.** Sonnet 5.5.

### Batch 8: Documents, register and test gates

- **Goal.** Documents and gates that tell the truth.
- **Closes.** G-01, G-02 (documentation route), G-03, C-03, F-02, F-03, F-04,
  F-05, and the AGENTS.md known-failure list.
- **Touches.** `docs/dependencies/DEPENDENCY_RISK_REGISTER.md`, ADR-024 status,
  `tool/check_governance_controls.dart` (register versions against the
  lockfile), AGENTS.md, `ARCHITECTURE_V2_PLAN.md` header and §4.1/§4.3 notes (a
  plan change-log entry approved by the user), `V2_OPERABILITY.md`,
  `V2_SERVER_HANDOFF.md`, THREAT_MODEL, CRYPTO_V2 §11/§14, METADATA docs, the four
  golden baselines (generated on Linux: CI artifact or WSL), deleting
  `test/failures/` and ignoring it, the admin registrants committed once
  regenerated, a test-hygiene fix for `devices_test.dart`.
- **Rules and tests.** `dart run tool/check_governance_controls.dart` after
  touching docs and CI; ui goldens on Linux; server client tests.
- **Regression risk.** Low.
- **Verify.** Governance check, ui suite on Linux, server suite.
- **APK / restart.** None.
- **Model.** Sonnet 5.5.

### Batch 9: Operations code

- **Goal.** A production process that survives reboots and is not the
  development tree.
- **Closes.** H-02, H-03, H-05, and the restore-cursor half of H-01.
- **Touches.** A release script (`dart compile exe` for `bin/server.dart` and
  `bin/migrate.dart` from a tag into the server folder), WinSW/NSSM or
  scheduled-task definitions under `deploy/windows/`, a start-up database retry
  in `bin/server.dart`/`platform/db/postgres_db.dart`, a health-and-disk check
  script, log rotation; for the restore cursor, a realtime `hello` field (or a
  mailbox response field) that tells a phone its cursor is ahead and an engine
  reaction that resets it, with a protocol fixture update and `REALTIME_V2.md`.
- **Rules and tests.** AGENTS.md "Deployment" section changes (the user approves:
  section 5); protocol fixture change; realtime and engine tests for the cursor.
- **Regression risk.** Medium for the cursor change (a wrong reset re-delivers
  or skips), low for the scripts.
- **Verify.** Server, engine and api suites; a restore drill with the new
  cursor handling.
- **APK / restart.** Server restart into the new process model (the user does
  it); a new app APK for the cursor reaction.
- **Model.** Opus 5.5 for the cursor protocol change; Sonnet 5.5 for the scripts.

### Not batched

- D-01: measure Argon2id and attachment sealing on the user's slowest phone
  first; open a batch only if it stalls.
- E-04: waits for the user's list of v1 behaviours to bring back next.
- C-04: input for an external review, when one is commissioned.
- G-04: split the large files when they are next changed for another reason.
- G-05: the user may delete the untracked leftovers.

## 5. Out-of-plan observations (decisions for the user)

1. **Inactive devices (A-01).** How long may a device stay silent before the
   server revokes it (WhatsApp unlinks companions after about 30 days)? And
   should a send skip an over-quota device silently, or report it to the sender
   (an additive protocol field)?
2. **SIM-swap protection.** THREAT_MODEL T-4 accepts that whoever controls the
   number can take the account over with `replace_existing`, and a password
   does not stop it (the server deletes it, `identity/application/registration.dart:126-138`).
   A WhatsApp-style registration lock (a password blocks `replace_existing` for
   N days unless given) is a change to the identity model and should get an ADR
   and a change-log entry (plan §12).
3. **Signed membership changes** (CRYPTO_V2.md §14, still open): closing
   server-forged group membership needs membership changes signed by the acting
   device, which changes plan §5 and needs a new ADR.
4. **Admin access (B-02).** LAN-only admin, a second factor (TOTP), or both?
   Shorter admin tokens with refresh?
5. **Windows (E-03).** Is the Windows client expected to notify? If not, say in
   the product docs that it must be open to receive.
6. **Production process (H-02, H-03).** Moving production to a compiled
   executable in `J:\Projects\Servers\helix_server`, run as a Windows service,
   changes the deployment workflow AGENTS.md describes ("Deploying = the user
   restarts the server"). This needs the user's approval and an AGENTS.md
   update.
7. **Budgets (A-03, A-05).** The server-wide storage budget and the daily SMS
   budget (and which country codes may receive codes) are the operator's numbers.
8. **Key-change behaviour** (CRYPTO_V2.md §14): hold sends to a contact whose
   identity key changed until the user looks, or keep today's automatic pin with
   a notice?
9. **v1 behaviour still wanted (E-04).** Group calls (deferred by decision),
   call links, scheduled calls, a return-to-call bar, a diagnostics page: which
   of these come next?
10. **External cryptographic review.** None has happened; C-04 lists where a
    reviewer's time is best spent.
11. **Admin console targets (B-09).** Keep macOS and Linux, or ship the console
    on Android and Windows only?
12. **Golden baselines (F-02)** need a Linux machine or a CI artifact; the user
    may prefer to generate them in WSL.
