# settings

The Settings tab and the pages it opens (Phase A3b). The tab itself is built by
the home screen (the router hands it in, because a feature may not import
another); every row opens a page registered in `settings_routes.dart`.

| Page | What it does | Where the data comes from |
|---|---|---|
| Tab | header (name, about or server host, picture) and the rows | `SettingsGateway.watchHeader`, `core/platform/profile_image_source.dart` |
| Account | masked phone, `~name`, change/set password, export, sign out, delete | `SettingsGateway` (`account`, `changePassword`, `exportAccount`, `deleteAccount`), core `signOutProvider` |
| Privacy | last seen / online / group-add audiences, found by phone / `~name` (server); read receipts, typing, default disappearing timer, app lock, blocked list | server `people.privacy`, engine `EngineSettings`, `AppSettings`, `PeopleService.watchAll` |
| Notifications | alerts for messages / groups / calls, sound, vibrate, previews, OS permission, muted chats (with unmute) | `AppSettings.notify*`, `NotificationPermissionSource`, `ChatsService.watchChats` |
| Chats | text size, Enter sends, media auto-download per kind | `AppSettings`, `MediaPolicySync` |
| Storage and data | database and media size, how space is freed | `StorageUsageProbe` |
| Help and about | version, server, legal documents (ops API, bundled fallback), licences, crash-report opt-in | `SettingsGateway.serverDetails/legal`, `CrashReporter` |
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
- **Crash reports** are opt-in, need the server flag `crash_reporting_upload`,
  and carry only the error's type, the app version and the platform.

## Known gaps

- Clearing cached media needs an engine API that evicts downloaded files and
  marks their attachments `remote` again; the Storage page therefore reads and
  explains, it does not delete.
- Notification sound/vibrate select an Android channel; calls consult
  `AppSettings.notifyCalls` in the calls feature (A3a).
- Per-conversation notification overrides live in the chat itself (A2); the
  Notifications page lists what is muted and can unmute.

## Review pass notes (v2-fixa)

- App lock: the control "Lock again" is a grace period (see `app/MODULE.md`);
  the footer says the app also asks on every fresh open.
- Images auto-download on Wi-Fi only by default (`AppSettings.mediaImages`).
- Account deletion: see "Deleting the account" below (the re-auth follow-up is
  done).

## Deleting the account

Account > Delete my account: the export offer and warning, then
`DeleteAccountPage` (`/settings/account/delete`). It asks for the word DELETE
and for the proof the engine's `deleteAccount` takes, chosen like the server
does: **password** for an account that has one (the number is asked once, with
its country code, when this phone does not remember it); **a texted code** for an
account without a password on a server that texts (found out from the server's
`invalid_credentials` answer, which lists `verification_token`: the code is
requested, then entered); otherwise **nothing**, and this phone signs a
challenge with its key. A wrong password, a lockout, a wrong code, offline and a
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
