# Privacy Evidence Matrix

| Concern | Evidence | Status |
|---|---|---|
| Privacy inventory | `helix_remote/docs/product/METADATA_INVENTORY.md`, `helix_remote/docs/product/PRIVACY_CLAIM_MATRIX.md` | Documented |
| Retention | `helix_remote/docs/product/RETENTION_AND_DELETION.md`, Phase 10 retention tests | Documented and component-tested |
| Deletion | `helix_remote/backend/test/privacy_compliance_test.dart`, `DELETE /api/v1/account/delete` | Backend-tested; the app purges local data afterwards (`purgeAfterAccountDeletion` in `helix_remote/app/lib/app/composition_root/runtime.dart`) |
| Export | `helix_remote/backend/test/privacy_compliance_test.dart`, `GET /api/v1/privacy/export` | Backend-tested; ciphertext-only. Does not yet include `account_passwords` or `history_backups` rows |
| Backup | backup crypto/storage tests and `helix_remote/backend/test/multi_device_backup_recovery_test.dart` | Component/backend-tested |
| Telemetry | `helix_remote/app/lib/app/remote_telemetry.dart` | Local aggregate telemetry only; no ad SDK |
| App-store disclosures | `helix_remote/docs/product/APP_STORE_PRIVACY.md` | Documentation required before submission |
| Data processing | `helix_remote/docs/product/PRIVACY_POLICY.md`; shipped legal text in `helix_remote/docs/legal/privacy_policy.md` | Documentation required before submission |

Release sign-off must confirm that public claims do not exceed executable
evidence and that no plaintext content, private media bytes, tokens, keys,
secret phrases, or full fingerprints appear in logs, telemetry, exports, push
payloads, or release artifacts.
