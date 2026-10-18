# Orbit UI prototype (the Helix redesign, direction B)

This is the HTML prototype of the Helix redesign. It's only a front end, runs on
sample data, and touches nothing in `helix_remote/`.

## Open it

```
python serve.py
```

Then open http://127.0.0.1:5317. The server turns caching off, so a reload always
shows the latest edits. The screen you're on is kept in the address, so
`http://127.0.0.1:5317/#group` opens the group chat directly.

- **Phone, 960 or 1280** (top of the viewer) switches between the phone and
  the Windows window at two widths. Every screen works in all three.
- **Bare mode** draws only the device at true size, for screenshots and
  side-by-side comparison:
  `http://127.0.0.1:5317/?bare&device=window-l&theme=arcade#group`.
  `device` is `phone`, `window-m` or `window-l`; neither choice is saved.
- **Screenshots:** `python tools/shoot.py --device window-l chats group`
  (`--all` shoots every screen in `screens.json`). Images go to `shots/`.
- **Screen list:** `python tools/manifest.py` rewrites `screens.json` and
  `INTERACTIONS.md`:
  - `screens.json` lists every screen state with its key, parameters, the
    screens under it and where it opens on a window. It also holds each
    screen's interactions.
  - `INTERACTIONS.md` is the same interactions as a checklist.
  - Together they are the Flutter port's checklist.
  - The run fails when a screen has no `interactions` list.

- **Left panel:** every screen and state, grouped like the app.
- **Right panel (Tweaks):** live design settings (accent, bubble colour, avatar
  roundness, bubble roundness, chat background, density, text size, tap
  targets). They're saved in this browser only. Tell Claude which values to
  keep and they become the defaults in `css/tokens.css`.
- **Phone width:** the phone frame disappears and the prototype fills the
  screen.

Most of it is interactive:
- Swipe or tap between tabs, and swipe chat rows (pin, archive).
- Long-press chats and messages.
- Send messages and watch the ticks change; Nadia replies.
- Swipe a message to reply. Hold the mic to record.
- Place and answer calls.

## Design decisions (final, 2026-10-16)

- **Look:** B, calm surfaces with precise "future" details. The default Orbit
  theme is light, and seven more themes are listed under Themes below.
- **Colour:** Helix blue accent `#2563EB`, the app icon's blue
  (`HelixColorTokens.signInBlue`), so sign-in and the app now share it. Your
  own messages are pale cyan `#E1F7FC` with dark ink text.
- **Type:** Geist and Geist Mono at 100% text size. Mono is for times, status,
  labels and codes.
- **Icons:** Phosphor (`phosphor_flutter` in Flutter).
- **Shapes:**
  - Avatars are rounded squares at 25% (changed from 18% on 2026-10-18).
  - Bubbles have a 9 px radius (was 10 px), with one sharp 5 px corner on the first
    bubble of a run.
- **Chat background:** plain (`--chat-bg`). There's no pattern.
- **List density:** comfortable, with a 72 px chat row.
- **Navigation:** the floating dock with two tabs, Chats and Calls. Your round
  profile picture at the top-right opens You (settings and profile).
- **Name:** the product is called Orbit everywhere in the prototype. The logo
  is `assets/orbit-mark.svg`. The server domain and the `HLX-` code formats
  are unchanged: they are infrastructure, not design.
- **Header:** the "Orbit" wordmark in gradient replaces the tab titles. Your
  round profile picture (gradient ring, no name) at the top-right opens You,
  with an amber dot while the checkup needs attention.
- **You (settings and profile):** opens from the profile chip.
  - Your profile as an orbit (`SCREENS.md` design change 19): your photo is
    the planet, a ring in the wordmark gradient circles it, and your ~name,
    devices and E2E ride the ring. There is no card. Tapping it opens the
    profile editor; the QR button shares your code.
  - A privacy checkup that shows only what needs fixing.
  - Topic tiles with live status.
  - The profile editor previews your profile live and says who sees what.
- **Topic pages** (Privacy, Notifications, Chats, Storage, Devices, Backup,
  Account) follow the You style:
  - a summary card,
  - live previews (what others see, your lock screen, your text size),
  - inline segmented choices,
  - a danger zone. Only the active
  tab shows its label, in a dark pill. A round blue "new" button sits beside it
  on Chats and Calls. You specially liked this dock; keep it as it is.
- **Call screens:** the logo's teal-to-blue gradient, not black. White text
  stays readable at 5:1 or better.
- **Chats tab:**
  - Filter chips for All, Unread and Groups.
  - "Archived chats" lives in the ⋮ menu, not as a row in the list.
- **Scope:** exactly the app's features, plus the changes you approved. Those
  are listed at the top of `SCREENS.md` because the Flutter port has to build
  them.

These values are the defaults in `css/tokens.css` and `js/app.js`. The Tweaks
panel still works for trying variations, and Reset returns to them.

## Themes

There are eight themes. Pick one under You > Appearance, or in the Tweaks
panel:
- **Light:** Orbit, Bloom, Mochi, Papyrus
- **Dark:** Orbit Night, Arcade, Terminal, Field

