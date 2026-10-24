# Helix Admin prototype (Orbit design language)

This is the HTML prototype of the Helix Admin redesign. It is a front end on
sample data and touches nothing in `helix_remote/`. There is no Dart or
Flutter work here; the design is reviewed in the browser first.

## Open it

```
python serve.py
```

Then open http://127.0.0.1:5318. The server turns caching off, so a reload
always shows the latest edits. The screen you are on is kept in the address, so
`http://127.0.0.1:5318/#users` opens Users & Devices directly.

- **Phone, 960 or 1280** (top of the viewer) switches between the Android
  layout and the Windows window at two widths.
- **Bare mode** draws only the device at true size, for screenshots:
  `http://127.0.0.1:5318/?bare&device=window-l#ops_reports`.
  `device` is `phone`, `window-m` or `window-l`; neither choice is saved.
- **Invites** only exist on servers in invite mode. The sample server registers
  by phone, so add `?invites=1` to see those screens:
  `http://127.0.0.1:5318/?invites=1#invites`.
- **Screenshots:** `python tools/shoot.py --device window-l users account`
  (`--all` shoots every state in `screens.json`). Images go to `shots/`.
- **Screen list:** `python tools/manifest.py` rewrites `screens.json` and
  `INTERACTIONS.md`; it runs the scripts in Node, so it needs no browser.

## Design direction: Orbit

The console keeps every real Helix Admin feature but adopts the Orbit product's
visual language.

- **Header.** A gradient `Helix Admin` wordmark on the page background, a
  floating server-status chip on the right (dot plus server name, opens
  Overview), and the places as a segmented pill group on Windows.
- **Phone navigation.** Orbit's floating dock: a rounded white pill above the
  bottom edge with a soft fade behind it. The active place is a dark pill with
  its icon and label; the other places show their icons alone.
- **Window navigation.** The same places sit in the header as pills; the active
  one is the dark pill. Invites joins them only on invite-mode servers.
- **Surfaces.** White cards with 16 px corners and a hairline, `#F4F6F9` page
  background, pill buttons, pill search fields, 28% rounded-square avatars.
- **Type.** Geist for text, Geist Mono for ids, times, log lines and codes.
- **Colour.** Helix blue `#2563EB`; state colours keep their meaning (green
  operational, amber warning, red destructive). There is one light theme.
- **Density.** Console rows stay compact (52 px), so the admin pages hold more
  than the phone app while sharing its shapes.

## Screens and features

The real admin navigation is preserved:

- **Overview:** six live tiles, service health, this server.
- **Users & Devices:** search and status filters; an account opens beside the
  list on a window and as a page on a phone. Account detail covers identity,
  devices with revoke, recovery code, suspend, resume, ban and delete.
- **Ops & Logs:** Reports, Audit, Logs and Config in one segmented control.
  Reports resolve or dismiss and link to the account. Logs stream, pause,
  filter and copy. Config edits the server name, worldwide mode, maintenance,
  app lock and password, feature flags and the admin session.
- **Invites:** create a one-time code (shown once), cancel open invites.
- **Access:** server address, then password or first-run password setup; wrong
  password; the app-lock screen.

Every list has loading, empty and error states where they matter. The
dashboard also has not-ready and offline states, and configuration has
maintenance on.

`SCREENS.md` is the full checklist: every screen, state and the copy that
belongs to it.

## Files

| File | What it is |
|---|---|
| `index.html` | The device frame, header, floating dock and script order |
| `css/tokens.css` | One light theme's tokens and semantic roles |
| `css/components.css` | Base components: avatars, rows, switches, dialogs, snackbar |
| `css/pages.css` | Fields, notices, QR, code boxes and settings-style pages |
| `css/console.css` | The admin frame and pages: header, dock, metrics, users, Ops, invites, access |
| `css/viewer.css` | The prototype viewer around the device (not part of the design) |
| `js/ui.js` | Component functions that take view-model-shaped data |
| `js/kit.js` | Fields, segmented controls, notices, cards and dialogs |
| `js/data.js` | Sample data for one morning (22 Oct 2026, 11:42) |
| `js/app.js` | Page stack, overlays, place table and manifest |
| `js/shell.js` | Place navigation, server chip, sign-out and lock |
| `js/screens/*.js` | `overview`, `users`, `ops_reports`, `ops_audit`, `ops_logs`, `ops_config`, `invites`, `signin`, `kit` |
| `assets/console-mark.svg` | The console mark on the sign-in card |
| `screens.json` | GENERATED: every screen state and its interactions |
| `INTERACTIONS.md` | GENERATED: the interactions as a checklist |
| `tools/shoot.py` | Screenshots any screen, device and state with headless Chrome |
| `tools/manifest.py` | Writes `screens.json` and `INTERACTIONS.md` |
| `SCREENS.md` | Every admin screen, state and line of copy |

## Status

The prototype covers the admin console's real screens: **43 screen states in
11 screens**, every state reachable from the screen index, on the phone and in
the Windows window. The screen index, the manifest and the screenshot tool all
work from the same registrations.

This is the version to review before any implementation work. Start with
`shots/overview.phone.png`, `shots/overview.window-l.png` and
`shots/users.window-l.png`.
