# ADR 033: A theme pack is signed data, and the app checks it before it opens it

Status: accepted (2026-10-23).

Plan of record: `docs/architecture/ARCHITECTURE_V2_PLAN.md` (§6.1, §12 change
log) and `orbit/PORT_PLAN.md` (Part C steps 1-2).

## Context

Part B made the app draw a theme from JSON: `OrbitTokens.fromThemeJson` reads
one document per theme, and the fourteen theme effects are a named registry
(`OrbitEffectKind`) that the app ships and a theme only switches on. Part C
sells the same thing as downloads: the other six themes become packs, and later
decorative animations and ringtones come the same way.

The download is the risk. Helix Global serves the pack, but the server is not
the trust anchor: it can be hacked, and a theme folder can be replaced in place
with no account compromise at all. `orbit/PORT_PLAN.md` Part C states the rule
this ADR implements - "Every pack is signed with the publisher's key. Before
using a pack, the app checks its signature, size limits and format. Font, audio
and animation files are a known attack route, so this holds even if the server
is hacked."

Two facts make that tractable rather than open-ended. A release Flutter build
cannot load downloaded code, so a pack is data and nothing else; and the effect
registry is already closed, so a pack can only name effects the app already
has. What was missing was the envelope: what a pack *is*, who signs it, and
where the checking happens.

## Decision

- **A pack is a folder with one manifest and one theme document.** The
  manifest (`manifest.json`, format version 1) names the pack, its publisher
  and its revision, lists every file by path, kind, byte size and SHA-256, and
  carries an Ed25519 signature. The theme document inside the pack is the same
  JSON the built-in themes are written in, unchanged, so a pack's theme and
  `assets/themes/orbit.json` are the same kind of thing.
  The format is specified in `docs/product/THEME_PACK_FORMAT.md`.
- **The gate is one function, in `packages/helix_remote_domain`.**
  `checkOrbitPack` returns either the parsed manifest or a typed refusal
  (`OrbitPackFailure`, fourteen of them until step 5's fifteenth, each with one
  line of safe detail). Nothing else in the client may decide whether a pack is
  usable.
- **The order of the checks is the security property.** Sizes, path shape and
  manifest shape are read first; then the publisher's signature over the
  canonical manifest bytes; only then are the pack's own files hashed and its
  theme document parsed. A pack whose signature does not verify is never opened,
  so no parser bug in the theme layer, the font loader or an image decoder can
  be reached by a pack that was not signed. A test pins this ordering.
- **The app holds the trust anchor; `orbit_ui` holds the registry.** The
  publisher keys and this build's effect and pattern names are *arguments* to
  the gate, not imports of it. That keeps `helix_remote_domain` free of any
  Helix or Flutter dependency (its architecture test already demanded this),
  keeps `OrbitEffectKind` the single source of what can be drawn, and puts the
  keys in the release build that ships them. Step 3 gives that a concrete shape:
  `--dart-define=HELIX_PACK_PUBLISHERS=slug:hex,slug:hex`, the same build-time
  switch as `HELIX_GLOBAL_PINS`, read by `PackTrust` in
  `app/lib/core/theme/orbit_packs.dart`. Not a page where a person types a key:
  a release app cannot take a trust decision from its own UI without turning the
  download of code-adjacent data into a self-granted permission.
- **Nothing is trusted until the owner publishes a key.** The app's anchor map
  ships empty for now, so every downloaded pack is refused as
  `unknownPublisher`. That is the safe direction for the step that only defines
  the format: no pack can be accepted before a human has chosen the key.
- **A pack can never bring an effect.** The gate refuses `unknownEffect` and
  `unknownPattern` by name against the injected registry, which is the same
  refusal `OrbitEffects.validate` already makes when a theme is parsed. A pack
  that asks for something the build does not have is refused, not degraded.
- **Signing is a repository tool, not app code.**
  `helix_remote/tool/theme_pack_tool.dart` is `keygen`, `pack`, `sign`,
  `verify` and `publish`. It reads a private key from a file named by
  `--seed-file`, uses it once, and never prints it. No client code can sign
  anything.
