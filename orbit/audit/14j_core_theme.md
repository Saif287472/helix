# Sweep 14j — app `core/theme`: the theme library and the pack folder

**Where:** `helix_remote/app/lib/core/theme/` —
`orbit_app_theme.dart` (200), `orbit_packs.dart` (777) — 977 lines.

Cross-reads: `main.dart:98-104` (start-up reads the packs and catches
everything), `packages/orbit_ui/lib/src/theme/orbit_tokens.dart:34-133, 155-173`
(`fromThemeJson` and `_meta` — every site that can throw), the format gate
`packages/helix_remote_domain/lib/domain/theme_packs.dart:646-711`
(`_checkTheme`: id, effect kinds, pattern kind — and nothing about tokens),
`app/lib/features/settings/application/theme_packs.dart:60-77, 96-146` (the
providers and the three actions), `orbit/audit/16a_orbit_ui_theme.md`
(AUD-16-1) and `90_REMEDIATION_PLAN.md` B10.

The folder itself is well built: every read re-runs the gate, files are
content-addressed, a pack is staged and renamed only after it passes, the
manifest's caps are checked before any byte is fetched, and older revisions are
cleaned up. The chosen theme survives a missing pack (the tokens fall back to
Orbit). What is not built is the *read* contract around the theme parse: the
store's decode is documented as "null is how a folder says so", but it only
converts one of the three exception families the parser actually raises — and
the page that shows the folder reads it before it can delete from it.

## Findings

### AUD-14j-1 One signed theme the parser cannot read takes the whole theme library down, and cannot be deleted from the app

