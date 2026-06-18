# Agent Workflow

This repository is a privacy-focused LAN messenger. Treat transport, crypto,
identity, trust, storage, and wipe behavior as security-sensitive.

## Required Flow

1. Understand the task and identify affected features.
2. Read the relevant roadmap, workflow doc, and contracts before editing.
3. Make a short implementation plan for non-trivial work.
4. Keep changes small and scoped to the requested stage.
5. Run targeted checks while developing.
6. Run the full verification pipeline before completion:

   ```powershell
   .\scripts\verify.ps1
   ```

7. Report changed files, verification results, risks, and unresolved issues.

## Search Rules

- Use targeted symbol search before opening broad directories.
- Do not scan `build/`, `.dart_tool/`, generated files, lockfiles, large assets,
  or unrelated modules.
- Prefer the workflow docs in `docs/workflows/` before reading large UI files.

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

## Completion Report

Every completion report should include:

- What changed.
- Files created or modified.
- Tests and checks run.
- Any critical/high-risk areas touched.
- Remaining risks or manual checks.
