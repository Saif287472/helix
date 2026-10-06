# Privacy Evidence Matrix

| Concern | Evidence | Status |
|---|---|---|
| Privacy inventory | `helix_remote/docs/product/METADATA_INVENTORY.md`, `helix_remote/docs/product/PRIVACY_CLAIM_MATRIX.md` | Documented |
| Retention | `helix_remote/docs/product/RETENTION_AND_DELETION.md`, `helix_remote/server/test/modules/` (mailbox expiry, media expiry, purge jobs) | Documented and server-tested |
| Deletion | `helix_remote/server/test/modules/ops_admin_test.dart` (compliance group), `helix_remote/server/test/client/engine/security_test.dart`, `DELETE /v1/account` | Server- and client-tested; the app wipes its local data afterwards |
| Export | `helix_remote/server/test/modules/ops_admin_test.dart` ("export holds every module section and no secrets"), `GET /v1/account/export` | Server-tested; metadata only, no secrets, tokens or ciphertext |
| Backup | `helix_remote/server/test/modules/media_backup_test.dart`, `helix_remote/packages/helix_remote_engine/test/backup/`, `helix_remote/server/test/client/engine/backup_test.dart` | Component- and server-tested |
| Telemetry | `helix_remote/app/lib/core/engine/crash_reporter.dart`, `helix_remote/server/test/modules/ops_admin_test.dart` | Opt-in crash reports (exception type, version, platform); logged redacted, never stored; no ad SDK |
| App-store disclosures | `helix_remote/docs/product/APP_STORE_PRIVACY.md` | Documentation required before submission |
| Data processing | `helix_remote/docs/product/PRIVACY_POLICY.md`; shipped legal text in `helix_remote/docs/legal/privacy_policy.md` | Documentation required before submission |

Release sign-off must confirm that public claims do not exceed executable
evidence and that no plaintext content, private media bytes, tokens, keys,
secret phrases, or full fingerprints appear in logs, telemetry, exports, push
payloads, or release artifacts.
