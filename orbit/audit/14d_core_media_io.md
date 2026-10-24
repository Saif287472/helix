# Sweep 14d — app `core/platform/`: the files the app reads, and the names it writes back

**Where:** `helix_remote/app/lib/core/platform/` — `app_blob_store.dart` (164),
`flutter_media_processor.dart` (143), `storage_usage.dart` (67),
`device_camera.dart` (120), `video_frames.dart` (51), `file_actions.dart` (35),
`qr_encoder.dart` (21), `app_info.dart` (18), `phone_numbers.dart` (119),
`contacts_access.dart` (203), `device_phone_book.dart` (76),
`app_storage.dart` (268) — 1,285 lines. Cross-reads: the
`fc_native_video_thumbnail` 3.0.1 Kotlin (`sizeToFit`) and the
`flutter_contacts` 2.5.0 README (property-scoped `update`).

This is the folder where the app touches the phone rather than the network, and
the two findings are both at that boundary: a size cap that is applied after
the memory it was meant to save has already been spent (14d-1), and a rename
that writes a first name into the phone's address book as if it were the whole
name (14d-2). The plumbing between them is sound — the blob store's resume
write is an append with an explicit `truncate` and `setPosition`, the storage
accounting walks the disk rather than trusting a stored number, and the
address book adapter asks for write permission only at the rename that needs it.

## Findings

### AUD-14d-1 The picture-size cap is checked after the whole file has been read and copied

