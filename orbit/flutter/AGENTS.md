# Orbit: working on this workspace

This file is the rules for the Orbit port. It is here because `orbit/` is
outside `helix_remote/`, so the app's own `AGENTS.md` does not reach it. The
repository's root `AGENTS.md` still applies in full — read it first.

What is being built, and in what order, is `orbit/PORT_PLAN.md`. The plan of
record; its checkboxes are the state of the work. `orbit/HANDOFF.md` is the
starting point for anyone picking this up cold.

## The one rule that makes Part B safe

**A screen never reads a provider, the database, the router or the engine.**
It gets two things, and nothing else:

- a **model**: plain immutable values, every clock or locale string already
  formatted;
- an **actions** object: callbacks such as `openChat(id)`, `archive(ids)`,
  `send(text)`.

Platform-heavy things (camera, QR scanner, video, call video, file picker) come
in as **slots** the app fills; the preview shows placeholders. Anything only
that one screen needs — which sheet is open, scroll position, the text being
typed, animations — stays inside the widget.

The contracts in `orbit/contracts/` are the seam, written per feature. Phase 4
turns each table into Dart exactly as written (`<Name>Model`, `<Name>Actions`,
`<Name>Screen`).

## Rules for every agent on this work

- **The prototype is the specification.** Before building a screen, read its
  JS and the CSS rules it uses. Sizes, spacing, corners, font sizes and colours
  come from there, and from tokens, never from typed values.
- **Don't invent.** If something isn't in the prototype, stop and ask. If
  something can't be matched in Flutter, write it in `orbit/DEVIATIONS.md` and
  ask.
- **Use the same screen keys** as the prototype (`prototype/screens.json`).
- **Stay out of the app until Part B.** Nothing under `helix_remote/` changes
  before Part B. Nothing under `helix_local/` changes, ever.
- **A batch isn't done** until its compare page is clean and the owner has
  approved it.
- **Keep batches small** and stop at each review.
- After the owner approves a batch, commit all uncommitted work. Never push.
- **Never stop or restart production.** Helix Global runs on the owner's PC;
  never run a deploy, install or release script.

## Themes are data

There is **no per-theme constant in Dart.** `prototype/tools/themes.py` writes
one JSON file per theme; `OrbitTokens` (a `ThemeExtension`) loads that JSON.
Built-in themes and downloaded theme packs share one format, because only data
is ever downloaded (Part C). A theme turns effects on **by name** through a
fixed registry — the app ships the effect types, packs carry their settings.

## Running the prototype

- `python orbit/prototype/serve.py` serves on port 5317. A side session may
  already serve it; just use it.
- `python orbit/prototype/tools/manifest.py` rewrites `screens.json` and
  `INTERACTIONS.md`. It needs Node, not a browser, and it fails if any screen
  has no `interactions` list.
- `python orbit/prototype/tools/themes.py` regenerates the CSS, the JS and the
  per-theme JSON. It must report **0 contrast failures**.
- Screenshots: `python orbit/prototype/tools/shoot.py --device
  phone|window-m|window-l --theme <id> [--query scroll=760] <keys>`, one at a
  time. Headless Chrome sometimes captures a page before every script has
  loaded, so a blank or unstyled shot means retake, not "the design is wrong".

## Porting and comparing a screen

- Build the screen in `packages/orbit_ui`, add its key to
  `apps/orbit_preview/lib/ported.dart`, then compare it: `shoot_html.py` for
  the prototype, `orbit_preview.exe --shoot <key>` for Flutter (build with
  `flutter build windows --debug` in `apps/orbit_preview` first). The steps
  are in `tools/compare/README.md`. A batch is shown to the owner with that
  report, not with a description.
- Screens are photographed by the app, never by a widget test: a test draws
  text in its test font, and `toImage` or file reads inside `testWidgets`
  wait forever on the fake clock. Read files in `setUpAll`.
- A font that `orbit_ui` bundles is `packages/orbit_ui/<family>` to Flutter.
  Always go through `OrbitFontStack.family` or `.style()`; a bare `'Geist'`
  silently draws the platform font.
- A screen reads the status bar as `MediaQuery.paddingOf(context).top`; the
  preview's device frame supplies the prototype's 40px.

## Working on Windows

- The shell is Git Bash; every command prints an "ng completion" warning.
  Ignore it.
- Heredocs with apostrophes, `\b` or `\n` break or write control characters
  into files. Write multi-line patches with the Write tool, then run them.
- `tar` needs `--force-local` for `C:` paths.
- Run `dart format` only on files you changed.
- Do not run Flutter analysis or tests for this workspace alongside the
  `helix_remote` server suite (see the root `AGENTS.md`).