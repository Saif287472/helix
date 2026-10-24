# Sweep 16a — `orbit_ui` themes: tokens, motion, effects, painters

Read-only. Scope: `packages/orbit_ui/lib/src/theme/` (2,009 lines read in full:
`orbit_tokens.dart`, `orbit_tokens.g.dart`, `orbit_theme.dart`,
`orbit_metrics.dart`, `orbit_text.dart`, `motion.dart`, `effects.dart`,
`pattern_painter.dart`, `effect_shapes.dart`, plus `css_gradient.dart`,
`turbulence.dart`, `svg_path.dart`, `orbit_font_families.dart` by their use),
the app side that loads and cross-fades a theme (`main.dart`,
`core/theme/orbit_app_theme.dart`), and the theme-pack decode path
(`core/theme/orbit_packs.dart`, `helix_remote_domain/lib/domain/theme_packs.dart`).
The pack pages and the a11y primitives are `16b_orbit_ui_packs_a11y.md`.

## What is sound

- **A theme is data, and only data.** Every value comes from one JSON document;
  the effect and pattern *types* stay in the app and a name the build does not
  ship is refused at load, not ignored (`effects.dart:121-143`,
  `orbit_tokens.dart:127-134`). A release build can therefore never be asked
  to run a pack's code.
- **Malformed values fail the load.** A colour without alpha, a string where a
  number belongs, a bad font stack, a negative duration, and a cubic-bezier
  whose x leaves 0..1 all throw `FormatException`
  (`orbit_tokens.dart:36-135`, `motion.dart:45-86`). Nothing is defaulted in
  silence.
- **Motion is theme data with the platform's veto.** The two durations and the
  curve come from the theme; `OrbitMotion.allowed` reads the OS's
  reduce-motion setting and the callers do not start the animation at all
  (`motion.dart:38-142`).
- **A pack never shadows a built-in.** The library spreads packs first and
  built-ins last (`orbit_app_theme.dart:54-62`), and the chosen theme falls
  back to Orbit when its id is not drawable (`:89-92`).
- **The pack gate is signature, digest, size and kind before anything moves**
  (`orbit_packs.dart:178-307`): files are fetched and stored by SHA-256, the
  staging folder is renamed only after the whole pack passes, and a folder
  that later fails is left on disk and simply not offered
  (`orbit_packs.dart:129-143`, `:369-434`).
- **The token surface is generated and cross-checked.** 111 getters are
  generated from the same table that writes the CSS (`orbit_tokens.g.dart`),
  and a test reads every theme's every token (`orbit_tokens_test.dart:61`).
- **Painters are cheap where it matters.** Each pattern tile is rasterised once
  and cached (`pattern_painter.dart:124-141`); `shouldRepaint` compares the
  pattern object and colour (`:109-111`), both of which are stable between
  frames of one token object.

## AUD-16-1 A signed theme pack that parses but cannot be drawn is accepted, and then breaks the next launch

