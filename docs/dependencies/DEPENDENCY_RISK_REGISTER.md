# Dependency Risk Register

| Package | Resolved version | Risk | Owner | Remediation |
|---|---:|---|---|---|
| `sqlite3_flutter_libs` | `0.6.0+eol` | EOL marker in resolved package version. Remote no longer depends on it (the v1 `helix_remote_storage` was deleted at Phase X; the v2 client database uses `sqlite3` with the SQLCipher build hook); Local storage still resolves it and must be reviewed separately. | storage-team | Keep visible until Local storage removes the obsolete shim or records a product-specific exception. |
| `file_picker` | `13.1.0` | **Directly declared** by Helix Remote at `helix_remote/app/pubspec.yaml`, a stable release. The prerelease exception of [ADR-024](../../helix_remote/docs/adr/024-file-picker-prerelease-exception.md) is retired (2026-10-14, review G-01): the app resolves stable 13.1.0. The committed `helix_remote/pubspec.lock` is what pins it. | platform-team | Take minor releases with the attachment tests; the Android and Windows attachment picker is a real-device check (`REMOTE_RELEASE_CHECKLIST.md`). |

## Architecture v2 dependency intake (2026-09-30)

These are the new direct dependencies for the Helix Remote v2 rebuild
(`helix_remote/docs/architecture/ARCHITECTURE_V2_PLAN.md`, ADR-025/027). Each
is added to a pubspec only in the plan phase that first uses it, and its
lockfile change is reviewed then, not in advance. Versions are the latest
stable releases checked on 2026-09-30.

| Package | Version | Declared by | Phase | Risk | Owner | Remediation |
|---|---:|---|---|---|---|---|
| `postgres` | `3.5.17` | `helix_remote/server` (**added in Phase 0**) | 0 | The only maintained pure-Dart PostgreSQL driver, with a small maintainer base. All SQL for the v2 server goes through it. | server-team | The `Db`/`Tx` interface (Phase S1) keeps it replaceable. Pin via the lockfile. The Postgres test suites run in CI against a real `postgres:17` service. |
| `drift` / `drift_dev` | `2.34.0` / `2.34.0` | `packages/helix_remote_db` (**added in C1**; `drift_dev` dev-only) | C1 | Code generation. Stale generated code could diverge from the schema. It must work with the `sqlite3` SQLCipher hook. Held one minor below the 2.35.0 checked on 2026-09-30: `drift_dev` 2.35 needs `analyzer` ≥ 13, which conflicts with the `test_api` that Flutter 3.44 pins. | client-team | Generated code is committed and CI fails when it is stale (`tool/codegen.dart --check`, a governance control). The SQLCipher wrong-key and no-plaintext tests (P2-01) are carried over in `helix_remote_db/test/encryption_test.dart`. The schema dump (`drift_schemas/`) and the migration test are checked in from schema 1. Move to 2.35+ together with the Flutter SDK bump that lifts the `test_api` pin. |
| `build_runner` | `2.15.1` | dev-only (`helix_remote_db`, **added in C1**) | C1 | Dev tool only, with a large transitive tree (`build`, `build_daemon`, `source_gen`, `dart_style`, …). 2.15.1 is the newest that resolves with `drift_dev` 2.34. | client-team | Keep it in `dev_dependencies` only. It is not part of the shipped app. |
| `flutter_riverpod` | `3.4.3` | `helix_remote/app` | A1 | Central to UI state. A major bump later would touch every feature. | client-team | Use plain providers, with no `riverpod_generator`, so there is less codegen to keep in step. Take upgrades on their own, with the widget suite. |
| `go_router` | `18.0.2` | `helix_remote/app` | A1 | Routing and deep links (`helix://`, `/open` links). A regression breaks shared links silently. | client-team | Deep-link tests for both link forms, plus the hidden advanced-mode entry. |
| `aws_signature_v4` + `aws_common` | `0.6.13` / `0.7.15` | `helix_remote/server` (**added in S1**) | S1 | The user chose it on 2026-10-01 for S3-compatible storage. It pulls in `built_value`, `built_collection`, `http2` and `os_detect`, all server-only. A signing bug would surface as rejected uploads, not leaked data. | server-team | Confined to `platform/blobs/` (architecture test). Presign structure is tested against AWS's documented SigV4 parameters. Local storage is the default. |
| `shelf`, `shelf_router`, `http` | `1.4.2` / `1.1.4` / `1.2.x` | `helix_remote/server` (S1) | S1 | Already used and reviewed by the v1 `backend/` (deleted at Phase X) before the v2 server took them over. | server-team | — |
| `http`, `crypto` | `1.6.0` / `3.0.7` | `packages/helix_remote_api` (**added in C3a**) | C3a | Already resolved and reviewed (`http` by the server and v1 backend, `crypto` by the protocol package); the lockfile is unchanged. `http` ≥ 1.5 is needed for `AbortableRequest` (timeouts and cancellation). `crypto` only checks `Sec-WebSocket-Accept` in the hand-made upgrade. | client-team | `http` is confined to the transport and the facades, `dart:io` to the socket adapter (`helix_remote_api/test/architecture_test.dart`). |
| `fake_async` | `1.3.3` | dev-only (`packages/helix_remote_api`, **added in C3a**) | C3a | Test-only, already resolved through the Flutter SDK's test packages. | client-team | — |
| `shelf_web_socket`, `web_socket_channel`, `googleapis_auth`, `stream_channel` | `3.0.0` / `3.0.3` / `2.3.3` / `2.1.4` | `helix_remote/server` (S3; `stream_channel` S7) | S3 | Already used and reviewed by v1 `backend/` (realtime relay, FCM token exchange). `stream_channel` was already resolved transitively (shelf); S7 imports it directly to wrap the upgraded socket for the WebSocket frame limit. | server-team | Google auth is confined to `platform/push/` (architecture test). |

