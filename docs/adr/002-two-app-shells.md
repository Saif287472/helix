# ADR 002: Two App Shells in One Monorepo

Status: accepted  
Date: 2026-06-19  

## Context
Helix is evolving to target two distinct products: `Helix Local` (LAN-only, ephemeral) and `Helix Remote` (cross-network, persistent). Both products share core source code primitives but must be built, compiled, and deployed as entirely independent applications.

## Decision
We will build the repository as a monorepo containing two distinct Flutter application shells:
1. `helix_local/app`
2. `helix_remote/app` (plus the `helix_remote/admin` console and the `helix_remote/backend` server)

Each application shell owns its own `pubspec.yaml`, `lib/main.dart`, and platform folders (`android/`, `windows/`).

> Update (2026-09): the original June layout (`apps/helix_local`, `apps/helix_remote`, shared `packages/`) was replaced by **two independent pub workspaces**, `helix_local/` (packages `helix_local/packages/helix_local_*`) and `helix_remote/` (packages `helix_remote/packages/helix_remote_*`). There is no root `pubspec.yaml` and no package is shared between them; see `docs/dependencies/WORKSPACE_LOCKFILE_POLICY.md`.

## Consequences
- One checkout holds both products; each workspace is resolved and built on its own.
- Product dependencies are separated at the `pubspec` level.
- Platform wrappers (APKs, executables) are entirely separate.