**Severity:** P2
**Confidence:** confirmed
**Where:** [orbit_packs.dart:562-579](file:///J:/Projects/helix/helix_remote/app/lib/core/theme/orbit_packs.dart#L562-L579),
[orbit_tokens.dart:36-135](file:///J:/Projects/helix/helix_remote/packages/orbit_ui/lib/src/theme/orbit_tokens.dart#L36-L135),
[orbit_tokens.dart:203-215](file:///J:/Projects/helix/helix_remote/packages/orbit_ui/lib/src/theme/orbit_tokens.dart#L203-L215),
[theme_packs.dart:645-711](file:///J:/Projects/helix/helix_remote/packages/helix_remote_domain/lib/domain/theme_packs.dart#L645-L711),
[main.dart:70-73](file:///J:/Projects/helix/helix_remote/app/lib/main.dart#L70-L73),
[main.dart:214](file:///J:/Projects/helix/helix_remote/app/lib/main.dart#L214),
[orbit_app_theme.dart:89-92](file:///J:/Projects/helix/helix_remote/app/lib/core/theme/orbit_app_theme.dart#L89-L92),
[orbit_theme.dart:20-33](file:///J:/Projects/helix/helix_remote/packages/orbit_ui/lib/src/theme/orbit_theme.dart#L20-L33),
[orbit_tokens_test.dart:209-234](file:///J:/Projects/helix/helix_remote/packages/orbit_ui/test/orbit_tokens_test.dart#L209-L234)

**What:** `ThemePackStore._pack` says in its own words that "drawing with it
needs every one of its 111 tokens, which is this parse's job" — but the parse
does no such check. `OrbitTokens.fromThemeJson` walks the *document's* groups
and stores whatever it finds; a token that is simply absent is never noticed.
`value<T>` throws `ArgumentError` only when a screen reads the missing token —
which the token test states is deliberate, for a buggy *screen*. A pack is not
a screen. So `_pack` accepts the document, the pack is listed on More themes
and can be chosen, and the first read of the missing token throws inside
`HelixRemoteApp.build` (`OrbitTheme.of` reads `accent`, `surface`, `ink`, …
for the `ColorScheme`), above the router and above every error boundary.

The domain gate does not close the gap either: it checks the theme document's
`id`, its effect kinds and its pattern kind (`theme_packs.dart:650-711`) and
nothing about its tokens.

**Trigger:** A trusted publisher signs a theme document missing one token — or,
more likely over time, a later app build adds a token while an older pack is
still installed and chosen. The pack passes signature, digest and size; the
gate passes; `decode` parses it. Choosing it writes the id to
`device_settings.json` (`orbit_app_theme.dart:81-85`), so the throw now happens
before the first frame of **every** launch. The only exit is clearing the app's
data or the pack folder by hand.

The same hole admits pattern params the painter force-unwraps —
`pattern_painter.dart:100-102` reads `colour` and `a` with `!`, `:162-163` and
`:204-205` likewise — so a signed `scanlines` or `neonGrid` pattern missing a
param throws during `paint`.

**Impact:** A data-only path the product promises is always safe can leave the
app unusable across restarts, with no in-app way back. That is worse than a
crash: re-opening the app repeats it.

**Fix sketch:** No wire or schema change. Make completeness part of the parse:
generate a `requiredTokenNames` list beside the getters and have
`fromThemeJson` throw `FormatException` for any absent name (and validate the
pattern params the painters read). `_pack`'s existing `on FormatException`
then turns an undrawable pack into "not a theme today", exactly as its comment
claims. Belt and braces: have `orbitTokensProvider` try to build `ThemeData`
from the pack and fall back to Orbit if it cannot, so a future read-time error
cannot be fatal at start-up.

**Test that proves it:** a theme document carrying only `colour.accent` must
load as `null` from `ThemePackStore().load(id)` (today it loads and is
choosable); and a widget test with `initialThemeIdProvider` set to that pack
must still pump a first frame on Orbit. Today neither exists — `theme_packs_test.dart`
has no case for a parseable-but-incomplete theme.

**Overlap:** AUD-16-6 (the download reports success for the same class of
pack). The token test at `:209-234` documents the read-time throw as intended;
this finding is that it must not be reachable from signed data.

## AUD-16-2 `OrbitTokens.lerp` returns the wrong theme at both ends, so every theme change flickers

**Severity:** P3
**Confidence:** confirmed
**Where:** [orbit_tokens.dart:236-252](file:///J:/Projects/helix/helix_remote/packages/orbit_ui/lib/src/theme/orbit_tokens.dart#L236-L252),
[orbit_tokens_test.dart:316-321](file:///J:/Projects/helix/helix_remote/packages/orbit_ui/test/orbit_tokens_test.dart#L316-L321),
[app.dart:1057-1059](file:///C:/flutter/packages/flutter/lib/src/material/app.dart#L1057-L1059),
[theme_data.dart:1794-1806](file:///C:/flutter/packages/flutter/lib/src/material/theme_data.dart#L1794-L1806)

**What:** The override is `if (other == null || t >= 1) return this; if (t <= 0)
return other;` — the endpoints are swapped against the `ThemeExtension`
contract. Flutter calls `extensionA.lerp(extensionB, t)` with `A` the theme
being left and `B` the theme being entered, so `t == 0` must be `A` and
`t == 1` must be `B`. Here it is the reverse. The unit test asserts the
inversion (`expect(orbit.lerp(night, 0), same(night))`), so it cannot catch it.

**Trigger:** Choosing any theme on You > Appearance. `MaterialApp` always wraps
its child in `AnimatedTheme`, using `themeAnimationDuration` (200 ms by
default, `app.dart:248`, `:1057-1059`), so the app cross-fades on every
change, including the fallback to Orbit when a chosen pack is deleted.

**Impact:** At the frame the animation starts, `t` is 0 and the **new** theme
is drawn; a frame later the value snaps back to almost the old theme, fades
correctly, and the final frame at `t == 1` draws the **old** theme again before
the new one lands. On screen that is a flash of the target theme, a fade, and a
flash of the old one — the transition reads as broken on a 60 Hz phone, and any
screenshot or `compare` run taken in that window is flaky.

**Fix sketch:** Swap the two returns (`t <= 0 → this`, `t >= 1 → other`) and
correct the test to the contract; add a test that goes through
`ThemeData.lerp`, which is the caller that matters. No schema or wire change.

**Test that proves it:** `ThemeData.lerp(OrbitTheme.of(orbit),
OrbitTheme.of(night), 0).extension<OrbitTokens>()` must equal `orbit` and at
`t == 1` must equal `night`. The current test asserts the opposite.

**Overlap:** None. Also note that a theme missing keys turns into `null` tokens
mid-fade (`orbit_tokens.dart:243-246`), which is the same class of pack as
AUD-16-1.

## AUD-16-3 Tokens are keyed by bare name in one flat map, so a document can silently replace a token from another group

**Severity:** P3
**Confidence:** likely
**Where:** [orbit_tokens.dart:105-135](file:///J:/Projects/helix/helix_remote/packages/orbit_ui/lib/src/theme/orbit_tokens.dart#L105-L135),
[orbit_tokens.g.dart:22-151](file:///J:/Projects/helix/helix_remote/packages/orbit_ui/lib/src/theme/orbit_tokens.g.dart#L22-L151)

**What:** Every group's value is stored as `values[token.key as String] = …`,
dropping the group, while the generated getters look tokens up by that same
bare name. Two groups with the same leaf name therefore keep only whichever
came last in JSON order: same type, the wrong value is drawn silently; different
type, `value<T>` throws `ArgumentError` at draw time. The class comment's
promise — "Throws `FormatException` when a token is missing or a value has the
wrong shape" (`orbit_tokens.dart:31-33`) — does not hold across groups.

**Trigger:** A theme pack (or a future generator change) that writes, say,
`"em": {"display": 0.1}` after `"weight": {"display": 700}`. The document
loads; `displayWeight` then reads a `double` and throws on the first screen
that draws a display title. The built-ins are safe because the generator emits
unique getter names, and the count test would catch a collision there.

**Impact:** Latent. It is the same failure mode as AUD-16-1 reached through a
different door: a signed document that parses into something the app cannot
draw.

**Fix sketch:** Key the map by `group.key` (the code already builds that string
at `:104`) and let `value<T>` look up `group.key` — or keep the flat map and
refuse a duplicate leaf name during the parse. Either way one `FormatException`
at load, not an `ArgumentError` at draw. A test with a colliding pair belongs
beside the malformed-value test.

**Test that proves it:** `fromThemeJson` with the two colliding groups above
must throw `FormatException` (today it loads, and `displayWeight` throws later).

**Overlap:** AUD-16-1 (undrawable signed data accepted).

## Structural proposal S16-1 One generated theme contract, checked by the same code for built-ins and packs

**Current shape:** The token surface exists twice — the generated getters know
the names, and the JSON parser treats the document as authoritative about which
names exist. The built-in test checks the two agree; nothing checks a pack.

**Hazard:** AUD-16-1 and AUD-16-3: a downloaded theme passes every gate and
then throws inside `MaterialApp`, and because the choice is persisted it throws
on every launch.

**Proposed shape:** The generator emits, beside `OrbitTokensValues`, a
`static const requiredTokens = <String>{...}` (and the required pattern params
per kind). `OrbitTokens.fromThemeJson` compares its parsed key set against it
and throws `FormatException` naming the missing token. `ThemePackStore._pack`
already catches that exception, so the pack path needs no new code — and the
existing built-in test can read the same set instead of inferring it.

**Migration path:** expand (add the generated list and the check, keep parsing
as it is) → migrate (fix any built-in or published pack that fails) → contract
(none needed; the parse is strict from then on). No wire or database change.

**Risk:** Low. A pack refused today that draws fine would surface only if it
was already incomplete; the check cannot reject a complete document. The one
compatibility cost is that an app update adding a token will stop offering
older packs that lack it — which is the correct outcome, and the fallback is
Orbit, not a broken screen.

**Rough size:** ~40 lines of generator output plus ~15 in the parse and a few
tests.

## Coverage gaps

- No test downloads, chooses and then *re-launches* with a pack that parses but
  is incomplete (AUD-16-1). `theme_packs_test.dart` covers unsigned, wrong
  bytes, wrong file, unknown effect, wrong kind and byte caps.
- No test exercises `ThemeData.lerp` on the extension (AUD-16-2); the only
  lerp test asserts the inverted endpoints.
- Pattern params are validated for `kind` only; the painters' `!` reads
  (AUD-16-1) are untested.
- The grain tile is synthesised synchronously on first paint
  (`pattern_painter.dart:216-260`, 25,600 turbulence evaluations for a 160px
  tile). Not measured here, so not a finding — but no budget test covers the
  first paint of a Papyrus/Bloom page.
- `_Tiles._cache` is a static map that is never cleared and keys on
  `p.params.toString()`, so the same settings in a different map order
  rasterise twice. Bounded by the themes on the device and small images; noted,
  not raised.
