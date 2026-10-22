# helix_remote_ui

The old Helix look, kept for the operator console (`admin/`) only: the colour,
space and radius tokens, the console theme and the two widgets it draws. The
app moved to `orbit_ui` (`orbit/PORT_PLAN.md`, Part B step 4) and imports
nothing here.

Depends on Flutter only: no engine, database, API, crypto or `orbit_ui`
package. Import `package:helix_remote_ui/helix_remote_ui.dart`; the two widgets
are a `part` file, `lib/src/components.dart`.

## What is here

- Tokens: `HelixColorTokens` (brand, status colours, the avatar palette),
  `HelixScrimColors`, `HelixNeutralColors`, `HelixCallColors`,
  `HelixConsoleColors` (the console's slate and blue), `HelixStatusColors`,
  `HelixSpace`, `HelixInsets`, `HelixRadius`, `HelixElevation`,
  `HelixTypography`, `HelixBreakpoints`.
- Theme: `HelixThemes.console()`. Light only - there is no dark or
  high-contrast variant, and the app's `light()`/`signIn()` builders were
  deleted with its old screens.
- Widgets: `HelixSkeleton` and `showHelixDestructiveDialog`.

The chat components, the gallery and the view models went with the app's move
to Orbit; `packages/orbit_ui` is where a screen is drawn now.

## Rules (each has a test in `test/package_rules_test.dart`)

- **Colours only from tokens or the colour scheme.** No `Color(0x...)` or
  `Colors.x` (not even `transparent`) outside `lib/helix_remote_ui.dart`.
- **Light theme only.** No dark variant exists.
- **English literals only.** No localisation layer.
- **Every `IconButton` has a `tooltip:`** (the scanner itself is tested).
- **Screenshots are allowed**: nothing here blocks capture.
- **Flutter is the only dependency**, and no library file imports the engine,
  database, API or crypto package.

## Tests

`flutter test` in this package runs `test/package_rules_test.dart` only (the
component, a11y, performance and golden tests left with the components). There
is no golden baseline here any more; the app's Orbit screens are scored
pixel-for-pixel against the prototype instead
(`orbit/flutter/tools/compare/score_all.py`).
