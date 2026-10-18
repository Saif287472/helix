# Orbit: start here (handoff, 2026-10-18)

For any agent picking up the Orbit redesign. Read this first, then the files
below in order.

## Where things stand

| Phase (`PORT_PLAN.md`) | State | Commit |
|---|---|---|
| 0: freeze the prototype (Windows layout, restyled pages, interactions) | approved | `c623f15` |
| 1: contracts and the gap list | approved | `eeb1eb2` |
| 1b: the state kit, and the Review 1 answers drawn | approved | `da028d3` |
| 2: the Flutter foundation | approved (Review 2) | see `git log` |
| **3: the components** | **done: 3.1 approved; 3.2 to 3.5 pending review** (`PORT_PLAN.md`) | see `git log` |
| 4: 10 screen batches | later | |
| Part B: into `helix_remote/` | only when the owner says so | |
| Part C: downloadable themes, animations, ringtones | after Part B | |

**Nothing under `helix_remote/` has been changed by this work** (the B1 to B4
fixes below were separate `helix_remote` work).

Separately, four bugs in the live app (B1 to B4 in `GAPS.md`) were fixed in
`helix_remote` commit `95407da` (2026-10-18): disappearing messages now start
their timer on display, take-over can finish on Helix Global, the reset screen
no longer treats every startup error as "could not be decrypted", and the
recovery-secret route after sign-in is reachable. They were done through the
`helix-feature` process. B5 to B13 remain open.

## Read in this order

1. `PORT_PLAN.md`, the plan of record:
   - the decisions table;
   - every phase, with its progress checkboxes;
   - "Rules for every agent". These go into `orbit/flutter/AGENTS.md` in
     Phase 2.
2. `prototype/README.md`: how to run the prototype, its tools, the design
   decisions and the file map.
3. `prototype/SCREENS.md`:
   - the app's feature checklist;
   - "Design changes you approved", items 1 to 20.
4. `contracts/README.md`, then the eight contracts. Each ends with
   "Decisions and Phase 1b".
5. `GAPS.md`: everything Review 1 decided, and what to build or not build in
   Part B.
6. `prototype/INTERACTIONS.md`: 307 behaviours. Each one becomes a widget
   test.
7. The repo's `AGENTS.md` at the root. Its rules apply in full.

## Phase 2, as built (approved at Review 2)

`PORT_PLAN.md`, Phase 2, has the checklist. In short:
- **`orbit/flutter/`** is the workspace. `packages/orbit_ui` is the design
  system (tokens, theme, fonts, icons, the logo, motion, the effect registry,
  the first screen, `OrbitStartup`). `apps/orbit_preview` is the viewer,
  built for Windows.
- **Themes are data.** `prototype/tools/themes.py` writes
  `packages/orbit_ui/assets/themes/*.json`, and `OrbitTokens` loads them.
- **Fonts.** A family that `orbit_ui` bundles is
  `packages/orbit_ui/<family>` to Flutter; always go through
  `OrbitFontStack.family` or `.style()`, never a bare family name. The
  preview registers the six pack themes' fonts with `OrbitFonts.registerPack`.
- **The compare tool** (`flutter/tools/compare/README.md`): `shoot_html.py`
  for the prototype, `orbit_preview.exe --shoot <key>` for Flutter, and a
  report page. A screen is ported by adding it to
  `apps/orbit_preview/lib/ported.dart`.
- **Not done:** the effect painters (pattern, scanlines, cursor, rules,
  stripes) move to Phase 3; the Windows title bar arrives with the window
  layouts.

Next: Phase 3 (the components), only when the owner says so.

## Rules that matter most

- **The prototype is the specification.** Sizes, colours and spacing come
  from its CSS and tokens, never from guesses. Anything that can't be
  matched goes in `DEVIATIONS.md`, and you ask the owner.
- **A screen never reads providers, the database, the router or the
  engine.** Model in, actions out (`contracts/`).
- **Small batches, stop at each review.**
  - After the owner approves a batch, commit all uncommitted work, with
    `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
  - Never push.
- **Never touch `helix_local/`.** Production (Helix Global) runs on the
  owner's PC: never stop or restart it, and never run deploy scripts.

## Gotchas found the hard way

- **Shell.** It is Git Bash on Windows; every command prints an "ng
  completion" warning, so ignore it. Heredocs with apostrophes, `\b` or
  `\n` break or write control characters into files. Write multi-line
  patches as a Python file with the Write tool, then run it with
  `python -I`.
- **Prototype server.**
  - `python prototype/serve.py` serves on port 5317.
  - A side session may already serve it there; just use it.
  - Launch config: `helix-prototype` in `.claude/launch.json`.
- **Screen list.** `python prototype/tools/manifest.py` writes
  `screens.json` and `INTERACTIONS.md`.
  - It runs the scripts in Node (`tools/manifest_node.js`), with no
    browser.
  - It refuses to write if any screen is missing or has no `interactions`
    list.
- **Screenshots.**
  - `python prototype/tools/shoot.py --device phone|window-m|window-l --theme <id> [--query scroll=760] <keys>`.
  - Run one at a time (the default).
  - Headless Chrome sometimes captures a page before every script has
    loaded, so a shot can come out blank or unstyled. Retake it, or use
    `flutter/tools/compare/shoot_html.py`, which waits for readiness.
  - Phone shots are 640 px wide with the phone at the left.
- **Bare mode.** `?bare&device=…&theme=…&scroll=…#key` shows one screen alone.
- **Reduce motion.** The in-app browser pane has it on. Never use
  near-zero transitions on every element: colours freeze when frames don't
  run. Turn animation and transitions off instead.
- **Prototype screens.** Each screen's interactions live next to its code
  (`interactions: [[gesture, on, does, layout?]]`), and a new screen needs
  that list.
- **Themes.** `python prototype/tools/themes.py` regenerates
  `css/themes.css` and `js/themes.js`. It must report "0 contrast failures".
- **The state kit.** Lists use `Kit.skeleton`, pages `Kit.loading`, and
  failures `Kit.loadFailed`. Also `Kit.permission`, `Kit.fieldLock`, and
  `App.snack(text, action, {tone: 'error'})`. Never draw a one-off loading
  or error state.

## Owner preferences

- Plain English.
- Ask before decisions that are theirs.
- Show screenshots at reviews.
- Before large or outward-facing steps, propose and wait. Nothing goes into
  the main app before Part B.
