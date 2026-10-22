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

## QR display — draws the prototype's SVG pattern until the app hands it a matrix

- **Prototype:** `js/kit.js` line 39 (`Kit.qr`), drawing a deterministic 29×29 matrix SVG pattern for display.
- **Flutter:** `OrbitQr` and `OrbitQrCard` (`packages/orbit_ui/lib/src/components/codes.dart`) paint the prototype's matrix cell for cell (`orbitQrCells` ports its FNV and xorshift with JavaScript's 32-bit rules; a test checks it against Node). When the app passes a `HelixQrMatrix`, the same widget paints that instead, so every real code in the app (link this device, the safety number, and since S1 the share sheet) is scannable. `orbit_ui` still has no generator and never encodes: the app builds the matrix in `app/lib/core/platform/qr_encoder.dart` and passes it through the model.
- **Why:** Encoding and rendering arbitrary dynamic QR codes needs a QR generator package (e.g. `qr_flutter`), which the app may not have or want as a dependency in `orbit_ui`. The prototype draws the pattern alone.
- **Owner:** the split is the design (pattern for the preview, matrix from the app); since S1 no shipped screen is left showing a pattern. Pending review (Part B, S1).

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

## Phase 4 batch 8 (You, Edit profile, Appearance, the topic pages)

- **The settings pages answer at once.** Privacy, Notifications and Chats
  keep their own copy of the choices, change it on a tap and tell the
  connector, as the prototype's shared prefs do; a new model from the app
  replaces the copy.
  - **Owner:** pending (batch 8).
- **Shadow order.** CSS draws a `box-shadow` list first-on-top and Flutter
  last-on-top; the planet's page-colour ring and the call screen's picture
  ring are listed last so they stay on top, as drawn.
  - **Owner:** pending (batch 8).
- **"Live preview" sits in a body-text line box** in the prototype (an
  inline eyebrow), so the port moves it 4px down and leaves 10px under it.
  - **Owner:** pending (batch 8).
- **A hero pill's text shrinks to an ellipsis** when it is wider than its
  row (large text); the prototype would overflow.
  - **Owner:** pending (batch 8).
- **The theme JSON's swatches are read** into `OrbitThemeMeta.swatches` for
  Appearance's hero.
  - **Owner:** pending (batch 8).

## Phase 4 batch 9 (settings pages, devices, backup)

- **Icons keep their CSS line box where it shows.** A device card's 26px
  icon is an `<i>` in a 1.4 line box, so the port gives it a 36px box.
  - **Owner:** pending (batch 9).
- **Tags and pills shrink to an ellipsis** rather than overflowing a
  narrow card when the text is large; the prototype would overflow.
  - **Owner:** pending (batch 9).
- **Backup's disabled button while running is at 60%**, the prototype's
  inline opacity, which replaces the usual disabled 45% rather than adding
  to it.
  - **Owner:** pending (batch 9).
- **Restore history is `RestoreScreen`** (batch 1) with `afterSignIn:
  false`, as the prototype reuses its restore page; the contract's
  `RestoreHistoryScreen` is that screen.
  - **Owner:** pending (batch 9).
- **The link and approve steps keep their camera as a slot** inside
  `OrbitScanFrame`.
  - **Owner:** pending (batch 9).

## Phase 4 batch 10 (the wide Windows layout)

- **Compared on a representative set, not every key.** 15 keys at 960px
  and 19 at 1280px, covering every placement (list, detail, info beside or
  over, full and boxed), overlays and the composer's anchored sheet: 0.3%
  to 7.3%. The other keys use the same frame; Review 4 is where to look
  at them.
  - **Owner:** pending (batch 10).
- **The preview composes a window from `screens.json`**: each key's base
  screens are pushed through the prototype's own `route` rules, and a base
  screen is drawn by the key whose screen and parameters match it. In the
  app, go_router's shell does this (frame.md's spike).
  - **Owner:** pending (batch 10).
- **The title bar is a stand-in** in the preview; the app tints the real
  Windows caption (frame.md).
  - **Owner:** pending (batch 10).
- **What is open on the right is marked in the list** for chats only so
  far (`OrbitCurrentScope`); topic tiles and call rows get it with the
  wiring.
  - **Owner:** pending (batch 10).
- **A window has no speaker or output control on a call**, as the
  prototype draws it; the app's empty output list on Windows says the
  same.
  - **Owner:** pending (batch 10).
