# Preview-only fonts (theme packs)

These fonts belong to the six themes that will be **downloaded**, not built in:
bloom, mochi, papyrus, arcade, terminal and field. The preview loads them from
these local files with `FontLoader` / `rootBundle`, which is deliberately the
same code path a downloaded theme pack will use in Part C — a pack is files on
disk, not something baked into the app. They are **not** bundled in
`packages/orbit_ui`; only the two built-in themes' fonts (Geist, Geist Mono)
are, and they live in `packages/orbit_ui/fonts/`.

Keeping them here also means an app build never fetches a font at runtime, and
the screenshot/compare tooling never needs the network.

Every file here is **SIL Open Font License 1.1**. The OFL requires the licence
to travel with the font, so each family has its licence text next to it as
`<Family>-OFL.txt`. **Adding a family means adding its licence in the same
change**, and when a family moves into a real pack its licence must move with
it.

These files are vendored verbatim from the `google/fonts` repository
(`ofl/<family>/`). **Do not hand-edit them**: no renaming, no converting, no
subsetting. Re-download from the upstream URL and update
`orbit/flutter/fonts/MANIFEST.md` (byte size, SHA-256, source URL, licence)
instead.

Note that DM Mono, Rajdhani and Barlow are **static** families upstream: each
requested weight is a separate file. Everything else is variable.

Most families also have a real upstream **italic** beside the roman, because the
prototype's CSS only requests an italic face on one family and the browser
synthesised the rest; Flutter does not synthesise an oblique, so the italics are
bundled rather than rendered upright. Two weights per static family, one file
per variable family. Four families (Cinzel, Rajdhani, Share Tech Mono, Black
Ops One) have no italic upstream and have none here. Every `FontLoader` call
must load the italic faces too, or they are bundled but unused — see the
manifest.

Manifest: [`orbit/flutter/fonts/MANIFEST.md`](../../../fonts/MANIFEST.md).