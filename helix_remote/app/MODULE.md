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
- A shared link (`https://helix.agiletechbd.com/open#HLX-…`, or
  `helix://open?code=…`) opens advanced mode and checks its code at once. The
  code travels in the **fragment**, so a browser never sends it to the server.
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
  5,000/day budget; `shared/widgets/qr_scanner_view.dart` owns the camera.

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

Shared additions: `core/people/name_lookup.dart` (the replaceable naming
adapter), `core/notifications/call_notifications.dart` (ringing notification,
also used by the FCM isolate), `HomeScreen(callsTab:)` (the tab is handed in
by the router), `HelixDeepLinkKind.groupLink`, and `ProviderScope` at the root
of `main.dart` (it was missing). Tests: `test/calls/` (includes the engine's real
`CallsService` over an in-memory network) and `test/groups/`, with fakes in
`test/support/`.
