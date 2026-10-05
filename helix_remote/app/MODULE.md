# helix_remote (app)

The Helix Remote Flutter client, rebuilt on the v2 stack (ADR-027,
`docs/architecture/ARCHITECTURE_V2_PLAN.md` §6.4). **Phase A1** replaced the
v1 `lib/` with this one: the old composition root, `remote_rest_client.dart`,
the onboarding notifier and every screen under `screens/` are gone from this
branch. `main` keeps them for reference until cutover.

## The shape

```
lib/
  main.dart                     zones, error reporting, the FCM background
                                handler registration, ProviderScope, the one
                                MaterialApp.router
  core/                         shared wiring, no feature state
    engine/
      helix_runtime.dart        owns the db + api + engine for one server;
                                `headless` for the FCM isolate
      runtime_providers.dart    the seam: RuntimeFactory, serverUrl,
                                runtimeProvider
      session_providers.dart    engine status -> AppAuthState, sign-out,
                                destructive reset
    router/app_router.dart      go_router, the redirect, deep-link routing
    links/                      HelixDeepLink, the HLX-INV-/HLX-REC- codecs,
                                the warm-start MethodChannel
    platform/                   AppPaths, SecureKeyStore (SQLCipher key),
                                ServerUrlStore, DevicePhoneBook
    lifecycle/                  resume -> reconnect + syncOnce
    security/                   AppLock + gate, AppSettings
    notifications/              local notifications (wake-ups only)
    push/                       the FCM background handler, PushTokenSource
  features/<feature>/
    application/                Riverpod Notifiers / StreamProviders, the
                                value objects the screens draw
    presentation/               screens and widgets, Stateless/Consumer only
  shared/widgets/               cross-feature widgets, startup and reset
                                screens, the link listener
```

**Every list is a `StreamProvider` over a drift watch query.** The engine owns
the query; `application/` maps rows into the plain value objects in
`helix_remote_ui`; a widget never sees a row, a column or a clock, and never
formats a date.

## What may import what

Enforced by `test/architecture_test.dart`:

- `presentation/` imports `dart:`/Flutter, its own feature, `shared/`,
  `helix_remote_ui` and `helix_remote_domain`. **Nothing else** — not the
  engine, the database, the crypto, the API or `core/`. Work goes in a Notifier
  or StreamProvider; the screen receives plain values.
- A feature never imports another feature. Shared state goes through a provider
  in `core/` or a widget in `shared/`.
- No v1 package (`helix_remote_storage`, `_sync`, `_groups`, `_backend`).
- No `sqlite3`/`drift` outside `helix_remote_db`, no `http`/WebSocket outside
  `helix_remote_api`.

## The engine, and the one seam

The app never constructs an `Engine` directly. It provides a `RuntimeFactory`,
and everything above reads `runtimeProvider`:

```dart
final runtime = await ref.watch(runtimeProvider.future);
runtime.engine.chats.watchChats();
```

That is what lets every test in this package run with no keystore, no database
file and no network: override `runtimeFactoryProvider`. The widget suites use an
in-memory encrypted database.

`HelixRuntime.open(..., headless: true)` starts an engine with no socket and no
timers, which is what the FCM background isolate needs - it calls `syncOnce()`
and closes.

## Sign-in

`features/sign_in/application/sign_in_controller.dart` is the whole flow: the
page machine, the validation, and the copy (`sign_in_copy.dart`). The screens
read `SignInState` and call methods; they hold no rules, which is why the Global
path and the personal-server path cannot drift apart.

The rules that were true in v1 and are still true (each has a test in
`test/sign_in_flow_test.dart` or `test/product_rules_test.dart`):

- Opens on the plain **Helix Global** page: a phone number, `Next`, and a
  `Terms & Privacy` link. No back button (nothing precedes it), and no
  host-your-own-server copy anywhere.
- **Personal servers are hidden.** Three taps in the bottom-right corner within
  two seconds of each other reveal an `Advanced mode` button in the same
  corner; a fourth tap opens it. `AdvancedModeCorner.tapWindow` and
  `.tapsToReveal` are public because the rule is public.
