# Critical and high security regression matrix

Each row names the test that reproduces the pre-fix condition and protects the implemented control. The matrix is reviewed whenever the enterprise-readiness audit changes.

| Audit finding | Regression test evidence |
| --- | --- |
| CRIT-1: reserved admin ID / operator takeover | `backend/test/phase1_privilege_escalation_test.dart` — reserved IDs, privilege grant/revoke, startup guard, and protected routes |
| CRIT-2: refresh token accepted as access token | `backend/test/phase1_auth_test.dart` — REST and WebSocket reject refresh tokens as access credentials |
| HIGH-1: unredacted persistent diagnostic log | `app/test/log_redaction_test.dart` — bearer tokens, identifiers, and response bodies are absent from logs |
| HIGH-2: screenshots and recording expose sensitive screens | `app/test/screen_security_test.dart` — secure screen mount and route transition preserve the protection flag |
| HIGH-3: Android backup extracts private data | `app/test/android_manifest_security_test.dart` — manifest requires `allowBackup=false` and extraction rules |
| HIGH-4: dependency lockfile is not enforced | CI `flutter pub get --enforce-lockfile` in `.github/workflows/ci.yml` |
| HIGH-5: 403 permission denial rotates refresh tokens | `app/test/remote_rest_client_auth_refresh_test.dart` and `backend/test/phase1_auth_test.dart` — only 401 triggers refresh and server reserves 403 for authorization |

Run the listed test files directly during incident verification, then run the complete relevant package suite before release.
