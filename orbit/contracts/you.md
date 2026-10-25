# Contract: you

Prototype screens: `settings-page` (states: `settings`, `you-allgood`, `you-share`, `settings-search`), `profile` (`profile`, `profile-taken`, `profile-new`), `appearance` (`appearance`), `privacy` (`privacy`, `privacy-lock`), `notifications` (`notifications`, `notifications-off`), `chats-settings` (`chats-settings`), `storage` (`storage`), `account` (`account`, `account-nopass`), `password` (`password`, `password-set`, `password-error`, `password-done`), `delete-account` (`delete-account`, `delete-account-sms`, `delete-account-key`), `blocked` (`blocked`, `blocked-empty`), `about` (`about`), `legal` (`legal`), `advanced` (`advanced`, `advanced-offline`)
Today's app: `features/settings/presentation/…` (`settings_tab`, `account_page`, `privacy_page`, `notifications_page`, `chats_page`, `storage_page`, `change_password_page`, `delete_account_page`, `blocked_page`, `about_page`, `legal_page`, `advanced_page`, `choice_sheet`), `features/settings/application/…`, `features/profile/presentation/profile_page.dart`, `features/profile/application/…`

Paths are under `helix_remote/app/lib/` unless they start with `packages/`
(under `helix_remote/`). Devices and Backup pages are in `devices_backup.md`;
the checkup here only reads from them.

## Shared by these screens

| Item | Notes |
|---|---|
| Times and sizes | Formatted by the connector: `formatAgo` (`core/format/labels.dart`, gives "21 days ago", not "3 weeks ago") and `formatBytes`, with `clockProvider`. |
| `HelixAvatarModel` | Reused for every avatar (`packages/helix_remote_ui/lib/src/view_models.dart`). Your own: `settingsAvatarProvider` bytes + `colorIndexFor(accountId)`. Other people: `personNameProvider(id)` (`core/people/people_names.dart`). |
| `HelixQrMatrix` | Reused for the share-sheet QR; encoded by `encodeQr` (`core/platform/qr_encoder.dart`). |
| `HelixPersonNames` | Reused for blocked rows (name, and the number line under it). |
| Failure sentences | Every `error` below is a sentence from `describeFailure` (`core/engine/failure_copy.dart`). The screen never formats an exception. |
| Toasts | "Profile saved", "Unblocked", "<Theme> theme on", "Link copied" are drawn by the screen when an action's `Future` completes and the model shows no error. |
| `UnlockMethod` | `biometricOrPin` / `windowsHello`: derive from the platform (`Platform.isWindows`). Today's app says "fingerprint, face or phone PIN" everywhere. Shared with frame.md's lock screen. |
| `YouTopic` | `profile`, `appearance`, `privacy`, `notifications`, `chats`, `devices`, `backup`, `account`, `accounts`, `storage`, `about`, `advanced`, `recovery`, `password`, `blocked`, `securityActivity`, `legal`. |

## You (`settings-page`)

Dart: `YouScreen`, `YouModel`, `YouActions`.

Your profile is drawn as an orbit (`SCREENS.md` design change 19,
2026-10-18; it replaced the Orbit ID pass). Dart: `OrbitProfile`, used by
`YouScreen` and, compact and without buttons, by the profile editor's preview.
- **The planet:** your photo, always round.
- **The ring:** a tilted ellipse in the theme's wordmark gradient. It is a
  CustomPainter drawn in two halves, behind the photo at the top and in front
  of it at the bottom.
- **The moons:** chips riding the ring for `helixName`, `deviceCount` and E2E.
- **Under it:** `name`, `about`, then `phoneMasked` · `serverName`, then the
  Edit profile pill and the QR button.
- **No card:** it sits on the page background.
- **The data and the two taps are unchanged.**

### Model
| Field | Type | Tag | Comes from today | Notes |
|---|---|---|---|---|
| `name` | `String` | have | `settingsHeaderProvider` → `SettingsHeader.name` (`features/settings/application/settings_providers.dart`) | Empty: the profile says "Add your name". Today it falls back to `~name` when the profile name is empty. |
| `about` | `String` | have | `SettingsHeader.about` (stored in `AppSettings.profileAbout`) | |
| `avatar` | `HelixAvatarModel` | have | `settingsAvatarProvider` + `SettingsHeader.accountId` | The photo is on this phone only (see Edit profile). |
| `helixName` | `String?` | have | `profileProvider` → `ProfileData.helixName` (`features/profile/application/profile_providers.dart`) | Null: "No ~name yet". |
| `phoneMasked` | `String?` | have | `ProfileData.phoneMasked`; else `accountOverviewProvider` → `AccountOverview.phoneMasked` (`features/settings/application/account_providers.dart`) | A linked device does not know the number; the overview gives the last 4 but needs the network. |
| `serverName` | `String` | have | `serverTitleProvider` (`features/settings/application/about_providers.dart`), else `SettingsHeader.serverHost` | The mono line under the name: "<phoneMasked> · <server>". |
| `deviceCount` | `int` | derive | `devicesProvider` length (`features/devices/application/devices_providers.dart`) | "2 devices": a moon on the ring. |
| `checks` | `List<CheckupItem>` | derive | see "The checkup" | Order: backup, devices, password, recovery, lock. |
| `checkupScore` | `({int ok, int total})` | derive | `checks` | "3 of 5" and the bar. |
| `needsAttention` | `bool` | derive | any check not ok | The same value drives the amber dot on the home avatar (home.md). |
| `tiles` | `List<YouTile>` (`topic`, `status`) | derive | see "The tiles" | |
| `storageLabel` | `String` | derive | `storageSummaryProvider` → `totalBytes` (`about_providers.dart`) | "1.2 GB on this phone" on the Storage row. |
| `versionLabel` | `String` | have | `aboutAppProvider.version` (`core/platform/app_info.dart`, `kAppVersion`) | Footer "Orbit 2.0.0 · <host>". |
| `serverHost` | `String` | have | `SettingsHeader.serverHost` | Footer. |
| `selectedTopic` | `YouTopic?` | derive | the right pane's current route (frame.md) | Window only: the marked tile or row. |
| `share` | `ShareCodeModel?` | have | `profileProvider`'s `helixName` → `_shareCode` (`shared/widgets/orbit_you_connector.dart`) | Null (no `~name`) hides the QR button and the whole sheet. See "The share sheet". |

#### The checkup (`CheckupItem`: `key`, `ok`, `title`, `statusText`, `fixLabel?`, `topic`)
| Check | Ok when | Tag | Comes from today | Notes |
|---|---|---|---|---|
| `backup` | a backup exists and `lastProblem == null` | derive | `backupSummaryProvider` → `BackupSummary.lastBackupAt`, `lastProblem`, `autoBackup`; `backupPageViewProvider.lastBackup` (`features/backup/application/backup_providers.dart`) | "Backed up 5 hours ago". The design has no not-ok text or fix. |
| `devices` | always (open question) | derive | `devicesProvider` | "2 devices, both signed in by you": the app cannot know "by you"; suggest "2 devices signed in". |
| `password` | `AccountOverview.hasPassword` | have | `accountOverviewProvider` | "Set. You can sign in on a new phone". The design has no not-ok text; the target would be `password`. |
| `recovery` | `BackupSummary.lastRecoveryBackupAt != null` | have | `backupSummaryProvider` | "Made today" / "No recovery backup yet" + Fix. Known only on the device that made it (devices_backup.md). |
| `lock` | `AppLockView.enabled` | have | `appLockViewProvider` + `relockLabel` (`settings_providers.dart`) | "On. Locks after 1 minute" / "App lock is off" + Turn on. |

#### The tiles
| Tile | Status line | Tag | Comes from today |
|---|---|---|---|
| Appearance | theme name | local | the new theme setting (see Appearance) |
| Privacy | "Receipts on/off" | derive | `readReceiptsProvider` |
| Notifications | "Sound on/off" | derive | `notifySoundProvider` |
| Chats | "Text default" | derive | `fontScaleSettingProvider` + `fontScaleLabel` |
| Devices | "2 linked" | derive | `devicesProvider` |
| Backup | "5 h ago" | derive | `BackupSummary.lastBackupAt` (a short form of `formatAgo`) |

