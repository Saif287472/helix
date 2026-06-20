# Phase 11 Release Test Pyramid

Phase 11 release assurance uses a risk-based pyramid instead of a single global
coverage percentage. Each high-risk area must have at least one executable gate
at the lowest practical layer and one release-level check before public
distribution.

| Layer | Scope | Required Evidence |
|---|---|---|
| Unit | Pure parsing, validation, crypto wrappers, state helpers | `flutter test` / `dart test` package suites |
| State-machine and property | Local workflow transitions, sync ordering, retry/backoff, wipe phases | deterministic transition tests and fuzz seed corpora |
| Contract | REST/realtime/encrypted envelope serialization, protocol fixtures | compatibility tests and malformed input fixtures |
| Component | Storage, sync, backend modules, attachment/backup/call/group services | package/backend component tests |
| Real backend/client E2E | Remote registration/login/prekey/message/device flows | backend integration and Phase 4 vertical-slice harness |
| Platform integration | Android/Windows builds, signing isolation, notifications, storage prefixes | release gate scripts and build-only verify mode |
| Accessibility | semantics, keyboard, contrast, 200% text scale | Phase 9 accessibility tests |
| Performance and load | pagination, asset budget, load baseline, DR drills | Phase 10 performance tools and runbooks |
| Security | boundaries, secrets, release hardening, dependency policy, external review gates | verify scripts, CI, and security review blockers |

## Risk Map

| Risk Area | Minimum Required Layers |
|---|---|
| Auth, identity, and device trust | unit, contract, backend/client E2E, security |
| Crypto and key lifecycle | unit, malformed/fuzz seed, component, external review |
| Storage, migration, backup, wipe | unit, component, platform, rollback rehearsal |
| Sync/outbox/realtime | state-machine, contract, component, load/reconnect |
| Privacy/deletion/export/telemetry | component, backend/client E2E, privacy evidence matrix |
| Release signing and artifact integrity | platform, SBOM/license, provenance, release checklist |

Coverage artifacts remain under `build/coverage/` and are not committed.
