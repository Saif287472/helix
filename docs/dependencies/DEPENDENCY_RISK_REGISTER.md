# Dependency Risk Register

| Package | Resolved version | Risk | Owner | Remediation |
|---|---:|---|---|---|
| `sqlite3_flutter_libs` | `0.6.0+eol` | EOL marker in resolved package version. Remote storage no longer depends on it after P2-01; Local storage still resolves it and must be reviewed separately. | storage-team | Keep visible until Local storage removes the obsolete shim or records a product-specific exception. |
| `file_picker` | `12.0.0-beta.7` | **Directly declared** by Helix Remote at `helix_remote/app/pubspec.yaml`, as a prerelease *ahead of* the 11.x stable line, so no stability guarantee applies. Recorded as an accepted exception in [ADR-024](../../helix_remote/docs/adr/024-file-picker-prerelease-exception.md). The committed `helix_remote/pubspec.lock` is what pins it; the declared caret range does not. | platform-team | Hold at the locked resolution. Revisit when `file_picker` 12 reaches stable, and retire the exception then. |

## Deferred major upgrades (MED-8)

The audit recorded several client dependencies as materially behind. The minor gaps
(`cryptography_flutter`, `mobile_scanner`, `flutter_webrtc`) have since resolved forward within
their existing caret ranges and no longer appear in `flutter pub outdated`. `googleapis_auth` was
taken from 1.6.0 to 2.3.3 — it is pure Dart on the backend, its FCM JWT signing path is covered by
`fcm_access_token_test.dart`, and the full backend suite passes on it.

The remainder are **deliberately not upgraded**, and are recorded here rather than left as silent
staleness. Each is a major version bump on a platform plugin whose failure mode is invisible to a
headless test suite — the suite would stay green while the shipped app broke.

| Package | Declared | Latest | Why it is held |
|---|---:|---:|---|
| `flutter_local_notifications` | `^18.0.0` | 22.2.0 | Four majors of API change, plus Android 14/15 behavioural and permission-model changes. The audit's own risk table calls this "a migration, not a bump" and requires a dedicated device test matrix, done alone. Nothing in CI can observe whether a notification actually arrives. |
| `flutter_secure_storage` | `^10.3.1` | 11.0.0 | Holds the SQLCipher database key. A migration that changes where or how the key is stored locks existing users out of their own message history, and the failure appears only on a device that already has data. Needs an upgrade-in-place test on a real install, not a fresh one. |
| `flutter_contacts` | `^1.1.9+2` | 2.3.1 | Major bump on the contacts permission surface, which feeds contact sync (P0-3). Permission regressions surface as an empty contact list, not an error. |
| `connectivity_plus` | `^6.1.3` | 7.3.1 | Drives the offline/outbox banner. A behavioural change in connectivity reporting degrades quietly — the app looks online while queueing. |

Each needs its own change, its own device matrix, and its own release. Bundling them, or taking any
one of them on a green CI run alone, is how a messaging app ships a build that cannot notify, cannot
unlock, or cannot sync.

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
