# Helix Long-Term Governance

Status: Phase 20 governance baseline.

## Review Cadence

- Quarterly architecture review: product boundaries, module ownership, scaling
  triggers, and ADR debt.
- Quarterly dependency review: outdated packages, advisories, abandoned
  dependencies, and SBOM deltas.
- Annual threat-model review: Local LAN assumptions, Remote backend trust,
  metadata minimization, deletion semantics, and external file limits.
- Security-claim review before every major release using
  `docs/product/PRIVACY_CLAIM_MATRIX.md`.

## ADR Rules

An ADR is required before:

- Moving code into `packages/shared/`.
- Reusing Local infrastructure in Remote or Remote infrastructure in Local.
- Changing protocol, crypto, identity, trust, storage, wipe, deletion, or group
  admin contracts.
- Extracting a broker or service from the Remote modular monolith.
- Changing release signing, rollout, rollback, or production access policy.

## Deprecation Policy

- Mark packages, APIs, schemas, and protocols deprecated before removal.
- Provide a compatibility window and migration path.
- Keep historical migration/security decisions with replacement records.
- Never delete evidence for a released security or privacy decision without a
  superseding record.

## Ownership Map

The canonical ownership map is `ownership-blast-radius.yaml`. Every app,
package, service, and tool module must have an owner, classification, and risk
level before release.

## Execution Ledger

`docs/architecture/PHASE_12_20_CLOSURE.md` remains the execution ledger for
remaining and blocked Phase 12+ work. Completion evidence must distinguish
repository controls from external review, signing, staging, and production
deployment evidence.
