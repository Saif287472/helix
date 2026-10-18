# Orbit fonts: manifest

Every font family the Orbit HTML prototype loads from Google Fonts, taken as
files from the upstream source of truth — the `google/fonts` repository on
GitHub — so that no screen and no screenshot tool ever touches the network.

The list is the `css2` request in `orbit/prototype/index.html` line 11. Note it
asks for **14** families (the brief said 13); all 14 are here.

Ten of the fourteen families also have their **real upstream italic** face,
from the same upstream directory as their romans. The prototype's CSS requests
an italic for Fraunces only, so the browser synthesised an oblique for the
others and Flutter will not — see
[Why the italic faces are bundled](#why-the-italic-faces-are-bundled).

## Why the italic faces are bundled

The prototype's CSS explicitly asks Google Fonts for an italic face for
**Fraunces only** (`ital,opsz,wght@0,…;1,…` on `index.html` line 11). For the
other thirteen families the request contained no italic face at all, so the
browser had none to download and **synthesised an oblique** by shearing the
roman face. Flutter does **not** reliably synthesise an oblique for a custom
font, so in Flutter every italic line would render **upright** while the
reference screenshot shows a slant: the typing indicator, the placeholder
bubbles, a missing quote and bloom's italic wordmark would each come out as a
difference in the compare tool, and the point of that tool is to find *real*
differences.

So each family's real italic is bundled next to its romans, from the same
`google/fonts` directory and the same licence, with the same axis coverage as
its roman: a variable family gets its `-Italic[…]` variable file, and the two
static families that have an italic upstream at all (DM Mono, Barlow) get the
italic of each weight already present, so weight matching still works. Nothing
was synthesised, substituted, renamed, converted or subset — the italic files
are unmodified upstream files, and the four families with no upstream italic
(recorded below) got none.

**Know what this changes.** The Flutter render is now a *drawn* italic where the
reference shot has a *sheared* one. They are close but not identical: each real
italic has its own slant angle — `-7°` for Barlow, `-8°` for Exo 2, `-9°` for
Nunito and JetBrains Mono, `-10°` for DM Sans and DM Mono, `-12°` for Geist and
Geist Mono, `-16°` for Fraunces, `-17.2°` for EB Garamond, all recorded per file
below — and its own advance widths, whereas a synthetic oblique keeps the
roman's widths and bolds it. If the compare tool still flags an italic line,
that is this gap, not a missing font, and closing it is a design decision for
the port owner.

## Licence

**All 14 families are under the SIL Open Font License 1.1.** Each licence text
was downloaded from the same upstream directory as the font, checked for the
`SIL OPEN FONT LICENSE` / `Version 1.1` header rather than assumed, and saved
next to the fonts as `<Family>-OFL.txt`. Nothing here is under a different or
non-open licence.

The OFL requires that the licence **travel with the fonts**: the copy of the
licence must be distributed with every copy of the font, including inside an
app, a theme pack or a screenshot bundle. That is why every family has its
licence file beside it in both font directories. Do not drop a licence file
when copying a family into a pack, and do not rename one away.

Two OFL conditions to keep in mind for the downloadable packs:

- The fonts must not be **sold on their own**, and any **Reserved Font Name**
  in a family cannot be reused for a modified version. Share Tech Mono declares
  a Reserved Font Name ('Share') — see its licence file.
- The fonts must not be **subset or otherwise modified** and called the same
  family. The bundled files are unmodified upstream files.

## Provenance

| | |
| --- | --- |
| Upstream | `google/fonts` on GitHub, `ofl/<family>/` |
| Base URL | `https://raw.githubusercontent.com/google/fonts/main/ofl` |
| Directory listing used to find filenames | `https://api.github.com/repos/google/fonts/contents/ofl/<family>` |
| Retrieved | 2026-10-18 (romans), 2026-10-18 (italics) |
| Total | 34 font files (20 roman + 14 italic), 14 licence files |

Filenames were **discovered through the GitHub contents API**, not guessed; the
roman pass and the italic pass each listed their family directory first. No file
was renamed, converted or subset. Every download was verified to be a real sfnt
font (magic bytes, never an HTML error page) before it was written, and every
file's size and SHA-256 below was then re-read from disk with a second,
independent hash implementation.

## Bundled with `packages/orbit_ui`

These two are the only fonts the design system bundles, because they are the only fonts the two built-in themes (Orbit, Orbit Night) use. They are declared in `packages/orbit_ui/pubspec.yaml`.

| Family | File | Bytes | SHA-256 | Requested | Axes / weight | Licence | Source URL |
| --- | --- | ---: | --- | --- | --- | --- | --- |
| Geist | `Geist[wght].ttf` | 169,056 | `73894e0448cae90a92b6c2f8732b7bb9acb7b94c418bff559dad4a18e1de9659` | wght 300..700 | variable, wght 100..900 | `Geist-OFL.txt` | `https://raw.githubusercontent.com/google/fonts/main/ofl/geist/Geist[wght].ttf` |
| — italic | `Geist-Italic[wght].ttf` | 174,584 | `a464348abe41a6392f18d04c0ac2ad3c26619357ff5fdd76aff3059116f45e62` | (browser synthesised it) | variable, wght 100..900, italic, angle -12° | — | `https://raw.githubusercontent.com/google/fonts/main/ofl/geist/Geist-Italic[wght].ttf` |
| — | **licence** | 4,387 | `1781d2806a07d91c` | — | — | SIL OFL 1.1 | `https://raw.githubusercontent.com/google/fonts/main/ofl/geist/OFL.txt` |
| Geist Mono | `GeistMono[wght].ttf` | 171,948 | `d00e590b8eb3a59acc329b2d044fd143ae935090b7da33199ebee27cc7de8196` | wght 400..600 | variable, wght 100..900 | `GeistMono-OFL.txt` | `https://raw.githubusercontent.com/google/fonts/main/ofl/geistmono/GeistMono[wght].ttf` |
| — italic | `GeistMono-Italic[wght].ttf` | 182,656 | `70c15be47d55f637197f7e38570dbca16b35777ea647dc3598f61bf3961d2b0d` | (browser synthesised it) | variable, wght 100..900, italic, angle -12° | — | `https://raw.githubusercontent.com/google/fonts/main/ofl/geistmono/GeistMono-Italic[wght].ttf` |
| — | **licence** | 4,387 | `1781d2806a07d91c` | — | — | SIL OFL 1.1 | `https://raw.githubusercontent.com/google/fonts/main/ofl/geistmono/OFL.txt` |

Font bytes in this section: **698,244** (341,004 roman + 357,240 italic).


## Local files for `apps/orbit_preview`

These belong to the themes that will ship as **downloaded packs**, so the preview loads them from files on disk (`rootBundle`/`FontLoader`) the way the real pack loader will. They are deliberately not in the package.

| Family | File | Bytes | SHA-256 | Requested | Axes / weight | Licence | Source URL |
| --- | --- | ---: | --- | --- | --- | --- | --- |
| DM Sans | `DMSans[opsz,wght].ttf` | 240,164 | `8cd08d97e89c24d0aa92edd2f0f4c8ee6195eee9b7c9f154865a58b02f0c1c0d` | opsz 9..40, wght 400..700 | variable, opsz 9..40, wght 100..1000 | `DMSans-OFL.txt` | `https://raw.githubusercontent.com/google/fonts/main/ofl/dmsans/DMSans[opsz,wght].ttf` |
| — italic | `DMSans-Italic[opsz,wght].ttf` | 285,040 | `22259c0cc8237221b80f44c76ba8d36e6bce3cda72779f5b2773643d499720ae` | (browser synthesised it) | variable, opsz 9..40, wght 100..1000, italic, angle -10° | — | `https://raw.githubusercontent.com/google/fonts/main/ofl/dmsans/DMSans-Italic[opsz,wght].ttf` |
| — | **licence** | 4,482 | `9af36190332437f5` | — | — | SIL OFL 1.1 | `https://raw.githubusercontent.com/google/fonts/main/ofl/dmsans/OFL.txt` |
| DM Mono | `DMMono-Regular.ttf` | 49,744 | `55b4c98f123daebb3ed27947ba47b2af00554fc6284d639a540bcef5e6258ad2` | wght 400;500 | static, usWeightClass 400 | `DMMono-OFL.txt` | `https://raw.githubusercontent.com/google/fonts/main/ofl/dmmono/DMMono-Regular.ttf` |
| — | `DMMono-Medium.ttf` | 50,360 | `fd327daf461db87b44a87def475d251bf03b997f7c07d9680592d75dbbfaad0b` | — | static, usWeightClass 500 | — | — |
| — italic | `DMMono-Italic.ttf` | 51,408 | `32b5bad9cbce64eac6d05c8abbeb619317f7e4cb354e1c33db761adbfaae1b16` | (browser synthesised it) | static, usWeightClass 400, italic, angle -10° | — | `https://raw.githubusercontent.com/google/fonts/main/ofl/dmmono/DMMono-Italic.ttf` |
| — italic | `DMMono-MediumItalic.ttf` | 52,552 | `a3b2211bb9cf5c4fc1a0b487553e673a737c2270c59b86bf1e0b48c77e587aa2` | — | static, usWeightClass 500, italic, angle -10° | — | `https://raw.githubusercontent.com/google/fonts/main/ofl/dmmono/DMMono-MediumItalic.ttf` |
| — | **licence** | 4,484 | `2bada5ea45c3c63b` | — | — | SIL OFL 1.1 | `https://raw.githubusercontent.com/google/fonts/main/ofl/dmmono/OFL.txt` |
| Fraunces | `Fraunces[SOFT,WONK,opsz,wght].ttf` | 360,440 | `177ff6c0f14e5550a3c624247cd1189611d4eb65d000b14944c63d967958abbb` | ital 0;1, opsz 9..144, wght 400..700 | variable, opsz 9..144, wght 100..900, SOFT 0..100, WONK 0..1 | `Fraunces-OFL.txt` | `https://raw.githubusercontent.com/google/fonts/main/ofl/fraunces/Fraunces[SOFT,WONK,opsz,wght].ttf` |
| — | `Fraunces-Italic[SOFT,WONK,opsz,wght].ttf` | 414,904 | `b24448c43702fac4ee856781d461a0dfba8d8e594b6e8e190234b75fed2c0e01` | — | variable, opsz 9..144, wght 100..900, SOFT 0..100, WONK 0..1 | — | — |
| — | **licence** | 4,391 | `bdf4c22802eaf804` | — | — | SIL OFL 1.1 | `https://raw.githubusercontent.com/google/fonts/main/ofl/fraunces/OFL.txt` |
| Nunito | `Nunito[wght].ttf` | 276,932 | `bb55a5ca5c2042335b3991af27c4d0705d0ef41cac6164ac737fd8f2a1e85207` | wght 400..900 | variable, wght 200..1000 | `Nunito-OFL.txt` | `https://raw.githubusercontent.com/google/fonts/main/ofl/nunito/Nunito[wght].ttf` |
| — italic | `Nunito-Italic[wght].ttf` | 281,832 | `b520cc871868b0acfca1beda875df7f4a44ebce914f8a89f83977fc9c09529c8` | (browser synthesised it) | variable, wght 200..1000, italic, angle -9° | — | `https://raw.githubusercontent.com/google/fonts/main/ofl/nunito/Nunito-Italic[wght].ttf` |
| — | **licence** | 4,385 | `580df76c95a1ec5a` | — | — | SIL OFL 1.1 | `https://raw.githubusercontent.com/google/fonts/main/ofl/nunito/OFL.txt` |
| EB Garamond | `EBGaramond[wght].ttf` | 851,176 | `ef9512f92f6d579e5dc75af59a5a4b1b8b47d2eda89e00b954d44520e5369027` | wght 400..700 | variable, wght 400..800 | `EBGaramond-OFL.txt` | `https://raw.githubusercontent.com/google/fonts/main/ofl/ebgaramond/EBGaramond[wght].ttf` |
| — italic | `EBGaramond-Italic[wght].ttf` | 754,468 | `bba2c4499c93c9612b90b9825d32b07da52fce2fe57562a1eb6b833553f93c4e` | (browser synthesised it) | variable, wght 400..800, italic, angle -17.2° | — | `https://raw.githubusercontent.com/google/fonts/main/ofl/ebgaramond/EBGaramond-Italic[wght].ttf` |
| — | **licence** | 4,398 | `0985066662eb755e` | — | — | SIL OFL 1.1 | `https://raw.githubusercontent.com/google/fonts/main/ofl/ebgaramond/OFL.txt` |
| Cinzel | `Cinzel[wght].ttf` | 125,468 | `f4d83d34d1f6c741193e4acf4b3dff9531e5a67b6aa65228d00a7db72a4e0f34` | wght 500..700 | variable, wght 400..900 | `Cinzel-OFL.txt` | `https://raw.githubusercontent.com/google/fonts/main/ofl/cinzel/Cinzel[wght].ttf` |
| — | **licence** | 4,383 | `f2b3029aba64c378` | — | — | SIL OFL 1.1 | `https://raw.githubusercontent.com/google/fonts/main/ofl/cinzel/OFL.txt` |
| Rajdhani | `Rajdhani-Medium.ttf` | 384,348 | `12ff7dcfe4c206e3875ac53b1762eab57de6a2fa7f5a86c26b97b88d6591eac2` | wght 500;600;700 | static, usWeightClass 500 | `Rajdhani-OFL.txt` | `https://raw.githubusercontent.com/google/fonts/main/ofl/rajdhani/Rajdhani-Medium.ttf` |
| — | `Rajdhani-SemiBold.ttf` | 390,340 | `94bbd25a18ca665999feb05a537de9fd2b860dcfb78bbe9ca00270825bf235da` | — | static, usWeightClass 600 | — | — |
| — | `Rajdhani-Bold.ttf` | 400,680 | `691470dd3286a14e9677940d0bf75796179841ba5215cbda1a2c8910a3226afd` | — | static, usWeightClass 700 | — | — |
| — | **licence** | 4,373 | `f62ef357d3a1c3d2` | — | — | SIL OFL 1.1 | `https://raw.githubusercontent.com/google/fonts/main/ofl/rajdhani/OFL.txt` |
| Exo 2 | `Exo2[wght].ttf` | 303,940 | `205a448676a2586f9c57c25f3d5c58ca8db7e6cf5edf7506783a010c6fe2bfb5` | wght 400..700 | variable, wght 100..900 | `Exo2-OFL.txt` | `https://raw.githubusercontent.com/google/fonts/main/ofl/exo2/Exo2[wght].ttf` |
| — italic | `Exo2-Italic[wght].ttf` | 302,556 | `bad568cea9ed23d6ae4aea41ad3f7747752952aabdd85d7f01474af392a21b32` | (browser synthesised it) | variable, wght 100..900, italic, angle -8° | — | `https://raw.githubusercontent.com/google/fonts/main/ofl/exo2/Exo2-Italic[wght].ttf` |
| — | **licence** | 4,386 | `7f95a8eeecc6904f` | — | — | SIL OFL 1.1 | `https://raw.githubusercontent.com/google/fonts/main/ofl/exo2/OFL.txt` |
| Share Tech Mono | `ShareTechMono-Regular.ttf` | 43,272 | `9ceab1f87414829af259c0f537573ae03ef7dd3147c0b27a36a1a0beb6732677` | (regular only) | static, usWeightClass 400 | `ShareTechMono-OFL.txt` | `https://raw.githubusercontent.com/google/fonts/main/ofl/sharetechmono/ShareTechMono-Regular.ttf` |
| — | **licence** | 4,429 | `9d96f445b6e9c701` | — | — | SIL OFL 1.1 | `https://raw.githubusercontent.com/google/fonts/main/ofl/sharetechmono/OFL.txt` |
| JetBrains Mono | `JetBrainsMono[wght].ttf` | 187,208 | `48715a42ec242c21e9f02692891e147d022299a52e48d5e413e1a942193ffeda` | wght 400..700 | variable, wght 100..800 | `JetBrainsMono-OFL.txt` | `https://raw.githubusercontent.com/google/fonts/main/ofl/jetbrainsmono/JetBrainsMono[wght].ttf` |
| — italic | `JetBrainsMono-Italic[wght].ttf` | 191,556 | `85ae2a5cd3f56baf1ce1c21a851322c58e3d8fbe8e8ad4a4d090a820dd7fe558` | (browser synthesised it) | variable, wght 100..800, italic, angle -9° | — | `https://raw.githubusercontent.com/google/fonts/main/ofl/jetbrainsmono/JetBrainsMono-Italic[wght].ttf` |
| — | **licence** | 4,399 | `b2fe5e8987594e9f` | — | — | SIL OFL 1.1 | `https://raw.githubusercontent.com/google/fonts/main/ofl/jetbrainsmono/OFL.txt` |
| Black Ops One | `BlackOpsOne-Regular.ttf` | 166,532 | `282a825b5f294377387e3969f765408157dbea8da0f5d0aae68c6bc704b145b3` | (regular only) | static, usWeightClass 400 | `BlackOpsOne-OFL.txt` | `https://raw.githubusercontent.com/google/fonts/main/ofl/blackopsone/BlackOpsOne-Regular.ttf` |
| — | **licence** | 4,411 | `f67ca4a200424868` | — | — | SIL OFL 1.1 | `https://raw.githubusercontent.com/google/fonts/main/ofl/blackopsone/OFL.txt` |
| Barlow | `Barlow-Regular.ttf` | 104,068 | `95aa02c7c43096e0dd44d787ba6216864a67157e402adab59b35572e0c1577ea` | wght 400;500;600;700 | static, usWeightClass 400 | `Barlow-OFL.txt` | `https://raw.githubusercontent.com/google/fonts/main/ofl/barlow/Barlow-Regular.ttf` |
| — | `Barlow-Medium.ttf` | 103,536 | `f8906f762cb73dca441da034bc363b2d8e2e68bc10d5c05e58717646c20cc4b4` | — | static, usWeightClass 500 | — | — |
| — | `Barlow-SemiBold.ttf` | 108,348 | `86577cb32f8abe3673db53ca0f4221e6856751a4f6730c867e00f720f8bb1fc5` | — | static, usWeightClass 600 | — | — |
| — | `Barlow-Bold.ttf` | 108,220 | `84e6a4d61e7c3e21f3c50ea6a4f7e5303a3467864c038be6ea3759bab8d547f9` | — | static, usWeightClass 700 | — | — |
| — italic | `Barlow-Italic.ttf` | 109,624 | `70cf45c354af39e55082fd506e748cc6a0a1812949875f99ded3f76bf691e4ca` | (browser synthesised it) | static, usWeightClass 400, italic, angle -7° | — | `https://raw.githubusercontent.com/google/fonts/main/ofl/barlow/Barlow-Italic.ttf` |
| — italic | `Barlow-MediumItalic.ttf` | 109,184 | `dbf6d2df1348c4a91874a15bbe7b3f3d893d491bd2ae73370795afe157c993b9` | — | static, usWeightClass 500, italic, angle -7° | — | `https://raw.githubusercontent.com/google/fonts/main/ofl/barlow/Barlow-MediumItalic.ttf` |
| — italic | `Barlow-SemiBoldItalic.ttf` | 111,820 | `277b45fc0b9f066bf77e88e5d147baae8d1ad7441cedee1dc305fc3dc6e84ce7` | — | static, usWeightClass 600, italic, angle -7° | — | `https://raw.githubusercontent.com/google/fonts/main/ofl/barlow/Barlow-SemiBoldItalic.ttf` |
| — italic | `Barlow-BoldItalic.ttf` | 111,996 | `079dcee4a53544177f3b16354b27b40b521e22861a40084ab4d052f0289ed9e8` | — | static, usWeightClass 700, italic, angle -7° | — | `https://raw.githubusercontent.com/google/fonts/main/ofl/barlow/Barlow-BoldItalic.ttf` |
| — | **licence** | 4,377 | `186d750eb496a4c1` | — | — | SIL OFL 1.1 | `https://raw.githubusercontent.com/google/fonts/main/ofl/barlow/OFL.txt` |

Font bytes in this section: **7,031,716** (4,254,776 roman + 2,776,940 italic).


## Families with no upstream italic

Four of the fourteen families ship **no italic face at all** in
`google/fonts` — checked against the contents API listing of each directory,
not assumed. Nothing was substituted for them (no other family's italic, no
synthesised, no renamed roman), so those four families have exactly the roman
files listed above and nothing more:

| Family | What upstream ships | Italic |
| --- | --- | --- |
| Cinzel | `Cinzel[wght].ttf` only | none upstream |
| Rajdhani | Light, Regular, Medium, SemiBold, Bold — all roman | none upstream |
| Share Tech Mono | `ShareTechMono-Regular.ttf` only | none upstream |
| Black Ops One | `BlackOpsOne-Regular.ttf` only | none upstream |

If a theme built on one of these sets `font-style: italic`, Flutter will render
it upright (and so will the browser) — that is a property of the typeface, not
a missing file, and the compare tool will agree with the prototype on it.

## What the parent agent must wire (not decided here)

- **Three families are static, not variable.** DM Mono, Rajdhani and Barlow
  have no variable font in `google/fonts`; each requested weight is its own
  file (see the file lists above). Every other family is a variable font whose
  axis range is wider than the range the prototype requested — declare the
  weight in `pubspec.yaml` and let the variable axis interpolate.
- **Legacy family names in the static files.** `Barlow-Medium.ttf`,
  `Barlow-SemiBold.ttf`, `Rajdhani-Medium.ttf`, `Rajdhani-SemiBold.ttf` and
  `DMMono-Medium.ttf` carry the *legacy* family name (`Barlow Medium`, ...) in
  name ID 1, with the correct typographic family in name ID 16. Declare them
  all under the plain family name and give each its correct `weight:`; do not
  split them into families named `Barlow Medium`.
- **No italic's family name differs from its own roman's.** Name ID 16 and
  name ID 1 were read out of every new file and compared with the matching
  roman: in all 13 cases the pair agrees, so each family is one font family
  with a roman and an italic face and nothing has to be split or renamed. The
  legacy quirks above are identical in the italic of the same weight
  (`Barlow-MediumItalic.ttf` says `Barlow Medium` exactly as
  `Barlow-Medium.ttf` does). Note also that `DM Sans` carries `DM Sans 9pt` in
  name ID 1 with `DM Sans` in name ID 16, and `Nunito`'s variable default
  weight is 200, so name ID 1 reads `Nunito ExtraLight` — in both cases the
  roman says the same thing.
- **Declare the italics with `style: FontStyle.italic`** under the same family
  name as the romans, same weight. Both `pubspec.yaml` declarations and the
  runtime `FontLoader` calls in the preview need the extra faces, or the
  italics are bundled but never used.
- **No `pubspec.yaml` was touched here** (another agent is reading those
  files), so nothing in this workspace declares a font yet.

## Judgement calls recorded here

- **Real italics are bundled, reversing the first pass's "roman only, except
  Fraunces".** That pass reasoned that since the browser synthesised the
  oblique, matching the request exactly meant downloading romans only, and
  that pulling in the real `-Italic` files "would be a change to the design,
  not a bug fix". The deciding fact is that Flutter does not synthesise an
  oblique for a custom font, so the roman-only set made every italic line a
  guaranteed difference in the compare tool — noise the tool must not produce.
  The real upstream faces are bundled for that reason, and the residual gap
  between a drawn italic and a sheared one is recorded above as a decision for
  the port owner rather than hidden.
- **A variable family's italic keeps its roman's axis coverage**, checked from
  the `fvar` table of each pair (Geist and Geist Mono wght 100..900, DM Sans
  opsz 9..40 + wght 100..1000, Nunito wght 200..1000, EB Garamond wght
  400..800, Exo 2 wght 100..900, JetBrains Mono wght 100..800). Only the
  static families were matched weight by weight.
- **No `upstream_info.md`, `METADATA.pb` or `DESCRIPTION` was kept.** They are
  useful provenance but carry no licence terms; the licence is what must
  travel.
