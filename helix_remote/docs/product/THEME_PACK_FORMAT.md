# Orbit theme packs: the format

Status: current, steps 1-2 of `orbit/PORT_PLAN.md` Part C (2026-10-23).
Decided by [ADR-033](../adr/033-theme-packs-are-signed-data.md).
Implemented by `packages/helix_remote_domain/lib/domain/theme_packs.dart`,
checked by `packages/helix_remote_domain/test/theme_packs_test.dart`,
written by `helix_remote/tool/theme_pack_tool.dart`, and served by
`helix_remote/server/lib/src/modules/ops/pack_host.dart`.

A theme pack is **data**. It carries a theme document in the JSON the built-in
themes are already written in, and it may only switch on effects this build
ships. A pack cannot bring code, cannot bring an effect, and cannot be used
until a publisher this app trusts has signed it. That is what makes it safe to
serve from a computer that might itself be hacked: the app checks the pack, not
the server.

## What a pack is

```
synthwave/
  manifest.json              the envelope; this document describes it
  themes/synthwave.json      the theme document, exactly like assets/themes/
```

`manifest.json`:

```json
{
  "formatVersion": 1,
  "id": "synthwave",
  "publisher": "agiletechbd",
  "revision": 1,
  "theme": "themes/synthwave.json",
  "files": [
    {
      "path": "themes/synthwave.json",
      "kind": "theme",
      "bytes": 109,
      "sha256": "215b71602638020f7cfc18c10c6fa652642833f2c69729d80c4ff7251fd872cb"
    }
  ],
  "signature": "woAAGLL8UU2ZyYhtqiGaAqNwaoCZHpyr8ADuGC0JtzTxz5QkuqtoZFBq6Eol3iN6l1BdOX+kBFDggpF9oE6BBw=="
}
```

| Field | Rule |
|---|---|
| `formatVersion` | must be exactly `1`. Anything else is refused, not guessed at. |
| `id` | the theme's id: `[a-z0-9][a-z0-9._-]{0,63}`. The theme document's own `id` must equal it. |
| `publisher` | whose key must have signed this, same shape as `id`. |
| `revision` | whole number from 1. The app keeps the highest it has per `id`. |
| `theme` | the path of the one theme document, and one of `files`. |
| `files[]` | up to 16 entries: `path`, `kind`, `bytes`, `sha256`. |
| `signature` | base64 of 64 bytes, Ed25519 over the bytes below. |

### `files[]`

`path` is relative to the pack root and is checked before anything opens it: no
leading or trailing `/`, no `.` or `..` segment, no empty segment, and each
segment matching `[A-Za-z0-9][A-Za-z0-9._-]*`, at most 96 characters in total.
Anything else is refused - the app never builds a filesystem path from a pack.

`kind` is one of three, and the extension must match it:

| kind | extensions | read by the app today |
|---|---|---|
| `theme` | `.json` | yes - it is the theme |
| `font` | `.ttf`, `.otf`, `.woff2` | no (Part C's font step ships the loader) |
| `image` | `.png`, `.webp` | no |

A `font` or `image` in a pack is signed, hashed and size-limited like any other
file and simply not read yet. That is deliberate: the format does not change
when a loader arrives.

Exactly one file is `kind: "theme"`, and it is the one `theme` names.

`sha256` is 64 lowercase hex characters of that file's bytes, and `bytes` is its
length. Both are compared with what the download delivered.

## What is signed

The manifest without its `signature` field, as JSON with every object's keys in
code-unit order, no whitespace, control characters escaped the way `dart:convert`
escapes them, UTF-8. The example above signs exactly these 253 bytes:

```
{"files":[{"bytes":109,"kind":"theme","path":"themes/synthwave.json","sha256":"215b71602638020f7cfc18c10c6fa652642833f2c69729d80c4ff7251fd872cb"}],"formatVersion":1,"id":"synthwave","publisher":"agiletechbd","revision":1,"theme":"themes/synthwave.json"}
```

`OrbitPackManifest.signingBytes()` produces them, `tool/theme_pack_tool.dart`
signs them, and the app rebuilds them from the manifest it downloaded. Those
same three strings - the bytes, the key, the signature - are pinned as vectors
in `packages/helix_remote_domain/test/theme_packs_test.dart`, so the signing
form cannot change without a test failing.

The signature is `publisher`'s Ed25519 signature. The app's trust anchor is a
map of publisher id to a 32-byte key, compiled into the release. **Today that
map is empty**: no pack is accepted anywhere until the owner generates a key
(`keygen`), pastes the public half into the app's anchor, and ships it. A pack
whose publisher is not in the map is refused as `unknownPublisher`, and so is a
map entry whose key is not 32 bytes.

## The limits

| | default | refused as |
|---|---|---|
| manifest | 64 KiB | `tooLarge` |
| one file | 8 MiB | `tooLarge` |
| a pack's files together | 24 MiB | `tooLarge` |
| file count | 16 | `tooManyFiles` |
| path length | 96 characters | `badPath` |

A built-in theme document is about 9 KiB, so these are far above what a real
pack needs and nowhere near what would hurt a phone. The declared size is
checked against the limit *before* the bytes are hashed, and the delivered size
against the declared one after.

## What the app refuses, and in which order

`checkOrbitPack` is the only place this is decided. Its order is the security
property: nothing from inside a pack is opened until its signature verifies.

1. **Sizes and shape, from the manifest alone** - `tooLarge`, `unknownFormat`,
   `badManifest`, `badPath`, `tooManyFiles`.
2. **The publisher and the signature** - `unsigned`, `unknownPublisher`,
   `badSignature`.
3. **The pack's own files** - `missingFile`, `changedFile` (a file that is not
   the one hashed, a size that is a lie, or something the manifest never
   listed).