- **Pages are kept to a readable width** (680px) in the detail pane only
  where they use `OrbitPage` or `OrbitYouPage`; a few pages with their own
  frame still fill the pane.
  - **Owner:** pending (batch 10).

## Part B batch 1 (sign-in and the entry screens, wired into the app)

All 30 sign-in and 17 entry states score exactly as at Review 4 after the
changes below, so none of them moved a pixel in the compared states.

- **Behaviour-only hooks added to `orbit_ui`**: `OrbitTextField` takes
  autofill hints, input filters and a submit callback; the sign-in screen
  takes the real legal documents (`legal`), hides the Terms where the app
  does not ask for them (`showTerms`, a personal server), pastes into the
  code field, and keeps the setup and SMS fields in step with the model.
  The hidden corner counts taps with a timer, not the wall clock.
  - **Owner:** pending (Part B batch 1).
- **The server badge shows on every personal-server step** (SMS code,
  password, name, take-over), as the app does; the prototype draws it on
  the phone step only. Helix Global steps never show it. (Contract
  "keep" row.)
  - **Owner:** pending (Part B batch 1).
- **Tap targets report their real size.** `OrbitTapArea` already answered
  taps across 48px; it now also tells accessibility services that size,
  and a text field's touchable area is its whole box. The sign-in page
  passes the app's tap-target and label guidelines.
  - **Owner:** pending (Part B batch 1).
- **Restore keeps the app's states**: offer rows show progress and the
  app's buttons (Accept, Decline, Pause, Resume, Try again) on the same
  card, and a failed or locked restore shows the app's sentence under a
  short title.
  - **Owner:** pending (Part B batch 1).
- **Link this device draws the real QR code** (`OrbitQr.matrix`), and its
  "did not work" page shows the app's reason.
  - **Owner:** pending (Part B batch 1).
- **"Orbit could not start" still offers the reset after a retry has failed
  too** (`ResetModel.offerReset`), below Try again, with the same DELETE
  confirmation. The approved design offers only Try again; without this a
  failure that never passes would leave the phone stuck. Not shown in any
  prototype state.
  - **Owner:** pending (Part B batch 1). Say if you want it removed.
- **No separate high-contrast theme**: the app always shows the Orbit
  theme, as Part B step 3 says.
  - **Owner:** pending (Part B batch 1).

## Part B batch 2 (Home on Orbit, wired into the app)

All 27 Home states score exactly as at Review 4. The agent that started this
batch ran out of credit before verifying it; the commander finished it.

- **`HomeActions.peopleCalls`** (orbit_ui): the Calls search's people panel
  places a call on a tap, the Chats one opens a chat; the Calls pane uses
  `peopleCalls ?? people`. Behaviour only.
  - **Owner:** pending (Part B batch 2).
