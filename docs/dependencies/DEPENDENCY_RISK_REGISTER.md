# Dependency Risk Register

| Package | Resolved version | Risk | Owner | Remediation |
|---|---:|---|---|---|
| `sqlite3_flutter_libs` | `0.6.0+eol` | EOL marker in resolved package version. Remote storage no longer depends on it after P2-01; Local storage still resolves it and must be reviewed separately. | storage-team | Keep visible until Local storage removes the obsolete shim or records a product-specific exception. |
| `file_picker` | `12.0.0-beta.7` | Prerelease transitive dependency resolved by Flutter plugins. It is not directly declared by Helix but must stay visible during dependency reviews. | platform-team | Re-resolve during quarterly dependency review and prefer stable transitive resolution when available. |
