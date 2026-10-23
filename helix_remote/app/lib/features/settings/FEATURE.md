# settings

The You page and the settings pages it opens (Phase A3b; the pages have drawn
the Orbit screens through connectors since Part B batches 8 and 9). The You
page itself is built in `shared/widgets/orbit_you_connector.dart` (it joins
several features); every tile and row opens a page registered in
`settings_routes.dart`.

| Page | What it does | Where the data comes from |
|---|---|---|
| You | header (name, about or server host, picture), the orbit, the checkup and the tiles; the QR button opens the share sheet (link, real code, Copy link, Share, "Scan someone's code") and shows only when the account has a `~name` | `SettingsGateway.watchHeader`, `shared/you_facts.dart`, `core/platform/profile_image_source.dart`, `profileProvider`'s `helixName` + `core/links/deep_link.dart` (`helixProfileLink`) + `core/platform/qr_encoder.dart` + `core/platform/share_adapter.dart` |
| Account | masked phone, `~name`, change/set password, export, "Switch account", "Sign out and remove", delete | `SettingsGateway` (`account`, `changePassword`, `exportAccount`, `deleteAccount`), core `signOutProvider`, `accountsProvider` |
| Accounts | the accounts signed in on this phone, to open, add or remove (asks first) | `accountLinesProvider`, `accountsPageProvider` (`core/engine/runtime_providers.dart`) |
| Privacy | last seen / online / group-add audiences, found by phone / `~name` (server); read receipts, typing, default disappearing timer, the device's app lock, blocked list | server `people.privacy`, engine `EngineSettings`, `AppSettings`, `PeopleService.watchAll`, `accountsProvider`'s `DeviceLock` |
| Notifications | alerts for messages / groups / calls, sound, vibrate, previews, OS permission, muted chats (with unmute) | `AppSettings.notify*`, `NotificationPermissionSource`, `ChatsService.watchChats` |
| Chats | text size, Enter sends, media auto-download per kind | `AppSettings`, `MediaPolicySync` |
| Storage and data | database and media size, the bar's split by kind, the biggest chats, and freeing one chat's photos and videos or documents (its messages stay) | `StorageUsageProbe`, `SettingsGateway.mediaStorage/biggestChats/freeChatSpace` (engine `MediaService`) |
| Help and about | version, server, legal documents (ops API, bundled fallback), licences, a line saying problem reports go to the server | `SettingsGateway.serverDetails/legal`, `core/diagnostics/anomaly_log.dart` |
| Advanced | server facts and allowed feature flags, sync now | `ops.serverInfo`, `Engine.syncOnce` |

## Rules this feature keeps

- **Gateways, not the engine.** `SettingsGateway` is the only thing that
  touches the engine/API; pages and notifiers are tested against a fake
  (`test/support/a3b_fakes.dart`). Local settings go through
  `core/engine/local_settings.dart`.
- **Honest controls.** "My contacts" is not offered as an audience (the contact
  list is not uploaded by this engine), there is no profile-photo/about
  audience (the server has none), the backup schedule is stated rather than
  offered, and nothing here can block screenshots.
- **Failures are sentences** (`core/engine/failure_copy.dart`); no exception
  text reaches a screen (`a3b_rules_test.dart` scans for it).
- **Media auto-download** is the person's choice (never / Wi-Fi / any network)
  per kind; `mediaPolicySyncProvider` turns it into the engine's size limits
  whenever the choice or the network changes.
