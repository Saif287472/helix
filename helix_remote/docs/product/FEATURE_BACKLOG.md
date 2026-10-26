# Orbit feature backlog (WhatsApp-style feature sets)

Status: written 2026-10-26 from four feature lists the user supplied, sized
against the code as it stands. Sizes are estimates from reading the code, not
from building; re-check a row before starting it.

## How to read this

**Size** (what a one-day build plan counts):

- **S, one file**: a single widget, copy, setting or engine tweak. No contract change.
- **M, about 10 files**: one slice (app provider + page + `orbit_ui` screen + engine call + tests).
  The wire format, schema and server are not touched.
- **L, more than that**: crosses layers or triggers a heavy checklist: new wire type or route (protocol
  fixtures, api client, server module, engine, app), a server migration, a local DB schema bump
  (5 to 6: step migration, schema dump, codegen), crypto (test vectors plus a design-review note), a new
  package, or a change to the target architecture (ADR).

**Status**: Built (exists end to end), Partial (engine or protocol exists, UI or a piece is missing),
Not built.

This backlog is a menu, not a plan: any row may be dropped because it does not fit the product direction.
Rules that apply to every row: English only; theme colours only; `IconButton` tooltips and 48 px targets;
screenshots stay allowed (so "cannot be screenshotted" is not a feature here); never `helix_local/`;
no APK builds (say whether one is needed); say which migration or `.env` line is new.
Path shorthand: `app/` = `helix_remote/app/lib`, `ui/` = `helix_remote/packages/orbit_ui/lib/src`,
`engine/` = `helix_remote/packages/helix_remote_engine/lib/src`, `proto/` =
`helix_remote/packages/helix_remote_protocol/lib/src`.

## Summary

| Size | Count | Features |
|---|---|---|
| Already built | 26 | see "Already built" |
| S (one file) | 1 | B2 |
| M (about 10 files) | 10 | A4, A6, A9, A10, B4, B8, C1, C5, C7, E4 |
| L (more than that) | 10 | A3, A5, A7, A8, A13, B3, C3, C4, D1, D2 |
| L+ (a project of its own) | 5 | D3, D4, D6, E1, E2 |
| Not planned | 5 | see "Not planned" |

## Already built (no work; listed so they are not requested twice)

| Feature | Where |
|---|---|
| Edit sent message (15 min window) | content `edit`; `engine/messaging/`; `ui/screens/chat/` |
| Delete for everyone | content `delete` |
| Reactions (any emoji) | content `reaction` |
| Reply and threading | `reply` field |
| Disappearing messages (`exp`) | content `exp`, `timer_changed` system row |
| View-once media | `flags.view_once`; enforced locally |
| Typing indicators | `typing`, ephemeral frame |
| Read and delivered receipts, with a global toggle | content `receipt`; `sendReadReceipts` setting |
| Last seen, profile photo and about audiences | `Audience` in `proto/modules/people.dart`; privacy page |
| Forward | `app/features/conversation/presentation/forward_screen.dart` |
| Mute, archive, pin chat | `conversations.pinnedAt`; chats tab |
| App lock | `app/core/security/app_lock.dart` |
| Multiple accounts on one phone | `settings/presentation/accounts_page.dart` |
| Safety number (key fingerprint) verification | engine `safety_number_changed`; contact info |
| Linked devices, revoke, security activity | `features/devices/` |
| Encrypted backup and restore, device-to-device transfer | `features/backup/` |
| Hashed phone discovery, `~name`, share link `/u/<name>` | `people` module |
| Storage page (free space by kind), report user, block | `settings/storage_page.dart`, reports in server |
| Text formatting `*bold*` `_italic_` `~strike~` `` `mono` `` (built 2026-10-26, A1) | `orbit_ui` `components/timeline.dart` `_formatted` |
| Find a group by the name of someone in it (built 2026-10-26, B7) | `app/features/chats/application/chat_search.dart` |
| Echo cancellation, noise suppression, auto gain on calls (built 2026-10-26, D5) | `helix_remote_calls` `web_rtc_call_engine.dart` |
| Clear chat history (B5) and the "online" audience (C2) | `conversation_settings.dart`; `PrivacySettings.online` |
| Personal server, server switching, anomaly log | sign-in advanced mode; `core/diagnostics/anomaly_log.dart` |

