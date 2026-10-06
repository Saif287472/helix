# Package Classification Spec

All pre-existing monorepo packages were classified as **Local-specific**. They now live in the `helix_local/` workspace as `helix_local_*` packages; Helix Remote has its own `helix_remote/packages/helix_remote_*` packages. The two workspaces share no packages.

| Original name | Current package and path | Category | Shared-Eligible |
| :--- | :--- | :--- | :--- |
| `helix_domain` | `helix_local_domain` in `helix_local/packages/helix_local_domain` | Local Domain | No (contains Local models) |
| `helix_protocol` | `helix_local_protocol` in `helix_local/packages/helix_local_protocol` | Local Protocol | No |
| `helix_crypto` | `helix_local_crypto` in `helix_local/packages/helix_local_crypto` | Local Crypto | No |
| `helix_transport` | `helix_local_transport` in `helix_local/packages/helix_local_transport` | Local Transport | No |
| `helix_storage` | `helix_local_storage` in `helix_local/packages/helix_local_storage` | Local Storage | No (retention constraints) |
| `helix_platform` | `helix_local_platform` in `helix_local/packages/helix_local_platform` | Local Platform | No |
| `helix_calls` | `helix_local_calls` in `helix_local/packages/helix_local_calls` | Local Calls | No |
| `helix_messaging` | `helix_local_messaging` in `helix_local/packages/helix_local_messaging` | Local Messaging | No |
| `helix_transfer` | `helix_local_transfer` in `helix_local/packages/helix_local_transfer` | Local Transfer | No |
| `helix_groups` | `helix_local_groups` in `helix_local/packages/helix_local_groups` | Local Groups | No |
| `helix_discovery` | `helix_local_discovery` in `helix_local/packages/helix_local_discovery` | Local Discovery | No |

## Helix Remote packages
`helix_remote/packages/`: `helix_remote_protocol`, `helix_remote_crypto`, `helix_remote_db`, `helix_remote_api`, `helix_remote_engine`, `helix_remote_calls`, `helix_remote_ui`, `helix_remote_domain`, `helix_remote_cli`, plus the test-only `helix_remote_architecture_rules` (workspace list in `helix_remote/pubspec.yaml`). `helix_remote_storage`, `helix_remote_sync` and `helix_remote_groups` were deleted at the Phase X cutover; their roles went to `helix_remote_db` and `helix_remote_engine`.

## Extraction Target
No shared packages exist, and no `packages/shared/` directory was created. A shared package would have to satisfy ADR 014.
