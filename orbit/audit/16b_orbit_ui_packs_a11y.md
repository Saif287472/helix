# Sweep 16b — `orbit_ui` pack pages and accessibility primitives

Read-only. Scope: the theme and ringtone pack pages
(`screens/you/theme_packs_screen.dart` 261, `screens/you/ringtone_packs_screen.dart`
269) and the app-side managers (`features/settings/application/theme_packs.dart`
289, `sound_packs.dart` 332), the accessibility primitives
(`components/button.dart` 158, `icon_button.dart` 97, `fields.dart` 475, and
`OrbitTapArea` in `theme/orbit_metrics.dart`), the toast/semantics path read by
use, and the accessibility tests. Themes, tokens and the pack gate are
`16a_orbit_ui_theme.md`.

## What is sound

- **One gate and one folder for both kinds.** The manifest — signed — decides
  whether a row is a theme or a sound; a theme page never lists a sound
  (`orbit_packs.dart:396-400`, `theme_packs.dart:64-77`, `sound_packs.dart:49-56`).
- **A failed pack never replaces what is on screen.** Bytes are staged and
  gate-checked before any rename (`orbit_packs.dart:260-307`); a pack that stops
  passing is dropped from the library and the app falls back to Orbit
  (`orbit_app_theme.dart:49-51`, `:89-92`).
- **Built-in ids are owned by the build.** A pack can never take a name the app
  ships, on either page (`orbit_app_theme.dart:54-62`, `sound_packs.dart:290-306`),
  and the install path refuses a built-in theme id outright
  (`theme_packs.dart:97-100`).
- **A device choice survives sign-out and is only ever a pack id.**
  `readTheme`/`readRingtone` validate the shape, and the store writes one key
  at a time (`orbit_app_theme.dart:134-200`).
- **The ringtone path keeps Android's copy and the channel in step.** A chosen
  pack's copy is republished on re-download, a failed publish reverts the
  choice, and delete forgets both the copy and the channel
  (`sound_packs.dart:129-144`, `:159-172`, `:219-228`).
- **Tap targets.** Controls drawn smaller than 48 px (a 44×26 switch, a 36/40
  segmented segment, a 38-high button) are wrapped in `OrbitTapArea`, which
  answers taps and reports semantics across 48 px (`orbit_metrics.dart:79-146`,
  `button.dart:154-156`, `icon_button.dart:95`, `fields.dart:400-414`).
- **Labels and feedback.** `OrbitIconButton` requires a tooltip and carries it
  as its semantics label (`icon_button.dart:14-20`, `:61-69`); toasts are live
  regions (`overlays.dart:468-470`); the field's own box is at least 52 px, so
  the whole field is the touchable and announced control
  (`fields.dart:219-228`, `:239-240`).
- **The guidelines run as tests**, at 2x text scale and with the OS
  high-contrast flag, on the sign-in page (`accessibility_test.dart:33-54`,
  `:113-123`), and the shared controls are measured individually
  (`primitives_test.dart:47-63`, `:220-268`).

## AUD-16-4 A field's visible label is not associated with its input, and an inline error is not announced

