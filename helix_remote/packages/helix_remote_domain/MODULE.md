# Package: helix_remote_domain

Status: current, and nearly empty on purpose. Phase X deleted the v1 entities,
status transition tables and message-content types (nothing in v2 used them:
v2 wire types live in `helix_remote_protocol`, stored rows in
`helix_remote_db`, UI value objects in `helix_remote_ui`).

## Purpose

Shared value types that belong to no other layer. Today that is two files:
`HelixLegalDocuments` (the versioned terms and privacy text the sign-in page
shows) and the Orbit pack format, whose gate every downloaded pack - a theme or
a ringtone - passes before the app reads a byte of it
(`orbit/PORT_PLAN.md` Part C, ADR-033, `docs/product/THEME_PACK_FORMAT.md`). The
server keeps its own copy of the legal text in `helix_remote_protocol`
(`lib/src/legal.dart`) so it can serve `GET /v1/server/legal`; keep the two texts
and versions in step when the documents change (`docs/legal/`).

## Public surface

`lib/models.dart` exports `domain/legal_documents.dart` and
`domain/theme_packs.dart`. The pack gate is two calls: `checkOrbitPack` is the
whole of it, and `checkOrbitPackManifest` the first half - the shape and the
signature, with no files - for a page that has to know what kind of pack an
offer is before it pays for the bytes.

## Who may depend on this

The app (the sign-in legal sheet, and a theme-pack download) and
`tool/theme_pack_tool.dart`, which writes and signs the packs the app checks.
It may grow again if a type is needed by both the engine and the UI and by no
wire format; folding it into `helix_remote_protocol` is the alternative if it
never does.

## What this may depend on

No Helix package and no platform. The pack gate is handed this build's effect
registry and its trusted publisher keys as arguments rather than importing them
from `orbit_ui` or the app: that keeps the registry the design system's, the
trust anchor the release build's, and this package testable on its own.

One hosted dependency, added for the pack format: `cryptography` (Ed25519 and
SHA-256 at the version `helix_remote_crypto` already declared, so the lockfile
did not move). `helix_remote_crypto`'s own `ed25519Verify` is not usable here -
the package graph lets crypto depend on domain, never the other way round.
