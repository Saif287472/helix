# Contract: the app frame

The frame holds the routes and window panes, the theme, overlays, the hosts
that wrap every screen, and the behaviour every screen gets for free.

- **Prototype:**
  - `orbit/prototype/js/app.js`: page stacks, `PLACEMENT`, overlays,
    themes and `GLOBAL_INTERACTIONS`;
  - `css/window.css`;
  - the "Every screen" section of `INTERACTIONS.md`.
- **Today's app:**
  - `app/lib/main.dart` (`MaterialApp.router` and its hosts);
  - `app/lib/core/router/app_router.dart`, `app/lib/shared/route_paths.dart`
    and `features/*/*_routes.dart`;
  - `features/home/presentation/home_screen.dart`;
  - `features/chats/presentation/chats_tab.dart`, which already puts the
    list and the chat side by side on wide windows;
  - `packages/helix_remote_ui` (`HelixThemes`, `HelixBreakpoints`).

Paths are relative to `helix_remote/`.

## 1. Routes

Today:
- One `GoRouter` (`appRouterProvider`). Its redirect alone decides between
  sign-in, the restore step, reset and home (`_redirectFor`).
- Home is a shell with three tabs: Chats, Calls and Settings.
- Every other screen is a pushed route, registered by its feature.
- Features never import each other; the router wires their seams.

Orbit keeps that router and its redirect unchanged, with these changes:

| Change | Tag | Notes |
|---|---|---|
| Home has two tabs, Chats and Calls | derive | `HomeTab` loses `settings`; the dock replaces `_HomeBar` |
| You is a route, opened from the profile picture | derive | New path, for example `/you`, built from today's `SettingsTab` content. The settings pages keep their `RoutePaths` (`/settings/privacy`, …) |
| Appearance is a new route under You | local | `/settings/appearance` |
| The deep-link routes stay as they are | have | `routeDeepLink` in `app_router.dart` |

## 2. Window panes (840 px and wider)

Today: only the Chats tab splits, into a 380 px list and the chat
(`ChatsTab.detailBuilder`). The Calls and Settings tabs, and every pushed
route, fill the window.

Orbit: every screen has a placement. The prototype's `PLACEMENT` table maps
onto today's routes like this:

| Placement | Prototype screens | Routes today |
|---|---|---|
| **list** (left, 380 px) | `home`, `archived`, `settings-page` (You), `group-new`, `group-join` | `/home`, `ChatRoutes.archived`, new `/you`, `GroupRoutes.create`, `GroupRoutes.join` |
| **detail** (right; picking in the list replaces it) | `chat`, `call-detail` | `ChatRoutes.conversation`, `CallRoutes.detail` |
| **info** (beside the chat from 1200 px; over it below) | `contact`, `group-info`, `shared`, `chat-settings`, `message-info` | `PeoplePaths.home/:id`, `GroupPaths.base/:groupId`, `…/shared`, `…/settings`, `…/info/:rowid` |
| **full** (covers the window) | `call`, `media-viewer`, `signin`, `restore` (after sign-in), `reset`, `lock` | `CallRoutes.call` (today shown by `CallHost`), `…/media/:rowid`, `AppRoutes.signIn`, `RoutePaths.restoreAfterSignIn`, `AppRoutes.reset`, `AppLockGate` (a gate above the navigator, not a route) |
| **inherit** (where it was opened from; on the right when opened from the list) | everything else | their routes as today |

| Frame behaviour | Tag | Notes |
|---|---|---|
| `OrbitWindowScaffold`: list, detail, info and full layers, and the placeholder ("Pick a chat", "Pick a call", "Pick a setting") | derive | Replaces the split inside `ChatsTab` |
| The right pane remembers its page for each list (Chats, Calls, You) | derive | UI state in the shell |
| The first page on the right has no back arrow; the info pane's first page has a close button | derive | |
| Esc closes the topmost thing | derive | `Shortcuts` and `Actions` in the shell |
| Sign-in, restore, link this device, reset and lock in a centred 440 px box | have + derive | The sign-in frame already boxes on wide windows (`sign_in_frame.dart`) |
| The title bar tinted to the theme | local | Windows runner (`app/windows/runner`): set the DWM caption and text colours from the theme. A small native change; `flutter pub get` registrant rules apply |

**Phase 2 spike (an engineering choice, not yours):** how go_router feeds
the panes. Two options:
- Recommended: nested `Navigator`s per pane inside a shell route, with
  `PLACEMENT` deciding which one a route pushes into.
- One stack, split by placement when drawing.

The spike settles this before any screen is built.

## 3. Theme

Decided on 2026-10-18 for the downloadable-themes phase (Part C in
`PORT_PLAN.md`). Three seams are built now, in Part A, so that phase needs no
rework:

