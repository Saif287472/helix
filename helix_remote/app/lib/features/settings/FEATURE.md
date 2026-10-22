# settings

The You page and the settings pages it opens (Phase A3b; the pages have drawn
the Orbit screens through connectors since Part B batches 8 and 9). The You
page itself is built in `shared/widgets/orbit_you_connector.dart` (it joins
several features); every tile and row opens a page registered in
`settings_routes.dart`.

| Page | What it does | Where the data comes from |
|---|---|---|
| You | header (name, about or server host, picture), the orbit, the checkup and the tiles | `SettingsGateway.watchHeader`, `shared/you_facts.dart`, `core/platform/profile_image_source.dart` |
| Account | masked phone, `~name`, change/set password, export, "Switch account", "Sign out and remove", delete | `SettingsGateway` (`account`, `changePassword`, `exportAccount`, `deleteAccount`), core `signOutProvider`, `accountsProvider` |
| Accounts | the accounts signed in on this phone, to open, add or remove (asks first) | `accountLinesProvider`, `accountsPageProvider` (`core/engine/runtime_providers.dart`) |
| Privacy | last seen / online / group-add audiences, found by phone / `~name` (server); read receipts, typing, default disappearing timer, the device's app lock, blocked list | server `people.privacy`, engine `EngineSettings`, `AppSettings`, `PeopleService.watchAll`, `accountsProvider`'s `DeviceLock` |
| Notifications | alerts for messages / groups / calls, sound, vibrate, previews, OS permission, muted chats (with unmute) | `AppSettings.notify*`, `NotificationPermissionSource`, `ChatsService.watchChats` |
| Chats | text size, Enter sends, media auto-download per kind | `AppSettings`, `MediaPolicySync` |
| Storage and data | database and media size, how space is freed | `StorageUsageProbe` |
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

- Clearing cached media needs an engine API that evicts downloaded files and
  marks their attachments `remote` again; the Storage page therefore reads and
  explains, it does not delete. Its bar is messages against all media and the
  chat list is empty until E2.
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

## Privacy: finding me by phone number

Turning "Find me by phone number" back on sends the account's own number with
the setting (`setPrivacy(phoneNumber:)`): the engine uses the number it
registered with; on a linked device it throws before sending and the page asks
for the number once (a country code is required), then retries. A server
refusal says Helix checks the number against the one the account was verified
with.