- **`helix_remote_domain` gains its first dependency**, `cryptography` at the
  version `helix_remote_crypto` already declared, so the workspace lockfile did
  not move. It takes Ed25519 and SHA-256 from there; the crypto package's own
  `ed25519Verify` is unreachable, because the graph lets crypto depend on
  domain and never the other way round.
- **Refusals are safe to log.** A detail names the field, the path or the
  registry name that failed - identifiers the format itself constrains - and
  anything a pack wrote about itself is passed through a shape filter first, so
  a pack cannot quote itself into the client's logs.

## Consequences

- Part C step 2 is the server endpoint that serves this folder, and it needed
  no part of the format: `HELIX_PACKS_DIR` is a tree of files the operator puts
  there with `publish`, `GET /v1/packs` lists the folder's own names and stats,
  the manifest is streamed byte for byte, and a file is picked by its SHA-256.
  The server holds no copy of these checks, signs nothing and holds no key, so a
  malicious or compromised endpoint can serve an old pack or no pack and cannot
  serve a new one.
- A pack revision is only comparable inside one publisher and one id; the app
  keeps the highest revision it has for a theme id, which is what makes a
  re-download an upgrade rather than a downgrade (step 3's job).
- `font` and `image` are named kinds in the format ahead of the step that ships
  their loaders, so a pack that carries one today is signed, hashed and
  size-limited and simply not read. When a loader comes, the gate does not
  change.
- The publisher key is one secret the owner must keep off this machine's normal
  backups and off any build server; losing it means no pack can ever be updated,
  and leaking it means anyone can ship themes to every device. Rotation is a
  format-compatible event (the anchor is a map), but no pack signed by the old
  key is re-accepted until the owner adds both.
- The domain package is now genuinely shared logic rather than a text file: it
  has a dependency, a CLI user (`tool/`), and a security invariant with tests.
- Screenshots, plain-English UI text, tooltips and 48 px targets are unaffected;
  the refusal strings the settings page will show in step 3 are plain English
  literals like any other UI text.

## Alternatives considered

- **Re-use `helix_remote_crypto` for the signature check.** Rejected: the
  package graph would have to invert, and the client's end-to-end crypto package
  is not where a design-system download's trust decision belongs.
- **Put the gate in `orbit_ui`.** Rejected: `orbit_ui` is a leaf that imports no
  Helix package and must stay pure UI; it would also have to own the trust
  anchor, which is release state, not design state.
- **Sign the whole pack as one blob (a detached signature over a tarball).**
  Rejected for step 1: the app downloads files one at a time and wants to refuse
  a truncated or swapped file with a named reason; per-file SHA-256 in a signed
  manifest gives that without a container format.
- **Reuse the theme document itself as the manifest** (add `publisher`,
  `signature` fields to it). Rejected: the eight built-in theme JSONs are
  generated by `orbit/prototype/tools/themes.py` and are theme data; an envelope
  that can carry a font or a sound has no business being inside a colour table.
- **Let the server sign packs with its own account key.** Rejected: that makes
  every operator's personal server a publisher of code-adjacent data to every
  client. One publisher key, pinned in the app, is the design.

## Amendment (2026-10-23): a pack may be a sound

`orbit/PORT_PLAN.md` Part C step 5, ruled by the owner the same day: a ringtone
arrives as a signed pack rather than through a second download route. So a
pack's one body file may be audio instead of a theme document.

What that took: an optional `contents` word in the manifest (`theme` or
`sound`, and absent means `theme`); `theme` became a field a pack may omit;
`audio` became a fourth file kind; and the gate gained `unknownContent` plus the
rule that a pack carries exactly one body file, a sound pack being that file and
nothing else beside it.

What did not change is the part worth recording. `contents` is only written when
it is not the default, so a theme pack's signed bytes - and the pinned vectors
above, and every pack already built - are byte for byte what they were before
ringtones were a thing. The order of the checks is the same, and a sound's bytes
are still never opened: the gate hashes them, and the app hands them to Android.
The server took no change at all, because the three pack routes serve a file by
its digest and never look at what it is.

One consequence is deliberately left open. A `HELIX_PACKS_DIR` holding both kinds
lists both on one route, since `contents` is inside the signed manifest and the
endpoint does not read it. Whether a page filters its list - a protocol and
server change, so the owner's call - or the two kinds go in two folders is the
remaining decision of step 5.