Each changes colours, fonts, shapes, the chat pattern, icon weight and small
effects. Layout and the "Orbit" title stay the same.

The themes are defined in `tools/themes.py`. Run `python tools/themes.py` to
regenerate `css/themes.css` and `js/themes.js`. It prints a contrast report
and must say "0 contrast failures". The Tweaks panel's accent, bubble and
shape controls only affect the Orbit theme.

## Windows layout

Windows 840 px and wider show the list on the left (380 px) and the picked
chat or page on the right. From 1200 px, contact and group info open in a
third pane beside the chat. Calls, the media viewer and the sign-in box cover
the window. `SCREENS.md` design change 15 has the details. The `PLACEMENT`
table in `js/app.js` says where each screen opens.

## Files

| File | What it is | Becomes in Flutter |
|---|---|---|
| `css/tokens.css` | The Orbit theme's tokens and every semantic role | `helix_remote_ui` tokens and `ThemeData` |
| `css/themes.css` | GENERATED: all eight themes' tokens and effects | one `ThemeExtension` per theme |
| `tools/themes.py` | The theme table, generator and contrast check | the source for the Dart theme table |
| `css/components.css` | Avatar, chat row, dock, rows, sheets, dialogs, snackbar | `helix_remote_ui` widgets |
| `css/screens.css` | Bubbles, composer, timeline, call screen | `helix_remote_ui` chat and call widgets |
| `css/window.css` | The Windows layout: panes, title bar, sign-in box, overlays on a window | `OrbitWindowScaffold` and the wide routes |
| `css/pages.css` | Fields, segmented controls, notices, QR, code boxes, sign-in, settings-style pages | `helix_remote_ui` form and page widgets |
| `js/ui.js` | Component functions that take view-model-shaped data | `HelixChatListTile`, `HelixMessageBubble`, … |
| `js/kit.js` | Page kit: field, segmented, notice, intro, QR, code box, progress, checkbox, section, switch and choice rows, and the You-style parts (page, summary card, status ring, steps, rules, danger zone) | `HelixTextField`, `InlineNotice`, `KeyCodeDisplay`, `OrbitSummaryCard`, … |
| `js/data.js` | Sample data shaped like `view_models.dart` | (the app's real providers) |
| `js/screens/*.js` | Screens and their states: `signin`, `home`, `conversation`, `chat_pages`, `calls`, `people`, `groups`, `settings`, `devices_backup`, `you`, `topics` | `features/*/presentation` |
| `assets/orbit-mark.svg` | The Orbit logo mark (sign-in, viewer) | the new app icon |
| `assets/logo.png` | The old Helix logo (no longer used) | — |
| `js/app.js` | Prototype engine: page stacks, the window panes and `PLACEMENT`, overlays, index, tweaks | `PLACEMENT` becomes the wide-window routes; the rest is not ported |
| `screens.json` | GENERATED by `tools/manifest.py`: every screen state, and every screen's interactions | the port's checklist |
| `INTERACTIONS.md` | GENERATED: the interactions as a checklist (266 items) | one widget test per item |
| `tools/shoot.py` | Screenshots any screen, device and theme with headless Chrome | the compare tool's HTML side |
| `SCREENS.md` | Every screen, state and line of copy in the real app | the checklist |

## Status

The prototype covers every screen in `SCREENS.md`: 181 screens and states in
the left panel, all reachable from each other the way the app links them, on
the phone and in the Windows window.

- **Sign-in:**
  - Phone, SMS code, password, name and take-over.
  - The personal-server code with server confirmation, and the hidden
    advanced corner (three taps, bottom right).
  - The legal sheet, the restore step, link this device (with "Is this your
    account?"), the reset screens and the app lock.
- **Home:** Chats (search, people panel, selection, swipe, archived), Calls
  (log, quick actions, dial pad, details) and Settings (search).
- **Conversation:**
  - Every message kind and every composer state.
  - Message actions, swipe to reply, search in chat, the blocked and left
    states, and unconfirmed members.
  - Sub-pages: forward, message info, media viewer and video player, send
    files, shared media and chat settings.
- **Calls:** incoming, calling and ringing, connecting, voice, video, poor
  connection, reconnecting and the ended reasons.
- **People:** the people search page, contact info (rename, mute,
  disappearing, report, block), safety number and scan.
- **Groups:** new group with the member picker, group info (owner, admin and
  member views), group settings, invite links, join requests, banned people,
  add members and join by link.
- **Settings:** account, change or set a password, delete account, privacy,
  blocked, notifications, chats, storage, help and about, legal, advanced, and
  profile.
- **Devices:** the list with its device sheet, approving a new device, and
  security activity.
- **Backup:** the backup page, restore history, sending to your other devices,
  and the recovery backup.

Every settings page now uses the You style (`SCREENS.md` design change 16).

Phase 0 of `../PORT_PLAN.md` is complete and approved (Review 0, 2026-10-18).
- Then the Flutter port, but only when you say the design is final.