4. **The theme document** - `badTheme`, `themeMismatch`, `unknownEffect`,
   `unknownPattern`.

Each refusal carries one line of detail: which field, which path, which
registry name. A pack's own words are quoted only where the format constrains
them to an identifier; anything else (an effect name from inside a theme
document, for example) is filtered to `(not an identifier)`, so a pack cannot
quote itself into a log line.

After the gate, the app hands the theme document to `OrbitTokens.fromThemeJson`,
which is strict about every token and validates the effects against the same
registry a second time. A pack that passes the gate but fails the parser is
never drawn, and the chosen theme falls back to Orbit.

## Making a pack

```
dart run tool/theme_pack_tool.dart keygen --seed-file keys/agiletechbd.hex
dart run tool/theme_pack_tool.dart build \
  --themes packages/orbit_ui/assets/themes \
  --ids bloom,mochi,papyrus,arcade,terminal,field \
  --out build/packs --publisher agiletechbd --revision 1 \
  --seed-file keys/agiletechbd.hex
dart run tool/theme_pack_tool.dart verify --in build/packs/bloom --key <publisher key>
dart run tool/theme_pack_tool.dart publish --in build/packs/bloom \
  --out "$HELIX_PACKS_DIR"
```

`keygen` prints the publisher key and writes the private one; it never prints
the private key. `build` is Part C step 8's one command: for every slug it
copies `--themes/<slug>.json` to `--out/<slug>/themes/<slug>.json` and writes
that folder's manifest, signing it when `--seed-file` is given, so a whole
theme table is staged without anyone building a folder by hand. The slug is
checked with the format's own rule (`isOrbitPackName`) before it becomes a
path, the document's own `id` must still be the slug, and a staged file that is
a different generation of the same theme is refused rather than overwritten.
What `build` writes is staging; `publish` is what makes an offer.
`pack` is the same step for one folder that already exists - a pack with a font
or an image beside its theme, which `build` cannot stage because those files
are not in the theme table. A folder built without a seed stays unsigned until
`sign --manifest FILE --seed-file PATH` signs it.
`pack` hashes the folder (its own `manifest.json` is never
listed) and refuses a folder whose single `.json` document calls itself another
theme. `verify` runs the app's own gate, not a copy of it; `--effects` and
`--patterns` are the publisher's dry run of the registry check, because
`orbit_ui` cannot be imported by a Dart script - say so in the output when they
are left out. `publish` copies a signed pack into the server's folder, and
re-checks the folder against the manifest on the way: a file the manifest names
must be there and must hash to what was signed, and an already-published
revision is never rewritten (build `--revision 2` instead), because that name
is the bytes a device may already hold.

Every theme document the generator writes is put through this pipeline in
`app/test/settings/theme_packs_test.dart` ("the theme table as packs"), signed
with a key that exists only for that run and installed through the real store,
so a theme that only looks right in JSON fails a test instead of arriving on a
phone as a refused download.

The seed file is a secret. Keep it off this machine's ordinary backups and off
any build server; losing it strands every pack ever signed with it, and leaking
it lets anyone ship a theme to every device.

## What the server does (step 2)

Three public routes, no session, in the `ops` module
(`server/lib/src/modules/ops/pack_host.dart`, `MODULE.md`):

