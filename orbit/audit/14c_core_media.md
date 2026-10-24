# Sweep 14c — app `core/platform/`: what an attachment is, and what is cleaned out of it

**Where:** `helix_remote/app/lib/core/platform/` — `image_metadata.dart` (282),
`mp4_metadata.dart` (272), `media_sanitizer.dart` (189),
`thumbnail_encoder.dart` (156), `blurhash.dart` (125), `pixel_decoder.dart`
(71), `profile_image_source.dart` (157) — 1,252 lines. Cross-reads:
`attachment_picker.dart` (231, the classifier that feeds all of this),
`media_temp.dart` (125), `features/conversation/application/composer_notifier.dart:495-540`
(what a send does with each outcome), and the tests
(`test/media/metadata_test.dart` 385, `test/media/attach_test.dart`,
`test/profile/profile_page_test.dart`).

The bytes-level work in this folder is the best in the app. The JPEG stripper
walks segments with every bound checked, keeps only JFIF (minus its thumbnail),
ICC and Adobe, writes back a one-tag orientation block, and drops everything
after the first EOI; PNG drops text/EXIF/time chunks and anything past IEND;
WebP drops EXIF/XMP and clears the VP8X flags. The MP4 cleaner patches boxes in
place (so no offset in the file moves), zeroes the three time headers, and
writes a same-size copy; the BlurHash is the reference algorithm over a
32-pixel average. The Sanitizer refuses to send what it could not clean, and the
composer enforces that (`composer_notifier.dart:511-514`). The defects are on
the *outside* of this careful code: what decides a file is a photo, and what
happens to the picture the profile page decodes.

## Findings

### AUD-14c-1 A file is a photo because of its name, so a photo without a known extension is sent with its EXIF intact

