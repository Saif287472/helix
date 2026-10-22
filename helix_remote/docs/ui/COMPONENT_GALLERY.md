# Helix Remote component gallery

**Superseded (2026-10-23).** The Remote app's visual language is now the Orbit
design system, `packages/orbit_ui`: its tokens (`OrbitTokens`), its components
under `lib/src/components/`, its screens under `lib/src/screens/`, and the view
models the app feeds them (`lib/models.dart`). The port is tracked in
`orbit/PORT_PLAN.md`, the accepted differences in `orbit/DEVIATIONS.md`, and
what a screen must look like in the prototype under `orbit/prototype/` - each
screen is scored against that prototype pixel for pixel
(`orbit/flutter/tools/compare/partb/score_all.py`).

What is still true:

- UI text is plain English string literals. There is no localisation layer.
- Every `IconButton` carries a `tooltip:`, and tap targets are at least 48 px.
- Nothing blocks screenshots.
- Colours come from the theme; no `Color(0x…)` or `Colors.x` in `app/lib`
  (`app/test/product_rules_test.dart`).

`helix_remote_ui` is no longer the client's kit: it keeps the old look for the
operator console only (its tokens, `HelixThemes.console()`, `HelixSkeleton` and
`showHelixDestructiveDialog`). See `packages/helix_remote_ui/MODULE.md`.
