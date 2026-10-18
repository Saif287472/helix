# Contract: devices and backup

Prototype screens: `devices` (states: `devices`), `approve-device` (states: `approve-device`, `approve-device-error`, `approve-device-review`, `approve-device-done`), `activity` (states: `activity`), `backup` (states: `backup`, `backup-running`, `backup-failed`), `restore-history` (states: `restore-history`), `transfer` (states: `transfer`, `transfer-empty`), `recovery` (states: `recovery`, `recovery-restore`)
Today's app: `features/devices/presentation/devices_page.dart`, `approve_device_page.dart`, `security_activity_page.dart`; `features/devices/application/devices_providers.dart`, `devices_gateway.dart`, `devices_models.dart`; `features/backup/presentation/backup_page.dart`, `restore_history_page.dart`, `transfer_page.dart`, `transfer_tile.dart`, `recovery_backup_page.dart`; `features/backup/application/backup_providers.dart`, `backup_gateway.dart`, `backup_models.dart`, `backup_copy.dart`; `core/engine/backup_policy.dart`

Paths are under `helix_remote/app/lib/` unless they start with `packages/` or
`server/` (under `helix_remote/`).

- **No shared view model fits.** `packages/helix_remote_ui/lib/src/view_models.dart`
  has nothing for devices, security events or history backup
  (`HelixTransferState` is a media download state, `HelixQrMatrix` is for the
  new device's QR code in `signin.md`). `security_views.dart` gives only
  `HelixQrScanFrame`, the frame around the scanner. The item types below are
  new and live in `orbit_ui`.
- **Name clash.** The app already has `DevicesActions` (the notifier in
  `devices_providers.dart`), `TransferView`, `TransferStage`,
  `RestoreStage` and `RecoveryStage`. The list screen is therefore
  `DeviceListScreen`, and the connector imports `orbit_ui` with a prefix for
  the enums.
- **Shared with `signin.md`.** The restore step after sign-in uses the same
  body as Restore history (`restoreFlowProvider`, the offers list and "I have
  a recovery secret"). "Welcome back", "Skip for now", "Continue" and
  `restoreStepProvider.finish()` are signin.md's. "Link this device" (the new
  device's side) is signin.md's; it shares `linkCheckNumber`,
  `linkProblemText` and the account key code with Link a new device.

## Shared item types

### `DeviceCardItem`
| Field | Type | Tag | Comes from today | Notes |
|---|---|---|---|---|
| `id` | `String` | have | `DeviceItem.id` (`devices_models.dart`) | |
| `name` | `String` | have | `DeviceRowView.title` (`devicesProvider`) | Falls back to the platform, then "Unnamed device". |
| `platformLabel` | `String?` | derive | `DeviceItem.platform` → "Android", "Windows"… (the switch in `_row`, `devices_providers.dart`) | Today it is joined into `DeviceRowView.subtitle`. Split it out. |
| `kind` | `DeviceKind` (`phone`, `desktop`, `other`) | have | `DeviceRowView.kind` (`DevicePlatformKind`) | Picks the icon. |
| `isThisDevice` | `bool` | have | `DeviceRowView.isThisDevice` | Highlighted card, no Remove or Lost. |
| `activeLabel` | `String` | derive | `formatAgo(DeviceItem.lastActiveAt ?? linkedAt, now)`, or "This device" | Today it is the second half of `DeviceRowView.subtitle`. The prototype tag drops "Active". |

### `SecurityEventRow`
| Field | Type | Tag | Comes from today | Notes |
|---|---|---|---|---|
| `kind` | `SecurityEventKind` (`signedIn`, `deviceAdded`, `deviceRemoved`, `passwordChanged`, `recoveryUsed`, `keyReset`, `other`) | derive | `SecurityEventItem.type` (`DevicesGateway.securityEvents()`) | Picks the icon. `SecurityEventView` drops the type today. |
| `title` | `String` | have | `SecurityEventView.title` (`securityEventsProvider`) | "Signed in", "A device was added", "A device was removed", "Password changed", "Recovery code used", "Your account key was reset", "Account activity". |
| `deviceName` | `String?` | have | `SecurityEventView.detail` (`SecurityEventItem.deviceName`) | |
| `when` | `String` | derive | `formatWhen(SecurityEventItem.at, now)` (`core/format/labels.dart`) | "Today, 08:02", "24 Sep, 14:05". Today the page uses `formatAgo` ("3 days ago"). |
| `needsCheck` | `bool` | have | `SecurityEventView.needsAttention` | True for a key reset and for a recovery code used. |
| `thisWeek` | `bool` | derive | `SecurityEventItem.at` within 7 days of now | Groups "This week" and "Earlier". |

### `TransferItem`
| Field | Type | Tag | Comes from today | Notes |
|---|---|---|---|---|
| `id` | `String` | have | `TransferView.id` | |
| `outgoing` | `bool` | have | `TransferView.direction == sending` | |
| `deviceName` | `String?` | have | `TransferView.deviceName` (`BackupGateway.watchOffers`, from the device list) | Null: "History from another device". |
| `stage` | `TransferStage` (`preparing`, `offered`, `waiting`, `downloading`, `importing`, `done`, `declined`, `cancelled`, `failed`) | have | `TransferView.stage` | The prototype's `ready` is `waiting` and its `receiving` is `downloading`. |
| `done` | `int` | derive | `TransferView.done`, merged with the receiving events of `BackupGateway.transferProgress` | `watchOffers` reports `done` only while importing (engine `BackupService.watchOffers`), so "Receiving (5 of 8)" shows 0 today. The engine's `transferProgress` has the count; `TransfersController` drops receiving events. |
| `total` | `int` | have | `TransferView.total` | 0 while sending is still preparing: see New backend work. |
| `problemText` | `String?` | have | `backupProblemText(TransferView.problem)` when `failed`, or `OfferActionsState.errorFor(id)` | |
| `busy` | `bool` | have | `OfferActionsState.busy.contains(id)` | An accept or decline is in flight. |
| `resumable` | `bool` | derive | `waiting` with `done > 0` or a problem, or `failed` (`TransferTile`) | Labels the button "Resume" or "Try again" instead of "Accept". |

## Devices (`devices`)

Dart: `DeviceListScreen`, `DeviceListModel`, `DeviceListActions`.

### Model
| Field | Type | Tag | Comes from today | Notes |
|---|---|---|---|---|
| `devices` | `List<DeviceCardItem>` | have | `devicesProvider` (`DevicesGateway.watch()` → engine `DeviceService.watch()`) | This device first. The hero counts them. |
| `loadState` | `LoadState` (`loading`, `ready`, `failed`) | have | `devicesProvider` `AsyncValue` | |
| `recentActivity` | `List<SecurityEventRow>` | derive | the first 2 of `securityEventsProvider` | New on this page. Empty while loading or on error. |
| `canSignOutOthers` | `bool` | derive | `devices` has a device that is not this one | The prototype hides the danger zone otherwise. |
| `busy` | `bool` | have | `devicesActionsProvider` → `DevicesActionState.busy` | |
| `error` | `String?` | have | `DevicesActionState.error` (`describeFailure`) | |
| `notice` | `String?` | have | `DevicesActionState.notice` | "Renamed.", "Device removed.", "Signed out 1 other device.", "There were no other devices." The prototype shows these as a toast. |

### Actions
| Action | Signature | Tag | Calls today | Notes |
|---|---|---|---|---|
| `rename` | `Future<void> Function(String id, String name)` | have | `DevicesActions.rename` → `DevicesGateway.rename` → engine `DeviceService.rename` | Interaction "Device card → Rename". An empty name is ignored; the dialog caps it at 60. |
| `remove` | `Future<void> Function(String id)` | have | `DevicesActions.revoke(id)` | "Remove this device (asks)". Not offered for this device. |
| `reportLost` | `Future<void> Function(String id)` | have | `DevicesActions.revoke(id, lost: true)` → `DELETE` device with `reason=lost` | "Lost or stolen (asks)". The only difference from `remove`: the server stores revoke reason `lost` instead of `user` on the device row (`server/lib/src/modules/identity/application/accounts.dart`). Same security event, same signals. |
| `signOutOthers` | `Future<void> Function()` | have | `DevicesActions.revokeOthers()` | "Sign out all other devices: asks first". |
| `openLinkDevice` | `void Function()` | have | `context.push(RoutePaths.devicesLink)` | "Link a new device". |
| `openActivity` | `void Function()` | have | `context.push(RoutePaths.devicesActivity)` | "See all activity". |
| `refresh` | `Future<void> Function()` | have | `DevicesActions.refresh()` | Called when the page opens and on pull-to-refresh. Not in the prototype. |
| `retryLoad` | `void Function()` | have | `ref.invalidate(devicesProvider)` | |
| `clearMessage` | `void Function()` | have | `DevicesActions.clearMessages()` | After the toast goes. |

### Kept inside the screen
The device sheet (open/close), the rename dialog and its text, the three
confirmation dialogs (remove, lost or stolen, sign out all), the device
strip's scroll.

### Slots
None.

### The app does this, the prototype does not show it
| What | Where in the app | Suggestion |
|---|---|---|
| Loading bar while the list loads | `devices_page.dart` | Keep in the new style. |
| "The device list could not be loaded." with retry | `devices_page.dart` (`HelixErrorState`) | Keep in the new style. |
| "No devices to show yet." | `devices_page.dart` | Keep (rare: the list always has this device once loaded). |
| Busy bar while an action runs | `DevicesActionState.busy` | Keep: spinner on the confirming button. |
| Action failure with "Try again" | `DevicesActionState.error` | Keep as an error toast or notice. |
| Pull to refresh | `RefreshIndicator` | Keep. |

### Copy that differs in meaning
| Prototype | App | Note |
|---|---|---|
| "Each can read your new messages" | "These devices can read your messages. If you do not recognise one, remove it and change your password." | The prototype drops the advice. It is on the Security activity page instead. |
| Lost or stolen confirmation: "…will be signed out at once. Consider changing your password too." | "…will be signed out at once and Helix will note that it is no longer yours…" | The sheet row still says "note that it is no longer yours", so the meaning survives. |

### New backend work
None.

## Link a new device (`approve-device`)

Dart: `ApproveDeviceScreen`, `ApproveDeviceModel`, `ApproveDeviceActions`.

### Model
| Field | Type | Tag | Comes from today | Notes |
|---|---|---|---|---|
| `step` | `ApproveStep` (`enter`, `review`, `approving`, `done`) | have | `approveLinkProvider` → `ApproveLinkState.step` | The step pills (Scan, Check, Done) follow it. |
| `error` | `String?` | have | `ApproveLinkState.error` (`linkProblemText`, `describeFailure`) | "That is not a Helix link code…", "That code has expired…", and the app-only ones below. |
| `serverHost` | `String` | have | `ApproveLinkState.request.serverHost` (`LinkRequest`) | "A device on helix.agiletechbd.com wants to join". |
| `checkNumber` | `String` | have | `LinkRequest.check` (`linkCheckNumber`, `devices_gateway.dart`) | "482 913". |
| `accountKeyCode` | `String?` | have | `LinkRequest.accountKeyCode` (`Provisioning.keyCode` of this account's key) | Null when this device cannot read it: hide the box. |
| `canScan` | `bool` | have | `linkScannerProvider != null` | False on Windows: paste only. |
| `historySending` | `bool` | have | `ApproveLinkState.sendingHistory` | |
| `historySent` | `bool` | have | `ApproveLinkState.historySent` | Row turns to "Sent". |
| `historyError` | `String?` | have | `ApproveLinkState.historyError` | |

### Actions
| Action | Signature | Tag | Calls today | Notes |
|---|---|---|---|---|
| `submitCode` | `Future<void> Function(String code)` | have | `ApproveLinkController.submit` → `DevicesGateway.inspectLink` | "Continue", and the scanner's callback. Checks the code parses and names this server. Empty input is ignored. |
| `approve` | `Future<void> Function()` | have | `ApproveLinkController.approve` → `DeviceAuthenticator.confirm` (`core/security/device_auth.dart`), then `DevicesGateway.deviceIds` and `approveLink` | "Approve". The fingerprint, face or PIN prompt is the system's (`local_auth`, Windows Hello on Windows), not a dialog the screen draws. Skipped when the phone has no screen lock. |
| `cancel` | `void Function()` | have | `ApproveLinkController.reset()` and pop | "Cancel". Disabled while approving. |
| `sendHistory` | `Future<void> Function()` | have | `ApproveLinkController.sendHistory` → `DevicesGateway.sendHistoryToNewDevice` | "Send (history)". Sends only to the device that appeared since the approval. |
| `done` | `void Function()` | have | `context.pop()` | "Done". |

### Kept inside the screen
The link code field and its Paste button (the kit's "Paste in a field"), the
step pills (from `step`).

### Slots
| Slot | What the app puts there | What the preview shows |
|---|---|---|
| `scanner` | `linkScannerProvider` builder (camera preview), calling `submitCode`; nothing on Windows | The scan frame with corners and the moving beam |

### The app does this, the prototype does not show it
| What | Where in the app | Suggestion |
|---|---|---|
| "That code is for a different server than the one this phone is signed in to…" | `linkProblemText(otherServer)` | Keep in the new style. |
| "Approval needs your phone's own unlock…" when the unlock fails | `linkProblemText(notConfirmed)` | Keep. |
| Offline and "The server did not accept that" | `linkProblemText(offline / notAllowed)` | Keep. |
| An expired code is found only after Approve, and the error shows on the review step | `ApproveLinkController.approve` | Return to the scan step on `expired`, as the `approve-device-error` state draws it (a small change in the controller). |
| "The new device has not finished joining yet. Wait a moment and try again." with Send still available | `historyError` (`notLinkedYet`) | Keep. |
| A phone with no screen lock approves without a prompt | `ApproveLinkController.approve` | Keep; say it in the foot note. |
| Continue with an empty field does nothing | `submit` | Disable Continue until there is text. |

### Copy that differs in meaning
| Prototype | App | Note |
|---|---|---|
| "Check that the new device shows the same numbers." (check number and key code together, before approving) | "The same number should be showing on the new device… The new device will then ask whether the account is its owner's and show the key code above: compare them." | The new device shows only the check number before approval. The key code appears there after approval, in "Is this your account?". The prototype's sentence asks for a check that cannot be done yet. |
| "Its code lasts ten minutes" | (intro only) | Static text: the approving device does not know when the code was made. |

### New backend work
None.

## Security activity (`activity`)

Dart: `SecurityActivityScreen`, `SecurityActivityModel`, `SecurityActivityActions`.

### Model
| Field | Type | Tag | Comes from today | Notes |
|---|---|---|---|---|
| `events` | `List<SecurityEventRow>` | derive | `DevicesGateway.securityEvents()` → engine `DeviceService.securityEvents(limit: 50)` → `GET` security events, newest first | Filtered to the last 30 days. Grouped by `thisWeek`. |
| `loadState` | `LoadState` | have | `securityEventsProvider` `AsyncValue` | |
| `eventCount` | `int` | derive | `events.length` | "5 events in the last 30 days". At most 50: the engine reads one page. |
| `toCheckCount` | `int` | derive | `events` where `needsCheck` | "1 to check" pill. |
| `deviceCount` | `int` | derive | `devicesProvider` length | "2 devices now" pill. |

### Actions
| Action | Signature | Tag | Calls today | Notes |
|---|---|---|---|---|
| `openDevices` | `void Function()` | have | `context.push(RoutePaths.devices)` (pop when opened from Devices) | "Review your devices". |
| `openChangePassword` | `void Function()` | have | `context.push(RoutePaths.changePassword)` | "Change your password". Set or change is decided by that page (`you.md`). |
| `retryLoad` | `void Function()` | have | `ref.invalidate(securityEventsProvider)` | |

### Kept inside the screen
Nothing.

### Slots
None.

### The app does this, the prototype does not show it
| What | Where in the app | Suggestion |
|---|---|---|
| Empty: "Nothing to show. Sign-ins, new devices and key changes appear here." | `security_activity_page.dart` | Keep in the new style. |
| "The activity could not be loaded." with retry | `security_activity_page.dart` | Keep. |
| "Recovery code used" is flagged like a key reset | `SecurityEventView.needsAttention` | Keep: both mean the account moved. |
| "Account activity" for an event kind this version does not know | `SecurityEventType.other` | Keep. |

### Copy that differs in meaning
| Prototype | App | Note |
|---|---|---|
| "Orbit keeps 30 days of activity." | (no claim) | Not true today: the server keeps every event (`identity.security_events`, no purge job; `server/lib/src/modules/identity/data/admin_store.dart` `purgeExpired` skips it). Either say "Showing the last 30 days" or build the retention below. |

### New backend work
| Item | Why the design needs it | Engine / server / protocol | Size: S, M, L |
|---|---|---|---|
| Delete security events older than 30 days | The footnote "Orbit keeps 30 days of activity" | Server: a purge in `identity.purge_expired`; `RETENTION_AND_DELETION.md`, `METADATA_INVENTORY.md`. Not needed if the copy changes. | S |

## Backup (`backup`)

Dart: `BackupScreen`, `BackupModel`, `BackupActions`.

### Model
| Field | Type | Tag | Comes from today | Notes |
|---|---|---|---|---|
| `loadState` | `LoadState` | have | `backupPageViewProvider` `AsyncValue` (`backupSummaryProvider` → `BackupGateway.watchSummary` → engine `BackupService.watchStatus`) | |
| `status` | `BackupStatusKind` (`never`, `done`, `running`, `failed`) | derive | `BackupRunState.running`, `BackupPageView.problem`, `BackupRunState.error`, `BackupSummary.lastBackupAt` | Picks the ring. `never` is app-only. |
| `lastBackupLabel` | `String` | have | `BackupPageView.lastBackup` (`formatAgo`) | "5 hours ago", "Never". |
| `lastBackupDetail` | `String?` | have | `BackupPageView.lastBackupDetail` | "12,480 messages, 3.1 MB", plus ". The oldest messages did not fit." when truncated. |
| `runMessages` | `int` | have | `BackupRunState.messages` | Messages read so far. |
| `runFraction` | `double?` | engine | none: engine `BackupProgress` (`backup/models.dart`) has `messages` and `bytes`, no total | The prototype's "62%". Null: an indeterminate ring. |
| `failureText` | `String?` | have | `BackupPageView.problem` (last automatic attempt) or `BackupRunState.error` (Back up now) | Via `backupProblemText`. |
| `waitingForWifi` | `bool` | engine | none: `PolicyBackupRemote` (`core/engine/backup_policy.dart`) throws `BackupFailure.notAllowed`, the same value as signed out or suspended | Needed to say "You were on mobile data and backups wait for Wi-Fi" as a fact. |
| `finishedText` | `String?` | have | `BackupRunState.finished` / `skipped` | "Your history is backed up." / "There is no history to back up yet." The prototype says "Backed up just now". |
| `autoBackup` | `bool` | have | `BackupPageView.autoBackup` | |
| `useMobileData` | `bool` | have | `backupOverMobileProvider` (`settingProvider(AppSettings.backupOverMobile)`) | |
| `offersWaiting` | `int` | derive | `incomingOffersProvider`, not finished | "1 waiting" on the Send tile. `BackupPage` counts it today. |
| `recoveryMade` | `bool` | engine | today `BackupSummary.lastRecoveryBackupAt != null`, which is this device's own record (engine `FullBackupState` in local settings) | A recovery backup made on another device shows "No recovery backup yet". |
| `recoveryMadeLabel` | `String?` | derive | `BackupSummary.lastRecoveryBackupAt` → "Today", "3 days ago" | `BackupPageView.recoveryBackup` gives "Not made" or `formatAgo`. |

### Actions
| Action | Signature | Tag | Calls today | Notes |
|---|---|---|---|---|
| `backUpNow` | `Future<void> Function()` | have | `BackupRunController.backUpNow` → engine `BackupService.backUpNow` | "Back up now / Try again". |
| `setAutoBackup` | `Future<void> Function(bool on)` | have | `BackupSettingsActions.setAutoBackup` → engine `BackupService.setAutoBackup` | "Back up every day". |
| `setUseMobileData` | `Future<void> Function(bool on)` | have | `BackupSettingsActions.setOverMobile` (local setting) | "Use mobile data". |
| `openRestore` | `void Function()` | have | `context.push(RoutePaths.backupRestore)` | "Restore" tile. |
| `openTransfer` | `void Function()` | have | `context.push(RoutePaths.backupTransfer)` | "Send to a device" tile. |
| `openRecovery` | `void Function()` | have | `context.push(RoutePaths.backupRecovery)` | "Create (recovery backup)". |
| `deleteServerBackup` | `Future<void> Function()` | have | `BackupRunController.deleteServerBackup` → engine `BackupService.deleteHistoryBackup` | "Delete my server backup: asks first". Deletes the history backup only; the recovery backup stays. |
| `retryLoad` | `void Function()` | have | `ref.invalidate(backupSummaryProvider)` | |
| `clearMessage` | `void Function()` | have | `BackupRunController.clearError()` | |

### Kept inside the screen
The delete confirmation dialog.

### Slots
None.

### The app does this, the prototype does not show it
| What | Where in the app | Suggestion |
|---|---|---|
| Never backed up ("Last backup: Never"), also right after deleting the server backup | `BackupPageView.lastBackup`; engine resets its state on delete | Add a fourth ring state to the design ("Not backed up yet"). |
| "There is no history to back up yet." | `BackupRunState.skipped` | Keep. |
| "The oldest messages did not fit." | `lastBackupDetail` (truncated) | Keep on the status line. |
| Two failure sources: the last automatic attempt and the Back up now run | `BackupPageView.problem`, `BackupRunState.error` | Keep both in the failed ring's line. |
| Every other failure: offline, conflict, too large, damaged, newer format… | `backupProblemText` (`backup_copy.dart`) | Keep: the failed ring's second line is the sentence. |
| Loading, and "The backup settings could not be loaded." with retry | `backup_page.dart` | Keep in the new style. |
| No message after deleting the server backup | `BackupRunController.deleteServerBackup` | Add the prototype's "Server backup deleted" toast (derive). |
| An automatic backup running in the background is not shown | `backupRunProvider` follows only its own run | Listen to `BackupGateway.backupProgress` for any run (derive), so `backup-running` also shows then. |
| Back up now shows busy while deleting | `deleteServerBackup` sets `running` | Show busy on the dialog's button instead. |

### Copy that differs in meaning
| Prototype | App | Note |
|---|---|---|
| Failed: "You were on mobile data and backups wait for Wi-Fi" | "The backup did not run. If you are on mobile data, turn on backup over mobile data or connect to Wi-Fi." | The app hedges because it cannot tell the cause (see `waitingForWifi`). |
| Delete: "A new one is made on the next run if daily backup is on." | "A new phone will not be able to restore from it until you back up again." | Both are true. The prototype loses the warning about restoring on a new phone. |

### New backend work
| Item | Why the design needs it | Engine / server / protocol | Size: S, M, L |
|---|---|---|---|
| A total for a running backup | The percentage in the running ring | Engine: count the messages to export first and report `total` on `BackupProgress` | S |
| A distinct "waiting for Wi-Fi" failure | The failed state's reason | Engine: a new `BackupFailure` value, thrown by `PolicyBackupRemote` | S |
| Whether the account has a recovery backup, and when it was made | "Recovery backup made" on every device, the You checkup, and not making a second one by mistake (a new one replaces the old, so the saved secret stops working) | Engine: read `GET /v1/backups/full` (`updatedAt`) instead of the local record; no server change | S |

## Restore history (`restore-history`)

Dart: `RestoreHistoryScreen`, `RestoreHistoryModel`, `RestoreHistoryActions`.
The same body is the restore step in `signin.md`.

### Model
| Field | Type | Tag | Comes from today | Notes |
|---|---|---|---|---|
| `stage` | `RestoreStageKind` (`idle`, `running`, `failed`, `done`) | have | `restoreFlowProvider` → `RestoreFlowState.stage` | |
| `phaseText` | `String?` | have | `RestoreFlowState.phase` | "Looking for your backup...", "Downloading your backup...", "Unlocking it...", "Adding messages...". |
| `fraction` | `double` | derive | the phase's place in that order, as the prototype computes it | The engine's `RestoreProgress` has no total, so this moves in four steps. |
| `added` | `int` | have | `RestoreFlowState.added` | "1,204 messages added so far", "Restored 2,318 messages". |
| `failureTitle` | `String?` | derive | `RestoreFlowState.problem` → a short title per `BackupProblem` | The prototype has only "No backup was found". |
| `failureText` | `String?` | have | `RestoreFlowState.error` (`backupProblemText`) | |
| `nothingNew` | `bool` | derive | `stage == done && added == 0` | "Your backup is already on this phone. Nothing new to add." |
| `offers` | `List<TransferItem>` | have | `incomingOffersProvider` (not finished) + `offerActionsProvider` | The app shows them here too; the prototype only on the after-sign-in step. |

### Actions
| Action | Signature | Tag | Calls today | Notes |
|---|---|---|---|---|
| `restore` | `Future<void> Function()` | have | `RestoreFlowController.restore` → engine `BackupService.restoreHistory` | "Restore from my backup", and "Try again". |
| `openRecoveryRestore` | `void Function()` | derive | `context.push(RoutePaths.backupRecovery)` | "I have a recovery secret". It must open on the Restore tab: add a tab parameter to the route (`RecoveryBackupPage` always opens on Create). |
| `done` | `void Function()` | have | `context.pop()` | "Done". |
| `acceptOffer` | `Future<void> Function(String id)` | have | `OfferActionsController.accept` | Same as on Send to my other devices. |
| `declineOffer` | `Future<void> Function(String id)` | have | `OfferActionsController.decline` | |
| `pauseOffer` | `void Function(String id)` | have | `OfferActionsController.pause` | |

### Kept inside the screen
Nothing.

### Slots
None.

### The app does this, the prototype does not show it
| What | Where in the app | Suggestion |
|---|---|---|
| Wrong key, damaged, newer format, rolled back, offline | `backupProblemText` | Keep: the failed ring's second line. |
| Already restored: "Nothing new to add." | `restore_history_page.dart` | Keep as a done variant. |
| Offers from other devices on the Settings path | `restore_history_page.dart` | Keep: the design already has the block for the sign-in step. |
| "I have a recovery secret" is disabled while restoring | `restore_history_page.dart` | Keep. |

### New backend work
None.

## Send to my other devices (`transfer`)

Dart: `TransferScreen`, `TransferModel`, `TransferActions`.

### Model
| Field | Type | Tag | Comes from today | Notes |
|---|---|---|---|---|
| `starting` | `bool` | have | `transfersProvider` → `TransfersState.starting` | Spinner on "Send my history". |
| `sendError` | `String?` | have | `TransfersState.error` | "This is your only device. Sign in on another device first." and others. |
| `outgoing` | `List<TransferItem>` | have | `TransfersState.outgoing` (from `BackupGateway.transferProgress`) | Kept in memory for the app run only. |
| `incoming` | `List<TransferItem>` | have | `incomingOffersProvider` (`BackupGateway.watchOffers`) + `offerActionsProvider` | |
| `incomingState` | `LoadState` | have | `incomingOffersProvider` `AsyncValue` | |
| `waitingCount` | `int` | derive | `incoming` with stage `waiting` | "1 waiting here" pill. |
| `fraction` (per item) | `double?` | engine | `TransferView.fraction`: null while sending prepares, because the engine does not know the total (`device_transfer.dart` `send`) | "Getting your history ready (3 of 8)" and its bar. Receiving has it (see `TransferItem.done`). |

### Actions
| Action | Signature | Tag | Calls today | Notes |
|---|---|---|---|---|
| `sendHistory` | `Future<void> Function()` | have | `TransfersController.send` → engine `BackupService.sendHistory` | "Send my history". |
| `cancelSend` | `Future<void> Function(String id)` | have | `TransfersController.cancel` → `BackupService.cancelSend` | "Cancel (sending)". |
| `accept` | `Future<void> Function(String id)` | have | `OfferActionsController.accept` → `BackupService.acceptOffer` | "Accept", also "Resume" and "Try again". |
| `decline` | `Future<void> Function(String id)` | have | `OfferActionsController.decline` → `BackupService.declineOffer` | "Decline: removes it". Today the row stays as "Declined" for a day; hide declined rows (derive). |
| `pause` | `void Function(String id)` | have | `OfferActionsController.pause` → `BackupService.pauseTransfer` | "Pause". The row returns to waiting with Resume. |
| `dismissSent` | `void Function(String id)` | have | `TransfersController.dismiss` | "Dismiss" on a finished sending row. |
| `dismissReceived` | `Future<void> Function(String id)` | engine | none: the engine keeps finished offers (`cleanUp` drops them after 1 day, failed after 2) and has no call to remove one | "Dismiss" on a finished incoming row. `TransferPage` passes no `onDismiss` for offers today. |

### Kept inside the screen
Nothing.

### Slots
None.

### The app does this, the prototype does not show it
| What | Where in the app | Suggestion |
|---|---|---|
| "Adding messages (x of y)" after receiving | `TransferTile._status` (`importing`) | Keep. |
| "Declined", "Cancelled", "Stopped" with the reason | `TransferTile` | Keep. |
| Resume and Try again on a paused or failed offer | `TransferTile` | Keep. |
| "Transfers could not be loaded." | `transfer_page.dart` | Keep. |
| A send failure ("This is your only device…") | `TransfersState.error` | Keep under the button. |
| Accept and Decline disabled while one runs | `OfferActionsState.busy` | Keep. |
| The sender's row stays "Waiting for your other device to accept" after the other device answers | the engine records answers but sends no progress | Keep; it goes when the app restarts or on Cancel. |

### Copy that differs in meaning
| Prototype | App | Note |
|---|---|---|
| "The other device has to accept before anything is sent." | "…encrypted on this phone before it leaves… the other device has to accept it." / "Nothing is downloaded until you accept." | The history is encrypted and uploaded to the server's relay before the other device accepts. Say "before anything is downloaded". |
| Pause shows a "Paused" toast | the row returns to waiting with Resume | Style only, if the row changes too. |

### New backend work
| Item | Why the design needs it | Engine / server / protocol | Size: S, M, L |
|---|---|---|---|
| A total while sending prepares | "Getting your history ready (3 of 8)" and its bar | Engine: estimate the segment count before export. Or drop the count and show an indeterminate bar. | S |
| Remove a finished incoming offer | "Dismiss" on a received transfer | Engine: `BackupService.dismissOffer` over the ledger's `removeIncoming`. A local hidden list is the cheaper option. | S |

## Recovery backup (`recovery`)

Dart: `RecoveryScreen`, `RecoveryModel`, `RecoveryActions`.

### Model
| Field | Type | Tag | Comes from today | Notes |
|---|---|---|---|---|
| `initialTab` | `RecoveryTab` (`create`, `restore`) | derive | a route parameter | Restore history opens it on Restore. |
| `made` | `bool` | engine | today `BackupSummary.lastRecoveryBackupAt`, this device's record only | See Backup, New backend work. |
| `madeLabel` | `String?` | derive | `BackupSummary.lastRecoveryBackupAt` | "Made today". |
| `secret` | `String` | have | `recoveryBackupProvider` → `RecoveryBackupState.secret` (engine `BackupService.generateRecoverySecret`) | Empty while it is made. Dropped from memory once the backup exists. |
| `handoffNote` | `String?` | have | `RecoveryBackupState.handoffNote` | "Copied. Put it somewhere safe now: it leaves the clipboard in a minute." / "Shared…". |
| `saved` | `bool` | have | `RecoveryBackupState.written` | |
| `stage` | `RecoveryStageKind` (`choose`, `creating`, `created`, `restoring`, `restored`) | have | `RecoveryBackupState.stage` | |
| `createdNothing` | `bool` | have | `RecoveryBackupState.created.skipped` | "There was no history to back up yet." |
| `restoredCount` | `int?` | have | `RecoveryBackupState.restored.added` | "Restored 2,318 messages." |
| `error` | `String?` | have | `RecoveryBackupState.error` (`backupProblemText`) | |
| `step` | `int` (0 to 3) | derive | `handoffNote != null` → 1, `saved` → 2, `created` → 3 | The pills Save the secret, Confirm, Create. |

### Actions
| Action | Signature | Tag | Calls today | Notes |
|---|---|---|---|---|
| `copySecret` | `Future<void> Function()` | have | `RecoveryBackupController.copy` → `secretHandoffProvider.copy` | "Copy". The clipboard is cleared after a minute. |
| `shareSecret` | `Future<void> Function()` | have | `RecoveryBackupController.share` → `secretHandoffProvider.share` | "Share". |
| `setSaved` | `void Function(bool saved)` | have | `RecoveryBackupController.setWritten` | "I saved it somewhere safe". |
| `create` | `Future<void> Function()` | have | `RecoveryBackupController.create` → engine `BackupService.createFullBackup` | "Create recovery backup". The You checkup reads `made` (`you.md`). |
| `restore` | `Future<void> Function(String secret)` | have | `RecoveryBackupController.restore` → `BackupService.restoreFullBackup` | "Restore from recovery backup". |

### Kept inside the screen
The Create / Restore tab, the recovery secret field, and the empty-field
check ("Type your recovery secret first.").

### Slots
None.

### The app does this, the prototype does not show it
| What | Where in the app | Suggestion |
|---|---|---|
| A spinner while the secret is made, and an error if it cannot be | `recovery_backup_page.dart` | Keep. |
| "It could not be shared from this device." | `RecoveryBackupController.share` | Keep. |
| "There was no history to back up yet." | `created.skipped` | Keep. |
| "The backup is already on this phone." (nothing added) | `restored.added == 0` | Keep. |
| Wrong secret, another account's backup, no backup, offline | `backupProblemText` | Keep in the error notice. |
| Tabs and Copy/Share are disabled while working; Create stays off until the secret is ready | `recovery_backup_page.dart` | Keep. |
| Restore is disabled with an empty field | `recovery_backup_page.dart` | The prototype keeps it on and shows a toast. Either is fine. |
| Delete the recovery backup exists but has no button | `RecoveryBackupController.deleteBackup` | Decide: add it to the danger zone, or drop it. |
| Making a new one replaces the old: the saved secret stops working | engine `createFullBackup` (one per account) | Warn when `made` is true. |

### New backend work
None beyond `made` (under Backup).
