# ADR 014: Shared-Package Eligibility Rules

Status: accepted  
Date: 2026-06-19  

> Status note (2026-09): no `packages/shared/` directory was ever created. The repository is now two independent workspaces (`helix_local/`, `helix_remote/`) that share no packages; these rules would apply only if a shared package is proposed in future.

## Context
Sharing code between Local and Remote apps too loosely will re-introduce tight coupling and cause bugs where Local changes break Remote or vice versa.

## Decision
Code qualifies for `packages/shared/` only if it satisfies all:
- Zero Local retention assumptions (e.g. RAM-only settings).
- Zero Remote synchronization or API endpoints.
- Zero local-network (mDNS, UDP, LAN WebRTC) dependencies.
- Zero secure-storage key names or database file paths.
- No destructively scoped methods (such as global wipe).
- Contains automated tests proving independent utility.

Eligible items: pure design theme tokens, layout grids, basic formatting utility functions.

## Consequences
- Clean boundaries between the product directories.
- Package classifications remain clean and easy to maintain.