- **A. A theme is data.**
  - `OrbitTokens` loads from one JSON format, written by
    `orbit/prototype/tools/themes.py`.
  - Built-in and downloaded themes use the same format.
  - Dart has no per-theme constants.
- **B. Effects are a fixed, named registry.**
  - The app contains the effect types: glow, scanlines, chat patterns, the
    cursor, ornaments, side stripes.
  - A theme turns effects on by name, with parameters.
  - A new effect type needs an app update; a later theme can reuse it.
- **C. Motion tokens are part of every theme.**
  - Durations and curves.
  - "Reduce motion" follows the system's accessibility setting.
  - Interface animations are built into the components in Part A: page
    transitions, a message rising when sent, reactions popping, swipe
    springs.
  - They must stay within the performance budgets: `performance_budget_test`,
    and no jank in long chat lists.

| Item | Tag | Notes |
|---|---|---|
| `OrbitTokens` (`ThemeExtension`) loaded from the theme JSON | derive | Replaces `HelixThemes.light()`. `themes.py` writes the JSON |
| Built into the app: Orbit and Orbit Night, with their fonts | derive | For offline use, first launch, and when a download fails |
| The other six themes: Bloom, Mochi, Papyrus, Arcade, Terminal, Field | engine | The first downloadable packs, which test the pipeline (Part C). The preview app loads all eight from local JSON |
| The effect registry, with each effect's parameters | derive | Fixed in the app; themes refer to effects by name |
| Motion tokens and reduce motion | derive | Part of the theme JSON. Reduce motion reads `MediaQuery.disableAnimations` |
| The chosen theme, kept on the device | local | New setting. Default Orbit. No day/night switching. When a chosen pack is missing or fails its checks, the app falls back to Orbit |
| `ThemeMode` follows the theme (light or dark); `highContrastTheme` is removed | derive | Decided 2026-10-17. Retires the "light theme only" rule and its `product_rules_test` |
| Icon weight per theme (`phosphor_flutter`) | derive | regular, light, duotone, bold |
| Fonts | derive | Only the built-in themes' fonts are bundled (Geist, Geist Mono). A pack carries its own fonts and comes from Orbit's own server, never from Google, so the privacy rule holds |
| The status bar and navigation bar icons follow the theme (Android) | derive | `SystemUiOverlayStyle` from the tokens |
| `MaterialApp.title` reads "Orbit" | derive | Today "Helix Remote" |
| Text size multiplies with the system's (`AppTextScale`) | have | `shared/widgets/app_text_scale.dart`. The Chats page's text size feeds it |

## 4. Hosts that wrap every screen (kept)

`main.dart` wraps the router in these hosts. They stay; only what they draw
changes style.

| Host | What it does | Orbit |
|---|---|---|
| `AppLifecycleHost` | Lifecycle: resume, sync | have, unchanged |
| `CallHost` | Keeps calls running under every screen and opens the full-screen call | have; the call screen is `calls.md` |
| `PhoneBookSyncHost` | Contact matching in the background | have; its prompts are in `home.md` |
| `AppLockGate` | The lock screen above the navigator; a live call gets through | have; drawn as the Orbit lock (`signin.md`) |
| `AppLinkListener` | Links from outside, refused with a reason while signed in | have; its messages are listed in `signin.md` and `home.md` |
| `UnconfirmedMemberHost` | Prompts about group members not yet confirmed | have; drawn in the Orbit style (`conversation.md`) |

## 5. Overlays

| Item | Tag | Notes |
|---|---|---|
| Sheet, menu, dialog and toast components | derive | Replace `helix_remote_ui/sheets_dialogs.dart` |
| On a window, a sheet is a centred dialog; a sheet from the composer pops up above its button | derive | |
| On a window, a menu hangs from its button | derive | Flutter's `MenuAnchor` does this natively |
| Toast with Undo, 2.8 s | have | `ScaffoldMessenger` with a `SnackBarAction`. On a window it centres under the right pane |

## 6. Global interactions

Each item in the "Every screen" section of `INTERACTIONS.md` belongs to the
frame:
- back arrow, Esc, tap outside, menu rows, Undo, toast timeout;
- right-pane memory, info pane, anchored menus, sheets as dialogs.

All are **derive**: frame code only, no data.

## The app does this, the prototype does not show it

| What | Where in the app | Suggestion |
|---|---|---|
| A splash while the database opens (the redirect waits) | `shared/widgets/startup_screen.dart` | Keep, in the Orbit style: the logo on `--bg` |
| A revoked device is sent back to sign-in | `_redirectFor` | Keep. Covered in `signin.md` |
| A new run starts on sign-in for an `https` server only | `main.dart` `_restoreServer` | Keep; nothing to draw |

## New backend work

None for the frame in Parts A and B. Part C adds a server endpoint that lists and serves theme, animation and ringtone packs (`PORT_PLAN.md`).
