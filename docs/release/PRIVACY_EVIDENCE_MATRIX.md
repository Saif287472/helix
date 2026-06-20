# Privacy Evidence Matrix

| Concern | Evidence | Status |
|---|---|---|
| Privacy inventory | `docs/product/remote/METADATA_INVENTORY.md`, `docs/product/PRIVACY_CLAIM_MATRIX.md` | Documented |
| Retention | `docs/product/remote/RETENTION_AND_DELETION.md`, Phase 10 retention tests | Documented and component-tested |
| Deletion | `privacy_compliance_test.dart`, account deletion endpoint | Backend-tested; app local cleanup still tracked as disconnected in closure docs |
| Export | `privacy_compliance_test.dart`, `/api/v1/privacy/export` | Backend-tested; ciphertext-only |
| Backup | backup crypto/storage tests and `multi_device_backup_recovery_test.dart` | Component/backend-tested |
| Telemetry | `apps/helix_remote/lib/app/remote_telemetry.dart` | Local aggregate telemetry only; no ad SDK |
| App-store disclosures | `docs/product/remote/APP_STORE_PRIVACY.md` | Documentation required before submission |
| Data processing | `docs/product/remote/PRIVACY_POLICY.md` | Documentation required before submission |

Release sign-off must confirm that public claims do not exceed executable
evidence and that no plaintext content, private media bytes, tokens, keys,
secret phrases, or full fingerprints appear in logs, telemetry, exports, push
payloads, or release artifacts.
