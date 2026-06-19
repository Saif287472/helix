# Cross-Product Acceptance Checklist

Status: Phase 20 repository and manual release checklist.

## Automated Gates

- Local app cannot import `packages/remote/**`.
- Remote app cannot import `packages/local/**`.
- Shared packages cannot import Local or Remote product packages.
- Secure-storage prefixes differ: `helix_local_v1_` vs `helix_remote_v1_`.
- Database filenames differ: `helix_local.db` vs `helix_remote.db`.
- Android application IDs differ: `com.helix.local` vs `com.helix.remote`.
- Remote source contains no Local LAN discovery, UDP broadcast, mDNS browsing,
  or Local panic-wipe orchestrator.
- Local source contains no Remote backend URL or Remote push/TURN registration.
- Package dependency firewall passes `tool/check_boundaries.dart`.

## Manual Device Gates

These require real Android/Windows artifacts and devices:

- Install both apps together.
- Run both apps simultaneously.
- Verify independent notification channels and Windows identities.
- Verify independent camera/microphone sessions and contention UX.
- Verify Local panic wipe leaves Remote data and sessions intact.
- Verify Remote logout/delete leaves Local data and sessions intact.
- Verify uninstalling either product leaves the other product intact.

Manual gates must be recorded in release notes before public distribution.