**Severity:** P3  **Confidence:** confirmed
**Where:**
[flutter_media_processor.dart:63-76](file:///J:/Projects/helix/helix_remote/app/lib/core/platform/flutter_media_processor.dart#L63-L76)
(`_image`), [flutter_media_processor.dart:44](file:///J:/Projects/helix/helix_remote/app/lib/core/platform/flutter_media_processor.dart#L44)
(`maxDecodeBytes`).
**What:** `_image` reads `await file.length()` first (line 65), then reads the
entire file as bytes and copies them (`Uint8List.fromList(await
file.readAsBytes())`, line 66), and only afterwards checks `length >
maxDecodeBytes` (line 74). The cap that exists so that "a decode of an image
this big would cost more memory than the preview is worth" is therefore applied
after two full-size allocations: the `readAsBytes` result and its copy.
**Trigger:** sending a picture whose file is over 96 MiB — a stitched panorama,
a scanned page, or an image picked from a cloud folder that materialises the
full file. The send path calls this for every image attachment
(`core/engine/media_processor` wiring).
**Evidence:** lines 65-76 in order: `length`, `readAsBytes` + `fromList`,
`imageSize` on a 256 KiB prefix, then the cap. The `_video` path in the same
file scans the MP4 before touching the file (line 100 onward), so the image
path is the outlier.
**Impact:** a send of a very large image momentarily holds 2× its size in
memory on top of the normal app footprint. On a mid-range phone already holding
the conversation this is an OOM kill — the app dies during a send, and the
draft/selection is lost. Nothing is corrupted; the failure is a crash.
**Fix sketch:** check `length` before reading; when it is over the cap, read
only the 256 KiB header (`file.openRead(0, 262144)`) for the dimensions and
return `_dimensions(header)`, exactly as the over-cap branch does today. The
full read stays on the below-cap path only.
**Test that proves it:** a test over a 97 MiB temp file (or a fake reader that
counts bytes) asserting the result is the dimensions-only `ProcessedMedia` and
that no more than 256 KiB were read.
**Overlap:** 14c-2 and S14c-2 are about the *decode* bound of the profile crop
and the fallback re-encode; this one is the read bound before any decode. B21
(the attachment batch) is the owner.

### AUD-14d-2 Renaming a person in Helix replaces the phone contact's whole name, dropping its other parts

**Severity:** P3  **Confidence:** likely
**Where:**
[contacts_access.dart:169-179](file:///J:/Projects/helix/helix_remote/app/lib/core/platform/contacts_access.dart#L169-L179)
(`saveName`'s update branch),
[device_phone_book.dart:49-74](file:///J:/Projects/helix/helix_remote/app/lib/core/platform/device_phone_book.dart#L49-L74)
(the engine-facing rename).
**What:** the update branch loads the contact (name and phone properties), then
calls `FlutterContacts.update(contact.copyWith(name: Name(first: name)))`. A
fresh `Name` carries only `first`; the structured parts the contact had —
middle, family, prefix, suffix, and the display name the phone derives from
them — are not passed on. With flutter_contacts 2.5.0's property-scoped update
(`update` writes the properties present on the object it is given), the parts
that are now null are written back as null. The whole Helix name, spaces and
all, also goes into the *given-name* field, so "Dr. Amina Rahman" becomes a
single first name with no family name.
**Trigger:** the person renames anyone in Helix (`saveName` is called from the
people feature after the engine's rename; the same adapter serves both the
read path and this write). The classic case: a phone contact saved as given
"Amina", family "Rahman" — the dialer sorts it under R, and other apps show
"Rahman, Amina" — is renamed once through Helix.
**Evidence:** line 176 is the only name construction on the update path;
`Name` is constructed with `first:` alone. The fetch on lines 170-173 asks for
`name` and `phone`, so the existing `Name` *is* available to preserve — it is
simply discarded. The create branch (line 181-184) does the same, which is
fine: there is no existing name to lose.
**Impact:** data loss outside Helix, in the person's own address book: the
structured name is destroyed for every other app on the phone (dialer, SMS,
car system), and the person has to retype it. Helix itself keeps the name it
was told (its own store is the source for display), so the loss is silent —
nothing in Helix looks wrong. The address book is the person's property; this
is a write-back feature that should not cost them their data.
**Fix sketch:** rename in place rather than replacing the name: if the contact
has a `Name`, keep its parts and set only `first` to the new name when it is a
single word, or split on the last space into `first`/`family` while keeping
middle/prefix/suffix. If the rule is "one display name", at minimum use
`contact.name.copyWith(first: name)`, never a fresh `Name`. The device phone
book deliberately does not see parts (`AddressBookContact` carries only the
display name), so this rule belongs in `FlutterContactsAccess`.
**Test that proves it:** a fake address book holding a contact with
`Name(first: 'Amina', middle: 'S.', family: 'Rahman', prefix: 'Dr.')`; after
`saveName(contactId: …, name: 'Amina R.')` the stored contact still has the
prefix and middle name, and the family name is either kept or deliberately
derived — asserting the exact chosen rule.
**Overlap:** AUD-12h-2 (clearing a nickname cannot undo the phone-book rename)
is the mirror image — a write-back with no way back. B5 already owns the naming
policy, including write-back (S2), and this finding is another rule in it.

## Verified safe

- **`AppBlobStore`** (`app_blob_store.dart:60-75`): a resumed download opens in
  append mode, `truncate`s to the length actually held, `setPosition`s there
  and appends — a partial file cannot be mistaken for a complete one, and the
  reported offset comes from the file, not from a stored counter.
- **`storage_usage.dart`**: walks the account folders it is given and sums them;
  it is device-wide by design (the storage page), and a missing folder counts
  as zero rather than throwing.
- **`device_camera.dart`**: the camera is created with the requested
  resolution, disposed on every exit path, and a denied permission answers a
  typed result rather than throwing. `video_frames.dart` asks the plugin for a
  frame at a max side; the plugin's Kotlin `sizeToFit` preserves the aspect
  ratio (checked in the pub cache), so the frame is not distorted.
- **`file_actions.dart`, `qr_encoder.dart`, `app_info.dart`**: small and total —
  a save-to-downloads that answers false on refusal, a pure QR margin
  calculation, a version constant pinned to `pubspec.yaml` by a test.
- **`phone_numbers.dart`**: the normaliser, display splitter and mask were read
  line by line; the calling-code prefix table is correct (one-, two- and
  three-digit codes), the trunk-zero replacement refuses without a country
  rather than guessing, and `guessNational` is opt-in for typed search only.
- **`app_storage.dart`**: the Windows path deliberately avoids `Documents`
  (OneDrive backup), the account-id check is a strict pattern, and the key is
  in the platform keystore with a "database present, key absent" refusal rather
  than a silent second key; `wipeLocalFiles` tries each target independently.

## Coverage notes

- Read in full: the twelve files in **Where** (1,285 lines), plus the
  `flutter_contacts` README and the video-thumbnail plugin's native source.
- `contacts_access.dart` and `device_phone_book.dart` were first opened under
  14a/14e notes; they are counted here.
- Not filed, checked and left alone: `saveName` when the contact exists but is
  not found by id creates a new contact with the number — the number is the
  same one that was searched for, so the duplicate carries the new name rather
  than losing it; and the extra full `readAll()` before `saveName` (two scans
  of the address book for one rename) is slow on a large book but not wrong.
  The latter is a candidate for the next pass if rename latency is ever
  reported.

## Structural proposals

**S14d-1 — one name-writing rule lives with the adapter that writes names.**
`FlutterContactsAccess` is the only code that talks to the address book; the
rule for what a rename does to an existing `Name` (preserve parts, split, or
keep as display name) belongs beside it, not in the caller. One helper
`Name renamed(Name? existing, String name)` with the test above makes 14d-2 a
single reviewed decision and gives the future "nil the nickname" repair
(12h-2) the same place to undo a rename.
