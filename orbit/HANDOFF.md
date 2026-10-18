# Orbit: start here (handoff, 2026-10-18)

For any agent picking up the Orbit redesign. Read this first, then the files
below in order.

## Where things stand

| Phase (`PORT_PLAN.md`) | State | Commit |
|---|---|---|
| 0: freeze the prototype (Windows layout, restyled pages, interactions) | approved | `c623f15` |
| 1: contracts and the gap list | approved | `eeb1eb2` |
| 1b: the state kit, and the Review 1 answers drawn | approved | `da028d3` |
| **2: the Flutter foundation** | **next; not started** | |
| 3, 4: components, then 10 screen batches | later | |
| Part B: into `helix_remote/` | only when the owner says so | |
| Part C: downloadable themes, animations, ringtones | after Part B | |

**Nothing under `helix_remote/` has been changed by this work.**

Separately, four bugs in the live app (B1 to B4 in `GAPS.md`) have a proposed
fix session. It has not been started, so they are not fixed. That is
`helix_remote` work and needs the `helix-feature` process.

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

## What Phase 2 is (the next job)

From `PORT_PLAN.md`, Phase 2, in short:
1. **A Flutter workspace at `orbit/flutter/`.**
   - `packages/orbit_ui` holds the design system and every screen.
   - `apps/orbit_preview` is the Flutter twin of the HTML viewer.
   - Use the same Flutter/Dart versions and lints as `helix_remote/`. Do
     not upgrade Flutter.
2. **Themes are data.**
   - `prototype/tools/themes.py` also writes one JSON per theme.
   - `OrbitTokens` (a `ThemeExtension`) loads that JSON.
   - Dart has no per-theme constants.
3. **Fonts and icons.**
   - Bundle only Orbit and Orbit Night's fonts: Geist and Geist Mono.
   - The preview loads the other themes' fonts from local files.
   - Icons come from `phosphor_flutter`.
4. **Motion tokens and an effect registry.** Effects are painters a theme
   turns on by name: patterns, glow, scanlines, cursor, ornaments, stripes.
5. **The preview app shell:**
   - the screen index with the same keys as `prototype/screens.json`;
   - a theme picker;
   - a 412×866 phone frame, plus the 960 and 1280 windows.
6. **The compare tool:**
   - prototype screenshots side by side with Flutter screenshots, an overlay
     slider and a difference score;
   - it must wait for the page to be ready (see the gotchas).
7. **Stop at Review 2:** the theme gallery in all eight themes, plus the
   compare tool working on one screen.

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
    loaded, so a shot can come out blank or unstyled. Retake it; the
    Phase 2 compare tool must wait for readiness.
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
