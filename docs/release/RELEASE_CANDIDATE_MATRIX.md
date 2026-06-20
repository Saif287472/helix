# Release Candidate Matrix

| Area | Local | Remote | Evidence |
|---|---|---|---|
| Android release build | Blocked until signing material exists | Blocked until signing material exists | `scripts/*_release_gate.ps1 -BuildArtifacts -Android` |
| Windows release build | Blocked until signing material exists | Blocked until signing material exists | `scripts/*_release_gate.ps1 -BuildArtifacts -Windows` |
| Signing isolation | `HELIX_LOCAL_*`, `helix_local.keystore` | `HELIX_REMOTE_*`, `helix_remote.keystore` | ADR 016 and Gradle signing guards |
| Co-installation | Product-scoped IDs and storage prefixes | Product-scoped IDs and storage prefixes | Phase 20 governance tests |
| Upgrade | Migration tests and rollback notes required | Migration tests and rollback notes required | storage/backend test suites |
| Uninstall/reinstall | Manual device matrix before public release | Manual device matrix before public release | release checklist sign-off |
| Permissions | LAN, notification, camera/mic only where needed | internet, notification, camera/mic only where needed | platform manifest review |
| Deep links | Product-scoped schemes only | Product-scoped schemes only | release checklist sign-off |
| Notifications | Local notification IDs scoped to Local | Remote push/notification IDs scoped to Remote | boundary and release checks |
| Clean machine | Fresh Windows/Android install test | Fresh Windows/Android install test | release candidate evidence packet |

No release candidate may proceed with a Critical/High open defect in auth,
crypto, storage, sync, wipe, deletion, or authorization.
