# Orbit: deviations from the prototype

Anything the Flutter port cannot match, or deliberately does not match, in the
HTML prototype. One entry per difference, newest last.

**The prototype is the specification.** This file is not a backlog of things to
"improve" — it is the list of places where the port had to differ, so the owner
can approve each one. A difference that is not written here is a difference
nobody checked.

Format:

```markdown
## <screen or component> — <one line>

- **Prototype:** what `orbit/prototype/` draws (`js/screens/*.js`,
  `css/*.css`, the screen's entry in `SCREENS.md`).
- **Flutter:** what was built instead, and where
  (`packages/orbit_ui/lib/...`).
- **Why:** why the prototype cannot be matched. "Flutter has no equivalent" is
  only an answer when it says what was done instead.
- **Owner:** approved / pending.
```

## Italic faces are real, where the prototype's are synthesised

- **Prototype (before 2026-10-18):** `prototype/index.html` line 11 asked
  Google Fonts for an italic face for Fraunces only. For the other families the browser **synthesises** an
  oblique when it meets `font-style: italic`, and the prototype does draw
  italic — bloom's wordmark, the typing indicator, placeholder bubbles, a
  missing quote.
- **Flutter:** the real italic face of every family that has one is bundled
  (`orbit/flutter/fonts/MANIFEST.md`: 13 files). Cinzel, Rajdhani, Share Tech
  Mono and Black Ops One have no upstream italic, so nothing is synthesised for
  them.
- **Why:** Flutter does not reliably synthesise an oblique for a custom font. If
  the real faces were not bundled, every italic line would render **upright**
  and the compare tool would report a difference on all of them — noise that
  hides real differences.
- **Consequence, accepted:** a real italic is still not a synthetic one. The
  faces carry their own slant angles (−7° Barlow to −17.2° EB Garamond) and
  their own advance widths, so italic text will differ slightly from the
  prototype's screenshots. That residual is smaller and more truthful than
  rendering upright, and it is the design's own intention rather than a
  substitute.
- **Owner:** approved 2026-10-18, resolved: the prototype now loads the same
  real italic faces (index.html line 11), so both sides draw the same italics
  and the compare tool measures like with like.

## Icons are Phosphor's own font files, not the `phosphor_flutter` package

- **Prototype:** Phosphor Icons 2.1.1 from unpkg, as icon fonts (`ph`,
  `ph-fill`, `ph-bold`, `ph-light`, `ph-duotone`).
- **Flutter:** the same icons from the same Phosphor font files, bundled in
  `orbit_ui` (`fonts/phosphor/`, MIT licence alongside) and declared as
  `const IconData` in `packages/orbit_ui/lib/src/icons/orbit_icons.dart`, so
  release builds still tree-shake the icon fonts.
- **Why:** `PORT_PLAN.md` named `phosphor_flutter`. Its newest release (2.1.0)
  declares `class PhosphorIconData extends IconData`, and `IconData` is
  `final` in Flutter 3.44, so the package does not compile, and upgrading
  Flutter is not allowed. The glyphs and code points are unchanged; only the
  Dart wrapper is ours.
- **Owner:** approved 2026-10-18, on the conditions above (recorded here,
  `const IconData`, licence kept).

## The logo is drawn as paths, not loaded as an SVG

- **Prototype:** `prototype/assets/orbit-mark.svg`, as a CSS background.
- **Flutter:** `OrbitMark` (`packages/orbit_ui/lib/src/brand/orbit_mark.dart`)
  paints the same rectangle, gradient, arcs and circles from the SVG's own
  numbers.
- **Why:** Flutter has no SVG renderer, and `flutter_svg` is a dependency the
  app does not have; `orbit_ui` must move into `helix_remote` unchanged. The
  compare tool shows the drawn mark matching the prototype's to within
  anti-aliasing.
- **Owner:** approved 2026-10-18 (Review 2).

## QR display — draws the prototype's SVG pattern, not a real encoder

- **Prototype:** `js/kit.js` line 39 (`Kit.qr`), drawing a deterministic 29×29 matrix SVG pattern for display.
- **Flutter:** `OrbitQr` and `OrbitQrCard` (`packages/orbit_ui/lib/src/components/codes.dart`) paint the prototype's matrix cell for cell (`orbitQrCells` ports its FNV and xorshift with JavaScript's 32-bit rules; a test checks it against Node).
- **Why:** Encoding and rendering arbitrary dynamic QR codes needs a QR generator package (e.g. `qr_flutter`), which the app may not have or want as a dependency in `orbit_ui`. The prototype draws the pattern alone.
- **Owner:** pending (to decide in Part B whether to add a real QR generator or slot).

## Prototype fixes made during Review 3.1 (not deviations; listed for approval)

The port follows the prototype, so these changed the prototype itself:

- **The chat patterns now render.** `tools/themes.py` left `#` unencoded in
  the pattern SVGs (`url(#n)`, `fill='#FFB3D1'`), which ends a data URL, so
  Chrome never drew Bloom's and Papyrus's grain, Mochi's hearts or Field's
  contours: only Arcade's grid and Terminal's scanlines ever showed. With `#`
  encoded they appear as the theme table describes, including Papyrus's grain
  behind every page.
  - **Owner:** approved 2026-10-18 (Review 3.1).
- **`kit-primitives` shows parts the way the app uses them:** the busy button
  keeps its label with the spinner (as in `devices_backup.js`), and the
  checkboxes are `Kit.check` rows rather than bare `.chk` boxes. A chat
  pattern swatch was added.
  - **Owner:** approved 2026-10-18 (Review 3.1).
- **`boot.js` reapplies `?scroll=` after the fonts load.** A page laid out
  before its fonts arrived was shorter, so a screenshot stopped scrolling
  early. Screenshot tooling only; nothing a person sees.

## Sub-pixel placement

- **Prototype:** Chrome snaps each box's edges to whole pixels.
- **Flutter:** draws them at their exact fractional position.
- **Why:** this is how the two engines render, not a choice. Text line
  heights such as 10.5px × 1.4 = 14.7px add up, so a shape further down the
  page can sit up to 1px lower than in the prototype, with a softer edge.
- **Owner:** approved 2026-10-18 (Review 3.1).

## Prototype fixes made during Review 3.2 (not deviations; listed for approval)

- **The search field no longer overflows when it has text.** `.search` had
  no `min-width: 0`, so with the clear button showing, the input's own width
  (about 213px) pushed the field 14px past its margin on a narrow bar (the
  kit frame; a 360px phone would do the same). `css/components.css` now sets
  it.
  - **Owner:** pending (Review 3.2, unattended run of 2026-10-19).
- **`home.js` exposes the tab header and the dock** (`App.homeParts`) so the
  `kit-shell` sheet draws the real ones. Nothing on Home changes.
  - **Owner:** pending (Review 3.2).
- **`boot.js` sets `?scroll=` exactly, even when the page went past it.**
  Chrome's scroll anchoring moved a scrolled page about 20px further when the
  fonts made the content above taller, so the prototype's shot was taken
  lower than asked. Screenshot tooling only.
  - **Owner:** pending (Review 3.2).

## Text lines take their CSS height (Review 3.2)

- **Prototype:** a line of text is `font-size × line-height` tall, a
  fraction of a pixel where it falls (12px × 1.4 = 16.8px).
- **Flutter:** rounds every line to a whole pixel (17px), so each block of
  text added up to half a pixel and a long page drifted several pixels.
  `OrbitText` (`lib/src/theme/orbit_text.dart`) takes the CSS height and
  centres the rounded lines on it; the components use it for text that sits
  in the flow. Inside a block of several lines, the top and bottom lines can
  still be up to half a pixel off.
- **Why:** the rounding is in the engine's paragraph layout, with no switch to
  turn it off.
- **Owner:** pending (Review 3.2).

## Glyphs can sit up to 2px lower inside their line (Review 3.2)

- **Prototype:** Chrome places each line's glyphs at a whole-pixel baseline.
- **Flutter:** the line boxes land within half a pixel of Chrome's (measured
  with the preview's `.boxes.txt` dump), but the glyphs inside can draw 1px
  lower, and 2px in JetBrains Mono (Terminal).
- **Why:** the two engines round the baseline differently. Matching it would
  mean a per-font nudge measured against Chrome on Windows, whose rounding is
  not the phone's.
- **Owner:** pending (Review 3.2).

## Review 3.3

- **Prototype addition:** a `kit-overlays` sheet (`js/screens/states.js`),
  with a key per overlay (`kit-overlays-sheet`, `-actions`, `-menu`,
  `-dialog`, `-input`, `-toast`, `-toast-error`, `-toast-undo`), each opened
  by the same `App.sheet`, `App.menu`, `App.dialog`, `Kit.inputDialog` and
  `App.snack` calls the screens make, with real text from those screens.
  - **Owner:** pending (Review 3.3).
- **The preview's phone has its own navigator**, so overlays open inside the
  phone and under its status bar, as the prototype's overlay layer does. In
  the app (Part B) they open on the app's navigator, under the system's
  status bar: the same picture.
  - **Owner:** pending (Review 3.3).
- **A dialog's field puts the caret at the end of its text.** The
  prototype's `input.focus()` leaves Chrome's caret at the start; Flutter's
  focused field puts it after the text, which is where someone renaming
  expects it.
  - **Owner:** pending (Review 3.3).

## Review 3.4

- **Prototype addition:** a `kit-rows` sheet (`js/screens/states.js`): every
  chat in `Data.chats` as Home draws it (with the swipe), a selected row, the
  archived chats with their archive flag, and every call in `Data.calls`.
  - **Owner:** pending (Review 3.4).
- **A typing row that has unread messages is `--ink-2`, not
  `--accent-ink`.** That is what the prototype's CSS does (the unread rule
  comes after the typing rule), so the port does the same; if the accent was
  meant, both should change together.
  - **Owner:** pending (Review 3.4).

## Review 3.5

- **Prototype addition:** a `kit-timeline` sheet (`js/screens/states.js`):
  the four sample conversations, the start of an empty chat, and the
  composer in each state. `conversation.js` exposes its composer
  (`App.convoParts`), and the sheet grows each composer's field to its draft
  as the chat screen does on mount.
  - **Owner:** pending (Review 3.5).
- **Prototype fix: the link card is a block.** `.linkcard` was an inline
  span holding block parts, so Chrome never drew its tinted card and added
  blank lines around it. `css/screens.css` now gives it `display: block`,
  which is what the design shows everywhere else.
  - **Owner:** pending (Review 3.5).
- **View models extended (the copy in `orbit_ui`).** `HelixPollContent`,
  `HelixEncryptionNoticeItem`, `HelixTypingItem`, `HelixNoticeTone` on
  notices, `sizeLabel` and a preview `swatch` on media items, and a notice's
  icon is now an `OrbitGlyph` (so the theme picks its weight) instead of an
  `IconData`. Part B reconciles this copy with `helix_remote_ui`.
  - **Owner:** pending (Review 3.5).
- **Placeholder bubbles take Field's stripe.** The prototype's stripe rule is
  more specific than the dashed placeholder edge, so a deleted or
  undecryptable message has a solid stripe on one side and dashes on the
  rest. The port does the same.
  - **Owner:** pending (Review 3.5).

## Phase 4 batch 3 (the conversation)

- **`ChatModel` and `ChatActions` cover what the prototype draws.** The
  contract's other fields and actions (rows newest first with message ids,
  `hasOlder`/`hasNewer`, `jump`, `unreadCount`, the search state and hits,
  `enterSends`, the voice gestures, the async signatures that return a
  sentence) are added when the screen is wired in Part B. The timeline items
  are oldest first for now.
  - **Owner:** pending (batch 3).
- **Not built yet, inside the screen:** swipe-to-reply, the scroll-to-latest
  button, the "+" emoji sheet and the Reactions sheet, the camera sheet after
  Camera in the attach sheet, the hold-to-record gesture, the "Copied" toast.
  The drawn states all match; these arrive with the wiring.
  - **Owner:** pending (batch 3).
- **Two prototype shots stop short of the bottom.** `chat-select` (the
  composer goes away after the prototype scrolls) and `chat-edit` (the field
  grows to two lines after it scrolls) leave the newest message cut off. The
  port opens at the newest message, as the prototype means to; those two keys
  score 20-28% for that reason alone.
  - **Owner:** pending (batch 3).

## Phase 4 batch 4 (the conversation's pages)

- **The media viewer is `--night`, not black.** `.viewer-page` asks for
  `#000`, but `.page.night` is more specific and wins, so the prototype
  draws `#090C15`. The port matches what the prototype draws. If black was
  meant, it is a one-line change in both.
  - **Owner:** pending (batch 4).
- **Night pages tell the status bar the way a phone expects.** The viewer
  sets `SystemUiOverlayStyle.light` with an `AnnotatedRegion`; the preview's
  status bar and gesture bar read it and turn `--night-text`, as
  `.phone-screen.on-night` does.
  - **Owner:** pending (batch 4).
- **The video seek bar is Flutter's slider** themed white, where the
  prototype draws Chrome's range input with `accent-color: #fff`.
  - **Owner:** pending (batch 4).
- **Not built yet:** the viewer's Previous / Next buttons and arrow keys on a
  window (batch 10, the wide layout), the "Forwarded" and "Chat cleared"
  toasts (the app's connector shows them), and the 3-second auto-hide of the
  video controls (it follows `VideoView.playing` once wired).
  - **Owner:** pending (batch 4).
- **Models follow the contract's names, with simpler signatures** where the
  contract returns a sentence or a result (`Future<String?>`); those return
  types arrive when each page is wired in Part B.
  - **Owner:** pending (batch 4).

## Phase 4 batch 5 (calls)

- **Every `<button>` keeps the browser's 1px of padding above and below**
  on the call screen (the control tiles, End, the round actions on Call
  details); the port adds it there so the tray and rows line up.
  - **Owner:** pending (batch 5).
- **The tray's shadow is drawn only outside it** (`OrbitOuterShadow`), as
  CSS does, so the see-through glass does not darken over its own shadow.
  - **Owner:** pending (batch 5).
- **The pulsing rings and Answer's nudge animate in the app** and sit still
  with reduce motion, as the prototype does under
  `prefers-reduced-motion`. The ring timing follows `@keyframes halo`; the
  nudge is not built yet.
  - **Owner:** pending (batch 5).
- **The video and camera pictures are slots** (`remoteVideo`, `localVideo`);
  the preview draws the prototype's gradients there.
  - **Owner:** pending (batch 5).

## Phase 4 batch 6 (people)

- **The QR code is drawn from a seed in the preview.** The contract's
  `HelixQrMatrix` arrives with the wiring; `SafetyNumberModel.qrSeed` stands
  in until then.
  - **Owner:** pending (batch 6).
- **The scanner's camera is a slot** inside `OrbitScanFrame`; "Simulate a
  match / a mismatch" stay as preview actions (the prototype's own
  stand-ins) and are not shown in the app.
  - **Owner:** pending (batch 6).
- **A missing action does nothing** on these pages rather than drawing its
  button disabled, as on the sign-in pages.
  - **Owner:** pending (batch 6).
- **`MuteFor` is shared** with Home (one enum with its labels) rather than
  the second copy the contract mentions.
  - **Owner:** pending (batch 6).

## Phase 4 batch 7 (groups)

- **The invite link's buttons wrap** onto a second line when the text is too
  large for one, where the prototype's row would overflow.
  - **Owner:** pending (batch 7).
- **`OrbitExtendedFab` has no blue shadow in Orbit.** `.xfab` first asks for
  one, but the later `.btn.primary, .fab, .xfab { box-shadow: var(--glow) }`
  wins, and Orbit's glow is none. The port does what the prototype draws.
  - **Owner:** pending (batch 7).
- **Group results return sentences in the contract** (`GroupResult`); the
  screens take plain callbacks until the wiring adds the toasts.
  - **Owner:** pending (batch 7).
