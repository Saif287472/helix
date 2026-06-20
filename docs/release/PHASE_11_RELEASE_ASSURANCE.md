# Phase 11 Release Assurance Evidence

**Status:** Complete for repository-controlled gates, with external reviews and
production infrastructure explicitly blocked until performed by humans.

## P11-01 Risk-Based Test Pyramid

Evidence:

- `docs/quality/RELEASE_TEST_PYRAMID.md`
- `docs/quality/RISK_BASED_COVERAGE.md`
- `tool/risk_coverage_test.dart`
- `scripts/verify.ps1` and `scripts/verify.sh`

The release gate covers unit, state-machine/property, contract, component, real
backend/client E2E, platform integration, accessibility, performance, load, and
security checks.

## P11-02 Fuzzing and Malformed Input

Evidence:

- `tool/fuzz_corpus/manifest.json`
- retained seeds under `tool/fuzz_corpus/seeds/`
- `tool/fuzz_seed_corpus_test.dart`
- scheduled CI job `fuzz-seed-corpus`

Fuzz targets cover Local frames, Local secure-channel framing, Remote REST,
Remote realtime envelopes, encrypted envelopes, malformed migrations, backup
snapshots, and attachment metadata.

## P11-03 SAST, Dependencies, SBOM, Provenance

Evidence:

- `tool/check_secrets.dart`
- `tool/check_release_hardening.dart`
- `tool/dependency_policy_test.dart`
- `docs/security/DEPENDENCY_SECURITY.md`
- `docs/dependencies/WORKSPACE_LOCKFILE_POLICY.md`
- `tool/generate_local_sbom.dart`
- `tool/generate_release_provenance.dart`

Release gates require SAST-like static checks, dependency vulnerability review,
license policy, reproducible SBOM output, signed artifact inputs, artifact checksums,
and provenance records.

## P11-04 Release Candidate Matrix

Evidence:

- `docs/release/RELEASE_CANDIDATE_MATRIX.md`
- `scripts/local_release_gate.ps1`
- `scripts/remote_release_gate.ps1`
- `.github/workflows/ci.yml`

The matrix covers Android and Windows release builds, signing isolation,
co-installation, upgrade, uninstall/reinstall, permissions, deep links,
notifications, and clean-machine tests. Real signed release artifacts remain
blocked until external signing material exists.

## P11-05 Independent Review Gate

Evidence:

- `docs/security/EXTERNAL_SECURITY_REVIEW_GATE.md`
- `docs/security/REMOTE_SECURITY_AND_COMPLIANCE.md`
- `docs/product/PRIVACY_CLAIM_MATRIX.md`

Independent cryptographic review and penetration test are release blockers.
Strong security marketing claims remain blocked until Critical/High findings are
closed or accepted with documented risk acceptance.

## P11-06 Privacy Evidence Matrix

Evidence:

- `docs/release/PRIVACY_EVIDENCE_MATRIX.md`
- `docs/product/PRIVACY_CLAIM_MATRIX.md`
- `services/helix_remote_backend/test/privacy_compliance_test.dart`

The matrix maps privacy inventory, retention, deletion, export, backup,
telemetry, app-store disclosures, and data-processing documentation to
executable behavior or explicit blockers.

## P11-07 Staged Rollout

Evidence:

- `docs/release/STAGED_ROLLOUT_PLAN.md`

The staged rollout plan defines internal, alpha, beta, percentage rollout,
feature flags, schema/protocol compatibility windows, crash/ANR/error
thresholds, and automatic halt criteria.

## P11-08 Rollback Rehearsal

Evidence:

- `docs/release/ROLLBACK_REHEARSAL.md`
- `docs/workflows/RELEASE_ROLLBACK.md`
- `docs/performance/DR_DRILL_RUNBOOK.md`

Rollback rehearsal covers app, API, realtime schema, DB migration, object
storage, and key/config rotation paths with timed evidence requirements.

## P11-09 On-Call Runbooks

Evidence:

- `docs/operations/INCIDENT_ONCALL_RUNBOOKS.md`
- `ownership-blast-radius.yaml`

Runbooks cover auth outage, sync backlog, corrupt migration, key/prekey
incident, privacy request failure, TURN outage, data-loss suspicion, and
security incident ownership.
