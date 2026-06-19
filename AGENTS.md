# Agent Workflow

This repository is a privacy-focused two-product messenger monorepo.
Treat transport, crypto, identity, trust, storage, and wipe behavior as
security-sensitive across **both** products.

## Repository Layout

```
apps/helix_local/    — Helix Local Flutter app (LAN-only, ephemeral)
apps/helix_remote/   — Helix Remote Flutter app (internet, persistent)
packages/
  local/
    helix_local_domain/    — Local domain contracts and ProductDescriptor
    helix_local_protocol/  — LAN wire protocol
    helix_local_crypto/    — Local crypto primitives
    helix_local_transport/ — Local secure channel
    helix_local_discovery/ — mDNS LAN discovery
    helix_local_storage/   — Local secure storage adapters
    helix_local_platform/  — Local platform integration
    helix_local_groups/    — Session-only LAN lobby
    helix_local_messaging/ — Ephemeral LAN messaging
    helix_local_calls/     — LAN WebRTC call engine
    helix_local_transfer/  — LAN file transfer
  shared/            — EMPTY placeholder (shared primitives, Phase 4+)
  remote/            — EMPTY placeholder (Remote packages, Phase 8+)
tool/                — Architecture boundary checker
scripts/             — verify.ps1 / verify.sh
docs/                — ADRs, product contracts, architecture docs
ownership-blast-radius.yaml — Package ownership and risk levels
```

## Product Boundary Rules (Phase 4)

These rules are mechanically enforced by `tool/check_boundaries.dart` and
`docs/architecture/module_boundaries.json`. Violations must not be suppressed.

### Hard prohibitions

- `apps/helix_local/**` must not import `packages/remote/**`
- `apps/helix_remote/**` must not import `packages/local/**` (once renamed)
- `packages/shared/**` must not import `packages/local/**` or `packages/remote/**`
- No package may import `apps/helix_local/**` or `apps/helix_remote/**`

### Current package classification

All packages under `packages/` are **Local-classified** until explicitly
extracted via the shared-code eligibility checklist in
`docs/adr/014-shared-package-eligibility.md`.

`packages/shared/` and `packages/remote/` are empty boundary placeholders.
Do not add code to them without following the extraction checklist.

### Identifier isolation

| Concern | Local value | Remote value |
|---|---|---|
| Android application ID | `com.helix.local` | `com.helix.remote` |
| Kotlin namespace | `com.helix.local` | `com.helix.remote` |
| Secure storage prefix | `helix_local_v1_` | `helix_remote_v1_` |
| Method channel namespace | `com.helix.local/` | `com.helix.remote/` |
| Android signing env vars | `HELIX_LOCAL_*` | `HELIX_REMOTE_*` |
| Keystore filename | `helix_local.keystore` | `helix_remote.keystore` |

If you add a new identifier (notification channel ID, URL scheme, database
name, tray icon, GUID) it must be product-scoped. Never reuse a Local
identifier in Remote or vice versa.

### ProductDescriptor

All product-specific runtime values are injected via `ProductDescriptor`
(`LocalProductDescriptor` / `RemoteProductDescriptor` in `helix_domain`).
Do not add new hard-coded product strings to package code. Add the value to
the descriptor and inject it through the composition root.

## Required Flow

1. Understand the task and identify affected features.
2. Read the current phase/closure docs in `docs/architecture/`, especially
   `docs/architecture/PHASE_12_20_CLOSURE.md` for Phase 20 work.
3. Read relevant ADRs in `docs/adr/` and workflow docs in `docs/workflows/`.
4. Make a short implementation plan for non-trivial work.
5. Keep changes small and scoped to the requested stage.
6. Run targeted checks while developing.
7. Run the full verification pipeline before completion:

   ```powershell
   .\scripts\verify.ps1
   ```

8. Report changed files, verification results, risks, and unresolved issues.

## Search Rules

- Use targeted symbol search before opening broad directories.
- Do not scan `build/`, `.dart_tool/`, generated files, lockfiles, large assets,
  or unrelated modules.
- Prefer the workflow docs in `docs/workflows/` before reading large UI files.
- Check `ownership-blast-radius.yaml` to understand which packages are
  high-risk before making changes.

## Forbidden Actions

- Never weaken authentication, validation, encryption, certificate checks, or
  trust decisions.
- Never log passwords, tokens, keys, message contents, private media bytes,
  secret sentences, or full fingerprints.
- Never hardcode credentials or environment-specific production URLs.
- Never disable tests, lint rules, boundary checks, secret scans, or CI steps to
  get a passing build.
- Never silently change public protocol, storage, wipe, trust, or group admin
  contracts.
- Never edit generated Flutter files manually.
- Never introduce deprecated or abandoned dependencies without documenting the
  reason and alternatives.
- Never perform broad refactors unrelated to the current stage.
- Never read, print, commit, or modify forbidden files listed in
  `docs/security/FORBIDDEN_FILES.md`.
- Never add a default constructor that silently selects Local or Remote
  infrastructure — inject via ProductDescriptor and composition root.
- Never add a destructive method whose product scope is ambiguous.
- Never move code into `packages/shared/` without passing the shared-code
  eligibility checklist.
- Never start Remote messaging, storage, calls, or group features before
  Phases 4–7 are complete and the Remote closure docs show executable
  evidence.

## Completion Report

Every completion report should include:

- What changed.
- Files created or modified.
- Tests and checks run.
- Any critical/high-risk areas touched.
- Remaining risks or manual checks.
