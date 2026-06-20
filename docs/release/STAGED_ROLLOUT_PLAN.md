# Staged Rollout Plan

## Stages

| Stage | Audience | Halt Criteria |
|---|---|---|
| Internal | Maintainers and test devices | any crash loop, auth failure, storage migration failure, or secret-scan finding |
| Alpha | Limited trusted testers | crash-free sessions below 99%, sync backlog growth, failed backup restore, privacy request failure |
| Beta | Broader testers | ANR or startup regression, p95 message send over SLO, elevated 4xx/5xx, DLQ growth |
| Percentage rollout | 5% -> 25% -> 50% -> 100% | automatic halt when thresholds below are exceeded |

## Feature Flags

Feature flags must default closed for new Remote messaging, attachment, backup,
call, group, and privacy flows until their compatibility windows are proven.
Flags must be product-scoped and must not reuse Local identifiers.

## Compatibility Window

- REST and realtime schemas support the previous released client for at least
  one rolling-upgrade window.
- Database migrations must be expand/migrate/contract and rollback-rehearsed.
- Protocol or storage breaking changes require release notes and an ADR.

## Automatic Halt Thresholds

- Crash-free sessions below 99%.
- Android ANR rate above 0.47%.
- API 5xx rate above 2% over five minutes.
- Outbox DLQ count greater than zero during rollout.
- Readiness probe failing for two consecutive minutes.
- Any Critical/High privacy, auth, crypto, storage, sync, wipe, deletion, or
  authorization defect.
