# AI Guardrails

These rules apply to human and AI-assisted changes.

## Non-Negotiable Protections

- Do not weaken authentication, authorization, validation, encryption,
  certificate checks, or fingerprint-based trust.
- Do not log passwords, tokens, private keys, session keys, message content,
  private media bytes, secret sentences, or full peer fingerprints.
- Do not hardcode credentials, signing material, local machine paths, or
  production URLs.
- Do not disable tests, lint rules, boundary checks, secret scans, or CI steps
  to obtain a passing build.
- Do not silently change public protocol frames, storage behavior, wipe
  behavior, group admin rules, or trust rules.
- Do not hard-delete audit-relevant data without an approved requirement.
- Do not edit generated Flutter files manually.
- Do not introduce deprecated or abandoned dependencies without review.
- Do not expose cryptographic material in app models, UI state, logs, or
  diagnostic exports.
- Do not read, print, commit, or modify files listed in
  `docs/security/FORBIDDEN_FILES.md`.

## Required Checks

Run the canonical verification pipeline before reporting completion:

```powershell
.\scripts\verify.ps1
```

For large or critical changes, also run targeted tests first and explicitly
name any manual checks that remain.

## Risk Reporting

Changes touching critical or high-risk areas from
`docs/ai/ownership-blast-radius.yaml` require a risk note. The note must name:

- The behavior changed.
- The verification performed.
- Any remaining manual review needed.
