# Package Classification Spec

All pre-existing monorepo packages are classified as **Local-specific** by default. They will be moved to `packages/local/` in Phase 4.

| Package Name | Current Path | Target Category | Shared-Eligible |
| :--- | :--- | :--- | :--- |
| `helix_domain` | `packages/helix_domain` | Local Domain | No (contains Local models) |
| `helix_protocol` | `packages/helix_protocol` | Local Protocol | No |
| `helix_crypto` | `packages/helix_crypto` | Local Crypto | No |
| `helix_transport` | `packages/helix_transport` | Local Transport | No |
| `helix_storage` | `packages/helix_storage` | Local Storage | No (retention constraints) |
| `helix_platform` | `packages/helix_platform` | Local Platform | No |
| `helix_calls` | `packages/helix_calls` | Local Calls | No |
| `helix_messaging` | `packages/helix_messaging` | Local Messaging | No |
| `helix_transfer` | `packages/helix_transfer` | Local Transfer | No |
| `helix_groups` | `packages/helix_groups` | Local Groups | No |
| `helix_discovery` | `packages/helix_discovery` | Local Discovery | No |

## Extraction Target
No shared packages exist at the baseline. If common UI widgets, themes, or non-functional utility models are decoupled in subsequent phases, they will be placed in `packages/shared/helix_ui_kit` or `packages/shared/helix_foundation` under the rules defined in ADR 014.