**Severity:** P3
**Confidence:** confirmed
**Where:** [fields.dart:198-228](file:///J:/Projects/helix/helix_remote/packages/orbit_ui/lib/src/components/fields.dart#L198-L228),
[fields.dart:280-297](file:///J:/Projects/helix/helix_remote/packages/orbit_ui/lib/src/components/fields.dart#L280-L297),
[fields.dart:298-326](file:///J:/Projects/helix/helix_remote/packages/orbit_ui/lib/src/components/fields.dart#L298-L326)

**What:** `OrbitTextField` draws its label as a sibling `OrbitText` above the
box, while the `TextField` inside uses `InputDecoration.collapsed(hintText: …)`
— no `labelText`, no `semanticsLabel`. A screen reader focusing the input
therefore hears the *hint* (or only the entered text, once the hint is gone),
never the label the sighted user reads. The error is likewise a plain
`OrbitText` below the box, not a live region and not tied to the field, so an
error that appears after submit is silent unless the person happens to swipe
onto it.

**Trigger:** TalkBack or VoiceOver on any form built from this field — sign-in
(number, code, password, name), group create, profile edit, report reason.
With the hint "1711 000001" the number field announces a sample number rather
than "Phone number"; after typing, it announces nothing identifying.

**Impact:** The primary form control of the whole app is unlabelled to the
users who need labels most, and validation failures go unheard. The visual
guidelines used in the suite do not test either.

**Fix sketch:** `Semantics(label: w.label, textField: true, child: …)` around
the input (or switch to `InputDecoration(labelText: …)` and let Flutter
associate it), and wrap the error row in `Semantics(liveRegion: true)`.
No wire or schema change.

**Test that proves it:** a `SemanticsTester` (or `tester.getSemantics`) over an
`OrbitTextField(label: 'Phone number', hint: '1711 000001')` must find
`label: 'Phone number'` on the editable node; today it finds the hint only.
An error-bearing field must expose a live region.

**Overlap:** None. The sign-in-specific copy audit (AUD-15-1/15-2) is a
different layer.

## AUD-16-5 Fixed-height controls clip a label that wraps at large text sizes

**Severity:** P3
**Confidence:** likely
**Where:** [button.dart:110-135](file:///J:/Projects/helix/helix_remote/packages/orbit_ui/lib/src/components/button.dart#L110-L135),
[button.dart:102](file:///J:/Projects/helix/helix_remote/packages/orbit_ui/lib/src/components/button.dart#L102),
[fields.dart:427-459](file:///J:/Projects/helix/helix_remote/packages/orbit_ui/lib/src/components/fields.dart#L427-L459)

**What:** `OrbitButton` puts a `Flexible(Text)` — deliberately allowed to wrap
("A label too wide for its button wraps and stays centred") — inside
`SizedBox(height: height)`, whose default is 48 and which the sign-in recovery
button sets to 40. `OrbitSegmented` puts its label inside a fixed
`Container(height: 36/40)`. Text scales through `MediaQuery.textScaler` with no
cap (`shared/widgets/app_text_scale.dart:16-28`), so at 2x a 13.5 px label is
27 px with a 37.8 px line: one line fits a 40 px box, two need 75.6. The
paragraph is constrained to the fixed height, the second line paints outside
it, and `Material(clipBehavior: Clip.antiAlias)` cuts it off. Nothing throws,
so no test notices.

**Trigger:** A phone-width screen at the OS's largest text (or the app's Large
size on top of a 1.5x system value) on a control whose label wraps — e.g.
"Use a recovery code instead" in the 40 px sign-in button, or a long segment
label. At the suite's 800 px test surface the same label fits on one line,
which is why `accessibility_test.dart:42-54` passes.

**Impact:** For a low-vision user the button reads as a fragment ("Use a
recovery…"), and an action can become unrecognisable. It does not crash, so
nothing in the gate reports it.

**Fix sketch:** Let the box grow: `ConstrainedBox(minHeight: height)` instead of
`SizedBox(height:)` (the prototype's 48 px is a minimum, and CSS would grow the
same way), and the same for the segmented control. No wire/schema change.

**Test that proves it:** pump the sign-in page at `textScaleFactor = 2` on a
360 px-wide surface and assert no overflow (a `Text` with `maxLines: 1` would
also assert the label is not silently cut); today that combination is only
tested at 800 px.

**Overlap:** None. The sign-in copy audit did not read the layout.

## AUD-16-6 A theme download reports success for a pack the page then cannot offer, and leaves its bytes behind

**Severity:** P3
**Confidence:** confirmed
**Where:** [theme_packs.dart:103-111](file:///J:/Projects/helix/helix_remote/app/lib/features/settings/application/theme_packs.dart#L103-L111),
[orbit_packs.dart:260-307](file:///J:/Projects/helix/helix_remote/app/lib/core/theme/orbit_packs.dart#L260-L307),
[orbit_packs.dart:562-579](file:///J:/Projects/helix/helix_remote/app/lib/core/theme/orbit_packs.dart#L562-L579),
[sound_packs.dart:127-128](file:///J:/Projects/helix/helix_remote/app/lib/features/settings/application/sound_packs.dart#L127-L128)

**What:** `PackFolder.install` moves a gate-passing pack into place and returns
`PackChange.installed` without ever calling `decode`. If the theme document
then fails `OrbitTokens.fromThemeJson` (a malformed token value — the domain
gate only checks its `id`, effects and pattern), `ThemePackActions.install`
still reads `store.load(id)` as null and falls through to
`'${pack?.name ?? id} theme downloaded.'`: the page says the theme arrived,
and More themes never lists it. The folder stays on disk and no page can
delete it. The sound sibling gets this right — it returns "That sound cannot be
used on this phone" when `load` comes back null (`sound_packs.dart:127-128`).

**Trigger:** A signed pack whose theme document has a token value of the wrong
shape (the one class of document that passes `checkOrbitPack` and fails the
parse).

**Impact:** A false success on a download the person can see did not happen,
plus bytes that count against the device for ever and cannot be removed in the
app. Confusing, not dangerous.

**Fix sketch:** Decode before moving (call `decode` on the `PackBytes` in
`install`, and throw `PackRefused(badTheme, …)` when it is null), or check
`load` right after install and return the refusal sentence. The first is
better: it leaves nothing behind. No wire/schema change.

**Test that proves it:** a signed theme pack with `"lengthPx": {"r-md":
"wide"}` must return a refusal sentence and leave no `packs/<id>` folder; today
it returns "downloaded" and the folder exists.

**Overlap:** AUD-16-1 (the same gate gap, reached by a missing token, which
does not even fail the parse).

## Structural proposal S16-1

Shared with `16a_orbit_ui_theme.md` — one generated token contract checked by
the parse, so "this signed theme cannot be drawn" is one refusal in one place.
AUD-16-6's fix (decode before the rename) is the second half of the same
change: nothing is installed until the app has proved it can draw it.

## Coverage gaps

- No guideline or contrast check ever draws with **Orbit Night**;
  `orbitTestTheme()` is Orbit only (`app/test/support/orbit_theme.dart:26`),
  and `accessibility_test.dart` runs the checks on that theme. A contrast
  regression in the one dark theme is invisible to the suite.
- The 2x checks run on the sign-in page at the default 800 px surface only
  (AUD-16-5); no pack page, Appearance, Ringtones or Settings > list is pumped
  at 2x or at phone width.
- `fields.dart` has no widget test for the label/error association (AUD-16-4);
  `primitives_test.dart` covers buttons, chips, tags, switches and checkboxes
  but not `OrbitTextField` semantics.
- The galleries' delete path has no confirmation dialog for a downloaded pack.
  The copy says a re-download costs nothing, so this is a product choice, not a
  finding — but nothing asserts it stays that way.
- A downloaded ringtone is named by its pack id (slug) on Ringtones and in
  Settings > Notifications (`sound_packs.dart:102`, `:143`, `:228`), where a
  theme shows its signed name. Documented as the format's design ("a sound pack
  carries no display-name"); recorded here so a later "add names to sounds"
  change knows where the words come from.