**Severity:** P3  **Confidence:** confirmed
**Where:**
[orbit_packs.dart:562-571](file:///J:/Projects/helix/helix_remote/app/lib/core/theme/orbit_packs.dart#L562-L571)
(`_pack` catches `FormatException` only),
[orbit_packs.dart:425-433](file:///J:/Projects/helix/helix_remote/app/lib/core/theme/orbit_packs.dart#L425-L433)
(`_read` catches `FileSystemException` only),
[orbit_packs.dart:129-143](file:///J:/Projects/helix/helix_remote/app/lib/core/theme/orbit_packs.dart#L129-L143)
(`stored()` lets the decode's exception through),
[orbit_app_theme.dart:49-51](file:///J:/Projects/helix/helix_remote/app/lib/core/theme/orbit_app_theme.dart#L49-L51)
(`reload` assigns from a read that can throw),
[theme_packs.dart:125-135](file:///J:/Projects/helix/helix_remote/app/lib/features/settings/application/theme_packs.dart#L125-L135)
(`remove` loads the pack before removing it).

**What:** `OrbitTokens.fromThemeJson` raises more than `FormatException`:

- `orbit_tokens.dart:87` — `values[s['token']! as String]! as Color`: a gradient
  stop that refers to a token this document does not define is a null-check
  `_TypeError`; one that refers to a non-colour token (a length, a weight) is a
  cast `_TypeError`.
- `orbit_tokens.dart:116` — `OrbitTextTransform.values.byName('$v')` throws
  `ArgumentError` for a transform name this build does not ship.
- `orbit_tokens.dart:159` — `json[k] as String?` throws `_TypeError` when `name`,
  `vibe`, `icon` or `id` is a number or a map.

`ThemePackStore._pack` converts only `FormatException`
(`orbit_packs.dart:569`), and `PackFolder._read` converts only
`FileSystemException` (`:431`). So a document that raises one of the others
escapes the folder as an exception, not as `null`, and every caller that reads
the folder loses *all* packs, not just the bad one:

- Start-up survives by accident: `main._installedPackThemes` catches `Object`
  (`main.dart:98-104`), so the app opens on Orbit — with every good downloaded
  theme also gone, and no sign of why.
- `DownloadedThemes.reload` (`orbit_app_theme.dart:49-51`) has no catch: after
  an install or a delete, the notifier throws and keeps its previous state, and
  `ThemePackActions._refresh` (`theme_packs.dart:142-146`) passes the exception
  to the page as a failure sentence.
- `installedPacksProvider` (`theme_packs.dart:60-62`) errors, so
  `themeGalleryProvider` draws `installed` as empty
  (`theme_packs.dart:216-217`: `.value ?? const []`) — every pack disappears
  from More themes, including the ones that parse.
- `ThemePackActions.remove` reads the pack for its display name *before*
  deleting (`theme_packs.dart:128`), so the read throws and the delete never
  runs. The only way out is clearing app data. The store's own `remove`
  (`orbit_packs.dart:556`) never reads, so the capability exists — the page
  just cannot reach it while the bad pack is present.

**Trigger:** a trusted publisher's signed theme whose document passes
`_checkTheme` (right id, known effect kinds, known pattern) but whose tokens
this build cannot draw — a gradient referencing a token the document forgot, a
`transform` this build does not ship, or `"name": 42`. A later app version that
drops a transform value reaches this on packs that were fine when installed.
Today `PackTrust` has an empty anchor, so no shipped build trusts any pack; the
first publisher key makes this live (the same latency B10/AUD-16-1 already
carries).

**Evidence:** the three throw sites above; `_pack`'s single `on
FormatException`; `_read`'s single `on FileSystemException`; the four callers
named above. Note the read path never decodes the bytes it installs: `install`
reads the revision already on disk to answer `alreadyCurrent`
(`orbit_packs.dart:186`, through `load`), then gates the new bytes and renames
without decoding them, so the first copy of a bad pack is reported installed
and fails on the next `stored()`/`load()`; a later update of that id throws at
the same `load` before it starts.

**Impact:** one bad theme hides every downloaded theme and blocks pack
management in-app until app data is cleared; the reported install failure does
not name the pack (the type error becomes a generic failure sentence). No data
is lost — the good packs are still on disk, and the app still starts — which is
why this is P3 rather than the launch crash of AUD-16-1.

**Fix sketch:** make the read contract the one its comments claim. (1) Have
`_pack` catch `Object` (and keep returning `null`), or wrap the decode in
`_read` itself so no decode exception can leave a folder read. (2) Have
`ThemePackActions.remove` remove first and read the name for the sentence
afterwards, or read through a tolerant lookup that cannot throw. (3)
`DownloadedThemes.reload` should assign only a successful read, so a throwing
read leaves the last good library in place. (4) Whichever way AUD-16-1 makes
the parse strict, it must end in `FormatException` — otherwise strictness turns
one bad pack into a dead folder.

**Test that proves it:** with a fake trusted publisher and a pack whose theme
document has `"transform": "no-such-transform"` (or a gradient `token` that is
not defined), `ThemePackStore().installed()` returns the other installed pack
and skips this one, `themeTokens()` returns the other theme, and
`ThemePackActions.remove(id)` deletes it and says so. A start-up test asserts
the downloaded library still contains the good pack.

**Overlap:** AUD-16-1/16-3 (the parse is the same contract; 16-1 is what a
chosen bad pack does, this is what a *stored* bad pack does to every other
pack), AUD-16-6 (install reporting success for a pack the page cannot offer),
AUD-7-4 (the same folder is walked per request). All in B10.

### AUD-14j-2 More themes re-reads up to 64 manifests one at a time on every visit

**Severity:** P3  **Confidence:** confirmed
**Where:**
[orbit_packs.dart:697-731](file:///J:/Projects/helix/helix_remote/app/lib/core/theme/orbit_packs.dart#L697-L731)
(`hostedPacks`: a sequential `await source.manifest` per id, serialized under the
`hostedPackProbe` cap at `:683`),
[theme_packs.dart:71-77](file:///J:/Projects/helix/helix_remote/app/lib/features/settings/application/theme_packs.dart#L71-L77)
(the provider is `autoDispose`, so the work is redone on every visit).

**What:** naming a row a theme needs its signed manifest, so `hostedPacks`
fetches one per pack id — correctly, and one after another
(`:713-729`). With `hostedPackProbe = 64` (`:683`) a full folder costs 64
sequential round trips, each with the API client's own retry and timeout, and
nothing is remembered between calls. Because `hostedPacksProvider` is
`autoDispose`, leaving More themes and coming back repeats all of it; the page
sits on `ListStatus.loading` for the whole time (`theme_packs.dart:276-280`),
and a failed probe is counted as `unverified` and re-probed next visit.

**Trigger:** a server folder listing a few dozen pack ids, a mobile link, and a
second visit to More themes.

**Evidence:** the loop and cap above; no cache of `id@revision → contents`;
the provider's `autoDispose`; the gallery's status derivation.

**Impact:** the page can wait for minutes on a slow link and re-pays the cost on
every visit, while the server absorbs 64 metadata reads per page view per
device. Not a correctness failure: rows appear once it completes, and an
unreachable host only yields `unverified`. The same premise from the server
side is AUD-7-4.

**Fix sketch:** probe with bounded concurrency (4–8 at a time) and remember the
verified kind per `id@revision` for the session (a small map in the provider or
in `ApiPackSource`), so a revisit and a gallery rebuild ask only about new
revisions. Keep the cap as the market bound. This does not change what is
offered.

**Test that proves it:** a fake `PackSource` that records in-flight calls and
adds a delay: `hostedPacks` never exceeds the concurrency bound and finishes
well inside the serial total; a second call for the same ids issues no
`manifest` requests. A source that throws for one id still yields the others.

**Overlap:** AUD-7-4 (server rescans the folder per request), AUD-16-6 (the
same manifest probe backs the page's offer). All in B10; the concurrency/cache
half is this sweep's addition to B10's "pack-host index" structure.

## Verified safe

- Built-ins always win over packs: `themeLibraryProvider` spreads the
  downloaded map first and `orbitThemeLibraryProvider` last
  (`orbit_app_theme.dart:57-62`), so a pack cannot shadow Orbit or Orbit Night
  whatever it calls itself.
- The chosen theme is a device setting that survives sign-out, is validated as
  a pack id on read (`orbit_app_theme.dart:134-200`), and falls back to Orbit
  when the library does not contain it (`:89-92`); deleting a pack keeps the
  choice on purpose, and the gallery shows Orbit as in use.
- `ThemeChoice.choose` refuses an id the library does not hold
  (`orbit_app_theme.dart:81-85`), so a stale tap cannot persist a theme that
  cannot be drawn.
- Pack trust has two deliberate read modes: `forThisBuild()` throws on a
  malformed anchor (build error, loudly), `forThisBuildOrNone()` returns empty
  for reads (`orbit_packs.dart:29-75`), so a folder read degrades to "no packs"
  rather than to an exception.
- Installation is correctly ordered: manifest caps before the first fetch
  (`:178-308`), the gate over the downloaded bytes *before* the rename, a
  per-attempt staging directory removed in `finally`, and older revisions
  pruned only after the new one is in place.
- Path handling is safe: ids are slug-checked before any join
  (`_isSlug`, `load` at `:146-157`), stored files are content-addressed hex
  names, and `_readCapped` checks the length before reading (`:436-440`).
- `FileDeviceSettingsStore` reads tolerantly (`:188-199`, any error → `{}`) and
  writes read-modify-write, so choosing a theme does not clear the ringtone.

## Coverage notes

Weighed and not filed:

- **Device-settings lost update:** `_write` reads, edits, writes
  (`orbit_app_theme.dart:168-183`). Two settings changed in the same few
  milliseconds could drop one, but both writers run on the UI isolate from
  separate user actions, and there is no path that changes theme and ringtone
  concurrently. Kept as a note for the `_write` refactor.
- **`_write` catches `FileSystemException` only:** an `ArgumentError` (a
  non-encodable value) would propagate to the caller; every value written is a
  validated string, so this is not reachable today.
- **Install rename race:** two simultaneous installs of one id share a staging
  name per attempt (microseconds) and the page serialises one action per row
  (`PackBusy`); not reachable from the UI.
- **`_newestOf` hashes every revision it finds** (`:347-367`) on every read.
  Normally one revision exists because install prunes the rest; the cost is
  bounded by pack size and the manifest cap. Not filed separately from
  AUD-14j-2's read cost.
- **`_readCapped` is length-then-read (TOCTOU):** the cap is a memory guard on
  files the app itself wrote from a hash-checked download, not a trust
  boundary against a local attacker who can already edit the folder.
- **`PackTrust.parse` accepts a duplicate publisher key silently** (later wins)
  — a build-config mistake, caught by review, not by code worth a finding.
- **`install` re-reads the pack for the success sentence**
  (`theme_packs.dart:110`) and falls back to the id; that is AUD-16-6's
  territory (a pack that cannot be drawn is still called downloaded).
- **Launch reads `readTheme()` outside the try in `main`:** a device-settings
  file that throws would abort start-up. `_read` catches everything, so no such
  path exists.

## Structural proposal

**S14j-1 — decode is one contract, and no folder read may throw for a bad
pack.** `decode` in `PackFolder` is documented as returning `null` for a pack
this app cannot use (`orbit_packs.dart:425-433`), but the theme's parser raises
three exception families. Make the contract literal: either `_read` catches
`Object` around `decode`, or `_pack` does; and the same decode function the
store uses at read time runs before the rename at install time (B10's
decode-before-rename). One seam, both halves of AUD-14j-1 and AUD-16-1/16-6.
This is B10's structure extended by one clause, not a new batch.
