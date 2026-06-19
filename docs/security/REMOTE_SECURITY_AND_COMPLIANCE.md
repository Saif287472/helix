# Helix Remote Security and Compliance Gates

Status: Phase 18 implementation evidence  
Date: 2026-06-19

## Incident Response

1. Triage the report and preserve relevant redacted audit records.
2. Classify severity: critical auth/key/data exposure, high abuse or deletion
   failure, medium availability/privacy regression, low documentation issue.
3. Disable affected credentials or admin access where applicable.
4. Prepare a fix, test with the full verification pipeline, and document the
   impacted commit range.
5. Notify affected users with known facts only. Do not speculate about plaintext
   exposure when only ciphertext/metadata evidence exists.

## Vulnerability Disclosure

- Reports should include affected commit/version, reproduction steps, expected
  impact, and whether sensitive data was accessed.
- Do not request real user secrets, private keys, production tokens, or
  plaintext message samples.
- Acknowledge receipt before public disclosure when real contact infrastructure
  exists.

## Dependency and CVE Response

- Run the normal verification pipeline for every dependency change.
- Run dependency advisory checks in CI or with `HELIX_DEPENDENCY_ADVISORY=1`.
- Critical CVEs in auth, crypto, storage, network, or parsing dependencies must
  block release until patched, removed, or explicitly risk-accepted.
- New dependencies require maintenance, license, privacy, and security review.

## Required Security Reviews

- Penetration test: BLOCKED until an actual scoped test is performed.
- Independent cryptographic review: BLOCKED until an external reviewer evaluates
  the exact implementation/version.
- Mobile application security review: BLOCKED until a release build is reviewed
  for Android and Windows targets.
- Backend security review: BLOCKED until the deployed backend, configuration,
  auth, admin, logging, and storage paths are reviewed.
- Secrets and access review: BLOCKED until production credentials and access
  roles exist.

## Production Access and Least Privilege

- Production admin accounts must be explicitly allow-listed.
- Admin actions must be logged with redacted audit metadata.
- Production access must use named accounts, MFA where available, and no shared
  credentials.
- Access should be granted only for active operational need and reviewed before
  every release.

## Marketing Claim Review

Before any public release, every privacy/security claim must be checked against:

- `docs/product/PRIVACY_CLAIM_MATRIX.md`
- `docs/product/remote/PRIVACY_POLICY.md`
- `docs/product/remote/METADATA_INVENTORY.md`
- `docs/product/remote/RETENTION_AND_DELETION.md`
- Current automated test results
- The unresolved blocker list in the master plan
