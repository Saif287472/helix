# Sweep 13 — `helix_remote_cli` and the server's `test/client/` harness

**Where:** `packages/helix_remote_cli/` — `lib/src/v2/cli_app.dart` (835),
`cli_io.dart` (126), `cli_home.dart` (84), `cli_args.dart` (80),
`bin/helix_v2.dart` (8), `lib/v2.dart` (9), `test/v2/architecture_test.dart`
(56), `test/v2/cli_v2_test.dart` (230); the harness around the client tests —
`server/test/client/engine/support.dart` (170),
`server/test/client/engine/cli_test.dart` (278),
`server/test/support/{harness,flows,test_client,test_platform,test_database}.dart`
(118, 102, 200, 98, 72). Cross-reads: `engine.dart:323-370` (what start and
`_activate` do unawaited), `account/device_service.dart:22-58`,
`messaging/outbox.dart:336-395` and `:426-477` (what "failed" means),
`db/lib/src/values.dart:23-50`, `app/lib/core/engine/server_policy.dart`, and
`docs/protocol/v2/CRYPTO_V2.md:572-583` (the documented HTTPS closure).

The CLI is a thin, mostly honest shell: it opens the encrypted database,
starts the engine, runs one command and closes everything in a `finally`;
`describeError` prints only codes and its own messages; the tests prove that no
password, SMS code, database key or full phone number reaches either stream.
Two things do not hold. The CLI is the one shipped client with no server-address
policy, so a typed `http://` origin carries the auth key and bearer tokens in
cleartext — the app refuses exactly this, and the crypto doc records the hole
as closed. And `send` prints "sent" for a message the outbox has already marked
`failed`, because it treats every status except `pending` as success. The
harness itself is sound and runs the real server and real clients; its gaps are
in what it never reopens.

## Findings

### AUD-13-1 The CLI accepts any `http://` server: the auth key and tokens cross the network in cleartext