## Media plugins (v2 app, 2026-10-05)

Camera and photo capture, voice notes, audio and video playback, previews for photos and videos. The user
approved adding plugins. Each is declared by `helix_remote/app`, used in **one** file under
`app/lib/core/platform/` behind an interface, and faked in the tests (`app/test/media_plugins_rules_test.dart`
asserts the one-file rule). The lockfile gained only these packages and their transitive dependencies
(`audioplayers_*`, `image_picker_*`, `record_*`, `video_player_*`, `file_selector_*`, `csslib`, `html`); no
existing entry moved. Versions are the latest stable releases checked on 2026-10-05; all resolve on Flutter 3.44.

| Package | Version | Why | Risk | Mitigation |
|---|---:|---|---|---|
| `image_picker` | `1.2.3` | First-party (flutter.dev) camera capture for a photo or a video through the system camera app, so there is no in-app camera screen to maintain and the camera permission is asked only when the person taps Camera. | Camera apps embed GPS and device details in what they save, and the plugin hands the file over unchanged. Android can kill the app while the camera is open (the capture is then lost). | Every photo and video is cleaned (`MediaSanitizer`) before the engine copies it, and a photo that cannot be cleaned is not sent. The capture is moved into an app-owned cache folder and deleted after the send. Lost-capture recovery is not implemented (device-only check). |
| `record` | `7.1.1` | The maintained cross-platform recorder (Android, iOS, Windows). AAC in MP4, loudness readings for the waveform, pause and resume, and audio-focus handling so a call pauses the recording. | Microphone access: a bug that leaves it open is a privacy failure. Single-maintainer package (llfbandit). Android silences a background app's microphone. | `DeviceVoiceRecorder` owns it: cancel on leaving the conversation, pause when the app goes to the background, delete the file after the send, and `RecordBackend` fake tests of the clock, pause, permission and cleanup paths. Permission is requested on the first hold, never at start-up. |
| `audioplayers` | `6.8.1` | Voice-note and audio playback with speed and seek on Android and Windows (native Windows support, unlike `just_audio`), with an audio-focus request. | Large native surface; focus behaviour differs by OEM. | `DeviceAudioPlayer` over an `AudioBackend` interface; one player, one note at a time; playback state machine tested with a fake. |
| `video_player` | `2.14.1` | First-party (flutter.dev, Flutter Favorite) inline and full-screen video playback via ExoPlayer. | No Windows implementation (it reports unsupported there). Hardware decoders differ by device. | `DeviceVideoPlayers.isSupported` is false off Android/iOS and the viewer then offers the share sheet, as before. A failed initialise shows the same fallback. The player is created only for the page on screen and disposed with it. |
| `fc_native_video_thumbnail` | `3.0.1` | One still frame from a video (Android `MediaMetadataRetriever`, Windows Media Foundation) for the chat thumbnail and BlurHash, without bundling FFmpeg. | Small package (47 likes); Linux would need system libraries (Linux is not a Helix target). | Behind `VideoFrameSource`; a failure or missing platform means the video is sent without a thumbnail, never that the send fails. |
| `image` | `4.10.1` (already resolved transitively) | Pure-Dart JPEG encoding of the small thumbnail the chat sends (a PNG thumbnail is ten times larger) and of the re-encode fallback for photo formats that cannot be cleaned in place (HEIC). | Pure-Dart encoding is slow for big pictures. | Only 320 px thumbnails and the rare fallback go through it, in a background isolate (`IsolateThumbnailEncoder`). The lockfile entry already existed; it is now also a direct dependency of the app. |

