# Helix Remote Release Checklist

Status: Phase 20 repository release gate, updated at Phase X for the v2 server. This
checklist is mandatory before a Remote public release. It does not create staging infrastructure, production
credentials, app-store accounts, or signing keys.

## Required Commands

Run these from `helix_remote/` (the scripts use workspace-relative paths).
Per `AGENTS.md`, agents do not run `-BuildArtifacts` or build APKs unless the
user asks.

- Run `.\scripts\verify.ps1`.
- Run `.\scripts\remote_release_gate.ps1`.
- Run `.\scripts\remote_release_gate.ps1 -BuildArtifacts` only after Remote
  signing material exists outside the repository.
- Run `.\scripts\remote_release_gate.ps1 -StagingE2E` only after real staging
  infrastructure and credentials exist.

## Remote Client

- `app/` (and `admin/`) analysis and tests pass.
- Remote app imports only Remote packages and allowed SDK packages.
- Remote application ID is `com.helix.remote`.
- Remote database filename is `helix_remote.db` (SQLCipher, key in the platform
  keystore).
- A release build refuses plain `http://` servers, localhost and emulator hosts
  (`app/lib/core/engine/server_policy.dart`, `ServerPolicy`).
- Remote Android release/main manifest does not enable global cleartext traffic
  or debug network-security config. TLS pinning is off unless the build passes
  `--dart-define=HELIX_GLOBAL_PINS=...` (`docs/operations/V2_SERVER_HANDOFF.md`,
  "TLS pinning"); decide per release whether to pin, and if so use the live
  certificate's current key.
- Android and Windows are the supported release platforms; iOS is explicitly
  excluded by ADR 023 until its platform controls are implemented and reviewed.
- Remote contains no Local LAN discovery, UDP broadcast, mDNS browsing, or Local
  panic-wipe orchestration.
- A second device signs in with phone number + password: release testing must
  verify identity-key unwrap, prekey publication, history-backup restore, the
  "new sign-in" alert on the other devices, and runtime startup. QR linking
  from a trusted device, device-to-device transfer and the recovery-backup
  restore must still work. Real-phone checks the headless suites cannot make
  are listed in `app/MODULE.md` (camera and microphone prompts, voice notes,
  video playback, the lock-screen incoming-call screen, audio routing, app lock
  after the app was swiped away).
- Sign-out paths: revoke one device, revoke all others, and an SMS-OTP sign-in
  on Helix Global signing the other devices out.

## Remote Server

- `server/` tests pass against PostgreSQL 17
  (`cd server; HELIX_REQUIRE_TEST_DATABASE=1 dart test --concurrency=3`).
- The wire contract tests pass: route catalog parity and documentation coverage
  and the golden fixtures (`packages/helix_remote_protocol`), and the api client
  parity test (`packages/helix_remote_api`).
- `docs/operations/V2_SERVER_HANDOFF.md` is current: the environment table was
  re-checked against the code and `server/.env.example` is complete.
- Health, readiness, account export, account deletion, and admin metrics gates
  are covered by tests.
- No plaintext messages, private media bytes, tokens, keys, backup secrets, or
  recovery phrases are logged or sent in push payloads.

## Signing and Artifacts

- Android signing uses only `helix_remote.keystore` and `HELIX_REMOTE_*`
  environment variables.
- Debug signing is forbidden for Remote release builds.
- Remote signing material must never reuse `HELIX_LOCAL_*` values.
- Windows signing uses a Remote-specific certificate identity outside the repo.
- Record release commit hash and artifact checksums.

## Staging and Production

- Staging is blocked until real infrastructure and credentials exist.
- Production deployment is blocked until staging E2E, rollback rehearsal,
  monitoring, backups, and status-page communication paths are complete.
- Production secrets must come from a vault or deployment secret manager, not
  committed files.
- Independent penetration-test and implementation-level cryptographic-review
  evidence must satisfy `docs/security/EXTERNAL_SECURITY_REVIEW_GATE.md`.

## Release Notes

- Use `docs/release/REMOTE_RELEASE_NOTES_TEMPLATE.md`.
- Call out known blockers and do not make strong claims about
  SQLCipher-capable database-at-rest encryption, independent crypto review,
  forward secrecy of the (implemented but unreviewed) DH ratchet, or staging
  completion unless the evidence exists.