```
GET /v1/packs
GET /v1/packs/{pack_id}/revisions/{revision}/manifest
GET /v1/packs/{pack_id}/revisions/{revision}/files/{digest}
```

`HELIX_PACKS_DIR` is the folder they read, in the layout `publish` writes
(`<id>/r<revision>/manifest.json` and the same folder's `files/<sha256>`). The
list is the folder's own names and file stats - it carries no display name,
because a name here would be unsigned while the one a device shows comes from
the signed theme document. The manifest comes out as it went in, byte for byte,
and a file is picked by its SHA-256 rather than by a path.

The endpoint signs nothing, holds no key, and knows no part of this format: it
has no copy of the limits except the two it refuses to stream past (64 KiB and
8 MiB), and it never parses what it serves. So a malicious or broken endpoint
can serve an older revision, a different pack, or nothing at all - it cannot
make a device accept anything, because `checkOrbitPack` still runs over the
bytes on the phone. That is the whole point of a pack being data.

## What the phone does (step 3)

`helix_remote/app/lib/core/theme/orbit_packs.dart` keeps what a person
downloads, in the server's own layout under the app's `packs` folder:

```
packs/<pack id>/r<revision>/manifest.json
packs/<pack id>/r<revision>/files/<sha256>
```

Rules that are the device's, not the format's:

- **The gate runs on every read, not only on download.** A folder that was
  edited afterwards, or that a newer app no longer trusts the publisher of, is
  simply not a theme. Its bytes stay on disk - deleting what a person downloaded
  is their action, not the app's reaction to a check.
- **Nothing is opened by a path a pack named.** Files are written and read by
  their SHA-256, which is what the route asks for too, so the folder a device
  holds is content-addressed and a file two revisions share is stored once.
- **A download is staged, checked, then renamed.** Bytes land in
  `packs/.staging/<id>-r<rev>-<time>` and only a pack that passes the gate is
  moved into place, so a refused or truncated download can never replace the
  theme on screen, and staging is removed whatever happens.
- **Revision numbers only compare inside one publisher and one id.** The store
  keeps the highest revision it has, refuses a downgrade (the newest thing on
  offer is what an update downloads), and returns `alreadyCurrent` without
  fetching when the revision on the device is already the one asked for. Older
  revisions of the same pack are deleted after a new one is in place, because
  the person cannot switch to them and they are the bulk of the folder's bytes.
- **Bandwidth is refused before it is spent.** A file over 8 MiB, a total over
  24 MiB or more than 16 files, as the manifest itself declares them, are
  refused before a byte is fetched; the delivered bytes are then re-checked
  against the manifest by the gate.
- **The anchor is the build's.** `PackTrust` reads
  `--dart-define=HELIX_PACK_PUBLISHERS=slug:hex,slug:hex` (the same shape as
  `HELIX_GLOBAL_PINS`), so the keys are release state compiled into the app that
  ships them, not data the network can hand out. It is empty by default, which
  means every pack is refused as `unknownPublisher` until the owner publishes a
  key and it reaches a build. A malformed value is read as "trusts nobody" on
  the start-up and theme-library read paths, so a typo in a define cannot stop
  the app starting or leave it with no theme; the pages that manage packs fail
  the action instead, so the typo is noticed rather than shipped silently.
- **A pack never takes a built-in theme's name.** The theme library is the
  downloaded packs with the built-ins merged over them, and a download of an id
  that is built in is refused in words, so Orbit and Orbit Night are always the
  app's own bytes.
- **The choice is a theme id, and it is checked on the way in and on the way
  out.** The saved value must match the pack id shape to be read at all, and a
  choice that is not currently in the library cannot be made. When a chosen pack
  stops passing its checks or is deleted, the app draws Orbit and keeps the
  choice, so re-downloading brings it back.
- **Its bytes are counted as themes.** The Storage page reports packs separately
  from media (a person deletes them on the themes page, not there) and names them
  in the split line only when there are any.
- **The page says which of the two it is naming.** You > Appearance's "More
  themes" row opens it: a theme this device holds is named by its own signed
  document, and one the server merely offers by the slug in the list, because
  the list route carries no display name on purpose. The page never shows a name
  it has not checked, and never reads a theme document before the gate has
  passed.

`app/test/settings/theme_packs_test.dart` pins all of this, including that an
unsigned, untrusted, swapped, over-cap or effect-asking pack writes nothing;
`packages/orbit_ui/test/theme_packs_test.dart` pins the page's four verbs, its
two groups, its waiting row and its "nothing is on offer" note.