New native build steps on Windows (`audioplayers_windows`, `record_windows`, `fc_native_video_thumbnail`,
`file_selector_windows`) appear in `app/windows/flutter/generated_plugins.cmake`; they have not been compiled
(no builds were run), so the next Windows build is the first check.

## Deferred major upgrades (MED-8)

The audit recorded several client dependencies as materially behind. The minor gaps
(`cryptography_flutter`, `mobile_scanner`, `flutter_webrtc`) have since resolved forward within
their existing caret ranges and no longer appear in `flutter pub outdated`. `googleapis_auth` was
taken from 1.6.0 to 2.3.3 — it is pure Dart, and the v1 test of its FCM token path
(`fcm_access_token_test.dart`) was deleted with the v1 backend. The v2 server's FCM provider
(`platform/push/push.dart`) has no automated test, because it needs Google's endpoints: the first real
push on cutover day is its check (`helix_remote/docs/operations/V2_SERVER_HANDOFF.md`, "The day").

Until 2026-10 the four below were **deliberately not upgraded**: each is a major version bump on a
platform plugin whose failure mode is invisible to a headless test suite. They were then taken anyway,
without the device matrix this section asked for (review G-01, 2026-10-09). The current state is in
"Client platform plugins" below; the table here is the record of why they were held.

| Package | Held at | Latest then | Why it was held |
|---|---:|---:|---|
| `flutter_local_notifications` | ^18.0.0 | 22.2.0 | Four majors of API change, plus Android 14/15 behavioural and permission-model changes. The audit's own risk table calls this "a migration, not a bump" and requires a dedicated device test matrix, done alone. Nothing in CI can observe whether a notification actually arrives. |
| `flutter_secure_storage` | ^10.3.1 | 11.0.0 | Holds the SQLCipher database key. A migration that changes where or how the key is stored locks existing users out of their own message history, and the failure appears only on a device that already has data. Needs an upgrade-in-place test on a real install, not a fresh one. |
| `flutter_contacts` | ^1.1.9+2 | 2.3.1 | Major bump on the contacts permission surface, which feeds contact sync (P0-3). Permission regressions surface as an empty contact list, not an error. |
| `connectivity_plus` | ^6.1.3 | 7.3.1 | Drives the offline/outbox banner. A behavioural change in connectivity reporting degrades quietly — the app looks online while queueing. |

Each needed its own change, its own device matrix, and its own release. Bundling them, or taking any
one of them on a green CI run alone, is how a messaging app ships a build that cannot notify, cannot
unlock, or cannot sync - which is what the 2026-10-09 review then found (E-01, E-03, B-01).

## Client platform plugins (2026-10-14)

Plugins whose failures a headless suite cannot see. Versions are the resolved ones in
`helix_remote/pubspec.lock`; `tool/check_governance_controls.dart` fails when a version in this
register (in any table) differs from the lockfile. "Device check" says whether a real-phone check of
the current major is recorded; the user confirmed on 2026-10-14 that none has been done yet, so each
stays **pending** until one is written here with its date and phone. The checks are listed in
`helix_remote/docs/release/REMOTE_RELEASE_CHECKLIST.md` ("Platform plugin majors").

| Package | Resolved | Declared by | Risk | Device check |
|---|---:|---|---|---|
| `flutter_local_notifications` | `22.3.1` | app | Four majors past 18: a notification that never shows is silent. | pending |
| `flutter_secure_storage` | `11.2.0` | app, admin | Holds the SQLCipher key (app) and the admin session (console); a storage change locks people out of their history, visible only on an upgraded install. | pending (upgrade in place) |
| `flutter_contacts` | `2.5.0` | app | Contacts permission and the people-naming order; a regression shows as an empty list. | pending |
| `connectivity_plus` | `7.3.1` | app | Offline detection for the outbox banner; a regression looks online while queueing. | pending |
| `firebase_core` | `4.15.0` | app | FCM initialisation (the 2026-10-09 review found it was never initialised in the UI isolate, E-01). | pending (with the push checks) |
| `firebase_messaging` | `16.7.0` | app | Wake-up pushes; no test reaches FCM. | pending (with the push checks) |
| `local_auth` | `3.0.1` | app, admin | App lock; on Android it needs a `FragmentActivity` (B-01), which only a phone shows. | pending |
| `shared_preferences` | `2.5.5` | admin | Console settings (server address, App lock switch). Low risk. | not needed |

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

