# Audit finding regression matrix

One row per finding in `docs/operations/ENTERPRISE_READINESS_AUDIT_2026-08-06.md`, naming the test
that reproduces the pre-fix condition and protects the implemented control.

Paths are relative to `helix_remote/`. Every test file named here is checked to exist by
`app/test/audit_findings_regression_test.dart`, so this table cannot quietly come to describe tests
that were renamed or deleted — the §21 failure mode this document would otherwise be prone to.

Rows marked **open** have no fix and therefore no regression test. They are listed so the gap is
visible here rather than only in the audit.

## Critical

| Finding | Regression test evidence |
| --- | --- |
| CRIT-1: reserved admin ID / operator console takeover | `backend/test/phase1_privilege_escalation_test.dart` — reserved IDs rejected including casing, ordinary IDs still register, `/ops/*` refuses a self-registered account, grant/revoke of the capability, startup guard |
| CRIT-2: refresh token accepted as access token | `backend/test/phase1_auth_test.dart` — REST and WebSocket both reject a refresh token as an access credential, and `/accounts/refresh` rejects an access token |

## High

| Finding | Regression test evidence |
| --- | --- |
| HIGH-1: unredacted, persistent, user-shared diagnostic log | `app/test/log_redaction_test.dart` — bearer tokens, phone numbers, and response bodies do not survive the write boundary |
| HIGH-2: screenshots and screen recording expose message content | `app/test/screen_security_test.dart` — acquire/release across nesting and route swaps, plus the Windows runner's `SetWindowDisplayAffinity` handler and its presence in the build |
| HIGH-3: `android:allowBackup` extracts app-private data | `app/test/android_manifest_security_test.dart` — manifest requires `allowBackup=false`, extraction rules, and full-backup content |
| HIGH-4: lockfile not committed, builds not reproducible | CI `flutter pub get --enforce-lockfile` on both Helix Remote jobs in `.github/workflows/ci.yml`, against a pinned Flutter version |
| HIGH-5: 403 overloaded, so every permission denial rotates a refresh token | `app/test/remote_rest_client_auth_refresh_test.dart` and `backend/test/phase1_auth_test.dart` — only 401 triggers a refresh; the server reserves 403 for authorization |

## Medium

| Finding | Regression test evidence |
| --- | --- |
| MED-1: full window re-fetch and re-decrypt per inbound message | `app/test/audit_findings_regression_test.dart` (delta path, no window re-read) and `app/test/phase4_performance_budget_test.dart` (1,000-message burst within the frame budget) |
| MED-2: no design system, localization, or responsive layout in the client | `app/test/phase5_design_tokens_test.dart` (no colour literals outside the UI package), `app/test/phase5_responsive_screenshot_test.dart` (phone/tablet/desktop), `app/test/helix_localizations_test.dart` |
| MED-3: non-constant-time comparison of JWT signature and admin token | `backend/test/constant_time_comparison_test.dart` — comparator correctness on every case `==` would handle, plus both call sites |
| MED-4: no crash reporting or analytics | `app/test/telemetry_reporter_test.dart` (opt-in required, sink required, failures never propagate, payload carries no token or phone number) and `backend/test/telemetry_crash_sink_test.dart` (authenticated, bounded, rate-limited, observable) |
| MED-5: accessibility effectively absent; text scale capped at 1.3× | `app/test/phase7_accessibility_test.dart` — every icon button labelled, guidelines on a real screen in both themes, high-contrast pair, usable at 2×, and no clamp anywhere in the shell |
| MED-6: in-memory rate limiter resets on restart | `backend/test/phase9_production_hardening_test.dart` — `SqliteRateLimitStore` survives a restart |
| MED-7: `file_picker` pinned to a drifting pre-release | `helix_remote/tool/check_governance_controls.dart` — the exception ADR and the declaring pubspec must agree; the declaration is now an exact version, not a caret |
| MED-8: client dependencies materially behind | Deferred deliberately, with reasons per package, in `docs/dependencies/DEPENDENCY_RISK_REGISTER.md`. Each remaining bump is a platform plugin whose failure mode a headless suite cannot see, so no test here would be honest |
| MED-9: dependency risk register factually wrong | `helix_remote/tool/check_governance_controls.dart` — an `absent` control asserts the withdrawn claim stays withdrawn, which a contains-only check cannot see |
| MED-10: release gate script cannot run | `helix_remote/tool/check_governance_controls.dart` — the script must still carry `--obfuscate` |
| MED-11: swallowed exceptions | **Partly open.** The app layer logs rather than swallowing silently; the 26 remaining are `ALTER TABLE … ADD COLUMN` idempotency guards where "already exists" is the expected outcome |
| MED-12: CI has no coverage gate, scanning, or integration tests | `.github/workflows/ci.yml` — coverage ratchet (`scripts/coverage.sh`), CycloneDX SBOM, OSV scan, and both `integration_test` suites |

## Low

| Finding | Regression test evidence |
| --- | --- |
| LOW-1: no release obfuscation, R8, or resource shrinking | `app/test/audit_findings_regression_test.dart` — minify, shrink, and keep rules |
| LOW-2: duplicate private helpers, dead `is_admin` claim | Removed in the Phase 3 architecture split; no dedicated test |
| LOW-3: invite codes travel in URL query strings | `app/test/audit_findings_regression_test.dart` — the code must be a POST body field |
| LOW-4: unused Android foreground-service permissions | `app/test/android_manifest_security_test.dart` — the permissions are tied to the presence of a service element, so neither can appear without the other |
| LOW-5: no iOS support | `docs/adr/023-ios-support-decision.md`, asserted by the governance checker |

## Findings from the remediation plan

| Finding | Evidence |
| --- | --- |
| P1-1 H2: `permessage-deflate` mismatch as a cause of WebSocket `1002` | `backend/test/websocket_compression_negotiation_test.dart` — **eliminated.** Compression is never negotiated in either direction; the tests protect that agreement |
| P1-1 H1: unserialised concurrent writers | `backend/test/websocket_replay_ack_test.dart` — every write goes through one per-connection object, with credit-window backpressure |
| P1-1 root cause | **Open.** Needs step 1 of the diagnostic procedure (bypass nginx on the VPS); see `docs/operations/HELIX_REMEDIATION_PLAN.md` |
| P0-1 TURN not configured | **Open — infrastructure.** `backend/test/turn_rest_credential_test.dart` pins the credential format; deploying coturn is a VPS action |
| P0-3 contact sync above 500 contacts | `backend/test/contacts_match_test.dart` — hash budget, 1,000-hash batches, unchanged-phonebook caching, partial results |
| §23 observability: correlation IDs not propagated | `backend/test/correlation_propagation_test.dart` — zone-scoped propagation into log lines, across await boundaries, and over the S2S hop |

## Running it

Run the listed files directly during incident verification, then `scripts/verify.sh` before release.
