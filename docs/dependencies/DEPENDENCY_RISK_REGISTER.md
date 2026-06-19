# Dependency Risk Register

| Package | Resolved version | Risk | Owner | Remediation |
|---|---:|---|---|---|
| `sqlite3_flutter_libs` | `0.6.0+eol` | EOL marker in resolved package version. Current Local and Remote SQLite tests depend on it; Phase 2 must replace plaintext Remote persistence with a SQLCipher-capable, supported option before release. | storage-team | Track under P0-06/P2-01 and remove from this register when replaced. |
| `file_picker` | `12.0.0-beta.7` | Prerelease transitive dependency resolved by Flutter plugins. It is not directly declared by Helix but must stay visible during dependency reviews. | platform-team | Re-resolve during quarterly dependency review and prefer stable transitive resolution when available. |