- **`showOrbitToast(overlay:)`** (orbit_ui): a caller above the navigator
  (the app's link listener) passes the navigator's overlay. Behaviour only.
  - **Owner:** pending (Part B batch 2).
- **Settings is no longer a dock tab.** Orbit's dock has Chats and Calls; your
  picture ("Your profile and settings") opens today's Settings page at
  `/settings` until the You batch replaces it.
  - **Owner:** pending (Part B batch 2).
- **Known gap: the wide Windows window lost the chat beside the list.** A chat
  opens as a full page on every width until the window batch (the last) wires
  `OrbitWindowScaffold`. Do not merge Part B before that batch.
  - **Owner:** pending (Part B batch 2).
- **"Opening Orbit…" on a cold start** (`/startup`): shown until the
  remembered server has been read (`sessionRestoreProvider`) and the database
  has opened, so a signed-in device no longer flashes sign-in. Once left it
  never returns: a personal-server sign-in that rebuilds the runtime keeps
  sign-in up (router test).
  - **Owner:** pending (Part B batch 2).
- **A setup link while signed in** shows the `chats-link-signed-in` toast for
  the normal 2.8s and changes nothing (journey test through the real link
  channel).
  - **Owner:** pending (Part B batch 2).
- **The privacy-checkup dot is never shown** (`meNeedsAttention` false) until
  the checkup summary moves to `core/` with the You batch.
  - **Owner:** pending (Part B batch 2).
- **The quick row** is the first two people in the call log.
  - **Owner:** pending (Part B batch 2).
- **Home keeps its search open** when you come back from a chat opened from
  it, as the screen's own state does.
  - **Owner:** pending (Part B batch 2).
- **Cleanup left for step 4:** the old `ChatsTab` and `CallsTabScreen` are no
  longer reachable but stay, with their widget tests, until those tests are
  rewritten against the connector; the connector lives in
  `shared/widgets/orbit_home_connector.dart` because it joins four features.
  - **Owner:** pending (Part B batch 2).

## Part B batch 3 (the conversation, wired into the app)

All 26 conversation states, `kit-timeline`, the three Message info states
and both Forward states score exactly as at Review 4 after the changes below,
so none of them moved a pixel in the compared states.

- **Behaviour-only hooks added to `orbit_ui`:**
  - `OrbitBubbleActions` (timeline): the quote, links in the text, the link
    card, each picture, a document's button, view-once, a voice message's
    play, speed and waveform (tap or drag to seek), and the reactions under
    a bubble answer taps when the caller passes a hook; without one they
    take no touches, as before. Right-click opens the actions view.
  - `ChatScreen`: the long-press menu can come from the app
    (`messageMenu`), with the reaction you already gave; "+" opens the React
    sheet with every emoji; a reaction under a message opens the Reactions
    sheet (spinner, "No reactions yet.", yours with "Tap to remove"); Delete
    for me and Delete for everyone ask first (the prototype's dialogs), and
    "It can no longer be deleted for everyone." when it is too late; Copy
    says "Copied"; the selection bar's Copy and Forward end the selection;
    the camera sheet (Take a photo, Record a video) and the attach tiles
    pick files; the emoji panel inserts at the cursor and closes when the
    field gets focus; back closes the selection, then the search; a pending
    member's buttons wait while the answer comes, and Remove asks first.
  - `OrbitComposer` takes the caller's text controller and focus (an edit
    fills the field, a reply puts the cursor in it, the draft is saved when
    the screen closes), sends on Enter when `enterSends`, reports the cursor
    with the text, and hands the whole person to a mention pick.
  - **Hold to record**: the mic records while held (the prototype's 220ms;
    the old app's was 500ms), sliding 120px towards the start cancels and
    80px up locks, and the gesture survives the switch from the field to the
    recording strip. A plain tap says "Hold the microphone to record a voice
    message."
  - **Swipe to reply** follows the prototype: theirs to the right, yours to
    the left, up to 80px, 56px to reply, measured from where the finger went
    down, springing back in 180ms (the old app slid every bubble to the
    right). Off while selecting and where nothing can be sent.
  - **Scroll to latest message** (`.to-bottom`): shown 160px from the bottom
    or after a jump into the past, with the unread count; it sits 10px above
    the composer, which is the prototype's 92px from the bottom while the
    composer is the usual height.
  - **Opening at the unread line** is the app's (`ChatModel.openAtUnread`);
    the preview opens at the bottom, as the prototype does.
  - **Bubbles tell a screen reader** who, what, when and how far it got, with
    Reply, "Go to replied message" and "Show reactions" as actions (the old
    bubble's summary); a bubble with controls keeps them reachable.
  - **The composer field's 48px is touchable**: its 12px above and below are
    the input's own padding now, so the 2x-text tap-target check passes.
  - **Owner:** pending (Part B batch 3).
- **The timeline is a lazy list built from the bottom** (it was one column
  of every message): it pages older and, after a jump, newer messages in,
  keeps your place when messages arrive while you read further up, and
  rebuilds only the rows that changed. Its rows have no repaint boundaries:
  with them, `chat-emoji` moves by 0.01% (text at a fractional offset is
  rasterised a hair differently). Turning them on is a performance choice
  for later, with a compare.
  - **Owner:** pending (Part B batch 3).
- **The emoji panel and the React sheet use the prototype's emoji**, not the
  app's longer list (the contract said the app's list would move in; the
  approved design draws these).
  - **Owner:** pending (Part B batch 3). Say if you want the longer list.
- **In-chat search**: results come from the app's search with its marked
  words; each shows who sent it (yours as "You"); a spinner while it runs and
  "The search could not be run." when it fails.
  - **Owner:** pending (Part B batch 3).
- **"This conversation could not be opened." offers Try again** in the app
  (the prototype's interaction list); the preview's stays disabled.
  - **Owner:** pending (Part B batch 3).
- **The derive items are built** (`application/`): the author's picture
  beside a group run, the size on a photo's download chip, the amber
  key-change notice, the call buttons' rule, the reply or edit banner, and
  the live waveform of a locked recording (`VoiceRecorder.levels`). The
  played-dot that survives a restart (new backend work, optional) is not.
  - **Owner:** pending (Part B batch 3).
- **Selection lives in the screen** (the app's `messageSelectionProvider` had
  no other user and is gone).
  - **Owner:** pending (Part B batch 3).

## Part B batch 4 (the conversation's pages, wired into the app)

All 25 states of these pages (Forward, Message info, the media viewer and
its video states, Send files, Media, links and docs, Chat settings) score
exactly as at Review 4 after the changes below.

- **Behaviour-only hooks added to `orbit_ui`:**
  - The **media viewer** pages follow the finger (a `PageView`, the old app's
    way; the prototype changes page after a 50px swipe) and ← and → turn
    them on any screen. A real photo is shown whole and zooms and pans (the
    old app's `InteractiveViewer`, up to 6x); the preview's stand-ins stay
    the prototype's 4:3. The video on screen draws the app's player (the
    `videoSurface` slot, `VideoView.surface`); a video beside it is its still
    with the play button. The controls hide 3 seconds after playing starts
    and come back on a tap (the prototype's timer). The seek bar follows the
    finger and seeks when let go. A failure gives the app's reason
    ("Videos cannot be played inside Helix on this device.", "This video
    cannot be played on this device.", "This video stopped playing.") in the
    prototype's layout.
  - **One picture has no "(1 of 1)" and no dots**; a page whose file is not
    on the device says "This file is not on your device yet." and hides
    Share; a message with no photo or video says "There is nothing to show
    here." (the old app's sentence; the prototype draws neither).
  - **The video's speed chip is a 48px target.** It is still drawn 30px
    high; the control row is 48px with 9px less padding above and below, so
    nothing moves.
  - **The viewer's bar grows with large text** (it was a fixed 60px and
    overflowed at 2x text).
  - **Forward**'s no-results state adds "Nothing matches “…”." (the
    prototype's in-chat search empty state; the contract keeps the old app's
    sentence), and the search ignores spaces around the words.
  - **Message info**'s failure is "The details could not be loaded." (the
    old app's sentence, as the contract says; Part A had its own).
  - **The caption on Send files grows to 4 lines** and starts sentences with
    a capital (the old app's field).
  - **Owner:** pending (Part B batch 4).
- **Message info shows one line per person**, Read, else Delivered, else
  "Not delivered yet" (the prototype); the old page listed Read and
  Delivered both. The message is its bubble (the prototype; the old page
  showed its text only), with its photos or file when it has them.
  - **Owner:** pending (Part B batch 4).
- **A real photo or video still is not cut to 4:3** in the viewer (the
  prototype's swatches are 4:3; cutting a portrait photo would hide most of
  it).
  - **Owner:** pending (Part B batch 4).
- **A document's line reads "482 KB · PDF · Yesterday"** (the prototype's
  "·"; the old page used commas). Links keep "example.org, 14:30", as the
  prototype draws them.
  - **Owner:** pending (Part B batch 4).
- **The toasts the prototype shows are the app's now:** "Forwarded" (or
  "Some messages could not be forwarded", as an error), "Chat cleared"
  (the old app said nothing), "Downloading..." and "This file is no longer
  on this phone." on the shared page.
  - **Owner:** pending (Part B batch 4).
- **The derive items are built** (`application/`): Message info's bubble
  and its "Recipients" heading for a group, the first frame of a picked
  video on Send files (`videoFramesProvider` over the existing
  `VideoFrameSource`), and the shared page's tab as a route parameter
  (`?tab=docs`, `?tab=links`; nothing opens it on another tab yet).
  - **Owner:** pending (Part B batch 4).

## Part B batch 5 (calls, wired into the app)

All 24 call states score exactly as at Review 4 after the changes below.

- **Behaviour-only hooks added to `orbit_ui`:**
  - **A screen reader hears the call** in the app's words: the status as a
    live region ("Incoming voice call", "Call duration 00:12", the end
    reason), the picture as "Picture of <name>", the name as a heading, the
    big video as "Video from <name>" or "Your camera", and the tile as a
    button, "Show your camera full screen" or "Show <name> full screen" (the
    port's tooltip had the two the wrong way round). Hidden video controls
    leave the screen reader's tree.
  - **"Connected" until the clock's first tick** (the preview always has a
    clock).
  - **The video slots get a stand-in**: until frames arrive, their picture
    on the gradient (smaller in the tile). The "CAMERA OFF" line of
    `call-video-their-camera-off` shows only when the app says the camera is
    off, which it cannot tell yet (no signal for it), so the app never
    shows it.
  - **Your tile** needs your camera's picture in the app, starts at the top
    end (the left in a right-to-left language), stays inside the safe area
    when dragged, and shows a move cursor on a desktop.
  - **A notice on a video call sits above the tray** (the prototype draws
    the notice on the voice layout only).
  - **An end reason steps aside while a notice shows** (the app's rule).
  - **Audio output with two outputs picks the other one** (not always the
    phone and its speaker), one output is no choice (disabled), and a
    speaker with a headset reads "Audio output: Headset".
  - **The camera button works from connecting on** (the app's rule; the
    prototype allows it once active). No compared state is a video call
    that is connecting.
  - **Call details**: Voice call and Video call spin while the call is
    placed, and a refusal is an error toast; a failure to load is "This
    call could not be loaded." (the old page's sentence; Part A had its
    own).
  - **Owner:** pending (Part B batch 5).
- **The derive items are built** (`application/`): the tinted end reason
  (`CallScreenState.endIsProblem`), the rows' titles ("Unanswered voice
  call" for no answer and "Voice call failed" / "Video call failed", the
  design's words), and Call details for someone who blocked you: no call
  buttons, and "<name> has blocked you. You can't message or call them."
  (`callPeerBlocksMeProvider`). Someone you blocked keeps the buttons, and
  a tap says why, as today.
  - **Owner:** pending (Part B batch 5).
- **The app's call sentences still say Helix** ("Helix needs the microphone
  to make calls…"; the preview says Orbit). They change with the app-wide
  rename (Part B step 3).
  - **Owner:** pending (Part B batch 5).

## Part B batch 6 (people, wired into the app)

All 25 compared states (Contact info, Safety number, Scan code, People,
and the Group info and Chat settings states that share the profile hero)
score exactly as at Review 4 after the changes below.

- **Behaviour-only hooks added to `orbit_ui`:**
  - **Contact info answers its actions**: Rename shows "Saved.", "Saved,
    and updated in your contacts." or "Saved in Orbit. Your phone did not
    let Orbit change your contacts.", and asks "Save in your phone
    contacts too?" (the prototype's dialog) only when the phone's
    permission is missing, never on Windows (the app's rule; the prototype
    asks whenever there is a number). A call that cannot start, shared
    media that cannot open, a block, unblock or report that does not go
    through each say so; Blocked., Unblocked. and Reported. as the
    prototype does. "This person could not be loaded." offers Try again.
  - **The report sheet says the note is sent too**: "Orbit learns who you
    reported, why, and your note. No messages are sent with the report."
    (the contract's suggestion; the prototype said "who and why" only).
  - **Safety number** draws the app's QR code (the modules it computed),
    labelled "QR code for the safety number with <name>" for a screen
    reader.
  - **Scan code** takes the app's camera, checks one code at a time, says
    "Verified. Your chat is private." and goes back on a match, and shows
    the prototype's "That code does not match" (do not trust this chat
    until compared in person) on a mismatch, then scans on. The
    prototype's "Simulate" buttons show only without a real camera.
  - **People** can draw the whole people panel (the same component as the
    Chats search: people, the look-up, the contacts card, groups), opens
    ready to type, and looks up on Enter (the contract keeps the app's
    page; the prototype draws only the people).
  - **The profile hero** tells a screen reader whose picture it is and
    makes the name a heading (Contact info, Chat settings, Group info).
  - **Owner:** pending (Part B batch 6).
- **The derive items are built** (`application/`): "<name> has blocked
  you." under the name, with no call tiles (`contactBlocksMeProvider`,
  `PeopleGateway.watchBlocksMe`); the scanned code's check moved from the
  screen into `ContactInfoActions.checkScannedCode`; one mute enum (the
  shared `MuteFor`, "Always" is the year 9999; the people feature had its
  own of 100 years).
  - **Owner:** pending (Part B batch 6).
- **Scan someone's code (contact mode) waits on the code format**: there is
  no route for it yet; it depends on the code format of `you.md` (batch 8).
  - **Owner:** pending (Part B batch 6). Built by S1 — see "Part B S1" at
    the end of this file.

## Part B batch 7 (groups, wired into the app)

All compared group states, the search fields and the pending-member cards
score exactly as at Review 4 after the changes below.

- **Behaviour-only hooks added to `orbit_ui`:**
  - **Every group change answers with its sentence**, shown as a toast
    (`GroupAnswer`: "Bob is now an admin.", "Only an admin can do that in
    this group.", "<Name> joined the group." …). Leaving and deleting go
    back to Chats when they work, and say so.
  - **The member picker** looks up a number (7 or more of its characters)
    or a `~name` only when nobody here matches, waits with a spinner, says
    why when nobody is found, and "That person is already in this group.";
    the person found is picked and the search clears. It filters on the
    name, number, `~name`, nickname and phone-book name (the old picker's
    rule; the port filtered on the name and number only). Its failure
    sentence is the app's ("Your people could not be loaded.").
  - **New group**: Create stays tappable and says "Enter a group name of 1
    to 100 characters." when there is no name (`group-new-error`; the old
    button was disabled); a picture that cannot be used says so ("That
    picture could not be used."); people who could not be added are named
    in the prototype's "Some people were not added" dialog, then the chat
    opens.
  - **Group info**: a member's menu offers only what the app allows (an
    admin cannot make an owner or touch another admin); "Remove picture"
    only when there is one; a line for a name still arriving; a timer set
    elsewhere is named ("3 days"); the picture and name are labelled for a
    screen reader; the pending cards' 38px buttons answer across 48px (5px
    of the card's own spacing moved into their touch area, so nothing
    moves).
  - **Group settings**, **Join requests** and **Banned people** load,
    fail with Try again ("This group could not be loaded.", "The requests
    could not be loaded. Only admins can see them.", "The list could not be
    loaded."), and say "You are not in this group" when it is gone.
  - **Invite with a link**: an error line under Create, Revoke waits while
    a link is made, and Copy says "Link copied.".
  - **Add members**: nobody added opens "No one was added" with the reasons
    and stays; otherwise its sentence and back.
  - **Join a group**: a text that is not a group link stays on the field
    with "That is not an Orbit group link. Check that you copied all of
    it."; Paste reads the clipboard.
  - **The member picker's search** answers across 48px (`OrbitTapArea`,
    which can now merge a text field's own semantics node), drawn at the
    prototype's 46px. Giving the field itself a 48px box moved its hint by a
    pixel, so it was not done.
  - **The picker rows grow with large text** (they were a fixed 64px and
    overflowed at 2x text).
  - **Owner:** pending (Part B batch 7).
- **The derive items are built** (`application/`): members', requesters'
  and banned people's pictures (`PeopleDirectory.imageOf`), the picker's
  rows with pictures (`groupCandidateItemsProvider`), the timer's label
  (`disappearingLabel`, moved from presentation), the name error on Create
  (`CreateGroupState.nameError`), an unusable picture
  (`UnusablePicture`), and the group-link check (`looksLikeGroupLink`,
  over `HelixDeepLink`).
  - **Owner:** pending (Part B batch 7).

## Part B, S3 (the invite links list, approved gap item)

- **Invite with a link lists every live link**, not only the ones made on
  this device since the app started (gap B5; the server now lists them,
  `GET /v1/groups/{group_id}/invite-links`). A link whose URL this device
  does not have (made elsewhere, or before a restart: the server keeps only
  a hash) gets a card without the URL well: its kind, then "Made by Nadia,
  3 Oct, 14:05. It cannot be shown again, but it can be revoked." in the
  caption style, and Revoke alone. The prototype has no such card; the
  Share/Copy card and the empty page are unchanged (group-invite and
  group-invite-empty identical to Review 4).
  - While the list loads the page does not say "Links you make appear
    here".
  - The card's kind line can shrink (it overflowed at large text).
  - **Owner:** pending (Part B, S3).

## Part B batch 8 (You, profile and the settings topics, wired into the app)

- **Notifications - no ringtone row.** The prototype offers a ringtone
  choice. `NotificationsScreen` leaves the row out until there is a sound to
  ship; the owner owes one (`HANDOFF.md`, "Waiting on the owner").
  - **Owner:** pending (Part B batch 8).
- **Storage - the bar splits by kind and the biggest chats are listed**
  (E2, E3, 2026-10-22). The prototype's split is built; see "Part B E2/E3"
  below for where voice notes and the hero's total sit.
  - **Owner:** pending review.
- **Notifications - the preview is a fixed sample.** The lock-screen preview
  reads "Someone: See you at six?" in every theme; the prototype draws a
  sample too, but the app does not make one from a real chat, because that
  would show content in a settings page nobody asked to preview.
  - **Owner:** pending (Part B batch 8).
- **Account - "Export first" only exports.** The prototype asks the person to
  export and stops; the app's delete page then still has to be opened by the
  person. `AccountScreen`'s dialog follows the prototype.
  - **Owner:** pending (Part B batch 8).

## Part B batch 9 (settings pages, devices and backup, wired into the app)

- **The last old pages are now Orbit screens (done 2026-10-22).** Approve a
  new device, both sides of a device transfer, Recovery backup (create and
  restore) and Restore history draw the Orbit screens through their
  connectors; the old pages and `transfer_tile.dart` are gone.
  - **Owner:** done (pending review).
- **Delete account asks for the number before texting a code.** On an account
  without a password, the code step first shows the number and asks the person
  to confirm, since the operator may charge for the text. The prototype goes
  straight to the code. `DeleteAccountScreen` takes `onSendCode` with the
  phone (`orbit_ui`, behaviour only).
  - **Owner:** pending (Part B batch 9).

## The last old pages (transfer, recovery and approval, 2026-10-22)

- **Approval shows a confirmation dialog, then the phone's unlock.** The
  prototype's Approve button sends at once. The app keeps both trust checks:
  `showOrbitDialog` asks first, and the system fingerprint/face/PIN prompt
  follows. The account key code (`LinkRequest.accountKeyCode`) is on the
  review with a note to compare it on the new device; it is part of the trust
  check and not in the prototype.
- **Without a camera only the paste field is offered.** `canScan` is false on
  Windows and wherever the platform has no scanner, so `ApproveDeviceScreen`
  hides the scan frame and the enter stage is the hero and the paste field.
  The prototype always draws the camera.
- **Delete recovery backup sits in the create tab's danger zone.** The
  prototype's recovery page does not offer it; the app has the action and the
  danger zone is the only place for it.
- **Transfer rows keep the app's statuses and buttons.** `TransferItem` takes
  the status sentence, progress and labels from the engine's `TransferView`:
  Accept, Resume and Try again are primary, Dismiss is ghost and the rest
  secondary; incoming offers have no Dismiss, and every button but Pause and
  Cancel is disabled while busy.
- **Restore history's "I have a recovery secret" opens Recovery on its Restore
  tab** (`/backup/recovery?tab=restore`). The prototype's pages stand alone.


## Saved accounts and switching (after Part B batch 9)

- **Sign-in has saved accounts and Remember me.** The prototype's sign-in has
  no saved-account rows and no switch. `SignInScreen` lists the accounts
  signed in here (a tap opens one) and the numbers this phone remembers (a
  tap opens the password step), and keeps "Remember me" on by default; only
  numbers are saved.
  - **Owner:** pending (saved accounts).
- **"Use a code instead" confirms the number first.** The prototype begins the
  text straight away. The app shows the number and asks the person to confirm,
  saying the operator may charge for it.
  - **Owner:** pending (saved accounts).
- **You has an Accounts page with no prototype.** `AccountsScreen` lists the
  accounts signed in on this phone (the one on screen first), with Add account
  and Remove. There is no prototype or preview screen: the owner skipped the
  prototype, and the screen follows the Account page's style. Removing asks
  first (`Remove <name>?`).
  - **Owner:** pending (saved accounts).
- **Account's sign-out dialog offers Switch account.** The prototype has one
  sign-out. `AccountScreen` now offers "Switch account", which keeps the
  account signed in, and "Sign out and remove", which deletes that account's
  data on this phone only.
  - **Owner:** pending (saved accounts).
- **The app lock is one setting for the device.** The prototype's Privacy page
  belongs to one account. The app keeps a `DeviceLock` in the account list, so
  one lock covers every account signed in here and goes with the last one;
  Privacy edits that setting for all of them.
  - **Owner:** pending (saved accounts).
- **Notifications name the account when more than one is signed in**, and
  previews show the account's name only when message previews are on, like the
  text. The prototype draws a single account.
  - **Owner:** pending (saved accounts).

## Part B E2/E3 (storage by kind and per-chat freeing, 2026-10-22)

- **The hero's total and the bar count different things.** The hero is the
  device probe (database, media files, thumbnails and transfers in progress);
  the bar's three shares are the engine's known attachment bytes plus the
  database, so the shares fill the bar. A few files therefore show in the
  hero and not in the split.
  - **Owner:** pending review.
- **Voice notes count with files and stay out of Biggest chats.** The
  prototype has no separate voice-note share, and a voice note cannot be
  freed on its own in a "Free up space" sheet. The bar's files share therefore
  adds voice notes to documents and unknown kinds; Biggest chats and the
  sheet leave them out.
  - **Owner:** pending review.
- **Freeing covers finished downloads only.** The engine deletes the file and
  thumbnail of attachments marked `ready`, clears their local paths and marks
  them `remote`; messages, keys and pointers stay. Uploads and downloads in
  progress are never touched. Files can be downloaded again while the server
  keeps the object (30 days).
  - **Owner:** pending review.
- **Chat names come from the app's chat list.** The engine returns a
  conversation id and byte counts, not a title; the Storage page looks the id
  up in the chat and archived lists, and draws "Chat" with a generated avatar
  until the list has loaded.
  - **Owner:** pending review.

## Part B S1 (the share link, app links and scan-to-chat, 2026-10-22)

- **The link answers in the app, not on the web page.** `GET /u/{name}`
  (`server/lib/src/modules/ops/share_page.dart`) serves one static page for
  every name, taken or not: it never looks the name up, so it cannot be asked
  to list the server's accounts. The button launches `helix://u/<name>`
  (Android uses an `intent://` URL for the same thing), and the app resolves
  the name with a session through `GET /v1/people/by-name/{name}`, which is
  where "Find me by ~name" and blocking are honoured.
  - **Owner:** pending review. Say if you want the page to answer instead;
    that is a name-enumeration oracle and was refused in the plan.
- **One sentence covers three cases.** A link to a name that does not exist,
  one whose owner has stopped being findable, and one from somebody who
  blocked you all get the same "No Helix account is called ~x on your server,
  or it is not findable by name." Any difference would leak which of the three
  it was. Own name gets its own plain sentence.
  - **Owner:** pending review.
- **A `~name` is per-server, so the link is too.** The page sits on Helix
  Global (`kHelixLinkHost`) whatever server you use, and the app looks the
  name up on the *receiver's* server. `~anna` therefore opens Anna as the
  receiver knows her; if the two accounts are on different servers it can
  name somebody else or nobody. This matches how `~name` uniqueness already
  works — one server, not a global directory.
  - **Owner:** pending review.
- **The share sheet shows only with a `~name`.** The prototype draws it for
  every account. Without a name there is nothing to link and no code to draw,
  so You hides the QR button (and its "an account with no ~name" test asserts
  the whole sheet is gone) until one is set in the profile editor.
  - **Owner:** pending review.
- **The sheet's three buttons are the app's, not the prototype's.** Copy link
  writes the system clipboard and toasts "Link copied"; Share opens the
  platform share sheet (`ShareAdapter.shareText`, subject "Message me on
  Helix"); Scan someone's code pushes `/scan-chat`. The prototype's sheet has
  no behaviour behind them.
  - **Owner:** pending review.
- **`/scan-chat` is a top-level route.** `/home/people/<id>/scan` is the
  safety-number scanner and its `:id` segment would swallow a path under
  `/home/people`, so contact scanning got its own path beside `/scan` rather
  than a nested one.
  - **Owner:** pending review.
- **Contact scan reuses the safety scanner's screen with its own wording.**
  `ScanMode.contact` says "Found them. Opening your chat." on a match and
  "That is not a share code" on one that names nobody; the safety number's
  "Verified. Your chat is private." and "That code does not match" stay for
  `ScanMode.safety`. One screen, two jobs, because the prototype drew them
  identically apart from the words.
  - **Owner:** pending review.
- **No infra change.** Android's autoVerify filter already claimed the whole
  host through `/.well-known/assetlinks.json` (`handle_all_urls`), so `/u/`
  only needed a `<data android:pathPrefix="/u/" />` entry in the existing
  filter; Windows already handles `helix://`. The route adds no migration and
  no `.env` line, but it needs the server rebuilt and restarted to answer.
  - **Owner:** pending review.