The rows Account, Help and about, Advanced have fixed subtitles; Storage uses `storageLabel`.

#### The share sheet (`ShareCodeModel`)
| Field | Type | Tag | Comes from today | Notes |
|---|---|---|---|---|
| `link` | `String` | have | `helixProfileLink(helixName)` (`core/links/deep_link.dart`) | `helix.agiletechbd.com/u/<name>`. Built (S1): the server answers `GET /u/{name}` with a static page (ops), and `HelixDeepLink.tryParse` reads both the https and `helix://` form. Needs a `~name` — no name, no sheet. |
| `qr` | `HelixQrMatrix` | have | `encodeQr(link)` (`core/platform/qr_encoder.dart`) | The payload is `link`; the sheet draws the real matrix, so it scans. `qrSeed` is the fallback the preview uses. |
| `name`, `helixName`, `avatar` | as above | have | as above | The small profile at the top of the sheet: the planet and its ring, the name and the ~name. |

### Actions
| Action | Signature | Tag | Calls today | Notes |
|---|---|---|---|---|
| `openProfile` | `void Function()` | have | `context.push(RoutePaths.profile)` | Tap, Enter or Space on your profile. |
| `openTopic` | `void Function(YouTopic)` | have | `RoutePaths.account`, `.privacy`, `.notifications`, `.chats`, `.storage`, `.about`, `.advanced`, `.devices`, `.backup`, `.blocked`, `.changePassword`, `.backupRecovery` (`shared/route_paths.dart`) | `YouTopic.appearance` needs a new route. Tiles, rows, search results and the checkup's arrows all use it. |
| `fixRecovery` | `void Function()` | have | `context.push(RoutePaths.backupRecovery)` | The prototype opens the Create tab. |
| `turnOnAppLock` | `Future<String?> Function()` | have | `appLockActionsProvider.setEnabled(true)` (`settings_providers.dart`) | Called after the screen's "Turn on app lock?" dialog. The phone's own prompt follows. Returns a sentence when it could not. |
| `copyShareLink` | `Future<void> Function()` | have | `Clipboard.setData`, then the "Link copied" toast (`shared/widgets/orbit_you_connector.dart`) | |
| `shareLink` | `Future<void> Function()` | have | `ShareAdapter.shareText` (`core/platform/share_adapter.dart`), subject "Message me on Helix" | The interface gained `shareText`; files still go through `shareFile`. Windows uses the same `ShareParams` path. |
| `scanCode` | `void Function()` | have | `context.push(RoutePaths.scanChat)` → `ScanChatScreen` → `PeopleActions.openScannedCode` | Contact mode of the scanner screen (`features/people/presentation/scan_chat_screen.dart`). A scanned `/u/<name>` resolves with `PeopleGateway.findByHelixName`, then `openChat`. |

### Kept inside the screen
Search mode, its text, the search index (fixed titles plus the tiles' live
status lines from the model), results and both empty states; whether the share
sheet, the "See all checks" sheet or the app-lock dialog is open; scroll
position.

### Interactions
| INTERACTIONS.md item | Maps to |
|---|---|
| Your profile (the orbit at the top) | `openProfile` |
| QR button under your profile | sheet kept inside; `copyShareLink`, `shareLink`, `scanCode` |
| Fix / Turn on in the checkup | `fixRecovery`; the dialog is kept inside, then `turnOnAppLock` |
| See all 5 checks | sheet kept inside; its rows call `openTopic`, `fixRecovery` or `turnOnAppLock` |
| Tile or row | `openTopic`; the mark comes from `selectedTopic` |
| Search | kept inside; a result calls `openTopic` |

### Slots
| Slot | What the app puts there | What the preview shows |
|---|---|---|
| none | The scanner is its own screen (`scan`). | |

### The app does this, the prototype does not show it
| What | Where in the app | Suggestion |
|---|---|---|
| Before the header loads: name "Helix", initials avatar | `settings_tab.dart` | Keep, in the new style (the orbit with its placeholders). |
| Search also matches group titles; empty text "Try a different title or description." | `settings_tab.dart` `_shown` | Drop (You has no groups); the prototype's copy wins. |
| Settings is a Home tab today; You is a pushed page from the avatar | `settings_tab.dart`, `features/settings/FEATURE.md` | frame.md and home.md. |
| App-lock refusals: "This phone has no screen lock. Set a PIN, pattern or fingerprint…" and "The app lock was not turned on, because the phone's unlock was not completed." | `AppLockActions.setEnabled` | Keep as a toast after Turn on. |
| No masked number on a linked device while offline | `AccountOverview` needs `refreshAccount()` | Keep: hide the number. |

### New backend work
| Item | Why the design needs it | Engine / server / protocol | Size |
|---|---|---|---|
| Share link `/u/<name>` | Share sheet: link, QR, copy, share | **Built (S1).** Server: `GET /u/{name}` in ops serves one static page and never answers whether the name exists. App: the Android filter took a `/u/` prefix (the host was already claimed in `assetlinks.json`), Windows had `helix://`, `HelixDeepLink` parses both. Lookup stays the session-carrying `/v1/people/by-name/{name}` (honours `discoverable_by_name`, people `MODULE.md`). | M |
| Scan someone's code to start a chat | "Scan someone's code" | **Built (S1).** App only: `/scan-chat` → the scanner in contact mode → `findByHelixName` → `openChat`. The parsed-but-unused `helix://contact/add` is left alone; a person's link is the one format. | S |

## Edit profile (`profile`)

Dart: `ProfileEditScreen`, `ProfileEditModel`, `ProfileEditActions`.

### Model
| Field | Type | Tag | Comes from today | Notes |
|---|---|---|---|---|
| `saved` | `ProfileData` | have | `profileProvider` (`features/profile/application/profile_providers.dart`) | `accountId`, `name`, `about`, `helixName`, `phoneMasked`. The fields start from it once. |
| `loading` | `bool` | have | `profileProvider` loading | |
| `loadFailed` | `bool` | have | `profileProvider` error | |
| `avatar` | `HelixAvatarModel` | have | `profileAvatarBytesProvider` + `accountId` | |
| `canPickPhoto` | `bool` | have | `canPickAvatarProvider` | False hides the photo buttons. |
| `nameMax`, `aboutMax` | `int` | have | `ProfileRules.maxName` (50), `ProfileRules.maxAbout` (139) | The counters. |
| `busy` | `bool` | have | `profileEditProvider` → `ProfileEditState.busy` | |
| `nameError`, `aboutError`, `helixNameError`, `error` | `String?` | have | `ProfileEditState` | `helixNameError` includes the server's refusal (`helixNameUnavailable`). |
| `notice` | `String?` | have | `ProfileEditState.notice` | "Photo updated.", "Photo removed.", "Your ~name is removed." |
| `photoShared` | `bool` | engine | nothing | False today: the photo stays on this phone. Drives the "Who sees what" photo row. |
| `findableByName` | `bool?` | have | `privacyProvider` → `PrivacyPrefs.discoverableByName` | The "~name: Public" row is only true when this is on. |
| `findableByNumber` | `bool?` | have | `PrivacyPrefs.discoverableByPhone` | Same for the phone row. |

### Actions
| Action | Signature | Tag | Calls today | Notes |
|---|---|---|---|---|
| `checkHelixName` | `String? Function(String input)` | have | `ProfileRules.helixNameProblem` / `normaliseHelixName` | Sync rule check as you type; null means the rules pass. The "This is your ~name" case is the screen comparing with `saved.helixName`. |
| `checkHelixNameAvailable` | `Future<bool?> Function(String name)` | server | nothing | "~x is available". No such route: only `PUT`/`DELETE /v1/account/helix-name` and the discovery lookup. The server answers "taken" and "looks like staff" the same on purpose, so nobody can probe names. |
| `choosePhoto` | `Future<void> Function()` | have | `ProfileEditor.chooseAvatar` | |
| `removePhoto` | `Future<void> Function()` | have | `ProfileEditor.removeAvatar` | No confirmation, as today. |
| `removeHelixName` | `Future<void> Function()` | have | `ProfileEditor.clearHelixName` | Confirmation kept inside (same copy as today). |
| `save` | `Future<bool> Function({required String name, required String about, required String helixName})` | derive | `ProfileEditor.save`, then `ProfileEditor.saveHelixName` when the `~name` changed | One Save for both. True when both succeeded: the screen pops and says "Profile saved". An empty `~name` field does not remove it (only "Remove my ~name" does). |

