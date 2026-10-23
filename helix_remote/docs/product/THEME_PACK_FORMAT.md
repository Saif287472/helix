# Orbit theme packs: the format

Status: current, step 1 of `orbit/PORT_PLAN.md` Part C (2026-10-23).
Decided by [ADR-033](../adr/033-theme-packs-are-signed-data.md).
Implemented by `packages/helix_remote_domain/lib/domain/theme_packs.dart`,
checked by `packages/helix_remote_domain/test/theme_packs_test.dart`, and
written by `helix_remote/tool/theme_pack_tool.dart`.

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
dart run tool/theme_pack_tool.dart pack   --in build/synthwave \
  --id synthwave --publisher agiletechbd --revision 1 \
  --seed-file keys/agiletechbd.hex
dart run tool/theme_pack_tool.dart sign   --manifest build/synthwave/manifest.json \
  --seed-file keys/agiletechbd.hex
dart run tool/theme_pack_tool.dart verify --in build/synthwave --key <publisher key>
```

`keygen` prints the publisher key and writes the private one; it never prints
the private key. `pack` hashes the folder (its own `manifest.json` is never
listed) and refuses a folder whose single `.json` document calls itself another
theme. `verify` runs the app's own gate, not a copy of it; `--effects` and
`--patterns` are the publisher's dry run of the registry check, because
`orbit_ui` cannot be imported by a Dart script - say so in the output when they
are left out.

The seed file is a secret. Keep it off this machine's ordinary backups and off
any build server; losing it strands every pack ever signed with it, and leaking
it lets anyone ship a theme to every device.

## What the server has to do (step 2)

Serve the folder, and a list of it, over HTTPS: for each pack, its `id`,
`publisher`, `revision`, the manifest, and the files the manifest names. The
endpoint does not sign anything, does not need the publisher key, and cannot
make a device accept a pack - the app re-checks every byte against the manifest
it downloaded. A malicious or broken endpoint can serve an older revision or no
pack at all; it cannot serve a new one.