**Severity:** P3  **Confidence:** confirmed
**Where:**
[attachment_picker.dart:172-195](file:///J:/Projects/helix/helix_remote/app/lib/core/platform/attachment_picker.dart#L172-L195)
(`describePickedFile` and the mime map),
[attachment_picker.dart:199-231](file:///J:/Projects/helix/helix_remote/app/lib/core/platform/attachment_picker.dart#L199-L231)
(`mimeForFileName`),
[media_sanitizer.dart:68-82](file:///J:/Projects/helix/helix_remote/app/lib/core/platform/media_sanitizer.dart#L68-L82)
(`PickedKind.document` and `audio` return `clean`).
**What:** the sanitizer decides whether to clean a file from `PickedFile.kind`,
and `kind` is derived from the file *name*: the extension is mapped to a MIME
type and its first segment. The map has `heic` but not `heif`, `avif`, `tif`,
`tiff`, `bmp`, or `ts`, and a file with no extension (some browsers and
download managers save that way) is `application/octet-stream`. Any of those
reaches the sanitizer as `PickedKind.document`, which is returned unchanged.
**Trigger:** send a photo saved as `.heif` (some Samsung and Sony cameras),
`.avif`, or `IMG_0001` with no extension — through the gallery's file view or
Documents. The photo is attached as a document with its GPS, time and camera
model.
**Evidence:** `final kind = switch (mime.split('/').first) { 'image' =>
PickedKind.image, ... _ => PickedKind.document };`
([attachment_picker.dart:181-186](file:///J:/Projects/helix/helix_remote/app/lib/core/platform/attachment_picker.dart#L181-L186));
the map is a switch over extensions with an `_ => application/octet-stream`
default and no `heif`/`avif`/`tif` entries
([attachment_picker.dart:199-231](file:///J:/Projects/helix/helix_remote/app/lib/core/platform/attachment_picker.dart#L199-L231));
`PickedKind.document` and `PickedKind.audio` are sent as `SanitizeOutcome.clean`
([media_sanitizer.dart:75-77](file:///J:/Projects/helix/helix_remote/app/lib/core/platform/media_sanitizer.dart#L75-L77)).
`describePickedFile` and `mimeForFileName` have no test at all (`grep` over
`app/test` finds no caller).
**Impact:** the one guarantee this folder exists for — nothing identifying
leaves the phone inside a file — holds only for the extensions someone
remembered. The person sees an ordinary file send; nothing says the metadata
was kept.
**Fix sketch:** classify by content. The sanitizer already knows how to tell a
JPEG/PNG/WebP/MP4 from anything else by its first bytes; run the same sniffing
before choosing `kind` (magic bytes, falling back to the extension), and have
one classifier that the composer, the preview and the sanitizer all call. At a
minimum add `heif`, `avif`, `tif`/`tiff` and `bmp` to the map.
**Test that proves it:** `describePickedFile` of `photo.heif`, `photo.avif` and
`IMG_0001` (a JPEG's bytes) answers `PickedKind.image`; a sanitizer test hands
it a JPEG named `IMG_0001` and gets `stripped`.
**Overlap:** none filed; the composer's refusal path is already right
(`composer_notifier.dart:511`).

### AUD-14c-2 The profile crop decodes the photo at full size and leaks the codec and image when the crop fails

**Severity:** P3  **Confidence:** confirmed
**Where:**
[profile_image_source.dart:52-84](file:///J:/Projects/helix/helix_remote/app/lib/core/platform/profile_image_source.dart#L52-L84)
(`cropToSquare`).
**What:** `instantiateImageCodec(bytes)` is called without a target size, so a
12-megapixel photo becomes a ~48 MB `ui.Image`; the square is then drawn scaled
down. The three native objects (`codec`, `source`, `cropped`) are disposed only
after every await succeeds: any throw from `toImage`, `toByteData` or the
recorder jumps to the catch with all of them still alive, and on a phone with
little memory that is exactly where a big picture throws.
**Trigger:** choose a large photo as the profile picture on a low-memory phone,
or any platform where `toImage(256, 256)` fails; the person sees
"could not read the picture", and the full-size decode stays allocated until
the GC gets to the finalizers.
**Evidence:** `final codec = await ui.instantiateImageCodec(bytes); ... final
cropped = await recorder.endRecording().toImage(size, size); final data = await
cropped.toByteData(...); source.dispose(); cropped.dispose(); codec.dispose();`
([profile_image_source.dart:57-76](file:///J:/Projects/helix/helix_remote/app/lib/core/platform/profile_image_source.dart#L57-L76)).
Every failure path goes to `on Object { throw const ProfileImageException(); }`
([profile_image_source.dart:81-83](file:///J:/Projects/helix/helix_remote/app/lib/core/platform/profile_image_source.dart#L81-L83)).
The class doc claims "a 12-megapixel photo never reaches a widget"
([profile_image_source.dart:13-15](file:///J:/Projects/helix/helix_remote/app/lib/core/platform/profile_image_source.dart#L13-L15)) —
true of the widget, but the full-size image is decoded here.
The page is tested only through `FakeProfileImageSource`
(`test/profile/profile_page_test.dart:176-206`), so `cropToSquare` itself has
no test.
**Impact:** a transient memory spike of two orders of magnitude more than
needed on the one screen that also holds the account's keystore-backed
providers; a failed crop on a big photo leaves native memory for the GC. The
person's answer is "could not read the picture" for a picture the gallery
shows fine.
**Fix sketch:** decode with a bound — `instantiateImageCodec(bytes,
targetWidth: ..., targetHeight: ...)` cannot crop to the centre square while
scaling (the target is the whole frame), so decode with the long side bounded
to `2 * size` and crop from that, or use `ui.ImageDescriptor` + `instantiateCodec`
with a target and crop the scaled frame. Move disposal into `finally`.
**Test that proves it:** a unit test (or a tiny golden) that `cropToSquare`
returns `size x size` PNG bytes for a 4000x3000 image, and a test with a
decoder that throws asserts the exception type only — the disposal itself is
verified by review, since Flutter gives no counter for live `ui.Image`s.
**Overlap:** `UiPixelDecoder` (`pixel_decoder.dart:50-53`) already decodes with
a target size, so the fix is to use the bound the other path has.

### AUD-14c-3 One unreadable file in a multi-select discards the whole selection

**Severity:** P3  **Confidence:** confirmed
**Where:**
[attachment_picker.dart:146-169](file:///J:/Projects/helix/helix_remote/app/lib/core/platform/attachment_picker.dart#L146-L169)
(`_pick`).
**What:** the loop over the picked files is inside one `try` whose catch returns
`const []`. If `File(path).length()` throws for one file — a Google Photos
cloud-only item, a `content://` copy the provider revoked, a path that
vanished — every file already described is thrown away and the person gets
"nothing picked".
**Trigger:** select ten photos on Android where one is a cloud placeholder or a
document provider that cannot stat it; nothing attaches, and the same selection
does it again.
**Evidence:** `for (final file in files) { ... final size = await
File(path).length(); out.add(...); } return out; } on Object { return const [];
}`
([attachment_picker.dart:150-167](file:///J:/Projects/helix/helix_remote/app/lib/core/platform/attachment_picker.dart#L150-L167)).
**Impact:** a send that cannot be completed, with no file named and no way
forward except guessing which photo is the problem.
**Fix sketch:** catch per file inside the loop and `continue` (or skip with a
count the composer can mention), keeping the rest of the selection.
**Test that proves it:** a picker test with three fake files where the middle
one's length throws returns two `PickedFile`s.
**Overlap:** the composer already counts refused files for the sanitizer path
(`composer_notifier.dart:506-518`), so the vocabulary exists.

### AUD-14c-4 (Idea) GIFs are always sent untouched, and a GIF can carry text and XMP

**Severity:** Idea  **Confidence:** confirmed
**Where:**
[image_metadata.dart:20-27](file:///J:/Projects/helix/helix_remote/app/lib/core/platform/image_metadata.dart#L20-L27)
(`isGif`),
[media_sanitizer.dart:170-174](file:///J:/Projects/helix/helix_remote/app/lib/core/platform/media_sanitizer.dart#L170-L174)
(the GIF short-circuit).
**What:** the comment says "A GIF has no EXIF block, so it is sent as it is",
and that is true of EXIF — but a GIF may carry Comment extensions (0xFE) and an
Application extension with the XMP identifier, which can hold a camera model or
author string. The file is never inspected.
**Trigger:** a GIF exported by an editor that writes its name into a Comment
block. Rare, and the payload is text, not coordinates.
**Evidence:** `if (ImageMetadata.isGif(bytes)) return _clean;`
([media_sanitizer.dart:172](file:///J:/Projects/helix/helix_remote/app/lib/core/platform/media_sanitizer.dart#L172)).
**Impact:** a narrow hole in the same guarantee as 14c-1, with much less
valuable data.
**Fix sketch:** strip Comment extensions and any XMP application extension
before the pass-through, or drop GIF from the accepted set (it would then be
re-encoded as a still, which nobody wants). Worth doing only when 14c-1's
content sniffing lands.
**Test that proves it:** a GIF with a Comment extension comes back without it
and still decodes.
**Overlap:** AUD-14c-1 (the classifier) and this are the same guarantee.

## Verified safe (read, no finding)

- **JPEG stripping** (`image_metadata.dart:52-141`): every segment length is
  bounds-checked (`length < 2 || end > b.length`), scan data is copied with its
  restart markers, the trailer after EOI is dropped, JFIF's thumbnail is
  dropped while its 12 header bytes are kept (the 14-byte JFIF header is
  rebuilt correctly), and the orientation block is a valid 34-byte APP1. A file
  with no scan (`!sawImage`) is refused. A corrupt file is null, never a
  partial pass-through.
- **Orientation parsing** (:181-200): endianness checked, IFD offset bounded to
  the segment, each 12-byte entry bounded, values outside 1-8 become 1.
- **PNG** (:212-233): chunk lengths checked against the buffer, IEND required,
  CRCs untouched because chunks are copied, not rebuilt.
- **WebP** (:238-273): RIFF size bounded to the buffer, odd chunk padding
  handled, the VP8X EXIF (0x08) and XMP (0x04) flag bits cleared, RIFF length
  rewritten.
- **MP4 scan/patch** (`mp4_metadata.dart`): 64-bit sizes and `size == 0`
  handled, every box bounded by its parent, `moov` capped at 64 MiB, patches
  are same-size and relative to the box start, `writeCleaned` streams and
  handles a patch spanning chunk boundaries, the display size is read at the
  right tkhd offsets for versions 0 and 1 (v0 matrix at +40, v1 at +52) and
  swapped only for a quarter turn.
- **BlurHash** (`blurhash.dart`): the reference encoder — linear light, the
  DC and AC quantisers, base83 and the 4x3/3x4 component split all match the
  published algorithm; a flat picture hashes to its colour (tested).
- **Thumbnail math** (`thumbnail_encoder.dart`): premultiplied alpha is
  composited on white (`src + (255 - a)`), the shadowed `shrink` averages whole
  blocks with a one-pixel minimum and no gaps, and the isolate boundary
  captures only plain data.
- **Composer contract** (`composer_notifier.dart:510-524`): `failed` is never
  sent, and the person is told why. The sanitizer's "unsupported" outcome
  (WebM/MKV) is sent unchanged by design and documented as such.

## Coverage notes

- Read in full: the seven files in **Where** (1,252 lines), plus
  `attachment_picker.dart` (231) and `media_temp.dart` (125) as cross-reads.
- `flutter_media_processor.dart` (the caller that decodes with a bound and asks
  these classes for thumbnails) is 14d; `video_frames.dart` is 14d.
- Test names checked in `test/media/metadata_test.dart` (15 tests: JPEG, PNG,
  WebP, MP4, the sanitizer's three outcomes, BlurHash, white flattening) and
  `test/media/attach_test.dart`.
- Not confirmed: whether Flutter's codecs apply a HEIC's own orientation when
  `_reencode` decodes it. If they do not, a re-encoded HEIC is rotated. Left
  under open questions rather than filed.

## Structural proposals

**S14c-1 — one classifier decides what a file is, by content.** The kind of a
picked file is read in `attachment_picker.dart` from its name; the sanitizer
re-decides from bytes; the preview decides from the MIME type. One
`AttachmentKind sniff(bytes, name)` (magic bytes first, extension as a hint)
used by all three makes 14c-1 impossible and gives 14c-4 one place to live.

**S14c-2 — every picture the app reads is decoded with a bound.** The engine's
thumbnail path decodes with `targetWidth`/`targetHeight`
(`pixel_decoder.dart:50-53`); the profile crop does not; the fallback re-encode
does (4096). One helper ("decode no larger than N on the long side") used by
all three removes the memory spike in 14c-2 and keeps the picture-orientation
policy in one place.
