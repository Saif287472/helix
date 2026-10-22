# ADR 031: Orbit is the app's design system

Status: accepted (2026-10-23).

Plan of record: `docs/architecture/ARCHITECTURE_V2_PLAN.md` (§6.1, §6 client
rules, §12 change log).

## Context

The v2 app was built on `packages/helix_remote_ui`: a light-only Material kit
of tokens, stateless components and view models, with the app mapping its own
state into those models. The product owner wanted a different product - a
distinct look of its own, a dark variant, and a design the prototype could be
held against. That is the Orbit port, planned in `orbit/PORT_PLAN.md`: an HTML
prototype under `orbit/prototype/`, the design system in
`packages/orbit_ui`, and the app's screens moved over one at a time, each
compared with the prototype's own render.

Since Phase X the app has gone through that move screen by screen. On
2026-10-20 Appearance grew a theme choice (Orbit and Orbit Night), which the
old kit - light only by rule - could not carry. This ADR records the end of the
move: what the two packages are now, and the import rule that goes with it.

## Decision

- **`packages/orbit_ui` is the app's design system.** Its tokens (`OrbitTokens`
  and the type, space, radius and font scales), its components
  (`lib/src/components/`), every Orbit screen (`lib/src/screens/`), and the
  view models the app feeds them (`lib/models.dart`, re-exported from
  `orbit_ui.dart`). It stays pure UI: models in, actions out, no engine,
  database, API, crypto or network import, no I/O in `build`.
- **The app imports nothing from `helix_remote_ui`.** Riverpod state reaches an
  Orbit screen through a connector in `app/lib/shared/widgets/`
  (`orbit_home_connector.dart`, `orbit_people_panel.dart`, and the rest), which
  maps providers into Orbit models and hands callbacks back out.
- **`packages/helix_remote_ui` remains the operator console's kit.** What the
  console actually draws: the colour, space, radius, elevation and typography
  tokens, `HelixThemes.console()`, `HelixSkeleton` and
  `showHelixDestructiveDialog`. The chat components, the gallery, the view
  models and their tests were deleted with the app's move, and so was this
  package's dependency on `orbit_ui`: it depends on Flutter only.
- **The import rule changes with it** (§6 rules, enforced by
  `app/test/architecture_test.dart`): `presentation/` may import its own
  `application/`, `shared/`, `orbit_ui` and `helix_remote_domain`.
- **The theme is chosen, not fixed.** The one picked on You > Appearance
  (Orbit, Orbit Night - more as packs later) is a device setting kept across
  sign-outs, and `app/test/product_rules_test.dart` checks that it is the only
  theme the app draws. This replaces the old "light theme only" rule.
- **Visual regression is the pixel gate, not a golden.** Every Orbit key is
  scored against the prototype by
  `orbit/flutter/tools/compare/partb/score_all.py` (the phone set and the
  window set, with the accepted differences listed in `orbit/DEVIATIONS.md`).

## Consequences

- The repo carries two UI kits that look nothing like each other. That is
  deliberate: the console is a dense operator tool on a different surface, and
  retheming it is separate work (parked with the console prototype).
- The old kit's rule suite shrinks from the component, accessibility,
  performance and golden tests to seven rules tests; the coverage moved to the
  app's own suite and `packages/orbit_ui/test/`.
- Screenshots stay allowed, UI text stays plain English literals, every
  `IconButton` keeps a tooltip and tap targets stay at least 48 px - the rules
  were re-asserted against Orbit, not relaxed.
- A screen that does not match the prototype is a documented difference or a
  bug; `orbit/DEVIATIONS.md` is the record.

## Alternatives considered

- Keep `helix_remote_ui` and retheme it for Orbit: rejected. Orbit's geometry,
  type scale and component set are different enough that the old widgets would
  have been rewritten anyway, and the console would have inherited a look it
  never asked for.
- Delete `helix_remote_ui` outright and port the console to Orbit now:
  rejected as one change too many; the console port is its own piece of work.
- Keep the golden test as the visual gate: rejected. A golden pins one
  platform's rasterisation, while the pixel gate compares against the
  prototype on the machine the design was made on.
