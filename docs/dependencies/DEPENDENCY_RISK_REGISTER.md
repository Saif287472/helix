# Dependency Risk Register

| Package | Resolved version | Risk | Owner | Remediation |
|---|---:|---|---|---|
| `sqlite3_flutter_libs` | `0.6.0+eol` | EOL marker in resolved package version. Remote storage no longer depends on it after P2-01; Local storage still resolves it and must be reviewed separately. | storage-team | Keep visible until Local storage removes the obsolete shim or records a product-specific exception. |
| `file_picker` | `12.0.0-beta.7` | **Directly declared** by Helix Remote at `helix_remote/app/pubspec.yaml`, as a prerelease *ahead of* the 11.x stable line, so no stability guarantee applies. Recorded as an accepted exception in [ADR-024](../../helix_remote/docs/adr/024-file-picker-prerelease-exception.md). The committed `helix_remote/pubspec.lock` is what pins it; the declared caret range does not. | platform-team | Hold at the locked resolution. Revisit when `file_picker` 12 reaches stable, and retire the exception then. |

## Correcting the record

This register previously described `file_picker` as a transitive dependency pulled in by the Flutter
plugins, which Helix did not itself declare. Both halves of that were wrong — it is, and always was,
a direct dependency of the client — and the error is recorded here rather than quietly overwritten,
because a control document that is confidently wrong costs more than one that is missing: reviewers
trusted it and skipped the check it existed to prompt.

The likely origin is worth knowing, since it will recur. In a pub workspace the root `pubspec.lock`
classifies every package from the *root* package's perspective, so a dependency declared by a member
package appears as `dependency: transitive` in the lockfile. Reading direct-versus-transitive off the
root lockfile is unsound in this repository; read it off the member `pubspec.yaml`.

`tool/check_governance_controls.dart` now asserts this row against the declaring pubspec, so the two
cannot drift apart again silently.