**Severity:** P2  **Confidence:** confirmed
**Where:**
[cli_app.dart:169-181](file:///J:/Projects/helix/helix_remote/packages/helix_remote_cli/lib/src/v2/cli_app.dart#L169-L181)
(`_server` checks only that a scheme and host exist),
[cli_app.dart:195](file:///J:/Projects/helix/helix_remote/packages/helix_remote_cli/lib/src/v2/cli_app.dart#L195)
(the address is used as-is),
[server_policy.dart:36-53](file:///J:/Projects/helix/helix_remote/app/lib/core/engine/server_policy.dart#L36-L53)
(the rule the app applies),
[CRYPTO_V2.md:579-583](file:///J:/Projects/helix/helix_remote/docs/protocol/v2/CRYPTO_V2.md#L579-L583)
(the documented closure).
**What:** `_server` rejects a missing scheme and host and nothing else, so
`--server http://example.org` (or `HELIX_SERVER=http://…`, or a saved
`config.json` written that way) is accepted and every request goes out over
plain HTTP: `PasswordSignInRequest(authKey:)` on `login`, the bearer access and
refresh tokens on every later run, `verificationToken` on `register`, and the
signed prekeys. The app refuses the same address outside a debug build's
development hosts (`ServerPolicy.check`, reason `notHttps`); the crypto doc
records HTTPS enforcement as *closed* on the strength of that app-side rule.
The CLI, which is a shipped client in the same repo and is pointed at personal
servers (`register --invite-env`, `--server`), has no equivalent.
**Trigger:** `helix_v2 --server http://<host> login --phone +… --password-env PW`
or `HELIX_SERVER=http://…` in a script; also an `http://` link code approved by
the CLI.
**Evidence:** the only validation is
`if (uri == null || !uri.hasScheme || uri.host.isEmpty)`
(cli_app.dart:176-180); there is no scheme test anywhere in the package
(`architecture_test.dart:22-54` pins *packages*, not policy). `ServerPolicy`
lives under `app/lib/core/`, which the CLI cannot import (it is plain Dart with
no Flutter and does not depend on the app), so the rule has no shared home.
The login path sends the password-derived auth key
(engine `account_service.dart`, `signInWithPassword`), and
`DbSessionTokenStore` keeps the returned tokens in the database for every
following command, so one cleartext exchange compromises all later ones.
**Impact:** Whoever watches the network (a public Wi-Fi, a LAN, a proxy) can
reuse the auth key to sign in a device of their own, and the tokens to read the
mailbox and send as the account. Message bodies stay E2EE ciphertext, so this
is credential and metadata exposure, not content — but it is total for the
account, and the documented threat model says it cannot happen.
**Fix sketch:** Move the address rule out of the app into a package the CLI
already uses (`helix_remote_protocol` or `helix_remote_domain`): scheme,
`userInfo`, query and fragment, ASCII/look-alike host, and the debug-only
loopback exception. Apply it in `_server` (and to a saved server on read) and
have the app call the same function. Keep a documented `--allow-http` opt-out
for a LAN personal server if that is the product decision, but make it explicit
and loud on stderr.
**Test that proves it:** `cli_v2_test.dart` — `--server http://example.org
status` exits 2 with a message naming the scheme, `https://example.org`
passes, and (if the opt-out stays) `http://127.0.0.1` is refused without it.
The app's existing "https is fine, cleartext is not" test keeps proving the
other side.
**Overlap:** S13-1 below is the structural form. No other finding in this audit
covers the CLI address rule; `17a` records that the admin checks its address
before sending, so the CLI is the gap.

### AUD-13-2 `helix_v2 send` prints "sent" for a message the outbox has already marked failed

**Severity:** P2  **Confidence:** confirmed
**Where:**
[cli_app.dart:533-541](file:///J:/Projects/helix/helix_remote/packages/helix_remote_cli/lib/src/v2/cli_app.dart#L533-L541)
(the copy),
[values.dart:23-50](file:///J:/Projects/helix/helix_remote/packages/helix_remote_db/lib/src/values.dart#L23-L50)
(`MessageStatus` and `failed`),
[outbox.dart:366-372](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/messaging/outbox.dart#L366-L372)
(give up when everyone blocked),
[outbox.dart:468-477](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/messaging/outbox.dart#L468-L477)
(`_giveUp` writes `MessageStatus.failed`).
**What:** `_send` awaits `drainOutbox()`, reads the row's status and prints
`status == MessageStatus.pending ? 'queued (…)' : 'sent'`. `failed` is a real
terminal status and is written by the very drain it just awaited: when every
recipient has blocked the sender, `_process` calls `_giveUp(op, 'blocked')`
instead of `_succeeded`, and `_giveUp` advances the row to `MessageStatus.failed`
(`advance` accepts `failed` over `pending`, values.dart:45-50). The op also
becomes `failed` on `expired` (older than `outboxMaxAge`), `bad_payload` and
`unknown_op`. Every one of those paths prints "sent".
**Trigger:** Bob runs `helix_v2 block +8801…` (or blocks Alice in the app), then
Alice runs `helix_v2 send +8801… "are you there"`. Exit code 0, text "sent".
The same happens to any script that sends while a stale op is being drained.
**Evidence:** the send path enqueues, drains inside `_send` (line 533) and
again in `_open` (line 230), and then classifies by exclusion
(`status == pending ? … : 'sent'`). The JSON branch prints the status
verbatim, so `--json` is correct and the human line is not; the CLI test only
ever asserts `anyOf('sent', 'delivered')` against a healthy peer
(cli_test.dart:114), so nothing holds the failure text.
**Impact:** An operator or a script that reads the human output believes a
message was delivered when the engine has decided it never will be. For
"blocked" this is the normal, expected outcome of sending to someone who
blocked you, and it is exactly the case the CLI gets wrong. (Scripts that parse
JSON see the truth, which is why this is P2 and not P1.)
**Fix sketch:** Map the status once, with all six values: `failed` → "not sent
(…reason)" using `SendFailedEvent`'s `errorCode` or the op's `errorCode`,
`pending` → queued, `sent`/`delivered`/`read`/`viewed` → sent/delivered. Do not
use `pending` as the only negative case.
**Test that proves it:** in `server/test/client/engine/cli_test.dart`: Bob
blocks Alice by number, Alice runs `send` → exit 0, stdout does not contain
"sent" and `--json` reports `"status":"failed"`.
**Overlap:** none known; the app draws this from the row and the outbox's
`SendFailedEvent` is already wired there, so it is CLI-only.

### AUD-13-3 `devices revoke` matches a prefix against a device list that a fire-and-forget refresh may not have filled

**Severity:** P3  **Confidence:** confirmed
**Where:**
[cli_app.dart:738-755](file:///J:/Projects/helix/helix_remote/packages/helix_remote_cli/lib/src/v2/cli_app.dart#L738-L755)
(`revoke` reads `engine.devices.list()`),
[cli_app.dart:713-714](file:///J:/Projects/helix/helix_remote/packages/helix_remote_cli/lib/src/v2/cli_app.dart#L713-L714)
(`list` refreshes first),
[engine.dart:341-357](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/engine.dart#L341-L357)
(`_activate` starts `_afterSignIn` with `unawaited`),
[device_service.dart:25-51](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/account/device_service.dart#L25-L51)
(`list` reads the table, `refresh` fetches it).
**What:** `devices list` calls `await engine.devices.refresh()`; `devices
revoke` calls `await engine.devices.list()`, which only reads the local
`self_devices` table. That table is filled by `_afterSignIn()`, which
`Engine.start` → `_activate` starts with `unawaited`, so at the moment the
command reads it the refresh is an HTTP round trip that has not necessarily
finished. On a home that has never listed (immediately after `link`, whose
pre-link start-time refresh has no session yet and throws) the table is empty
and `revoke` answers "no such device" for a device that exists.
**Trigger:** Link a second device; in the new home, without running `devices`
first, run `devices revoke <first 12 chars>` — or, on any home, revoke a device
that was linked elsewhere since the last `devices` run. Offline, the refresh
fails and only the stored (possibly stale) list is consulted.
**Evidence:** `_devices`'s two branches use different sources (714 vs 743);
`otherDeviceIds()` documents the same "fetches it when this device has never
done so" idea (device_service.dart:54-58) but `list()` does not; the transfer
sender already guards this by refreshing and falling back
(device_transfer.dart:100-105). The CLI end-to-end test only ever revokes after
`devices` in the same run (cli_test.dart:195-209), so the race is invisible.
**Impact:** The one command a person runs after losing a phone reports "no such
device" and exits 1; the workaround (run `devices` first) is not hinted
anywhere. A revoked device stays in the account until they discover it.
**Fix sketch:** In `revoke`, `await engine.devices.refresh()` in a try (fall
back to `list()` when offline), then match the prefix; or give
`DeviceService.list({bool fresh = false})` and use `fresh: true` here and in
`devices list`.
**Test that proves it:** link a second device, start a fresh CLI home with no
prior `devices` call and run `devices revoke <prefix>` — it must succeed (and a
test that returns the stored list when the server is unreachable must still
work).
**Overlap:** S13-2 below generalises the fix; AUD-12r's transfer sender is the
other consumer of the same staleness.

### AUD-13-4 The first Ctrl-C is swallowed, so interactive `chat` cannot be interrupted

**Severity:** P3  **Confidence:** likely
**Where:**
[cli_io.dart:24-49](file:///J:/Projects/helix/helix_remote/packages/helix_remote_cli/lib/src/v2/cli_io.dart#L24-L49)
(`ProcessSignal.sigint.watch().first`),
[cli_app.dart:544-568](file:///J:/Projects/helix/helix_remote/packages/helix_remote_cli/lib/src/v2/cli_app.dart#L544-L568)
(`_chat` waits only on `readLine`).
**What:** `ConsoleIo` registers a SIGINT listener once and completes
`_interrupted` on the first signal; the `.first` cancels the subscription at
that point. Only `_watch` waits on `io.interrupted` (cli_app.dart:698-702).
`_chat` — and every prompt in `register`, `login` and `link` — waits on
`readLine` alone, so under Dart's signal semantics (a watched signal does not
run the default terminate) the first Ctrl-C silently does nothing. The second
press either terminates the process through the restored default (skipping
`engine.close()`) or does nothing on a platform that keeps a listener alive;
either way the first press is lost. `watch` does exit cleanly, which is why the
asymmetry is easy to miss.
**Trigger:** `helix_v2 chat "Bobby"`, then Ctrl-C. Nothing happens; the user
presses it again.
**Evidence:** `ProcessSignal.sigint.watch().first.then(...)` is constructed in
the `ConsoleIo` constructor and never re-armed; `_chat`'s loop has no
`interrupted` branch; `BufferIo.interrupted` never completes
(cli_io.dart:125), so no test can see the difference. `/quit` is the only
documented exit (usage text, cli_app.dart:66-68).
**Impact:** The reflex every terminal user has is inert in the one mode that
owns the terminal. A second press aborts without closing the database, so the
skip is not harmless in principle (SQLCipher recovers, but a hot WAL is left
and the engine's graceful path — drain, socket close — never runs).
**Fix sketch:** Race `io.readLine` against `io.interrupted` in `_chat` (as
`_watch` already does); let `_open`'s `finally` close the engine. Keep the
signal subscription alive (complete one completer and re-arm if the command
should keep running), or restore the default handler after the command ends.
**Test that proves it:** a `BufferIo` whose `interrupted` completes while a
read is pending makes `chat` return 0 and the engine close (assert the DB is
closed / `close()` ran).
**Overlap:** none; the app owns its own lifecycle and does not use this class.

### AUD-13-5 `react` only reaches the newest 200 messages, and the `all` flag it would need is declared but unused

**Severity:** P3  **Confidence:** confirmed
**Where:**
[cli_app.dart:620-640](file:///J:/Projects/helix/helix_remote/packages/helix_remote_cli/lib/src/v2/cli_app.dart#L620-L640)
(`pageOlder(…, limit: 200)` then a prefix match over that page),
[cli_args.dart:16-23](file:///J:/Projects/helix/helix_remote/packages/helix_remote_cli/lib/src/v2/cli_args.dart#L16-L23)
(`all` is a declared boolean flag),
[cli_app.dart:585](file:///J:/Projects/helix/helix_remote/packages/helix_remote_cli/lib/src/v2/cli_app.dart#L585)
(`read` has `--limit`).
**What:** `_react` reads one page of 200 and looks for a single id prefix in it;
a message older than that page yields "no such message" even though `read
--limit N` prints it. There is no `--limit` or `--all` for `react`, and the
`all` flag that exists in `CliArgs.booleanFlags` is read by nothing in the
package (the other flags are all used: `json`, `replace`, `show`, `lost`,
`help`).
**Trigger:** a chat with more than 200 messages; `read --limit 500` shows the
id, `react PEER <id-prefix> 👍` says "no such message". Also two different
messages with the same 4-character prefix are reported as "ambiguous" only
within the page, so the answer changes as the chat grows.
**Evidence:** the page size is a literal (626-629); the lookup is a prefix over
`page.messages` (630-632); `read`'s limit is an option (584-585). The usage
text advertises `react PEER MESSAGE_ID EMOJI` with no limit (cli_app.dart:70).
**Impact:** A documented command fails on ordinary long chats, with a message
("no such message") that blames the wrong thing; the user cannot tell whether
the id is wrong or merely old.
**Fix sketch:** accept `--limit`/`--all` and page backwards until a unique match
or the start of the chat, or add a DAO lookup by `messageId` prefix (the engine
already has `chats.message(rowid)`; an id-prefix query is a one-liner in the
messages DAO and is what `read`'s printed ids are for).
**Test that proves it:** seed 201 messages, react to the oldest by id prefix —
it must succeed.
**Overlap:** none; the same 200-page pattern in `read` is bounded by its own
`--limit` and documented.

### AUD-13-6 `db.key` is created with the default file mode (`0644` under a `022` umask)

**Severity:** P3  **Confidence:** confirmed
**Where:**
[cli_home.dart:57-80](file:///J:/Projects/helix/helix_remote/packages/helix_remote_cli/lib/src/v2/cli_home.dart#L57-L80)
(the key and its file),
[cli_home.dart:69-72](file:///J:/Projects/helix/helix_remote/packages/helix_remote_cli/lib/src/v2/cli_home.dart#L69-L72)
(`writeAsStringSync`).
**What:** On first use the CLI writes the 64 hex characters of the database key
to `db.key` with `File.writeAsStringSync`, which creates the file with the
process umask — `0666 & ~022 = 0644` on a typical Unix account, i.e. readable
by every local user, while the encrypted `helix.db` next to it is only as safe
as that key. The class doc already says an env-var key from a password manager
is the right setup "for anything but a test machine", but the file is what the
CLI creates by default, on any platform, on first use. On Windows the file
inherits the profile directory's ACL, which is user-only, so the exposure is
POSIX (Linux/macOS, CI runners, shared build hosts).
**Trigger:** any first command that creates the account on a multi-user POSIX
machine, followed by another local user reading `~/.helix_cli_v2/db.key`.
**Evidence:** `writeAsStringSync` has no mode argument; Dart exposes no
`chmod`, so the fix is an explicit `Process.run('chmod', ['600', …])` after
creation (or `File.open(mode: writeOnly)` with a restrictive open, which Dart
does not give either). `test/v2/cli_v2_test.dart:66` checks only the length of
the contents, never the mode.
**Impact:** Full compromise of the local history for any other account on the
machine — the encryption is intact, the key is simply world-readable.
**Fix sketch:** create `db.key` with mode `0600` (POSIX) — write via a temp file
in the same directory, `chmod 600`, then rename into place; on Windows rely on
the profile ACL and say so in the doc comment. Optionally refuse to *read* a
`db.key` whose mode is looser than `0600` and print the one-line fix.
**Test that proves it:** a POSIX-only test (skipped on Windows) asserting
`FileStat.mode & 0x1FF == 0x180` after `key(create: true)`.
**Overlap:** none; the app's key lives in secure storage, not a file.

### AUD-13-7 The CLI end-to-end test's "no unread" assertion can never fail

**Severity:** P3  **Confidence:** confirmed
**Where:**
[cli_test.dart:157](file:///J:/Projects/helix/helix_remote/server/test/client/engine/cli_test.dart#L157)
**What:** `expect(lastJson(chats)['chats'], isNot(contains('unread: 1')))`.
`chats` is a `List<Map<String, Object?>>`; `contains('unread: 1')` is the
Iterable matcher, which tests each *element* for equality with the string
`'unread: 1'`, and a map never equals a string. The matcher is therefore always
false and `isNot(…)` always passes. The claim it was meant to make — that Bob's
`read` marked the chat read, so Alice's `chats` shows `unread: 0` — is asserted
nowhere; the human branch's "(1 unread)" suffix is asserted nowhere either. The
row shape in JSON is `{'unread': <int>, …}` (cli_app.dart:502-510).
**Trigger:** delete `await engine.chats.markRead(id)` (cli_app.dart:617) and the
test stays green.
**Evidence:** the neighboring assertions in the same test do read real keys
(`name`, `text`, `status`), so this one is an outlier; the intended value is
already in the map under `unread`.
**Impact:** A regression in `read`'s mark-read — the behavior the app's unread
badges and the server's manifest depend on — passes CI.
**Fix sketch:** `expect((lastJson(chats)['chats'] as List).single['unread'], 0)`
on Alice's side, and optionally assert the plain-text branch omits "(1 unread)".
**Test that proves it:** the corrected assertion fails when `markRead` is
removed.
**Overlap:** none; a test-quality fix, no code change.

## Verified safe

- **Nothing secret is printed.** `describeError` never prints a response body,
  a token or an unexpected exception's text (cli_app.dart:110-139), and the
  test pins `password_locked (locked)`, `unexpected StateError` and a
  no-echo `DbEncryptionException` (cli_v2_test.dart:189-228); the end-to-end
  test collects stdout, stderr and prompts from every run and asserts no full
  phone number, password, SMS code or `db.key` appears (cli_test.dart:211-227),
  and that masked numbers do (`+880`).
- **A malformed key is refused without echoing it** (cli_home.dart:73-83), and
  a read-only command creates neither `helix.db` nor `db.key`
  (cli_v2_test.dart:146-159).
- **The engine, API client and database are closed in a `finally`**, so a
  command that throws still closes the socket and the SQLCipher handle
  (cli_app.dart:221-235).
- **Signing in on a code is confirmed against the account it names.** `link`
  prints the account, the `~name` and the identity fingerprint and requires a
  `y` before `_addDevice` runs (cli_app.dart:370-382); the link code itself is
  shown deliberately and is documented as a public one-time key (cli_app.dart:
  comments at the `link` output).
- **Argument handling is total:** flags take no value, options may appear
  anywhere, `-h` works, a missing value is a usage error with exit 2, and an
  unknown command is reported by name (cli_args.dart:21-49;
  cli_v2_test.dart:29-54, 124-144).
- **The harness runs the real stack.** `EngineWorld` builds a real `HelixApi`
  over the real REST and WebSocket clients against an in-process server on a
  real Postgres schema (support.dart:56-83); no fakes stand in for the
  transport, and every registration goes through the real SMS challenge
  (support.dart:86-106).
- **One schema per test, dropped afterwards**, so client tests are
  parallel-safe and cannot see each other's rows (test_platform.dart:15-19,
  48-94); the URL is never printed, and a missing database skips unless
  `HELIX_REQUIRE_TEST_DATABASE=1` (test_database.dart:17-45).
- **`HELIX_DEV_MODE` changes only config validation** (a cluster may use local
  blobs; a tiny storage budget is allowed) — request handling is the
  production path (server_config.dart:209, 281-334). It does not, for example,
  disable rate limits.
- **`settle` rethrows after its deadline** rather than spinning forever, and
  the message helpers assert on decrypted rows (support.dart:137-170).
- **`--json` is machine-clean:** one JSON object per command on stdout, prompts
  and progress on stderr (cli_app.dart:766-767; `_print`).

## Coverage notes

- **No client test reopens a file-backed database.** `EngineWorld.create`
  hands every user `HelixDb.inMemory` (support.dart:66), and the "headless"
  test stops and starts the engine on that same open handle
  (devices_test.dart:81, 97). The reopen path the app performs at every launch
  (schema migration, key check) is exercised only by the CLI test, across
  processes.
- **`testEngineConfig` sets `maintenanceInterval: 30 minutes`** (support.dart:
  25), so device refresh, block sync, retention and prekey rotation run only in
  the tests that override it; a client test cannot accidentally depend on
  maintenance, but also rarely covers it.
- **The CLI test covers one happy path** (register/login/link/contacts/send/
  read/fetch/chats/devices) and the misuse group; `watch`, `chat`, `react`,
  `block`/`unblock`, `logout`, `--limit`, `--show` without `--json`, and
  `register --replace` have no client-level test.
- **`_Io` answers every prompt titled `code` from the SMS provider**
  (cli_test.dart:269-277), so a prompt regression (asking twice, or for the
  password under that title) would be satisfied silently. The "no secret
  printed" sweep also excludes the `link` run, whose output object is not added
  to `outputs` (cli_test.dart:160-180 vs 213).
- **`flows.secondDevice` mints a password setup whose identity wrap is random
  bytes** (flows.dart:15-20): right for session and API tests, unusable for
  anything that unwraps the AIK. It is used by API, module and federation
  tests, never to recover an identity, so nothing is wrong today — but the name
  invites that use.
- **`_open` evaluates `home.key(create: createKey)` before opening the
  database** (cli_app.dart:202-205), so a `register` that later fails at the
  network still leaves a fresh `db.key` behind; harmless (the database is
  encrypted with it if it was created) but it makes "did a key file exist?"
  a poor signal for scripts.
- **`_watch`'s `--timeout` uses an uncancellable `Future.delayed`**
  (cli_app.dart:698-702); the binary exits via `exit()` so it does not hang, but
  an embedder using `runHelixCli` keeps a timer alive for the full timeout.

## Structural proposals

### S13-1 One server-address rule for every client, in a package they share

`ServerPolicy` is the right rule in the wrong place: it sits under
`app/lib/core/engine/`, so the CLI (plain Dart, no Flutter, no app dependency)
cannot apply it, and today it does not. Move `ServerUrlProblem`/`check` into
`helix_remote_protocol` (or `helix_remote_domain`, which already holds shared
value types) and have the app, the CLI and the admin all call it; `_server`
keeps only the precedence (`--server`, `HELIX_SERVER`, `config.json`). That
closes AUD-13-1 by construction and makes the crypto doc's "HTTPS enforcement:
closed" true of every client the repo ships, not just the app. It also gives
the CLI one place to add the debug/LAN exception rather than a scheme test
sprinkled through commands.

### S13-2 `Engine.start` should own "the device list is current"

Four call sites decide independently: `_afterSignIn` refreshes unawaited
(engine.dart:352), `device_transfer.send` refreshes and ignores failure
(device_transfer.dart:100-105), the outbox sender refreshes on a stale list
(sender.dart:259), and `DeviceService.list` reads whatever is stored
(device_service.dart:25). The next reader of the list inherits the race
(AUD-13-3). Give the service one entry point — `list({bool fresh = false})` or
`ensureFresh({Duration maxAge})` — and make "I need this to be right" a call,
with the offline fallback documented once. Commands then cannot pick the
unrefreshed variant by accident.

### S13-3 The client harness should restart across a *reopen*

`EngineWorld.stop()`/`start()` keeps the same in-memory `HelixDb`, so the one
operation the app performs at every launch — reopening an encrypted file and
migrating it — has no server-side client test. Add `EngineWorld.restart(user)`
that closes the engine and database and reopens the same file (a temp file in
`setUp` instead of `inMemory`), and run the existing "coming back online" and
headless-catch-up tests on it. That is where a schema-step bug or a
key-check change would show up before a release, and it is cheap: the helpers
already tear a user down and rebuild it (support.dart:42-47, 125-134).