- A shared link (`https://…/open#HLX-…` - exactly `/open`, over https - or
  `helix://open?code=…`) opens advanced mode with its code. The code travels in
  the **fragment**, so a browser never sends it to the server. **Any code or
  link that names a server other than Helix Global stops at a confirmation**
  ("This code wants to sign you in on <host>"): no request is made until the
  person agrees, the host (not the server's self-chosen name) is shown on every
  page that follows, and a link is only applied when the device is known to be
  signed out (`SessionRestore` settled, auth not ready); it is dropped when
  anyone signs in or out.
- Only Helix Global asks for the Terms. A personal server has its own operator
  policies.
- Sign-in pages use `HelixThemes.signIn()` (the app icon's blue) as a local
  `Theme`; the rest of the app stays on `HelixThemes.light()`.
- No exception text ever reaches a screen: every failure is one of the
  sentences in `sign_in_copy.dart`.
- The password never leaves the device. The engine sends only the HKDF-derived
  auth key.

## The background isolate

`core/push/push_background.dart` is registered before `runApp`. When a data-only
message arrives with the app closed it builds its **own** engine, opens the same
encrypted database with the key from the keystore, reads the mailbox over REST,
applies everything, and raises one grouped local notification.

It never reads content from the payload. The payload is only a wake-up; the
message is decrypted by the engine, so nothing that crossed a push provider can
land on the lock screen.

This is also the reason the app keeps no SQLite outside the db package: the
isolate has to reach the same file the UI isolate has.

## Logging

Two places may log, and each may report an **exception type only** - which
`test/architecture_test.dart` asserts by inspecting the interpolated values:

- `main.dart` (`FlutterError.onError`, the zone handler)
- `core/push/push_background.dart` (an isolate that has no UI)

Nothing else in `lib/` may contain `print`, `debugPrint` or `developer.log`.

## Testing

- `architecture_test.dart` — the import boundaries above.
- `product_rules_test.dart` — the carried-over rules: design tokens, icon-button
  tooltips, no clamped text scaling, screenshots allowed, English only, light
  theme only, the Android manifest expectations.
- `accessibility_test.dart` — the sign-in page and the shared controls against
  Flutter's own `meetsGuideline` checks, at the default and largest text scale,
  in the high-contrast theme.
- `sign_in_flow_test.dart` — the page machine and the corner, headless.
- `deep_link_test.dart` — every documented link form and what is refused.
- `performance_budget_test.dart` — the plan §6.4 budgets (16 ms for a 5,000-chat
  first page; a 1,000-row burst inside the CI budget).
- `integration_test/onboarding_journey_test.dart` — the hidden corner on a real
  device.

## Not in A1

Groups, calls, the conversation, the people search, media, backup and the
settings pages are A2 and A3. The Calls tab is deliberately an honest empty
state rather than a dead button. A1's job was the shell and the wiring, and the
three tabs all read through the same `StreamProvider` pattern A2 will extend.

Group calls stay deferred from v2 entirely (plan §13).

## People (Phase A2b)

`features/people/` (see its `FEATURE.md`): the naming helper, phone-book
integration, people search and the contact info screen. What other features
consume lives outside the feature folder, because features never import each
other:

- `core/people/people_names.dart` - `peopleDirectoryProvider`,
  `personNameProvider(id)`, `PersonName` / `PeopleDirectory`: phone-book name,
  then nickname, then number, then `~Helix name`, reactive.
- `shared/widgets/people_search_panel.dart` - `PeopleSearchPanel`, mounted
  under the Chats (A2a) and Calls (A3a) search fields.
- `shared/navigation/conversation_seams.dart` - `ConversationSeams`:
  `openChat` (A2a), `openSharedMedia` (A2a), `startCall` (A3a);
  `people_paths.dart` has the routes into contact info and search.
- `core/platform/` - `ContactsAccess` (the only user of `flutter_contacts`),
  `DevicePhoneBook` over it, `phone_numbers.dart` (E.164, country of the
  account's own number). `shared/widgets/phone_book_sync_host.dart` runs
  discovery on start, resume, hourly and after address-book changes, within the
  5,000/day budget; `shared/widgets/qr_scanner_view.dart` owns the camera (the one scanner).

Tests: `people_names_test`, `phone_numbers_test`, `phone_book_test`,
`people_search_test`, `contact_info_test`, `people_rules_test`,
`people_performance_test`; fakes in `test/support/people_fakes.dart`.

## Settings, devices, backup and profile (Phase A3b)

Four features on the same pattern: `application/` holds a **gateway interface**
(the only code that touches the engine or API, with an `Engine...Gateway`
implementation) plus Riverpod notifiers that turn what it returns into
sentences and state; `presentation/` draws it. Tests replace the gateway with
a fake from `test/support/a3b_fakes.dart`, so a page's real notifier runs with
no engine, database or network.

- `features/settings/` the tab and Account, Privacy, Notifications, Chats,
  Storage, About (+ legal) and Advanced pages. See its `FEATURE.md`.
- `features/devices/` device list, approving a device, security activity, and
  the new device's QR page. See its `FEATURE.md`.
- `features/backup/` Backup settings, restore (also the post-sign-in step),
  device transfer, recovery backup. See its `FEATURE.md`.
- `features/profile/` your name, about, `~name` and picture. See its
  `FEATURE.md`.
- `shared/route_paths.dart` the paths these pages link to each other with
  (features may not import features); `shared/widgets/inline_notice.dart`,
  `app_text_scale.dart`; `shared/format.dart` (sizes, "5 minutes ago").
- `core/` additions: `engine/local_settings.dart` (typed settings seam),
  `failure_copy.dart` (error to sentence), `post_sign_in.dart`, `clock.dart`,
  `backup_policy.dart`, `crash_reporter.dart`, `global_server.dart`;
  `platform/` adapters behind interfaces with fakes (`qr_encoder`,
  `qr_scanner`, `share_adapter`, `network_probe`, `storage_usage`,
  `profile_image_source`); `security/device_auth.dart`;
  `notifications/notification_permission.dart`.
- Router: the three feature route lists are spread in, and `refreshListenable`
  now follows `authStateProvider` and `postSignInProvider` (before, `redirect`
  only ran on navigation, so a finished sign-in did not leave the sign-in page).
  Sign-in also falls back to Helix Global when no server has been chosen.
- Engine: `AccountService.changePassword` (additive; covered by
  `server/test/client/engine/devices_test.dart`).

## Phase A3a: calls and groups

Two features, each with its own `FEATURE.md`.

- `features/calls`: the Calls tab (real call log, folding, call detail, delete,
  call back, a people-search seam), the full-screen call (incoming, dialing,
  live voice and video, ended reasons), and the runtime: the engine's
  `CallMediaFactory` over `helix_remote_calls`, audio routing, permissions,
  ringing, foreground service, proximity, lock-screen flags.
  `core/calls/call_host.dart` keeps it all running under every screen;
  `core/calls/place_call.dart` is the seam every call button reads.
- `features/groups`: create, info, settings, invite links, join requests, bans,
  add members, join by link (`HLX-GRP-` links), encrypted picture and
  description editing.

Shared additions: `core/notifications/call_notifications.dart` (ringing notification,
also used by the FCM isolate), `HomeScreen(callsTab:)` (the tab is handed in
by the router), `HelixDeepLinkKind.groupLink`, and `ProviderScope` at the root
of `main.dart` (it was missing). Tests: `test/calls/` (includes the engine's real
`CallsService` over an in-memory network) and `test/groups/`, with fakes in
`test/support/`.

## Chats and conversation (Phase A2a)

`features/chats` is the Chats tab and `features/conversation` is the
conversation screen (see each `FEATURE.md`). What they share is in `core/`
because features may not import each other:

- `core/chat/chat_gateway.dart` - everything a chat screen asks of the engine,
  in one class. Tests subclass it: reads stay the engine's real watch queries
  over an in-memory database, writes are simulated (`test/support/chat_harness.dart`).
- `core/chat/message_semantics.dart`, `chat_naming.dart`, `search_snippet.dart`,
  `core/format/labels.dart` - pure helpers (preview kinds, notices, time labels).
- `core/platform/` - `AppBlobStore` (the engine's file store, now passed to
  `HelixRuntime.open(blobs:)` and the FCM isolate), the attachment picker, voice
  recorder, audio player and share-sheet adapters.
- `core/calls/call_launcher.dart` - the seam the calls feature fills.
- `shared/navigation/chat_locations.dart` - route paths any feature can open;
  `shared/widgets/mute_choice.dart` - the mute sheet.

`HomeScreen` takes the Chats tab as a constructor argument (`chatsTab`), built
in `core/router/app_router.dart`, so home does not import the chats feature.

Tests: `chat_list_test.dart`, `conversation_test.dart`, `chat_logic_test.dart`,
`chat_performance_test.dart` (5,000 chats; first page of 100,000 messages; a
1,000-message burst - build-count and relative-cost checks, no wall-clock
asserts). Widget tests that touch the database run real async work inside
`tester.runAsync` (see `settle`/`chatTest` in the harness).

## Integration (A2/A3 wiring)

The four feature branches were built in parallel against documented seams. This
is the final wiring; `test/journeys/` walks it.

- **One naming source.** `core/people/people_names.dart`
  (`peopleDirectoryProvider`, `personNameProvider`, `PersonName.fromRow`): phone
  book, nickname, number, `~Helix name`. The chat list, conversation, call log
  and call screen, groups, settings (blocked list), contact info and the FCM
  isolate (`core/push/push_background.dart`) all read it. `ChatPeople` and
  `name_lookup.dart` are gone. A stranger is `Helix user <short id>` everywhere.
- **People search.** The router builds `ChatsTab(peopleResults:)` with
  `PeopleSearchPanel(mode: chats, embedded: true)` and
  `CallsTabScreen(peopleSearch:)` with `PeopleSearchPanel(mode: calls)`. A chat
  result opens or starts the conversation; a calls result calls.
- **Calls.** `ConversationSeams.startCall` (contact info, search) and
  `callLauncherProvider` (conversation header) both resolve to
  `placeCallProvider`, so a refusal is one sentence (`outcome.message`) in a
  snackbar. `RouterConversationSeams.openChat` pushes `chatLocation(id)`
  (`/chat/:id`); `groupChatLocationProvider` defaults to the same.
- **Shared media.** `ConversationSeams.openSharedMedia` opens
  `/chat/:id/shared` (photos and videos, documents, links) over the engine's
  `watchSharedAttachments` / `watchMessagesWithLinks` (additive: db
  `MessagesDao`, `ChatsService`).
- **Info pages.** A direct chat's header opens contact info, a group's opens the
  group info (`shared/navigation/group_paths.dart`, `people_paths.dart`); the
  conversation menu and settings link to both and to shared media. The Chats tab
  menu has New group and Join a group with a link (there was no entry to the
  create screen before).
- **Duplicates removed.** One QR scanner adapter
  (`shared/widgets/qr_scanner_view.dart`, null on Windows), one clock
  (`clockProvider`; the chat, call, group and people clocks are gone), one
  date-time label (`formatWhen` replaces the call and group ones), `formatAgo`
  moved next to the other labels in `core/format/labels.dart` (`shared/format.dart`
  only re-exports for presentation), offline and signed-out group errors reuse
  `describeFailure`. `formatBytes` (binary, storage and limits) and
  `formatFileSize` (decimal, a file in a chat) stay separate on purpose.
- **Tests.** `test/journeys/` (sign-in to a call in the Calls tab, header call
  failure, shared media, group create/info/add member, settings to devices and
  back, `HLX-GRP` link preview and join, and the whole `HelixRemoteApp`).

### Media plugins (filled after the integration)

The three seams that had no plugin are now filled, each behind its interface in
`core/platform/` (the plugin is imported by exactly one file; `test/media_plugins_rules_test.dart`):

- **Camera and photo capture**: `AttachmentPicker.takePhoto` / `recordVideo` over `CameraCapture`
  (`device_camera.dart`, `image_picker`, the system camera app). Camera permission is asked by the
  plugin when Camera is tapped; a refusal is `AttachmentPermissionDenied` and one sentence. The attach
  sheet's Camera and the field's camera button ask photo or video first. Captures live in
  `<cache>/helix_capture` (`MediaTemp`), are swept after 6 h, and deleted after the send or when the
  preview is left.
- **Metadata stripping**: `MediaSanitizer` (`media_sanitizer.dart`) runs in `ComposerNotifier.sendFiles`
  *before* the engine copies a file (the engine records the copy's size first, so the engine's processor
  cannot rewrite it). JPEG/PNG/WebP are cleaned losslessly in an isolate (`image_metadata.dart`: EXIF,
  XMP, IPTC, comments, trailers; a JPEG keeps a one-tag orientation block); MP4/MOV/3GP get location
  and tag boxes turned into `free` and their time stamps zeroed (`mp4_metadata.dart`); a format that
  cannot be cleaned in place (HEIC) is decoded and re-encoded as JPEG; a photo that cannot be cleaned is
  **not sent**. WebM/MKV videos and GIFs pass unchanged (documented limits). Originals are never changed.
- **Previews**: `FlutterMediaProcessor` (`flutter_media_processor.dart`) is the engine's `MediaProcessor`
  (passed through `HelixRuntime.open(mediaProcessor:)`): dimensions, a 320 px JPEG thumbnail
  (`dart:ui` decode scaled while decoding, JPEG encode and BlurHash in a background isolate), video length
  and size from the MP4 boxes and a frame from `fc_native_video_thumbnail`. It never throws.
- **Voice notes**: `VoiceRecorder` over `DeviceVoiceRecorder` (`record`): AAC-LC mono in `.m4a`
  (`audio/mp4`), loudness readings every 100 ms turned into a waveform of at most 72 bytes, a clock that
  does not count pauses, 10 minute limit (the composer stops and sends), `VoicePhase` stream so a call
  that pauses the microphone stops the clock. The composer handles permission denied, a finger lifted
  while the permission prompt or the microphone was opening, background (held recording dropped, locked
  one paused and resumed), and leaving the conversation. The file is deleted after the send.
- **Playback**: `AudioPlayerAdapter` over `DeviceAudioPlayer` (`audioplayers`, audio focus requested);
  `PlaybackNotifier` plays one note at a time (starting a recording or a video stops it), speed 1/1.5/2,
  seek, played marks, failure sentence. Video: `VideoPlayers` over `DeviceVideoPlayers` (`video_player`);
  `VideoSession` / `VideoPlayerView` is the full-screen player (play/pause, seek bar, time, speed, replay,
  pauses in the background). Where there is no player (Windows) or the decoder refuses the file the
  viewer offers the share sheet as before.
- A fix found on the way: `HelixComposer` re-parented the microphone button when recording started, which
  dropped the finger's gesture (release never sent); it now keeps one tree shape (`helix_remote_ui`).

Only a real phone can show: the system camera round trip and its permission prompt (and a capture lost
when Android kills the app), the microphone prompt on first hold, recording quality and the waveform,
call and background interruptions, audio focus and ducking, ExoPlayer decoding of real videos, video
frame extraction and the EXIF orientation of thumbnails, and the Windows native build of the new plugins.
Proximity/earpiece playback is not done.

- Still open: the group member picker is its own list (it reads the same people
  table as the search, so it was not swapped for the panel); a minimised
  return-to-call bar; group calls (deferred, plan section 13).

## Security review pass (v2-fixa)

- **App lock** (`core/security/app_lock.dart`). Cold start: once per process,
  when `sessionRestoreProvider` has settled and the session is `ready`, the
  gate covers the app until the stored setting is read, then locks if it is on
  (unreadable setting = locked). A sign-in made in this process does not lock.
  "Lock again" is a real grace period: backgrounded for at least that long (or
  a clock set backwards) locks on return; "Immediately" locks on background.
  A call lifts the lock only once connecting or active, not while ringing.
- **Servers** (`core/engine/server_policy.dart`). https only; `http` reaches
  `localhost`/`127.0.0.1`/`10.0.2.2` in debug builds only; no user info, query,
  fragment or non-ASCII host. Enforced in sign-in (before any request), on the
  remembered server at start, in `ServerUrlNotifier.use` and in
  `HelixRuntime.open` (which the push isolate uses too).
- **Pinning** (`core/platform/tls_pinning.dart`). Android's network security
  config does not govern Dart sockets. A runtime for Helix Global is built
  under `HttpOverrides` with a context that trusts no CA; the pin (SHA-256 of
  the leaf SPKI, `builtInPins` = the XML's, plus `--dart-define=
  HELIX_GLOBAL_PINS=a,b` for the next key) decides in `badCertificateCallback`,
  for REST and the realtime socket (via the api package's existing `sockets`
  injection; no api change). Fail closed; debug builds unpinned. The pin is the
  leaf key: a renewal with a new key and no shipped pin makes Global
  unreachable. Verify the pin against the live certificate before release.
- **One engine** (`core/platform/engine_lease.dart`). A heartbeat lease file
  beside the database: the push isolate stands aside while the app runs; a
  second Windows window is refused (`EngineAlreadyRunning`, shown by the reset
  screen without the destructive option). Best-effort advisory, not a mutex.
- **Local files**. Windows data lives in the local (non-roaming) app-data
  folder, not Documents (OneDrive). Sign-out and the destructive reset delete
  the avatar and attachments, clear the file picker's temporary copies (also
  after every media send), and the reset works from the files alone.
- **Contacts** read access is requested up front; write only at a rename.
- **Call notifications** name the caller, and are `public`, only with message
  previews on; otherwise "Helix" and `private`.
- Link handling: the router ignores the platform's start URL; a link's code
  stays in `pendingLinkProvider`, never in a route location.
