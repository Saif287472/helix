# Bundled fonts (Orbit UI)

These are the fonts the app **ships with**, because they are the only ones the
two built-in themes need: **Geist** (`Geist[wght].ttf`, `css/themes.css:83`)
and **Geist Mono** (`GeistMono[wght].ttf`). Both are variable fonts, so one
roman file each covers every weight the themes use. They are declared as
assets in `../pubspec.yaml`.

Each family also has its real upstream **italic** (`Geist-Italic[wght].ttf`,
`GeistMono-Italic[wght].ttf`). The prototype's CSS only asks Google Fonts for
an italic on one family, so the browser synthesised an oblique for these two;
Flutter does not, and an upright italic is a guaranteed difference in every
compare shot. See the manifest for why.

Nothing else belongs here. The other six themes ship later as **downloaded
theme packs**, so their fonts live with the preview app instead
(`apps/orbit_preview/fonts/`) and are loaded from local files at runtime, the
way a real pack will be. A font must never be fetched from the network at
runtime, and a screenshot tool must work offline.

Every file here is **SIL Open Font License 1.1**. The OFL requires the licence
to travel with the font, so each family has its licence text next to it as
`<Family>-OFL.txt`. **Adding a family means adding its licence in the same
change** — a font without its licence cannot be shipped.

These files are vendored verbatim from the `google/fonts` repository
(`ofl/geist/`, `ofl/geistmono/`). **Do not hand-edit them**: no renaming, no
converting, no subsetting. Re-download from the upstream URL and update
`orbit/flutter/fonts/MANIFEST.md` (byte size, SHA-256, source URL, licence)
instead.

Manifest: [`orbit/flutter/fonts/MANIFEST.md`](../../../fonts/MANIFEST.md).