## A. Messaging and expression

| ID | Feature | Status | Size | Probable files (and why) |
|---|---|---|---|---|
| A1 | Text formatting (bold, italic, strike, mono) | **Built 2026-10-26** | done | `orbit_ui` `timeline.dart` (`_formatted`, WhatsApp word-edge rules, markers hidden, wire text stays plain), test `orbit_ui/test/message_formatting_test.dart`. Not done: composer toolbar buttons, formatting in chat-list previews and notifications (they show the markers). |
| A2 | Polls: draw, create and vote | **Built 2026-10-26** | done | `orbit_ui` `timeline.dart` (`_Poll`), `compose_pages.dart` (`OrbitNewPollPage`), `chat_screen.dart` (attach sheet, `onVote`, `onCreatePoll`); app `message_mapper.dart`, `chat_gateway.dart`, `message_actions.dart`, `conversation_screen.dart`. Tests: `orbit_ui/test/polls_events_test.dart`, `app/test/poll_event_flow_test.dart`. Not done: closing a poll (honoured when received, not offered), who voted. |
| A3 | Pin message in a chat | Not built | **L** | A pin is shared state, so it needs a new content action `pin` (proto `bodies/actions.dart`, CONTENT_V2.md, fixtures, `HELIX_UPDATE_FIXTURES=1`), engine apply (`messaging/apply.dart`), a `messages` column (`pinnedAt`: **DB schema 6**, codegen), app banner and menu. Local-only pin would be M (DB column plus UI) but would not show to the other side. |
| A4 | Starred (saved) messages | Not built (engine keeps none) | **M** | Local only: `messages.starred` column means DB schema 6 (if bundled with A3, one bump), DAO query, engine service method, app Starred page and menu entry, `ui/` screen. Counts L if it is the only thing bumping the schema. |
| A5 | Stickers and animated emoji | Partial (`sticker` type exists, UI "needs newer version") | **L** | Draw sticker bubble; sticker picker and packs (storage, download, a pack format like `THEME_PACK_FORMAT.md`); sticker maker (image to webp via `FlutterMediaProcessor`); send path in engine. New pack format means a doc and tests. |
| A6 | GIF picker | Partial (GIF attachments exist) | **M** | A provider (Tenor or Giphy) leaks the query to a third party and breaks the privacy claims; only an in-app saved-GIFs list is safe. Needs a privacy decision first. |
| A7 | Live and motion photos | Not built | **L** | Picker plugin support on Android, `MediaSanitizer` handling of the embedded video, a new `MediaItem` kind (proto change plus fixtures), viewer. Sizeable and low value. |
| A8 | Voice message transcripts (on-device) | Not built | **L** | Needs an on-device speech model (new plugin and platform code, large download), an adapter file in `app/core/platform/`, a transcript store (cache or DB column), UI on the voice bubble. Privacy gain is that nothing leaves the phone. |
| A9 | Rich link previews | Partial (`link_preview` in text body) | **M** | Fetching the URL from the sender's phone is a metadata leak to the site; app, composer and bubble work. Decide the privacy stance first. |
| A10 | Edit revision history | Not built | **M** (was S) | "Edited" already shows. The engine overwrites `messages.body` and keeps only `editedAt`, so a revision list needs a table or column: **DB schema 6**, DAO, engine apply and send paths, backup snapshot, `message_info_screen.dart`. |
| A11 | Media draft with caption, waveform, duration, view-once | Built (send-files page, composer) | n/a | Nothing to do. |
| A12 | Transfer progress (0.0 to 1.0) | Built (transfer queue with progress) | n/a | Nothing to do. |
| A13 | RAM-only ephemeral files | Not built | **L** | Today view-once files are on disk until opened, then deleted. True RAM-only means a decrypt-to-memory viewer, no cache writes (`MediaTemp`, `media_viewer_screen.dart`, video player cannot play from memory, so images only). Document the limit honestly in `PRIVACY_CLAIM_MATRIX.md`. |

## B. Chat organisation and personalisation

