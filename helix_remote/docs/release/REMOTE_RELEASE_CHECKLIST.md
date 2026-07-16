# Helix Remote Release Checklist

Status: Phase 20 repository release gate. This checklist is mandatory before a
Remote public release. It does not create staging infrastructure, production
credentials, app-store accounts, or signing keys.

## Required Commands

- Run `.\scripts\verify.ps1`.
- Run `.\scripts\remote_release_gate.ps1`.
- Run `.\scripts\remote_release_gate.ps1 -BuildArtifacts` only after Remote
  signing material exists outside the repository.
- Run `.\scripts\remote_release_gate.ps1 -StagingE2E` only after real staging
  infrastructure and credentials exist.

## Remote Client

- `apps/helix_remote` analysis and tests pass.
- Remote app imports only Remote packages and allowed SDK packages.
- Remote application ID is `com.helix.remote`.
- Remote database filename is `helix_remote.db`.
- Remote secure-storage prefix is `helix_remote_v1_`.
- Remote production runtime config rejects HTTP/WS, localhost, emulator hosts,
  and insecure transport flags.
- Remote Android release/main manifest does not enable global cleartext traffic
  or debug network-security config.
- Remote contains no Local LAN discovery, UDP broadcast, mDNS browsing, or Local
  panic-wipe orchestration.
- Fresh-device account restore is link-first: release testing must verify
  trusted device approval, backup decryption, snapshot restore, prekey
  publication, and runtime startup.

## Remote Backend

- `services/helix_remote_backend` unit/integration tests pass.
- OpenAPI and realtime compatibility fixtures pass.
- Health, readiness, privacy export, account deletion, and admin metrics gates
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

## Release Notes

- Use `docs/release/REMOTE_RELEASE_NOTES_TEMPLATE.md`.
- Call out known blockers and do not make strong claims about
  SQLCipher-capable database-at-rest encryption, independent crypto review, full
  DH/skipped-key ratchet support, or staging completion unless the evidence
  exists.