## Retired at Phase X (cutover, 2026-10)

The v1 workspace members `helix_remote_storage`, `helix_remote_sync`, `helix_remote_groups` and the
`backend` package were deleted, together with the v1 REST client, crypto and CLI inside surviving
packages. Declared dependencies that only they used were dropped from the remaining pubspecs
(`flutter`, `cryptography_flutter`, `flutter_secure_storage` and `helix_remote_domain` from
`helix_remote_crypto`, which is now pure Dart; `uuid`, `path` and the domain and storage packages from
`helix_remote_calls`; `meta` from `helix_remote_domain`; the domain package from `helix_remote_api`;
`helix_remote_domain` and the test package from `tool`). `helix_remote/pubspec.lock` did not change: every
resolved package is still declared by some remaining member (the app still declares
`cryptography_flutter`, and the app and the admin console `flutter_secure_storage`). Nothing was added.

## Orbit UI package and its bundled fonts (2026-10-19)

Orbit Part B step 1 (`orbit/PORT_PLAN.md`) moved `orbit_ui` into the Helix Remote workspace
(`helix_remote/packages/orbit_ui`). It declares no hosted dependency beyond the Flutter SDK
(`flutter_lints` is dev-only and was already resolved), so `helix_remote/pubspec.lock` did not change.
It ships font files, vendored verbatim, which are dependencies in their own right:

- **Phosphor icons** (Regular, Light, Bold, Fill, Duotone; `packages/orbit_ui/fonts/phosphor/`),
  MIT licence (`LICENSE` beside the files). Risk: an icon renamed or dropped upstream. Mitigation: the
  icon table `lib/src/icons/orbit_icons.dart` names only code points present in these files, and the
  files are never replaced without regenerating it; release builds tree-shake each font to the
  glyphs used.
- **Geist and Geist Mono** (variable roman and italic; `packages/orbit_ui/fonts/`), SIL Open Font
  License 1.1, the licence text beside each family. Source, byte size and SHA-256 are in
  `orbit/flutter/fonts/MANIFEST.md`. Risk: none at runtime (no network fetch). Mitigation: a family is
  added only together with its licence.

Owner: client-team.


## Theme packs: the domain package's first dependency (2026-10-23)

Orbit Part C step 1 (`orbit/PORT_PLAN.md`, ADR-033) added one hosted dependency
and one internal edge:

| Package | Version | Declared by | Why | Risk | Owner | Remediation |
|---|---:|---|---|---|---|---|
| `cryptography` | `2.9.0` | `packages/helix_remote_domain` (**new**), `helix_remote_crypto` (already), `tool` (**new**) | A pack's manifest is checked with Ed25519 and its files hashed with SHA-256 before the app opens anything. | The package decides whether a downloaded theme is drawn on every device, so a verification bug is a shipping bug. It is the same resolved version `helix_remote_crypto` already used for the protocol's X3DH and Sender Keys, so nothing new entered the build and `helix_remote/pubspec.lock` did not change; `flutter pub get --enforce-lockfile` still resolves. | client-team | Confined to one file (`lib/domain/theme_packs.dart`) and to `tool/theme_pack_tool.dart`. Signing vectors are pinned in `packages/helix_remote_domain/test/theme_packs_test.dart` (the canonical bytes, the key and the signature), and the gate's refusal cases are tested there. A wrong signature, an unknown publisher or an unsigned pack is refused, never degraded. |

`tool/pubspec.yaml` also gained a path dependency on `helix_remote_domain`, so
`dart run tool/theme_pack_tool.dart verify` checks a pack with the same code the
app runs rather than a second implementation that can drift from it. `tool/`
is not shipped, and no package depends on it.

The trust anchor is empty in this change: `checkOrbitPack` refuses every
publisher until the owner generates a key with `keygen` and adds the public half
to the app. No pack can be accepted by a build that has no key in it.
