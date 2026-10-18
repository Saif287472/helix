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
- **Flutter:** `OrbitQrDisplay` (`packages/orbit_ui/lib/src/components/qr_display.dart`) paints the prototype's deterministic matrix pattern.
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

