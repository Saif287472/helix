# ADR 002: Two App Shells in One Monorepo

Status: accepted  
Date: 2026-06-19  

## Context
Helix is evolving to target two distinct products: `Helix Local` (LAN-only, ephemeral) and `Helix Remote` (cross-network, persistent). Both products share core source code primitives but must be built, compiled, and deployed as entirely independent applications.

## Decision
We will build the repository as a monorepo workspace containing two distinct Flutter application shells:
1. `apps/helix_local`
2. `apps/helix_remote`

Each application shell owns its own `pubspec.yaml`, `lib/main.dart`, and platform folders (`android/`, `windows/`). They will share package directories located in the `packages/` folder.

## Consequences
- A single workspace checkout will compile both apps.
- Product dependencies are separated at the `pubspec` level.
- Platform wrappers (APKs, executables) are entirely separate.
