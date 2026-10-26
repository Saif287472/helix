# people (Phase A2b)

Finding people, naming them, and everything about one person: the phone-book
integration, people search for the Chats and Calls tabs, and the contact info
screen. There is no Contacts tab and there are no contact requests: anybody can
message or call anybody who has not blocked them.

Own profile viewing and editing is A3b. This feature draws *other* people's
profiles (name, about, picture) only.

## What other features use

Three seams, by import path. A feature never imports another feature
(`test/architecture_test.dart`), so everything other features consume lives in
`core/` or `shared/`, not in this folder.

### 1. Naming: `core/people/people_names.dart`

How a person is shown, everywhere. Order (AGENTS.md): **phone-book name, then
nickname, then number, then `~Helix name`**; below those the engine's own
fallbacks (the name the person chose for themselves, then `Orbit user <short
id>`, with `(domain)` for a person on another server). `PersonName.display` is
exactly what the engine's `PersonNaming.displayName` answers, so a chat row, a
notification and a call screen can never disagree.

```dart
// application/ code (a mapper, a notifier):
final people = ref.watch(peopleDirectoryProvider).value ?? PeopleDirectory.empty;
people.nameOf(accountId).display            // the one name, never empty
people.nameOf(accountId).names              // HelixPersonNames for HelixPersonTile
people.nameOfConversation('direct:<acct>')  // null for a group
people.labelOf(accountId)                   // display, plus (…1234) / (~name) on a collision

// For one person, rebuilt only when THAT person changes:
final name = ref.watch(personNameProvider(accountId));
name.toItem()          // HelixPersonItem for HelixPersonTile
name.avatar            // HelixAvatarModel (picture if this device has one)
name.maskedNumber      // for logs and errors; screens show the full number
```

- `peopleDirectoryProvider` is **one** stream over the engine's people watch
  query (`peopleRowsProvider`, the test seam), however many rows read it. It is
  reactive: a rename, a phone-book match, a profile arriving all change it.
- A stranger (no row yet) is `PersonName.unknown(id)`, never an error.
- Collisions: `PeopleDirectory.collides(id)` / `labelOf(id)`. A list that shows
  two people under one name should use `labelOf`.
- Numbers: screens show a person's number to the user (the product rule says a
  person with no name is shown *by* their number); `maskedNumber` is for
  anything that could be logged.

Every feature reads it (chat list, conversation, calls, groups, settings, and the
FCM isolate through `PersonName.fromRow`); there is no other naming adapter.
`PeopleDirectory` also answers `displayOf`, `firstNameOf`, `secondaryOf`,
`avatarOf`, `isBlocked`, `isVerified` and takes a `fallbackName` for a stranger a
roster named.

### 2. Search: `shared/widgets/people_search_panel.dart`

```dart
HelixSearchField(controller: c, onChanged: (_) => setState(() {}),
    onSubmitted: (text) => PeopleSearchPanel.submit(ref, text));
PeopleSearchPanel(query: c.text, mode: PeopleSearchMode.chats /* or .calls */)
```

- **A2a** mounts it in the Chats tab's search with `PeopleSearchMode.chats`
  (tap opens the conversation, creating it).
- **A3a** mounts it in the Calls tab's search with `PeopleSearchMode.calls`
  (tap places a voice call; each row also has voice and video buttons).
- Both show it as soon as the search opens (the new chat and new call buttons
  open it), so the contacts card and "Refresh contacts" are reachable, and
  both pass `PeopleSearchPanel.submit` as the keyboard's search key
  (`onSearchSubmitted`). Until 2026-10-14 neither did: with nothing typed the
  tabs showed their own empty state, so the contacts could never be allowed.
- A standalone screen exists too: `PeoplePaths.search` /
  `PeoplePaths.searchFor(calls: true)`. `helix://contact` links land on
  `/home/people` (the same screen).

What it does:

| Text | Behaviour |
| --- | --- |
| nothing | people the user knows (phone-book or nicknamed), not blocked, not strangers, not themselves; asks once for contacts permission first, with the privacy copy |
| a name | filters people and groups **on the device as you type** - no network |
| a number (`01711-000001`, `+880 1711 000001`) | filters stored numbers as you type; a "Find +880 1711000001 on Helix" row does the **one** discovery lookup, only when tapped or on the keyboard's search key |
| `~name` | the same, as an exact `~Helix name` lookup |

Network lookups are never automatic: each number lookup spends one of the 5,000
daily discovery lookups and tells the server which number was asked about.
States handled: searching, found (stored, so it joins the list), not on Helix
(the server does not say whether the number is unregistered or private, and
neither does the UI), your own number, rate limit / daily budget used up,
offline, any other failure (one plain sentence, never the exception).