| ID | Feature | Status | Size | Probable files |
|---|---|---|---|---|
| B1 | Chat wallpapers (local, per chat or default) | **Built 2026-10-26** | done | `orbit_ui` `components/wallpaper.dart` (`wallpaperLook`, `showOrbitWallpaperSheet`), `chat_screen.dart`, `chat_pages.dart` (chat settings row), `you_screens.dart` (Appearance row); app `shared/wallpaper.dart`, `app_settings.dart`, `conversation_settings.dart`, `conversation_screen.dart`, `appearance_page.dart`. Tests: `orbit_ui/test/wallpaper_test.dart`, `app/test/wallpaper_test.dart`. Six theme-coloured wallpapers; no photo wallpapers (they need a picker, a sanitised local copy and storage). Account settings, not device settings. |
| B2 | Custom chat bubble colours | Partial (Orbit theme tokens) | **S** | Theme tokens only; a per-chat colour is M. Must come from `OrbitTokens`. |
| B3 | Custom lists and filters (folders) | Not built | **L** | `conversation_lists` plus members tables: **DB schema 6**, DAO, engine `chats_service.dart`, chats-tab chips, manage-lists screen in `ui/`, backup (lists should survive restore: `backup` crypto payload change, a note in the crypto review). Local-only without backup is M. |
| B4 | Favourites | Not built | **M** | Like pin chat but a flag: a `favourite` column (schema 6), filter chip in chats tab. Can be the first built-in list of B3. |
| B5 | Clear chat history and purge media | **Already built** | n/a | `ConversationSettings.clear()` and `ChatGateway.clearChat`; the storage page frees media. |
| B6 | Per-chat notification policy | Built (per-chat mute; overrides on the chat) | n/a | Nothing to do. |
| B7 | Group search by mutual contact names | **Built 2026-10-26** | done | `chat_search.dart` (`memberNamed`), test `app/test/chat_search_members_test.dart`. Not done: the same match inside the People tab. |
| B8 | Group admin controls (who can edit info, send, add) | Partial (roles and group settings exist) | **M** | Check `group_settings_screen.dart` and `groups` module for "announcement only" and "who can add"; each missing switch is a state field (protocol `modules/groups.dart`, server `groups`, engine, app). |

## C. Privacy and security

| ID | Feature | Status | Size | Probable files |
|---|---|---|---|---|
| C1 | Silence unknown callers | Not built | **M** (was S) | A setting (`app/core/security/app_settings.dart`, `settings_providers.dart`, `privacy_page.dart`, the `orbit_ui` privacy topic screen) plus a rule in the engine `calls_service.dart` beside `_isBlocked` (a caller not in the people list: no ring, still logged as missed) and its tests. Decide first whether this fits "anyone can call anyone". |
| C2 | Show your own "online" separately | **Already built** | n/a | `PrivacySettings.online` and the privacy page row. |
| C3 | Chat lock (per-chat biometric lock, hidden list) | Not built | **L** | `conversations.locked` (schema 6); a Locked folder in the chats tab; biometric prompt (`app_lock.dart` generalised); redacted notification previews (`core/notifications/`); excluded from search and from `watchSharedAttachments`; a note that backup contains locked chats. |
| C4 | Passkeys (WebAuthn) in place of SMS | Not built | **L** | New identity endpoints (server `identity` module, `proto/modules/identity.dart`, fixtures), a platform plugin, recovery-flow changes. A new auth mechanism: needs an ADR and crypto review note. Do not weaken the password-derived key rule. |
| C5 | Biometric-protected backup key | Not built | **M** | Keystore wrapper in `app/core/security/`, backup page toggle; engine untouched. |
| C6 | Usernames in place of numbers | Built (`~name`, share link, "find me by ~name") | n/a | Nothing to do. |
| C7 | Data export (account report) | Partial (chat export exists; account report missing) | **M** | Server `compliance` module report route (new route: public-route snapshot and fixtures), api client method, engine, settings page. |
| C8 | Contact share links with expiry and pre-approval | Contradicts a product rule | n/a | The app has no contact requests by design. The `/u/<name>` link exists; expiry only is M. |
| C9 | Report with context hashes, admin moderation | Built (reports module, admin console) | n/a | Nothing to do. |

## D. Calls and meetings

