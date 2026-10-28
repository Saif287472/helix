# orbit

The Orbit design record for the Flutter port: `PORT_PLAN.md`, `DEVIATIONS.md`,
`GAPS.md`, `HANDOFF.md`, the screen `contracts/`, the `audit/` of the port and
the `flutter/` workspace with its tools.

The HTML prototype this was built from (`orbit/prototype/`, the loose
`index.html`, `app.js` and `styles.css` here, and the older `console/prototype/`)
was removed on 2026-10-28 and is no longer the specification: the Flutter screens
in `helix_remote/packages/orbit_ui` are. Code comments and older docs that name
`orbit/prototype/...` mean the files as they were at commit `260107a`
(`git show 260107a:orbit/prototype/<path>`). The theme generator
`orbit/prototype/tools/themes.py` is among them; `orbit_tokens.g.dart` is kept
as it is and now edited by hand, or regenerate it from that commit's script.