A number typed with a leading `0` is read in the country of **this account's own
number** (`PhoneNumbers.normalize`), which is how `01711…` finds the right
person. There is no libphonenumber; the address book never guesses a country,
search does (a typed number of at most ten digits is taken as national).

### 3. Navigation seams: `shared/navigation/conversation_seams.dart`

People hand over to other features through `conversationSeamsProvider`, whose
default is `RouterConversationSeams`. The owner of each destination edits its
own method there:

| Method | Resolves to |
| --- | --- |
| `openChat(conversationId)` (`direct:<account>` or `group:<id>`) | the conversation route (`chatLocation`) |
| `openSharedMedia(conversationId)` | `/chat/:id/shared` (conversation feature) |
| `startCall(accountId, video:)` returns null, or the sentence to show | `placeCallProvider` (calls feature) |

Paths into this feature are in `shared/navigation/people_paths.dart`:
`PeoplePaths.person(id)` (contact info - from the conversation header and a
group's member list), `.safetyNumber(id)`, `.scan(id)`, `.search`.

## Layout

```
application/
  people_gateway.dart    PeopleGateway: the narrow engine surface the screens use
                         (EnginePeopleGateway is the real one; tests fake it);
                         SafetyNumberData (groups, QR text/matrix); PhoneBookSyncLog
  people_search.dart     PeopleQuery.parse, searchPeople (pure), lookup controller,
                         PeopleActions (open chat / start call, and the share link:
                         openPersonLink / openScannedCode)
  phone_book_sync.dart   contactsPermissionProvider, phoneBookSyncProvider
  contact_info.dart      ContactPerson (TrustState), disappearing/report types (mute
                         is shared/widgets/mute_choice.dart's MuteFor),
                         contactBlocksMeProvider (they blocked you, ADR-030),
                         ContactInfoActions (rename, block, report, verify, the
                         scanned code's check, ...)
  people_failures.dart   PeopleFailure: rateLimited / offline / other
presentation/            connectors for orbit_ui's pages: contact_info_screen.dart
                         (ContactScreen), safety_number_screen.dart, safety_scan_screen.dart
                         and scan_chat_screen.dart (both ScanCodeScreen, in its two
                         modes, over the scanner), people_search_screen.dart
                         (the people panel of shared/widgets/orbit_people_panel.dart)
people_routes.dart       /scan-chat, /home/people, /search, /:id, /:id/safety, /:id/scan
```

Platform code is behind an adapter in `core/platform/`: `ContactsAccess`
(permission, read, write, change stream; `FlutterContactsAccess` is the only
file that touches `flutter_contacts`), `DevicePhoneBook` (the engine's
`PhoneBook` over it), `phone_numbers.dart`. The camera is behind
`shared/widgets/qr_scanner_view.dart` (`qrScannerBuilderProvider`, the only scanner; devices uses it too).
Fakes for tests: `test/support/people_fakes.dart`.

## Phone book

- **What leaves the phone:** salted HMAC hashes of E.164 numbers, in batches of
  the engine's `maxBatch`, via `PeopleService.syncPhoneBook`. Never raw numbers
  or names (`test/people_rules_test.dart` forbids the app calling the discovery
  route itself).
- **Permission:** asked only when the person taps "Allow contacts" under the
  explanation, as read+write together (reading finds people, writing keeps a
  rename in the phone). `denied` leaves the card; `permanentlyDenied` offers
  "Open settings"; Windows (`unsupported`) shows nothing.
- **When it syncs** (`PhoneBookSyncHost`, mounted in `main.dart`): when the
  device becomes signed in (on start once the engine has opened, and after a
  fresh sign-in; until 2026-10-14 the start-up check ran on the first frame,
  before the engine was ready, and was skipped), on resume, hourly while open,
  and 30 s after the address book changes. Triggers that arrive together run
  one sync. The
  controller decides if it is *due*: at most every 12 h by itself (1 h after an
  address-book change), never on a day when the last sync showed less budget
  left than it spent, and the daily limit being hit is remembered until the next
  UTC day. The log is in the encrypted database (`app.phonebook_sync`). A person
  can always press "Refresh contacts". The address-book change feed is followed
  only while the read permission is granted: the platform refuses to open it
  otherwise, and until 2026-10-23 that refusal was reported as a crash
  (`PlatformException(permission_denied)` from `flutter_contacts`). A feed that
  fails while followed (permission taken away) is stopped, and the next resume
  or hourly check re-reads the permission.
- **Matching names:** the engine stores the phone-book name with each match.
  Known limit: a contact deleted from the phone keeps its stored name until the
  person is renamed or rematched (the engine has no "unmatch").
- **Rename writes to the phone:** `PeopleService.setNickname` calls the adapter,
  which renames the contact that holds the number (found by normalised number,
  however it is written) or creates one. When the phone takes the name the
  engine also updates the stored phone-book name, because that name outranks the
  nickname and would otherwise hide the rename until the next sync. Without
  permission the screen asks ("Save in your phone contacts too?") and, if the
  person agrees, requests it and saves.

## Contact info

Header (picture, name, number line, blocked, about from the encrypted profile -
read once on open when this device has their profile key), Message / Voice /
Video, key-changed warning, Name (rename, number, `~name`), Chat (media seam,
mute 8 h / 1 week / always, disappearing 24 h / 7 d / 90 d), Encryption (safety
number, with the trust state), groups in common, Block / Unblock, Report.

Trust (`TrustState`): `noKey` (nothing exchanged), `unverified`, `verified`,
`keyChanged` (their key changed after it was pinned and has not been verified
since). A key change is a warning, never a block: the engine keeps the chat
working, clears the verified mark, and this screen says so in words and links
the safety number. The safety number screen shows the 12 groups of 5 digits
(`HelixSafetyNumberView`), a QR code (`HelixQrDisplay`) and a scanner
(`HelixQrScanFrame`). The QR holds the crypto layer's payload as unpadded
base64url **text** (scanners report text reliably); a match marks verified, a
mismatch says so and does nothing else.

Never in a snackbar or an error: a name or a number (`test/people_rules_test.dart`
scans for interpolation).

## A person's share link (S1)

`https://helix.agiletechbd.com/u/<~name>` (and `helix://u/<name>`) is the one
thing a person can hand to somebody who is not in their phone book. Both
forms parse to `HelixDeepLinkKind.personLink` in `core/links/deep_link.dart`,
which is the only place a name is normalised (trim, drop the leading `~`,
lower case) and the server's `SetHelixNameRequest.pattern` decides whether the
link is worth following at all.

Nothing in this feature navigates for it. `AppLinkListener`
(`shared/widgets/app_link_listener.dart`) holds the link until the device is
signed in and calls `PeopleActions.openPersonLink`, and the same method
resolves a code scanned in contact mode (`openScannedCode`). Both look the
name up with a session through `PeopleGateway.findByHelixName` - which is why
"Find me by ~name" and blocking are honoured - and then use the `openChat`
seam. `GET /u/{name}` on the server is a static page and answers nothing about
the name; the only lookup is this one.

The sentences are deliberately blunt: a name that does not exist, one whose
owner is not findable and one that has blocked you are all
"No Orbit account is called ~x on your server, or it is not findable by name."
An answer that could tell them apart would let anyone walk the server's names.
`test/person_link_test.dart` pins that the exception behind a failure never
reaches the screen.

## Note to self

Your own account is a chat: `direct:<own account>`, titled **Note to self**
(`chat_naming.dart`'s `noteToSelfTitle`) and called **You** everywhere else
(a reply quote, a member list). The engine keeps no people row for your own
account, so the app supplies the person: `selfPersonProvider` builds it from the
gateway's own account id and your own picture, and `peopleDirectoryProvider`
folds it in (`withSelf`). `PeopleDirectory.isSelf(id)` is then the one question
the screens ask - it is what drops the "You " sender prefix from a note's chat
list row and what keeps the header from showing presence, call buttons or block.

- The Chats tab's people panel and the people search screen put it above the
  people you know ("Message yourself"). The Calls tab does not show it: you
  cannot call yourself (`PeoplePanelModel.self` is null there).
- It is silent: a note lands on the other device unread, without a notification
  or a delivered receipt (the engine applies your own message quietly).
- `searchPeople` still leaves yourself out - the note is a row in the panel, not
  a search hit. The forward sheet never offers you as a stranger to start a chat
  with (`forwardTargetsProvider` filters your own id), but once the note exists
  it is a chat like any other and can be forwarded into.
- A `~name` link or QR code of your own account opens this chat; until
  2026-10-26 it answered "That is your own ~name." instead.

## Engine additions this feature needed (small, additive)

- `PeopleService.report(account, category, {note})` over the existing
  `people.report` client.
- `PeopleService.aboutOf` / `watchAbout`; `refreshProfile` now stores the
  profile's `about` line (a typed setting `people.about:<account>`, so no schema
  change).
- `PeopleService.setNickname` updates the stored phone-book name when the phone
  accepted the write.

## Not here

- A person's picture from their profile (a media pointer needing a download):
  the avatar shows what this device has (`avatarBlob`), else initials.
- Presence ("online" dot, last seen) on rows.
- Own profile editing (A3b), the Calls tab list and call screen (A3a), shared
  media lists (A2a): the entry points exist as seams.