| ID | Feature | Status | Size | Probable files |
|---|---|---|---|---|
| D1 | Screen sharing (1:1) | Not built | **L** | `helix_remote_calls` (WebRTC capture, Android foreground-service permission), call signalling field, call screen controls in `ui/screens/calls/`, platform manifests. |
| D2 | Call transfer between devices | Not built | **L** | Multi-device call handoff in the calls state machine (engine `calls`), a signal type, server calls module, UI. |
| D3 | Group calls | Not built (deferred by the plan) | **L+** | Needs an SFU and the `group_calls` module; the plan reserves room. Needs its own plan and ADR; not a one-day item. |
| D4 | Call links, waiting room, scheduled calls with RSVP | Not built | **L+** | Server module and routes, `event` type exists for RSVP, but joining rooms needs group calls (D3). |
| D5 | Noise suppression, QuickHD | **Noise suppression built 2026-10-26** | done | `web_rtc_call_engine.dart` `getUserMedia` audio constraints (echo cancellation, noise suppression, auto gain). QuickHD (a fast first video resolution) is not done. No test: it needs a real microphone. |
| D6 | Web calling (browser) | Not built | **L+** | A web client; the engine is pure Dart, but a web app, Wasm drift and a WebSocket story are a new project. |

## E. Communities, channels, platform

| ID | Feature | Status | Size | Probable files |
|---|---|---|---|---|
| E1 | Communities (umbrella of groups) | Not built | **L+** | New server module, protocol, engine and app feature; new package registrations in `architecture_rules`. Plan and ADR first. |
| E2 | Channels (one-way broadcast) | Not built | **L+** | Unencrypted or fan-out model conflicts with the E2EE design; needs an ADR. |
| E3 | Group events and RSVPs | **Built 2026-10-26** | done | Same slices as A2 (`_Event`, `OrbitNewEventPage`). Not done: end time, plus-ones, calendar export. The zone is sent as `UTC±HH:MM` (documented in CONTENT_V2.md). |
| E4 | Live location | Partial (engine; no updates sent) | **M** | Location plugin, send updates, map-less bubble. Permissions and battery need a decision. |

## F. AI

| ID | Feature | Status | Size | Notes |
|---|---|---|---|---|
| F1 | Meta AI assistant, summaries, AI photo editing, AI themes | Not planned | n/a | Any server-side AI sees plaintext and breaks the end-to-end claim. Only an on-device model (large download) could fit, which is L+ and a separate decision. |

## Not planned (and why)

- View-once that "cannot be screenshotted": screenshots are allowed everywhere by product rule.
- Contact request workflows: there are no contact requests by design.
- AI features that send content to a server (F1).
- Third-party GIF or sticker search that leaks queries (A6) until a privacy design exists.
- Channels and Communities as designed by WhatsApp (E1, E2) without an ADR.

## Suggested one-day batches

Given the sizes above, one day (a gate of analyze and tests after each step) fits roughly:

1. **Morning, small wins:** A1 formatting, B7 group search, D5 noise suppression (done 2026-10-26).
2. **Midday, two M slices:** A2 polls UI (pairs with E3 events), B1 wallpapers.
3. **Afternoon, one L that shares a single schema bump:** DB schema 6 carrying A3 (pinned message),
   A4 (starred) and B4 (favourites) together, one migration and one codegen run.

Not in this batch: C3 chat lock, C4 passkeys, D1/D2 calls, A5 stickers, A8 transcripts. Each needs its own day or more.

## Open questions for the user

1. ~~Is "Orbit" the new name of the whole product?~~ Answered by `main` (2026-10-26): the rename so far is
   user-facing copy only ("Orbit", "Orbit Global", "an Orbit user" in the app and the admin console).
   Package, folder, route and doc names stay `helix_*`. New copy in this backlog's features says Orbit.
2. A6, A9: may the app contact a third party (GIF search, link previews)? Today it contacts none.
3. A3: should a pin be shared with the other side (needs a wire change) or only for you?
4. F1: is an on-device model acceptable, or are AI features out?

## Adding a feature later

Append a row to the right table with: ID, what the user sees, status, size, and the probable files and
why. Move it to "Already built" when it ships. Check `ARCHITECTURE_V2_PLAN.md` sections 3 to 6 first; a
change to those needs an ADR in `helix_remote/docs/adr/`.
