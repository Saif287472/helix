# Helix Local Release Checklist

## Preflight

- Run `.\scripts\verify.ps1`.
- Run `.\scripts\local_release_gate.ps1`.
- Confirm `kCapForwardSecrecy` is not advertised unless an external review has
  approved the claim.
- Confirm Local and Remote identifiers remain distinct.
- Confirm no files from `docs/security/FORBIDDEN_FILES.md` are read, printed, or
  committed.

## Signing

- Keep `helix_local.keystore` outside git.
- Set `HELIX_LOCAL_STORE_PASSWORD`.
- Set `HELIX_LOCAL_KEY_ALIAS`.
- Set `HELIX_LOCAL_KEY_PASSWORD`.
- Do not reuse any `HELIX_REMOTE_*` signing material.

## Build

- Run `.\scripts\local_release_gate.ps1 -BuildArtifacts`.
- Archive `build/release/helix_local_sbom.json` with the release.
- Record the release commit hash and artifact checksums.

## Manual Platform Checks

- Android foreground service starts and stops cleanly.
- Android microphone/camera permission prompts appear only when needed.
- Windows close-to-tray and restore behavior match the privacy checklist.
- Offline LAN discovery, chat, file transfer, groups, calls, and panic wipe work
  with internet disconnected.