- **Problem reports** (the anomaly log, `core/diagnostics/anomaly_log.dart`)
  are sent by every build with no switch (the owner's decision, 2026-10-21);
  About says so. They never carry message content, keys or full numbers.
- **Orbit screens, app data.** The pages are connectors on `orbit_ui`
  screens; no screen formats an exception and no page reads the engine
  directly.
- **The app lock is the device's.** One `DeviceLock` in the account list
  covers every account signed in here and goes with the last one; Privacy
  edits it through `AppLockActions` (`accountsProvider.notifier.setLock`).

## Known gaps

- Freeing space covers photos, videos, video notes, GIFs and documents; voice
  notes stay with their messages. See "Storage: what counts" below.
- Notification sound/vibrate select an Android channel; calls consult
  `AppSettings.notifyCalls` in the calls feature (A3a). There is no ringtone
  row until there is a sound to ship.
- Per-conversation notification overrides live in the chat itself (A2); the
  Notifications page lists what is muted and can unmute.

## Review pass notes (v2-fixa)

- App lock: the control "Lock again" is a grace period (see `app/MODULE.md`);
  the footer says the app also asks on every fresh open. Since 2026-10-21 the
  setting is one for the device, not one per account.
- Images auto-download on Wi-Fi only by default (`AppSettings.mediaImages`).
- Account deletion: see "Deleting the account" below (the re-auth follow-up is
  done).

## Accounts on this phone

Several accounts can stay signed in here. Each has its own database, key and
folder (`core/platform/app_storage.dart`, `core/platform/account_slots.dart`);
the account list and the device app lock live in the keystore. `AccountsPage`
(`accounts_page.dart`) opens, adds or removes one; removing signs out and
wipes that account only, after asking. Account > Sign out offers "Switch
account" (which keeps it) and "Sign out and remove". Sign-in shows the numbers
this phone remembers; only numbers are saved. `core/push/` keeps every
account's push token current and raises notifications and calls for the
accounts not on screen.

## Deleting the account

Account > Delete my account: the export offer and warning, then
`DeleteAccountPage` (`/settings/account/delete`). It asks for the word DELETE
and for the proof the engine's `deleteAccount` takes, chosen like the server
does: **password** for an account that has one (the number is asked once, with
its country code, when this phone does not remember it); **a texted code** for an
account without a password on a server that texts (found out from the server's
`invalid_credentials` answer, which lists `verification_token`: the number is
shown and confirmed first, because the operator may charge for the text, then
the code is requested and entered); otherwise **nothing**, and this phone signs
a challenge with its key. "Export first" in the dialog only exports; the delete
page is opened by the person next. A wrong password, a lockout, a wrong code, offline and a
refusal are each a sentence; success shows "Your account was deleted" while the
engine's hard wipe and `signOutProvider` clean up and the router moves to
sign-in. `DeleteAccountController` holds the code's challenge in memory only.

## Storage: what counts

The hero's total is the device probe (database, media, thumbnails and work in
progress, and downloaded theme packs). The bar's three shares are the engine's
known content: messages and keys (database), photos and videos (images, videos,
video notes, GIFs), and files (documents, unknown kinds and voice notes). Biggest
chats count downloaded photos, videos and documents; voice notes are not offered
on their own. A chat's title and avatar come from the chat list ("Chat" until it
has loaded). Freeing a chat deletes the files and thumbnails of `ready`
downloads, clears their local paths and marks those attachments `remote`;
messages, keys and pointers stay, and the files download again while the server
keeps the object (30 days). Uploads and downloads in progress are never touched.
Pack bytes are named in the split line ("· 2.0 MB themes") only when there are
any, and are not freeable here: they are deleted on You > Appearance, with the
theme they carry.

## Privacy: finding me by phone number

Turning "Find me by phone number" back on sends the account's own number with
the setting (`setPrivacy(phoneNumber:)`): the engine uses the number it
registered with; on a linked device it throws before sending and the page asks
for the number once (a country code is required), then retries. A server
refusal says Helix checks the number against the one the account was verified
with.

## Theme packs: getting, updating and deleting one

`application/theme_packs.dart` is the download manager's wiring; the store and
the trust anchor are in `core/theme/orbit_packs.dart` and nothing here repeats
their rules. `ApiPackSource` is `PackSource` over the signed-in account's server
(`runtime.api.ops`), so `install` asks that host for the list, the manifest and
each file by its SHA-256. `installedPacksProvider` reads this device's folder
through the provider's store (the build's anchor); `hostedPacksProvider` asks
the host, and is `autoDispose` because it needs the network.
`ThemePackActions.install`/`remove` return the sentence the page shows: which
theme arrived, that it was already up to date, that the theme is built in (so
there is nothing to download), that the pack is no longer on offer, that it
cannot be used, that it was deleted, that it is not on this device. A refusal is
the format's own plain-English reason, never anything a pack wrote about itself.
After either action the theme library is re-read, so a pack that just arrived is
choosable on Appearance without a restart, and one that just went leaves the app
drawing Orbit while the person's choice stays saved. The page that lists and
taps these is Part C step 4.
