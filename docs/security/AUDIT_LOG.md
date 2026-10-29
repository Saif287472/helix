# Security audit log

One row per finding from the external static audits, so coverage and fixes stay
visible across reports. The auditor saw only dumped source files, never a
running system, so every finding is triaged against the code first.

Verdicts: **Fixed** (confirmed, fixed, regression test), **Known** (accepted in
the docs), **Not a bug**, **Decision** (needs a product decision). Tests are in
`helix_remote/server/test/modules/identity_audit_test.dart` unless noted.

## Report 1 - Identity and kernel (server)

| Id | Title | Verdict | Commit | Test |
|---|---|---|---|---|
| F-1 | Password change does not end other sessions | Fixed (decided: end the other devices' sessions, caller stays in) | `563caf0` | `F-1 a password change ends the other devices, not the caller`; `F-1 a refresh racing a password change leaves no live session` |
| F-2 | Server verifier is HMAC, not Argon2id | Known - by design (`identity/MODULE.md`, THREAT_MODEL T-7: the client runs Argon2id, the server HMACs the derived key) | - | - |
| F-3 | Account-status / password-params reveal account existence | Known - ADR-032, THREAT_MODEL T-12, `REST_V2.md` | - | - |
| F-4 | One verification token authorizes concurrent operations | Fixed (atomic `take` before commit; put back if the transaction fails) | `563caf0` | `F-4 one verification token replaces an identity once`; `F-4 one verification token changes a password once`; `F-4 a failed use leaves the token for a retry` |
| F-5 | Decoy password lockout loses attempts under contention | Fixed (64 jittered compare-and-set tries, then fail closed with 429) | `563caf0` | `F-5 every decoy sign-in failure is counted under contention` |
| F-6 | Refresh-token purge destroys reuse-detection evidence | Fixed (spent tokens kept 365 days past expiry, in both purges) | `563caf0` | `F-6 a spent refresh token is still caught after it expired`; `F-6 spent tokens are still purged once the window has passed` |
| F-7 | Account deletion leaves verification state usable | Not a bug - a challenge or token proves control of a number, not of the account, and lives minutes | - | - |

### Residual notes

- F-1: a password sign-in token (`st_`, 5 minutes) minted with the old password
  before the change can still add a device afterwards. It needs the old password
  and expires quickly; not changed.
- F-6: the operator's purge no longer removes spent tokens early (it still
  removes unspent expired or revoked ones after a day).