### Kept inside the screen
The three fields' text, the live profile preview (`OrbitProfile`, compact) built from them and the model,
the rule message under the `~name` field, the remove dialog.

### Interactions
| INTERACTIONS.md item | Maps to |
|---|---|
| Name / About (preview updates) | kept inside |
| ~name (checked as you type) | `checkHelixName`; availability `checkHelixNameAvailable` |
| Photo / Remove | `choosePhoto`, `removePhoto` |
| Remove my ~name (asks first) | dialog kept inside, then `removeHelixName` |
| Save | `save`; toast kept inside |

### Slots
| Slot | What the app puts there | What the preview shows |
|---|---|---|
| none | The photo picker is a platform sheet started by `choosePhoto`. | |

### The app does this, the prototype does not show it
| What | Where in the app | Suggestion |
|---|---|---|
| Loading bar; "Your profile could not be loaded." with Try again | `profile_page.dart` | Keep in the new style. |
| Busy bar while saving or picking | `profile_page.dart` | Keep: spinner in Save. |
| Name and `~name` saved separately ("Save", "Claim ~name" / "Save ~name"), staying on the page with "Saved." | `profile_page.dart` | Use the prototype's one Save; keep each field's error when only one part fails. |
| Server refusal: "That name is not available. It may already be taken, or it may be one that could be mistaken for Helix staff…" | `helixNameUnavailable` | Keep the meaning (the prototype's "That name is not available. Try another." hides why). |
| Photo errors: "That file could not be read as a picture. Try another.", "The photo could not be changed. Try again." | `ProfileEditor.chooseAvatar` | Keep as toasts. |
| "Your photo is kept on this phone. Sharing it with your contacts is not available yet." | `profile_page.dart` | Keep until photo sharing ships. |
| Photo buttons hidden where the platform cannot pick | `canPickAvatarProvider` | Keep. |
| Phone number row (masked) with "Those who already have it can find you by it unless you turn that off in Privacy." | `profile_page.dart` | Dropped by the design (your profile on You shows it); fine. |

### New backend work
| Item | Why the design needs it | Engine / server / protocol | Size |
|---|---|---|---|
| Share the profile photo with people you have messaged | "Who sees what: Name, about and photo · Encrypted" | Engine: upload as `persistent` media (server kind exists: 5 MiB, kept until deleted, `server/lib/src/modules/media/MODULE.md`), put the pointer in `ProfileContent.avatar` (field exists, `packages/helix_remote_protocol/lib/src/modules/people.dart`), which `PeopleService.setOwnProfile` does not send today (`packages/helix_remote_engine/lib/src/features/people_service.dart`); receivers fetch it into `PersonRow.avatarBlob`. No server or protocol change found. | M |
| Live `~name` availability | "~x is available" | Server: a new check route with a rate limit; it undoes the deliberate "no probing" rule. Alternative: say "Looks good" from the rules and give the server's answer on Save. | S |

## Appearance (`appearance`)

Dart: `AppearanceScreen`, `AppearanceModel`, `AppearanceActions`.

Themes are data. Built in: Orbit and Orbit Night only. Downloadable packs:
Bloom, Mochi, Papyrus, Arcade, Terminal, Field, Jungle, Ocean and Metal, all
nine published on 2026-10-25. Appearance lists the built-ins and the packs this
device holds, a card each; getting, updating and deleting a pack is the page
behind its "More themes" row.

### Model
| Field | Type | Tag | Comes from today | Notes |
|---|---|---|---|---|
| `themes` | `List<OrbitThemeOption>` | local | nothing; built-in entries from the generated theme table (`orbit_ui`, `tools/themes.py`) | Grouped Light and Dark by the screen. |
| `themes[].id`, `.name`, `.vibe`, `.isDark`, `.swatches` (`List<Color>`: bg, accent, out, second) | as named | local | `tools/themes.py` `reg` | For packs these come from the pack catalog (next row). |
| `themes[].source` | `ThemeSource { builtIn, downloaded, notDownloaded }` | engine | nothing | Pack side: catalog, download, storage. |
| `themes[].downloadBytes` | `int?` | engine | nothing | Shown on a pack not yet downloaded. |
| `themes[].downloadProgress` | `double?` | engine | nothing | The design has no state for it yet. |
| `currentThemeId` | `String` | local | nothing; new `AppSettings.theme` (`Setting<String>('app.theme', 'orbit')`) in `core/security/app_settings.dart` | Also drives `MaterialApp` (below). |
| `current` | `OrbitThemeOption` | derive | `themes` + `currentThemeId` | The hero card. |

### Actions
| Action | Signature | Tag | Calls today | Notes |
|---|---|---|---|---|
| `chooseTheme` | `Future<void> Function(String id)` | local | nothing | Writes `AppSettings.theme`. Only for built-in or downloaded themes. The current theme does nothing (kept inside); the toast is kept inside. |
| `downloadPack` | `Future<void> Function(String id)` | engine | nothing | Later phase. |
| `deletePack` | `Future<void> Function(String id)` | engine | nothing | Later phase. |

### Kept inside the screen
The toast, the "current does nothing" check, scroll position. Each card draws
itself in its own theme from the theme's tokens.

### Interactions
| INTERACTIONS.md item | Maps to |
|---|---|
| Theme card | `chooseTheme`; the current one does nothing (kept inside) |

### Slots
| Slot | What the app puts there | What the preview shows |
|---|---|---|
| none | | |

### The app does this, the prototype does not show it
| What | Where in the app | Suggestion |
|---|---|---|
| One light theme, fixed: `theme: HelixThemes.light()`, `highContrastTheme: HelixThemes.highContrastLight()`, `themeMode: ThemeMode.light` | `main.dart` `HelixRemoteApp.build` | Replace with the chosen theme (its own `ThemeMode`); remove `highContrastTheme`; retire the light-only rule in AGENTS.md and `product_rules_test` (PORT_PLAN Part B). |
| "Helix has one theme, a light one." | `features/settings/presentation/chats_page.dart` footer and doc comment | Drop. |
| Sign-in uses `HelixThemes.signIn()` | AGENTS.md product rules | signin.md: decide whether sign-in follows the chosen theme. |
| Pack states (not downloaded, size, downloading, failed, delete) | none | Not drawn: back to Phase 0 before the pack phase. |

### New backend work
| Item | Why the design needs it | Engine / server / protocol | Size |
|---|---|---|---|
| Theme packs | Six themes move from built in to downloadable | Engine (pack side): catalog, download, store, delete. Packs are **data only, never code**: tokens, fonts (OFL), pattern and effect parameters. A pack can only choose among effects `orbit_ui` already ships (glow, scanlines, ornaments, stripes). **Signed, and the signature checked before use**, against a key pinned in the app. Where packs are hosted is open (server or a static host). | M |

## Privacy (`privacy`)

Dart: `PrivacyScreen`, `PrivacyModel`, `PrivacyActions`.

### Model
| Field | Type | Tag | Comes from today | Notes |
|---|---|---|---|---|
| `prefs` | `PrivacyPrefs?` | have | `privacyProvider` → `PrivacyState.prefs` (`features/settings/application/privacy_providers.dart`) | `lastSeen`, `online`, `groupAdd` (`AudienceChoice`), `discoverableByPhone`, `discoverableByName`. Server-held; null until loaded. |
| `loading`, `saving` | `bool` | have | `PrivacyState.loading`, `.saving` | |
| `error` | `String?` | have | `PrivacyState.error` | |
| `needsNumber` | `bool` | have | `PrivacyState.needsNumber` | The screen asks for the number (turning "find me by phone number" back on, on a device that does not know it). |
| `audienceChoices` | `List<AudienceChoice> Function(AudienceChoice)` result per row | have | `audienceChoicesFor` | "My contacts" appears only when the server already holds it: the segmented control then needs a third segment. |
| `readReceipts` | `bool` | have | `readReceiptsProvider` (`settings_providers.dart`) | |
| `typing` | `bool` | have | `typingIndicatorsProvider` | |
| `defaultTimerSeconds` | `int?` | have | `defaultDisappearingProvider` | Choices `disappearingChoices`, labels `disappearingLabel` ("24 hours" vs the design's "24 h": style). |
| `appLock` | `AppLockView` | have | `appLockViewProvider` | `enabled`, `relockAfterSeconds`. |
| `relockChoices` | `List<int>` | have | `relockChoices`, `relockLabel` | "Immediately", "After 1 minute" vs "Now", "1 min": style. |
| `unlockMethod` | `UnlockMethod` | derive | platform | Switch subtitle. |
| `blockedCount` | `int` | derive | `blockedProvider` length | Pill "1 blocked" and the Blocked row. |
| `blockedAvatars` | `List<HelixAvatarModel>` | derive | `blockedProvider` ids → `personNameProvider(id)` | The avatar stack. |
| `ownName`, `ownAvatar` | `String`, `HelixAvatarModel` | have | `settingsHeaderProvider`, `settingsAvatarProvider` | The preview's head. |
| `previewViewerName` | `String` | derive | most recent direct chat, or fixed copy | "What Nadia sees" (open question). |
| `summary` | `String` + pills | derive | `prefs`, `readReceipts`, `appLock`, `blockedCount` | "1 of 2 statuses hidden", "Receipts on", "App lock off", "1 blocked". |

### Actions
| Action | Signature | Tag | Calls today | Notes |
|---|---|---|---|---|
| `setLastSeen` | `Future<void> Function(AudienceChoice)` | have | `PrivacyController.setLastSeen` | |
| `setOnline` | `Future<void> Function(AudienceChoice)` | have | `PrivacyController.setOnline` | |
| `setGroupAdd` | `Future<void> Function(AudienceChoice)` | have | `PrivacyController.setGroupAdd` | |
| `setFindByNumber` | `Future<void> Function(bool)` | have | `PrivacyController.setDiscoverableByPhone` | |
| `setFindByName` | `Future<void> Function(bool)` | have | `PrivacyController.setDiscoverableByName` | |
| `submitNumber` | `Future<bool> Function(String)` | have | `PrivacyController.submitNumber` | False: not a number with a country code. |
| `cancelNumber` | `void Function()` | have | `PrivacyController.cancelNumber` | |
| `retryLoad` | `Future<void> Function()` | have | `PrivacyController.load` | |
| `setReadReceipts` | `Future<void> Function(bool)` | have | `SettingsActions.setReadReceipts` | |
| `setTyping` | `Future<void> Function(bool)` | have | `SettingsActions.setTypingIndicators` | |
| `setDefaultTimer` | `Future<void> Function(int? seconds)` | have | `SettingsActions.setDefaultDisappearing` | |
| `setAppLock` | `Future<String?> Function(bool)` | have | `AppLockActions.setEnabled` | Returns the refusal sentence. |
| `setRelockAfter` | `Future<void> Function(int seconds)` | have | `AppLockActions.setRelockAfter` | |
| `openBlocked` | `void Function()` | have | `context.push(RoutePaths.blocked)` | |

### Kept inside the screen
The live "What … sees" preview (drawn from the model), the phone-number
dialog's text, scroll position.

### Interactions
| INTERACTIONS.md item | Maps to |
|---|---|
| Everyone / Nobody choices | `setLastSeen`, `setOnline`, `setGroupAdd`; preview kept inside |
| Read receipts / Typing / Being found | `setReadReceipts`, `setTyping`, `setFindByNumber`, `setFindByName` |
| Disappearing messages for new chats | `setDefaultTimer` |
| Lock Orbit (Lock again appears) | `setAppLock`; `setRelockAfter` |
| Blocked | `openBlocked` |

### Slots
| Slot | What the app puts there | What the preview shows |
|---|---|---|
| none | | |

### The app does this, the prototype does not show it
| What | Where in the app | Suggestion |
|---|---|---|
| Server choices hidden behind a loading bar until they arrive; local switches show at once | `privacy_page.dart` | Keep in the new style (skeleton segments). |
| Saving bar while a server choice is sent | `privacy_page.dart` | Keep: a spinner on the changed control. |
| Load failure with Try again; a failed change goes back with "That was not saved. …" | `PrivacyController` | Keep as a notice. |
| Phone number dialog: "Your phone number", "With its country code, like +88017XXXXXXXX", Turn on; toast on a bad number; refusal "Helix did not turn this on. It checks the number against the one your account was verified with…" | `privacy_page.dart` `_askForNumber`, `PrivacyController.update` | Keep; not drawn in the design. |
| "My contacts" shown when another client set it | `audienceChoicesFor` | Keep a third segment for that case. |
| App-lock refusal toasts | `AppLockActions.setEnabled` | Keep. |

## Notifications (`notifications`)

Dart: `NotificationsScreen`, `NotificationsModel`, `NotificationsActions`.

### Model
| Field | Type | Tag | Comes from today | Notes |
|---|---|---|---|---|
| `osAllowed` | `bool?` | have | `notificationPermissionProvider` (`settings_providers.dart`) | False shows the notice. |
| `alertMessages`, `alertGroups`, `alertCalls` | `bool` | have | `notifyMessagesProvider`, `notifyGroupsProvider`, `notifyCallsProvider` | `AppSettings.notify*` (`core/security/app_settings.dart`). |
| `sound`, `vibrate` | `bool` | have | `notifySoundProvider`, `notifyVibrateProvider` | Pick the Android message channel (`core/notifications/local_notifications.dart`). |
| `previews` | `bool` | have | `notificationPreviewsProvider` (`AppSettings.notificationsPreview`, off by default) | Also hides the caller's name on the ringing notification. |
| `muted` | `List<MutedChatItem>?` | have | `mutedChatsProvider` → `MutedChat` (`id`, `title`, `until`) | Null while loading. |
| `mutedFailed` | `bool` | have | `mutedChatsProvider` error | |
| `muted[].avatar` | `HelixAvatarModel` | derive | `SettingsGateway.watchMuted` reads `engine.chats.watchChats`; `MutedChat` has no avatar | |
| `summary` | `String` | derive | the alerts and `previews` | "2 of 3 alerts on · previews hidden". |
| `ringtone` | `RingtoneOption` (`id`, `name`) | local | nothing; new `AppSettings.callRingtone` | The ringtone for incoming calls. One default is bundled. |
| `ringtones` | `List<RingtoneOption>` (`id`, `name`, `builtIn`, `downloaded`) | engine | nothing | Downloaded ahead of time: a call cannot wait for a download. Later phase. |

### Actions
| Action | Signature | Tag | Calls today | Notes |
|---|---|---|---|---|
| `setAlert` | `Future<void> Function(AlertKind, bool)` | have | `SettingsActions.setNotifyMessages`, `.setNotifyGroups`, `.setNotifyCalls` | |
| `setSound` | `Future<void> Function(bool)` | have | `SettingsActions.setNotifySound` | |
| `setVibrate` | `Future<void> Function(bool)` | have | `SettingsActions.setNotifyVibrate` | |
| `setPreviews` | `Future<void> Function(bool)` | have | `SettingsActions.setNotificationPreviews` | |
| `unmute` | `Future<void> Function(String chatId)` | have | `MutedActions.unmute` | |
| `allowNotifications` | `Future<void> Function()` | have | `NotificationPermission.request` | The design says it opens the phone's notification settings; today it shows the system prompt, which Android stops showing after a refusal. Opening the settings page is a small platform call `LocalNotifications` does not have. |
| `chooseRingtone` | `Future<void> Function(String id)` | local | nothing | |
| `openMoreRingtones` | `void Function()` | engine | nothing | "Get more ringtones". Later phase. |

Ringtone on the platforms:
- **Android:** a notification channel's sound is fixed when the channel is
  created. Today calls ring through the channel `helix_incoming_calls_ringtone`
  with the phone's own ringtone (`content://settings/system/ringtone`,
  `core/notifications/call_notifications.dart`), shown by
  `NotificationCallRinger` (`features/calls/application/platform/notification_call_ringer.dart`,
  `callRingerProvider`). A custom ringtone needs a new channel per ringtone,
  or the app playing the sound itself (harder when the app was started by a
  push).
- **Windows:** `AlertCallRinger` repeats a system alert; a custom ringtone
  needs audio playback.

### Kept inside the screen
The lock-screen preview (fixed sample text, flags from the model), the
"Unmuted" toast, the ringtone picker sheet.

### Interactions
| INTERACTIONS.md item | Maps to |
|---|---|
| Messages / Groups / Calls tiles | `setAlert` |
| Sound / Vibrate / Show message previews | `setSound`, `setVibrate`, `setPreviews`; preview kept inside |
| Unmute (muted chat) | `unmute` |
| Allow notifications (when off) | `allowNotifications` |
| (new, not in the prototype) Ringtone row | `chooseRingtone`, `openMoreRingtones` |

### Slots
| Slot | What the app puts there | What the preview shows |
|---|---|---|
| none | | |

### The app does this, the prototype does not show it
| What | Where in the app | Suggestion |
|---|---|---|
| Muted chats: loading bar, "Muted chats could not be loaded", "No muted chats" | `notifications_page.dart` | Keep; the design draws no empty or error state. |
| "Muted for now" (timed) vs "Muted" | `notifications_page.dart` | Keep the difference. |
| Lock-screen footer: "Off, a notification says "New message" and nothing more… Helix servers and the push service never see message text either way." | `notifications_page.dart` | Keep: it is a privacy claim the design drops. |
| Ringtone row | none | Not drawn: back to Phase 0 (reserved by the owner 2026-10-18). |

## Chats (`chats-settings`)

Dart: `ChatsSettingsScreen`, `ChatsSettingsModel`, `ChatsSettingsActions`.

### Model
| Field | Type | Tag | Comes from today | Notes |
|---|---|---|---|---|
| `textScalePercent` | `int` | have | `fontScaleSettingProvider` | Applied app-wide by `AppTextScale` (`shared/widgets/app_text_scale.dart`), multiplying the phone's size. |
| `textScaleChoices` | `List<(int, String)>` | have | `fontScaleChoices`, `fontScaleLabel` | 90/100/115/130: Small, Default, Large, Extra large. |
| `enterSends` | `bool` | have | `enterToSendProvider` | |
| `autoDownload` | `Map<MediaKindChoice, MediaDownloadPolicy>` | have | `mediaImagesProvider`, `mediaAudioProvider`, `mediaVideoProvider`, `mediaDocumentsProvider` | Defaults Wi-Fi, Always, Never, Never. |
| `summary` | `String` | derive | the above | "Text default · Enter adds a line". |

### Actions
| Action | Signature | Tag | Calls today | Notes |
|---|---|---|---|---|
| `setTextScale` | `Future<void> Function(int percent)` | have | `SettingsActions.setFontScale` | |
| `setEnterSends` | `Future<void> Function(bool)` | have | `SettingsActions.setEnterToSend` | |
| `setAutoDownload` | `Future<void> Function(MediaKindChoice, MediaDownloadPolicy)` | have | `SettingsActions.setMediaPolicy` | `mediaPolicySyncProvider` turns it into engine limits (`features/settings/application/media_policy_sync.dart`). |

### Kept inside the screen
The conversation preview at the chosen size.

### Interactions
| INTERACTIONS.md item | Maps to |
|---|---|
| Text size buttons | `setTextScale`; preview kept inside |
| Enter key sends | `setEnterSends` |
| Download automatically choices | `setAutoDownload` |

### Slots
| Slot | What the app puts there | What the preview shows |
|---|---|---|
| none | | |

### The app does this, the prototype does not show it
| What | Where in the app | Suggestion |
|---|---|---|
| "Small previews always load so a chat is not blank." | `chats_page.dart` footer | Add to the footnote. |
| "Always" still stops at a size ceiling (photos and voice 10 MB, video 50 MB, documents 25 MB) | `MediaDownloadLimits` | Say so in the footnote, or accept the gap. |

## Storage and data (`storage`)

Dart: `StorageScreen`, `StorageModel`, `StorageActions`.

### Model
| Field | Type | Tag | Comes from today | Notes |
|---|---|---|---|---|
| `totalBytes`, `databaseBytes`, `mediaBytes` (as labels) | `String` | have | `storageSummaryProvider` → `StorageSummary` (`about_providers.dart`, `core/platform/storage_usage.dart`) | Hero "1.2 GB on this phone · 184 MB messages and keys · 1.0 GB media". |
| `loading`, `failed` | `bool` | have | `storageSummaryProvider` | |
| `photosVideosBytes`, `filesBytes` | `int` | have | `SettingsGateway.mediaStorage()` → engine `MediaService.storageUsage()` | The bar's split, from `Attachments.size` where a local copy exists. Photos are images, videos, video notes and GIFs; files are documents, unknown kinds and voice notes (voice notes have no free-up of their own). |
| `biggestChats` | `List<StorageChat>` (`chatId`, `title`, `avatar`, `bytes`, `mediaBytes`, `documentBytes`) | have | `SettingsGateway.biggestChats()` (engine joins attachments and messages); title/avatar from the chat list | Downloaded media only, voice notes left out; `"Chat"` until the chat list loads. |
| `autoDownloadSummary` | `String` | derive | the four media providers | "Photos on Wi-Fi, voice always, videos and documents never". |
| `backupOverMobile` | `bool` | have | `backupOverMobileProvider` (`backup_providers.dart`) | "Allowed" / "Wi-Fi only". |

### Actions
| Action | Signature | Tag | Calls today | Notes |
|---|---|---|---|---|
| `freeChatSpace` | `Future<int> Function(String chatId, FreeKind kind)` | have | `SettingsGateway.freeChatSpace` → engine `MediaService.freeChatSpace` | `FreeKind { photosVideos, documents }`; deletes the files and thumbnails of `ready` downloads, clears their local paths and marks them `remote`, keeps messages, keys and pointers, and returns bytes freed. They can be fetched again while the server keeps the object: 30 days for attachments. |
| `openAutoDownload` | `void Function()` | have | `context.push(RoutePaths.chats)` | |
| `openBackup` | `void Function()` | have | `context.push(RoutePaths.backup)` | |
| `retry` | `void Function()` | have | `ref.invalidate(storageSummaryProvider)` | |

### Kept inside the screen
The "Free up space in …" sheet, the "<n> MB freed" toast.

### Interactions
| INTERACTIONS.md item | Maps to |
|---|---|
| Chat in Biggest chats | sheet kept inside, then `freeChatSpace` |
| Download automatically / Backup over mobile data | `openAutoDownload`, `openBackup` |

### Slots
| Slot | What the app puts there | What the preview shows |
|---|---|---|
| none | | |

### The app does this, the prototype does not show it
| What | Where in the app | Suggestion |
|---|---|---|
| Loading; "The storage figures could not be read." with retry | `storage_page.dart` | Keep in the new style. |
| The probe returns zeros when it cannot read the folder | `DeviceStorageUsageProbe.measure` | Keep. |
| "To free space, delete messages or a whole chat: the files go with them." | `storage_page.dart` | Replaced by E3: the screen now says "Tap a chat to free space without deleting its messages." |

### New backend work
| Item | Why the design needs it | Engine / server / protocol | Size |
|---|---|---|---|
| Media size by kind and by chat | The bar's split, "Biggest chats" | Engine + `helix_remote_db` DAO query | **Built** (E2, pending review) |
| Free a chat's photos, videos or documents | "Free up space" sheet | Engine: delete files, set `transfer` back to remote, keep the pointer | **Built** (E3, pending review) |

## Account (`account`)

Dart: `AccountScreen`, `AccountModel`, `AccountActions`.

### Model
| Field | Type | Tag | Comes from today | Notes |
|---|---|---|---|---|
| `overview` | `AccountOverview?` | have | `accountOverviewProvider` (`account_providers.dart`) | `phoneMasked`, `helixName`, `hasPassword`, `passwordUpdatedAt`, `phoneKnownOnDevice`. Needs the network. |
| `loading`, `loadFailed` | `bool` | have | `accountOverviewProvider` | |
| `name`, `avatar` | `String`, `HelixAvatarModel` | have | `settingsHeaderProvider`, `settingsAvatarProvider` | Hero. |
| `deviceCount` | `int` | derive | `devicesProvider` | Pill "2 devices". |
| `since` | `String?` | derive | `AccountInfo.createdAt` (`packages/helix_remote_protocol/lib/src/modules/identity.dart`), returned by `engine.settings.refreshAccount()` but not copied into `AccountOverview` | Add `createdAt` in `EngineSettingsGateway.account()`. "Since Sep 2026". |
| `passwordSubtitle` | `String?` | have | `passwordSubtitleProvider` | "Changed 21 days ago" / "Not set. Add one to sign in on a new phone." |
| `busy`, `error`, `notice` | `bool`, `String?`, `String?` | have | `accountActionsProvider` → `AccountActionState` | |

### Actions
| Action | Signature | Tag | Calls today | Notes |
|---|---|---|---|---|
| `openPassword` | `void Function()` | have | `context.push(RoutePaths.changePassword)` | Change or Set. |
| `openSecurityActivity` | `void Function()` | have | `context.push(RoutePaths.devicesActivity)` | |
| `exportData` | `Future<bool> Function()` | have | `AccountActions.exportData` | Shares `helix-account-export-<date>.json`; the design says `orbit-account.json`. |
| `signOut` | `Future<void> Function()` | have | `AccountActions.signOut` | "Sign out and remove": signs this account out of this phone and deletes its data here; the other accounts stay. Confirmation kept inside. |
| `onSwitchAccount` | `VoidCallback?` | have | `context.push(RoutePaths.accounts)` | "Switch account", offered in the sign-out dialog; keeps this account signed in. Null hides it. |
| `startDelete` | `Future<void> Function({required bool exportFirst})` | have | `AccountActions.exportData`, then `context.push(RoutePaths.deleteAccount)` | Dialog kept inside. Today "Export first" exports and then goes on to the delete page; the prototype only exports. |
| `retry` | `void Function()` | have | `ref.invalidate(accountOverviewProvider)` | |

### Kept inside the screen
The sign-out and delete dialogs.

### Interactions
| INTERACTIONS.md item | Maps to |
|---|---|
| Change or set a password / Security activity | `openPassword`, `openSecurityActivity` |
| Export my data | `exportData` |
| Sign out (asks first: Switch account, or Sign out and remove) | dialog kept inside, then `onSwitchAccount` or `signOut` |
| Delete my account (Export first or Continue) | dialog kept inside, then `startDelete` |

### Slots
| Slot | What the app puts there | What the preview shows |
|---|---|---|
| none | | |

### The app does this, the prototype does not show it
| What | Where in the app | Suggestion |
|---|---|---|
| Progress bar while exporting or signing out; failure notice | `account_page.dart` | Keep in the new style. |
| "The export was ready but could not be shared from this device." | `AccountActions.exportData` | Keep as a notice. |
| "Your account details could not be loaded. You may be offline." with Try again | `account_page.dart` | Keep; the hero then shows name only. |
| "Phone number hidden" when no number is known | `account_page.dart` | Keep: hide it in the hero. |
| The `~name` row opens the profile | `account_page.dart` | Dropped by the design; fine. |

## Accounts (`accounts`)

Dart: `AccountsScreen`, `AccountsModel`, `AccountsActions`, `AccountsEntry`.
No prototype screen (added 2026-10-21 with saved accounts; drawn in the
Account page's style). Route `RoutePaths.accounts`, reached from Account >
Sign out > Switch account and from the You tile.

### Model
| Field | Type | Tag | Comes from today | Notes |
|---|---|---|---|---|
| `accounts` | `List<AccountsEntry>` (`id`, `title`, `detail`, `avatar`, `current`) | have | `accountLinesProvider` (`features/settings/application/accounts_providers.dart`), from `accountsProvider` (`core/engine/runtime_providers.dart`) | The account on screen first, then the others, most recent first. Title: the name, else the masked number; detail: the masked number under a name, else the server. |
| `busy`, `notice` | `bool`, `String?` | have | `accountsPageProvider` → `AccountsPageState` (`busy`, `error`) | Removing; the last failure. |

### Actions
| Action | Signature | Tag | Calls today | Notes |
|---|---|---|---|---|
| `onOpen` | `ValueChanged<String>?` | have | `accountsPageProvider.open` → `accountsProvider.notifier.switchTo` | Closes the account on screen (it stays signed in) and opens the other. |
| `onAdd` | `VoidCallback?` | have | `accountsPageProvider.add` → `accountsProvider.notifier.addAccount` | Sign in one more; the others stay. |
| `onRemove` | `ValueChanged<String>?` | have | `accountsPageProvider.remove` | Signs that account out of this phone and wipes its data here. Asks first ("Remove <title>?"). |

### Kept inside the screen
The remove dialog.

## Change password (`password`)

Dart: `PasswordScreen`, `PasswordModel`, `PasswordActions`.

### Model
| Field | Type | Tag | Comes from today | Notes |
|---|---|---|---|---|
| `hasPassword` | `bool` | have | `accountOverviewProvider` → `hasPassword` | Change vs Set. |
| `lastChanged` | `String?` | have | `AccountOverview.passwordUpdatedAt` + `formatAgo` | "Last changed 3 weeks ago". |
| `needsPhone` | `bool` | have | `hasPassword && !phoneKnownOnDevice` | |
| `minLength` | `int` | have | `PasswordRules.minLength` (8) | The first rule. |
| `loading` | `bool` | have | `accountOverviewProvider` loading | |
| `busy`, `done` | `bool` | have | `changePasswordProvider` → `ChangePasswordState` | |
| `currentError`, `newError`, `confirmError`, `error` | `String?` | have | `ChangePasswordState` | |

### Actions
| Action | Signature | Tag | Calls today | Notes |
|---|---|---|---|---|
| `submit` | `Future<void> Function({required String current, required String next, required String confirm, String? phoneNumber})` | have | `ChangePasswordController.submit` | |
| `notSameAsCurrent` | `bool Function(String current, String next)` | derive | nothing | The rule "Not the same as your current one" is new: neither the controller nor the server checks it. A text comparison only. |
| `done` | `void Function()` | have | `context.pop()` | |

### Kept inside the screen
The three fields' text, Show passwords, the rules list computed from the
fields and `minLength`, the button's on/off state.

### Interactions
| INTERACTIONS.md item | Maps to |
|---|---|
| Password fields (rules tick, button turns on) | kept inside, using `minLength` and `notSameAsCurrent` |
| Show passwords | kept inside |
| Change password / Set password | `submit`; the saved state from `done` in the model |

### Slots
| Slot | What the app puts there | What the preview shows |
|---|---|---|
| none | | |

### The app does this, the prototype does not show it
| What | Where in the app | Suggestion |
|---|---|---|
| Phone number field, "Needed once to check your current password", on a linked device | `change_password_page.dart` | Add to the design. |
| "That is not your current password." and the lockout sentence under Current password | `ChangePasswordController.submit` | Keep (the design draws only the mismatch). |
| "Enter your current password." | same | Keep. |
| Offline or rate-limited notice | same | Keep. |
| Loading bar while the account loads | `change_password_page.dart` | Keep. |

## Delete my account (`delete-account`)

Dart: `DeleteAccountScreen`, `DeleteAccountModel`, `DeleteAccountActions`.

### Model
| Field | Type | Tag | Comes from today | Notes |
|---|---|---|---|---|
| `proof` | `DeleteProof { password, code, device }` | have | `hasPassword ? password : deleteAccountProvider.proof` (`features/settings/application/delete_account_providers.dart`) | See the note under this table. |
| `codeSentTo` | `String?` | have | `DeleteAccountState.codeSentTo` | "We sent a 6-digit code to …". |
| `showNumber` | `bool` | have | `DeleteAccountState.needsNumber`, or password proof on a device without the number | |
| `loading` | `bool` | have | `accountOverviewProvider` loading | |
| `busy`, `done` | `bool` | have | `DeleteAccountState` | |
| `confirmError`, `passwordError`, `numberError`, `codeError`, `error` | `String?` | have | `DeleteAccountState` | |

An account without a password starts as `device`. Only when the server answers
`invalid_credentials` listing `verification_token` (`DeletionNeedsCode`) does
the page switch to `code`, and it requests the code by itself. So the
prototype's first SMS state ("Send me a code" before anything is sent) appears
only when the number is needed first or sending failed.

### Actions
| Action | Signature | Tag | Calls today | Notes |
|---|---|---|---|---|
| `submit` | `Future<void> Function({required String confirmation, String password, String phoneNumber, String code})` | have | `DeleteAccountController.submit` | The connector adds `hasPassword` and `phoneKnown` from the overview. |
| `sendCode` | `Future<void> Function({String phoneNumber})` | have | `DeleteAccountController.sendCode` | "Send me a code" and "Send a new code". |
| `exportFirst` | `Future<bool> Function()` | have | `AccountActions.exportData` | |
| `cancel` | `void Function()` | have | `context.pop()` | |

After `done` the engine has wiped the phone; `signOutProvider` runs and the
router moves to sign-in.

### Kept inside the screen
The fields' text, the eye in the password field.

### Interactions
| INTERACTIONS.md item | Maps to |
|---|---|
| Type DELETE | kept inside; checked by `submit` |
| Send me a code (SMS) | `sendCode` |
| Eye in the password field | kept inside |
| Delete my account | `submit` |
| Export my data first / Cancel | `exportFirst`, `cancel` |

### Slots
| Slot | What the app puts there | What the preview shows |
|---|---|---|
| none | | |

### The app does this, the prototype does not show it
| What | Where in the app | Suggestion |
|---|---|---|
| Phone number field when the device does not know it ("Needed once to check your password, with its country code") | `delete_account_page.dart` | Add to the design. |
| Errors under each field: "Type DELETE in capital letters to confirm.", "That is not your password.", lockout, "Enter the number with its country code…", "The code is 6 digits.", "That code did not match…", "Ask for a code first." | `DeleteAccountController` | Keep under the fields (the design only toasts "Type DELETE to confirm."). |
| Fields disabled while busy | `delete_account_page.dart` | Keep. |
| Loading bar while the account loads | same | Keep. |

## Blocked (`blocked`)

Dart: `BlockedScreen`, `BlockedModel`, `BlockedActions`.

### Model
| Field | Type | Tag | Comes from today | Notes |
|---|---|---|---|---|
| `people` | `List<BlockedItem>?` | have | `blockedProvider` → `BlockedPerson` (`id`, `name`) (`privacy_providers.dart`) | Null while loading. Empty: "Nobody is blocked". |
| `people[].names`, `people[].avatar` | `HelixPersonNames`, `HelixAvatarModel` | derive | `personNameProvider(id)` (`core/people/people_names.dart`) | The number line under the name; `BlockedPerson` carries only the name. |
| `loadFailed` | `bool` | have | `blockedProvider` error | |
| `busyId`, `error` | `String?` | have | `blockedActionsProvider` → `BlockedActionState` | |

### Actions
| Action | Signature | Tag | Calls today | Notes |
|---|---|---|---|---|
| `unblock` | `Future<void> Function(String accountId)` | have | `BlockedActions.unblock` | Confirmation and "Unblocked" toast kept inside. |
| `retry` | `void Function()` | have | `ref.invalidate(blockedProvider)` | |

### Kept inside the screen
The unblock dialog.

### Interactions
| INTERACTIONS.md item | Maps to |
|---|---|
| Unblock (asks first) | dialog kept inside, then `unblock` |

### Slots
| Slot | What the app puts there | What the preview shows |
|---|---|---|
| none | | |

### The app does this, the prototype does not show it
| What | Where in the app | Suggestion |
|---|---|---|
| Loading; "The blocked list could not be loaded." with retry | `blocked_page.dart` | Keep. |
| A spinner on the row being unblocked; a failure notice | `blocked_page.dart` | Keep. |

## Help and about (`about`)

Dart: `AboutScreen`, `AboutModel`, `AboutActions`.

### Model
| Field | Type | Tag | Comes from today | Notes |
|---|---|---|---|---|
| `appName`, `version` | `String` | have | `aboutAppProvider` | "Orbit", "Version 2.0.0". No build number exists: "(412)" has no source. |
| `server` | `ServerDetails?` | have | `serverDetailsProvider` (`about_providers.dart`) | `name`, `host`, `termsVersion`, `privacyVersion`. Null while checking or failed. |
| `serverFailed` | `bool` | have | `serverDetailsProvider` error | |
| `crashReports` | `bool` | have | `crashReportsOptInProvider` | |
| `crashReportsAllowed` | `bool?` | have | `ServerDetails.allowsCrashReports` | Null while checking; false: no switch. |
| `termsVersion`, `privacyVersion` (offline) | `String` | have | `legalProvider` → `LegalText` | The tiles' "Version 3" when the server cannot be reached. |

### Actions
| Action | Signature | Tag | Calls today | Notes |
|---|---|---|---|---|
| `openDocument` | `void Function(LegalDoc)` | derive | `context.push(RoutePaths.legal)` | `LegalPage` has no initial-document parameter today; add one (`?doc=privacy`). |
| `openServerDetails` | `void Function()` | have | `context.push(RoutePaths.advanced)` | |
| `openLicences` | `void Function()` | have | `showLicensePage` | |
| `setCrashReports` | `Future<void> Function(bool)` | have | `SettingsActions.setCrashReportsOptIn` | |

### Kept inside the screen
Nothing.

### Interactions
| INTERACTIONS.md item | Maps to |
|---|---|
| Terms of Service / Privacy Policy tile | `openDocument` |
| Server details | `openServerDetails` |
| Open-source licences | `openLicences` |
| Send crash reports | `setCrashReports` |

### Slots
| Slot | What the app puts there | What the preview shows |
|---|---|---|
| none | The licence page is Flutter's own. | |

### The app does this, the prototype does not show it
| What | Where in the app | Suggestion |
|---|---|---|
| The crash switch appears only when the server accepts reports: "This server does not accept crash reports", "Checking what the server accepts..." | `about_page.dart` | Keep (the design always shows a switch). |
| Server row "Checking..." / "Could not be reached" | `about_page.dart` | Keep in the hero pill. |

## Terms and Privacy Policy (`legal`)

Dart: `LegalScreen`, `LegalModel`, `LegalActions`.

### Model
| Field | Type | Tag | Comes from today | Notes |
|---|---|---|---|---|
| `legal` | `LegalText?` | have | `legalProvider` (`about_providers.dart`) | Titles, versions, bodies; from the server, else the copy shipped with the app. |
| `fromServer` | `bool` | have | `LegalText.fromServer` | False adds "(copy shipped with the app)". |
| `loading`, `failed` | `bool` | have | `legalProvider` | |
| `initialDoc` | `LegalDoc` | derive | route parameter (see About) | |

### Actions
| Action | Signature | Tag | Calls today | Notes |
|---|---|---|---|---|
| `retry` | `void Function()` | have | `ref.invalidate(legalProvider)` | |

### Kept inside the screen
Which document is shown.

### Interactions
| INTERACTIONS.md item | Maps to |
|---|---|
| Terms / Privacy | kept inside |

### Slots
| Slot | What the app puts there | What the preview shows |
|---|---|---|
| none | | |

### The app does this, the prototype does not show it
| What | Where in the app | Suggestion |
|---|---|---|
| Loading; "The documents could not be loaded." with retry; "(copy shipped with the app)" | `legal_page.dart` | Keep. |

## Advanced (`advanced`)

Dart: `AdvancedScreen`, `AdvancedModel`, `AdvancedActions`.

### Model
| Field | Type | Tag | Comes from today | Notes |
|---|---|---|---|---|
| `server` | `ServerDetails?` | have | `serverDetailsProvider` | Hero: name, host; pills: version, "New accounts can join" (`openRegistration`). |
| `reachable` | `bool` | derive | `!serverDetailsProvider.hasError` | "Connected" / "Cannot reach it". It means the server answered, not that the live socket is up. |
| `facts` | `List<(String, String)>` | have | `serverFactsProvider` | The design lists Largest attachment, Terms version, Privacy policy version; it drops Federation (off today). |
| `flags` | `List<(String, bool)>` | have | `serverFlagsProvider` | |
| `syncing` | `bool` | have | `syncNowProvider` → `SyncState.busy` | |
| `syncDone` | `bool` | have | `SyncState.notice` ("Up to date.") | The "Up to date" tag. |
| `syncError` | `String?` | have | `SyncState.error` | |

### Actions
| Action | Signature | Tag | Calls today | Notes |
|---|---|---|---|---|
| `checkNow` | `Future<void> Function()` | have | `SyncNow.run` → `SettingsGateway.syncNow` | |
| `retry` | `void Function()` | have | `ref.invalidate(serverDetailsProvider)` | |

### Kept inside the screen
Nothing.

### Interactions
| INTERACTIONS.md item | Maps to |
|---|---|
| Check for messages now | `checkNow` |
| Try again (cannot reach the server) | `retry` |

### Slots
| Slot | What the app puts there | What the preview shows |
|---|---|---|
| none | | |

### The app does this, the prototype does not show it
| What | Where in the app | Suggestion |
|---|---|---|
| A failed "Check for messages now" shows a sentence | `advanced_page.dart` | Keep. |
| Federation domain fact when set | `serverFactsProvider` | Drop while federation is off. |

## Copy that differs in meaning

| Where | Prototype | Today's app | Note |
|---|---|---|---|
| Edit profile, "Who sees what" | "Name, about and photo · People you have messaged · Encrypted" | Footer: "Your name and about line are encrypted. Only people you have messaged can read them; Helix servers cannot." | **Both wrong since ADR-030:** the name is also sent in the clear to the operator (`PUT /v1/profile/name`). About stays encrypted; the photo is not shared at all today. |
| Edit profile, "Who sees what" | "Phone number · Never shown. Only people who already have it can find you · Hidden" | "Helix never shows your number to people…" | Since ADR-030 the operator can read the full number (sealed under `HELIX_PHONE_KEY`). "Hidden" from people is true; "never shown" is not. "Can find you" only while "Find me by phone number" is on. |
| Edit profile, "Who sees what" | "~Orbit name · Anyone can look it up to message you · Public" | "stored on the server, not encrypted" | Lookup honours "Find me by ~name"; say "when Find me by ~name is on". |
| Legal (sample text) | "What it never sees: … your profile name" | Server text, or the bundled policy (version 2026-09-25, `packages/helix_remote_domain/lib/domain/legal_documents.dart`) | The prototype's sample contradicts ADR-030. The bundled policy also predates it ("identifies accounts by a salted phone-number hash rather than storing the full number"). Owner to update the policy; not a UI change. |
| Blocked | "Orbit tells them they are blocked" | (no pill) | Matches ADR-030. ADR-030 also tells them when they are **unblocked**; the unblock dialog could say so. |
| Account, Sign-in footer | "Your password never leaves this phone. Orbit only receives a key made from it." | Adds: "If you forget it, you can still sign in with a code sent to your number, which moves your account to the new phone and signs your other devices out." | The design drops what happens when the password is forgotten. |
| Privacy, Messages footer | "Turning receipts or typing off also hides other people's from you." | Adds: "Read receipts in groups and your own devices are not affected." | The design drops the exception. |
| Privacy, Being found | (no footer) | "Without these, people can still message you if they have your number or ~name from somewhere else." | Dropped meaning; keep it. |
| Privacy, App lock | "Calls still ring while Orbit is locked." | "…asks when you open Helix, and when you come back after the time you choose… It keeps the screen private; it does not add another key to your messages." | The design drops "it is not encryption". |
| Notifications, Allow notifications | Opens the phone's notification settings | Shows the system prompt | See `allowNotifications`. |
| Storage, footnote | "Tap a chat to free space without deleting its messages." | "To free space, delete messages or a whole chat." | Depends on the new engine work. |
| Storage, free-up sheet | "Removed files can be downloaded again while the sender's copy is on the server." | (none) | True for 30 days (media `MODULE.md`); say so. |
| Account, Delete dialog | "Export first" exports only | "Export first" exports, then opens the delete page | Pick one. |
| Account, export file | `orbit-account.json` | `helix-account-export-<date>.json` | Part of the rename decision. |
| You, devices check | "2 devices, both signed in by you" | (none) | The app cannot know "by you". |

## Open questions for the product owner

1. **Share your code:** build the `/u/<~name>` link (server page, app links, scan to chat), hide the QR button, or drop it? It works only for accounts with a `~name` and "Find me by ~name" on. An account-id link (the parsed but unused `helix://contact/add`) would work without a `~name`.
2. **`~name` "is available" as you type:** add a server check (it lets anyone probe taken names, which the server avoids on purpose), or show "Looks good" from the rules and the server's answer on Save?
3. **Profile photo for contacts:** build it (engine, M), or keep it on the phone and say so in "Who sees what"?
4. **"Who sees what" and the privacy policy after ADR-030:** approve new wording (the name and the number are visible to the operator).
5. **Checkup rules:** when are backup and devices "not ok", and what are their text and fix? Is the password check a fix target when not set?
6. **Privacy preview:** "What Nadia sees": a fixed sample name, or your most recent contact?
7. **Theme packs:** where are packs hosted and who holds the signing key? If the current pack is deleted, fall back to Orbit? Should the theme show before sign-in and survive sign-out (settings live in the account's database, which sign-out wipes)?
8. **Ringtone:** keep "Phone's ringtone" (today's behaviour) as a choice next to the bundled default? On Android: a channel per ringtone, or the app plays the sound?
9. **Biggest chats and freeing a chat's media:** build (engine, S + M) or hide?
10. **About:** drop the build number "(412)", or add one to `AppInfo`?

## Decisions and Phase 1b (2026-10-18)

Review 1 approved every recommendation in `../GAPS.md`. For this contract:

- Share your code is built (S1): `/u/<~name>`, app links and scan-to-chat.
- The ~name rules are checked as you type; whether it is free is the server’s answer on Save (S2 not built).
- Sharing your profile photo with people you message is built (E1).
- “Who sees what” follows ADR-030 (W1); the privacy policy text is yours to update (W2).
- Checkup rules: backup when none in 7 days; devices when one is unused for 30 days; password when none is set; recovery when none is made; app lock when off.
- The privacy preview shows your most recent chat’s name, or “Someone”.
- The theme is a device setting, so it survives sign-out; packs come with Part C.
- Ringtone: Orbit (default) or the phone’s own ringtone; downloads come with Part C.
- Biggest chats and freeing a chat’s media are built (E2, E3).
- About shows the version and the build number.

**How the “keep” rows are drawn.** Every row above marked keep (today’s
behaviour, in the new style) uses the state kit (`frame.md`, the `state-kit`
screen):
- a list that is loading: `Kit.skeleton`;
- a page that is opening: `Kit.loading`;
- “could not be loaded”: `Kit.loadFailed`, with Try again;
- a permission: `Kit.permission`;
- a field refusal or lockout: the field’s error and `Kit.fieldLock`;
- any other refusal: an error toast;
- a sentence on the page: `Kit.notice`.

Rows marked drop are not built.

New prototype states drawn in Phase 1b (keys in `screens.json`):

- `privacy-number-needed`: Privacy · your number is needed (linked device)
- `password-linked`: Change password · linked device (number needed)
- `password-wrong`: Change password · wrong current password, locked out
- `delete-account-linked`: Delete my account · linked device (number needed)
- `about-no-crash`: Help and about · server takes no crash reports
