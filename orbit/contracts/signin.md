# Contract: sign-in and app entry

Prototype screens: `signin` (states: `signin`, `signin-phone-error`, `signin-offline`, `signin-code`, `signin-code-error`, `signin-password`, `signin-password-error`, `signin-name`, `signin-name-terms`, `signin-takeover`, `signin-advanced`, `signin-advanced-rec`, `signin-advanced-error`, `signin-server`, `signin-join`, `signin-legal`), `restore` (states: `restore`, `restore-running`, `restore-failed`, `restore-done`), `link-device` (states: `link-device`, `link-device-expired`, `link-device-confirm`), `reset` (states: `reset-window`, `reset-key`, `reset-decrypt`), `lock` (states: `lock`)
Today's app: `features/sign_in/presentation/…`, `features/sign_in/application/…`, `features/backup/presentation/restore_history_page.dart`, `features/backup/presentation/transfer_tile.dart`, `features/backup/application/restore_step.dart`, `features/backup/application/backup_providers.dart`, `features/devices/presentation/link_this_device_page.dart`, `features/devices/application/…`, `shared/widgets/reset_screen.dart`, `shared/widgets/startup_screen.dart`, `shared/widgets/app_link_listener.dart`, `core/security/app_lock.dart`, `core/links/…`, `core/router/app_router.dart`

Paths are under `helix_remote/app/lib/`, except those starting with
`packages/` (under `helix_remote/`).

How these screens are reached today (`_redirectFor` in
`core/router/app_router.dart`). No screen here decides it:

| Situation | Where the router sends you |
|---|---|
| Signed out or revoked | `/sign-in` (`AppRoutes.signIn`); `/link-device` (`RoutePaths.linkThisDevice`) is the one other page allowed |
| Signed in while `postSignInProvider` is `offerRestore` (`core/engine/post_sign_in.dart`) | `/restore` (`RoutePaths.restoreAfterSignIn`), once |
| Signed in | `/home`; `/sign-in`, `/restore` and `/link-device` redirect there |
| `authStateProvider` has an error (`core/engine/session_providers.dart`) | `/reset` (`AppRoutes.reset`) |
| App lock | Not a route: `AppLockGate` (`core/security/app_lock.dart`, mounted in `main.dart`) stacks the lock over the navigator |

`core/security/device_auth.dart` (`deviceAuthenticatorProvider`) is not used
by these screens. It guards approving a new device and turning the lock on
(`devices_backup.md`, `you.md`).

## Sign in (`signin`)

Dart: `SignInScreen`, `SignInModel`, `SignInActions`.

One screen with eight steps, `SignInStep`: `phone` (Helix Global),
`serverPhone` (`signin-join`), `smsCode`, `password`, `newAccount` (the name
step), `takeOver`, `serverCode` (`signin-advanced*`), `serverConfirm`
(`signin-server`). The controller is `signInControllerProvider` →
`SignInController` (`features/sign_in/application/sign_in_controller.dart`),
its state `SignInState` (`sign_in_state.dart`).

### Model
| Field | Type | Tag | Comes from today | Notes |
|---|---|---|---|---|
| step | `SignInStep` | derive | `SignInState.page`, `.mode`, `.pendingServerHost`, `.isNewAccount`, mapped as `sign_in_screen.dart` does (`_CodePage`, `_PhonePage`, `_OtpPage`, `_PasswordPage`, `_NamePage`) | `serverConfirm` = page `code` with `pendingServerHost` set; `takeOver` = page `name` with `accountExists` |
| countryCode | `String` | have | `SignInState.countryCode` (`'+880'`, fixed; no setter) | The field's prefix |
| detectedCountry | `String?` | derive | Input `SignInState.digits`. Nothing detects a country today: no country picker, no dialling-code table, no phone-number package (looked in `app/lib`, the engine and `app/pubspec.yaml`) | Interaction "Phone number: shows which country it detected". The field only accepts digits, spaces and hyphens. Open question |
| phoneDigits | `String` | have | `SignInState.digits` | Initial text of the field. Today's `PhoneField` ignores it, so the field is empty after Back |
| phoneLabel | `String` | have | `SignInState.phoneLabel` (`+880 1711 000001`) | Subtitle of `smsCode` and `password` |
| smsCode | `String` | have | `SignInState.otpCode` | Cleared by a resend |
| displayName | `String` | have | `SignInState.displayName` | Max 80 |
| setupCode | `String` | have | `SignInState.codeString` | |
| setupCodeKind | `SetupCodeKind` (`none`, `invite`, `recovery`) | derive | `isHelixInviteCode` / `isHelixRecoveryCode` on `SignInState.codeString` (`core/links/helix_code.dart`) | The line under the field. The prototype detects while typing; today `SignInState.codeType` is set only after a successful check |
| isRecovery | `bool` | have | `SignInState.isRecovery` | "Recover your account" or "Join the server" |
| serverBadge | `String?` | derive | `SignInState.pendingServerHost ?? serverHost`, then `serverName`, as `_ServerBadge` builds it | `chat.rahman.family (Rahman Family)`; null on Helix Global |
| pendingServerHost | `String?` | have | `SignInState.pendingServerHost` | The host in "This code wants to sign you in on …" |
| showTerms | `bool` | derive | `SignInState.isNewAccount && requiresTerms` (`_NamePage`) | Helix Global only. See the take-over row below |
| termsAccepted | `bool` | have | `SignInState.tosAccepted` | |
| busy | `bool` | have | `SignInState.isLoading` | Spinner in the primary button |
| error | `String?` | have | `SignInState.errorMessage` (always a `SignInCopy` sentence, never exception text) | The line under the fields |
| canGoBack | `bool` | derive | `SignInState.page` and `.mode`: every step but the Global `phone` step (`SignInFrame.onBack`) | |
| showAdvancedCorner | `bool` | derive | Steps `phone` (Global) and `serverCode` (`AdvancedModeCorner` in `sign_in_screen.dart`) | |
| showLegalLink | `bool` | derive | Step `phone` (Global) only | Footer "Terms & Privacy" |
| legal | `LegalDocumentsModel` (title, version, effective date and text, for Terms and Privacy) | have | `HelixLegalDocuments.termsTitle`, `termsVersion`, `termsOfService`, `privacyTitle`, `privacyVersion`, `privacyPolicy`, `effectiveDate` (`packages/helix_remote_domain/lib/domain/legal_documents.dart`) | The same documents as the Terms page in `you.md` |

### Actions
| Action | Signature | Tag | Calls today | Notes |
|---|---|---|---|---|
| onPhoneChanged | `void Function(String digits)` | have | `SignInController.updateDigits` | Interaction "Phone number" |
| onPhoneNext | `Future<bool> Function()` | derive | `SignInController.submitPhone` | Interaction "Next checks the length". `submitPhone` only refuses an empty number (`SignInState.e164`): add the length check in `application/` |
| onSmsCodeChanged | `void Function(String code)` | have | `SignInController.updateOtpCode` | Interaction "SMS code" |
| onSmsCodeNext | `Future<bool> Function()` | have | `SignInController.submitOtp` | Also called by the sixth digit. Goes to `password` (account with a password) or `newAccount` / `takeOver` |
| onResendCode | `Future<bool> Function()` | have | `SignInController.resendOtp` | Interaction "Resend code". On true the screen shows the toast "A new code is on its way" |
| onPasswordChanged | `void Function(String password)` | have | `SignInController.updatePassword` | The password never goes into the model |
| onSignIn | `Future<bool> Function()` | have | `SignInController.signInWithPassword` | Sets `postSignInProvider.offerRestore()`, so the restore step follows |
| onForgotPassword | `void Function()` | have | `SignInController.forgotPassword` | Interaction "Forgot password?": opens `takeOver` |
| onLinkInstead | `void Function()` | have | `SignInController.linkFromAnotherDevice` (pushes `RoutePaths.linkThisDevice` through `appRouterProvider`) | Interaction "Link from another device instead", on `password` and `takeOver`. In Orbit the connector routes, not the controller |
| onNameChanged | `void Function(String name)` | have | `SignInController.updateDisplayName` | |
| onNewPasswordChanged | `void Function(String password)` | have | `SignInController.updateNewPassword` | "Password (optional)" |
| onTermsChanged | `void Function(bool accepted)` | have | `SignInController.setTosAccepted` | Interaction "Terms checkbox" |
| onCreateAccount | `Future<bool> Function()` | have | `SignInController.completeSetup()` | Fails with the Terms error when they are not ticked |
| onSkipName | `Future<bool> Function()` | have | `SignInController.completeSetup(skip: true)` | Interaction "Skip". Still needs the Terms on Global |
| onTakeOver | `Future<bool> Function()` | have | `SignInController.completeSetup()` (with `accountExists`, it sends `replaceExisting`) | "Continue" on `takeOver`. Cannot finish on Global today: see below |
| onBack | `void Function()` | have | `SignInController.goBack`; on `serverConfirm`, `SignInController.declineServer` | Interaction "Back arrow on a step" |
| onOpenAdvanced | `void Function()` | have | `SignInController.openAdvancedMode` | After the screen's hidden corner reveals "Advanced mode" |
| onSetupCodeChanged | `void Function(String code)` | have | `SignInController.updateCode` | Interaction "Personal-server code"; Paste also lands here |
| onSetupCodeNext | `Future<bool> Function()` | have | `SignInController.submitCode` | Checks the code offline first; a server not yet approved moves to `serverConfirm` and nothing is sent |
| onConfirmServer | `Future<bool> Function()` | have | `SignInController.confirmServer` | "Continue": checks the code with that server (`inviteLookup` / `recoveryLookup`), then `serverPhone` |
| onCancelServer | `void Function()` | have | `SignInController.declineServer` | "Cancel": forgets the code |

### Kept inside the screen
- The text fields and their controllers, autofill hints (national phone
  number, one-time code, name, new password), and the eye toggle.
- The SMS field's digits-only filter, and calling `onSmsCodeNext` on the
  sixth digit.
- The hidden corner: three taps, each within 2 s of the last, show "Advanced
  mode" for 2 s; tapping it calls `onOpenAdvanced`.
- Paste on the code field: reads the clipboard and calls
  `onSetupCodeChanged`.
- The Terms and Privacy sheet (opened by the footer link or "Read the Terms
  and Privacy Policy") and its Terms / Privacy segment.
- The spinner while `busy`, disabling Back and the secondary button while
  `busy`, the step transition, and the resend toast.

### Slots
None.

### The app does this, the prototype does not show it
| What | Where in the app | Suggestion |
|---|---|---|
| Errors the prototype does not list: "Enter the invite or recovery code you were given.", "This code is not complete…", "This recovery code is not valid…", "This invite code was cancelled by the server admin." / "…has expired." / "…is not valid.", "This code points to a server that is not reachable securely…", "Enter your password.", "Request a new code first.", "Enter the six-digit code from the SMS.", "Enter the code sent to your phone first.", "This password no longer unlocks your account…", "Could not sign in. Please try again.", "Could not create the account. Try again.", "This server would not let this device register…" | `SignInCopy` (`features/sign_in/application/sign_in_copy.dart`) | Keep, in the same error line |
| The server badge on every personal-server step (code check, phone, SMS, password, name), not only the phone step | `_ServerBadge` in `sign_in_screen.dart` | Keep |
| An invite or recovery link (`https://helix.agiletechbd.com/open#HLX-…`, `helix://open?code=…`, `helix://invite?…`) opens `serverCode` with the code filled and checks it at once, which stops at `serverConfirm` | `AppLinkListener` (`shared/widgets/app_link_listener.dart`), `pendingLinkProvider` (`core/links/pending_link.dart`), `HelixDeepLink.setupCode` (`core/links/deep_link.dart`), `SignInController.consumePendingCode` (the screen calls it after its first frame) | Keep. Part B's connector calls `consumePendingCode`, not the screen |
| The same link while signed in is dropped with no message. `routeDeepLink`'s comment says the UI explains why; it does not | `AppLinkListener._onLink` | Add a toast, or drop (open question) |
| While the database opens (`AppAuthState.starting`, or still loading), the router stays on `/sign-in`, so a signed-in person briefly sees the phone step. `StartupScreen` ("Opening Helix…"), `StartupErrorScreen` and `EngineBusy` exist but nothing uses them | `_redirectFor`; `shared/widgets/startup_screen.dart` | Add a startup state to the design (open question) |
| When an invite fails for a number that already has an account, the controller can switch to a recovery code (`beginPhoneRecovery`, `SignInState.showPhoneRecoveryPrompt`), but no button calls it | `sign_in_controller.dart` | Add "Use a recovery code" under that error, or drop |
| Back from `password` goes to `takeOver`, whose Continue signs the other devices out. Back from `newAccount` goes to `phone` | `SignInController.goBack` | The prototype returns to the previous step. Suggest `phone` for both, because the SMS code is already used (open question) |
| `takeOver` on Helix Global cannot finish: `completeSetup` requires the Terms, and the step has no checkbox. The prototype has none either (`SCREENS.md` lists it as a bug). "Forgot password?" leads here | `completeSetup`, `_NamePage` | Add the checkbox to `takeOver` (open question) |
| A number that is too short is still sent; the server's refusal shows "Could not reach the server…" | `submitPhone`, `SignInCopy.connectFailure` | Add the prototype's length check (`onPhoneNext`) |
| The legal sheet's version line shows "┬╖" (a mis-encoded "·") | `features/sign_in/presentation/widgets/legal_documents_sheet.dart`, line 73 | Fix in the port |
| Copy: the legal documents. The prototype has placeholder text, versions "3" and "4", and "1 September 2026". The app has the real Helix Global documents, version "2026-09-25", effective "September 25, 2026" | `HelixLegalDocuments` | Keep the app's documents: they are what people agree to (`termsVersion` is sent at registration) |
| Copy: the take-over warning. The prototype says "Continuing moves your account to this phone and signs your other devices out." The app says it only in the password step's note | `_NamePage` | Prototype wins |
| Copy: resend. The prototype confirms with "A new code is on its way"; the app shows nothing | `resendOtp` | Prototype wins |

### New backend work
None. Country detection (if wanted) is client-only: a dialling-code table or
a phone-number package (dependency policy applies).

## Restore your chats (`restore`)

Dart: `RestoreScreen`, `RestoreModel`, `RestoreActions`.

The same screen is Settings, Backup, Restore history (`restore-history`, in
`devices_backup.md`); `afterSignIn` tells them apart. Today it is
`RestoreHistoryPage(afterSignIn: true)` on `RoutePaths.restoreAfterSignIn`
(`features/backup/backup_routes.dart`).

### Model
| Field | Type | Tag | Comes from today | Notes |
|---|---|---|---|---|
| afterSignIn | `bool` | have | `RestoreHistoryPage.afterSignIn` (route argument) | Title, "Welcome back", no back, Skip, footer |
| status | `RestoreStatus` (`idle`, `running`, `failed`, `done`) | have | `restoreFlowProvider` → `RestoreFlowState.stage` (`features/backup/application/backup_providers.dart`) | The status ring |
| phaseText | `String?` | have | `RestoreFlowState.phase` ("Looking for your backup...", "Downloading your backup...", "Unlocking it...", "Adding messages...") | Card title while running |
| progress | `double?` | derive | `RestoreFlowState.phase`, one step of four per phase, as the prototype's ring does | Interaction "runs with a percentage". A true percentage needs engine work (below) |
| addedSoFar | `String?` | derive | `RestoreFlowState.added`, formatted "1,204 messages added so far" | The app shows it once `added` or `existing` is above 0 |
| failureTitle | `String?` | derive | `RestoreFlowState.problem` | Prototype: "No backup was found". Short titles for the other problems are new copy |
| failureText | `String?` | have | `RestoreFlowState.error` (`backupProblemText`, `features/backup/application/backup_copy.dart`) | |
| doneTitle | `String?` | derive | `RestoreFlowState.added`: "Restored 2,318 messages", or when 0, "Your backup is already on this phone" | |
| offers | `List<TransferRowModel>` | derive | `incomingOffersProvider` (unfinished only) → `TransferView`; `offerActionsProvider` → `busy`, `errorFor(id)`; labels and buttons as `TransferTile` builds them (`features/backup/presentation/transfer_tile.dart`) | "From your other devices". The same row type as `devices_backup.md`'s transfer rows |

### Actions
| Action | Signature | Tag | Calls today | Notes |
|---|---|---|---|---|
| onRestore | `Future<void> Function()` | have | `restoreFlowProvider.notifier.restore()` | Interaction "Restore from my backup"; also "Try again" |
| onRecoverySecret | `void Function()` | derive | `context.push(RoutePaths.backupRecovery)` | Interaction "I have a recovery secret". `RecoveryBackupPage` always opens on Create; opening on Restore needs a route argument. Also see the redirect row below |
| onAcceptOffer | `Future<void> Function(String id)` | have | `offerActionsProvider.notifier.accept(id)` | Interaction "Accept"; also Resume and Try again |
| onDeclineOffer | `Future<void> Function(String id)` | have | `offerActionsProvider.notifier.decline(id)` | Interaction "Decline" |
| onPauseOffer | `void Function(String id)` | have | `offerActionsProvider.notifier.pause(id)` | App only |
| onSkip | `void Function()` | have | `restoreStepProvider.finish()` (`features/backup/application/restore_step.dart`), then go to `RoutePaths.home` | Interaction "Skip for now" |
| onContinue | `void Function()` | have | After sign-in, as `onSkip`; otherwise `context.pop()` | Interaction "Continue" |

### Kept inside the screen
- The ring animation, button spinners, and disabling Skip and "I have a
  recovery secret" while running.

### Slots
None.

### The app does this, the prototype does not show it
| What | Where in the app | Suggestion |
|---|---|---|
| Other failures: offline, wrong key, damaged, newer format, older backup refused, another account, another device backing up, not allowed (mobile data), unknown | `backupProblemText` | Keep the sentence under a short title |
| "Your backup is already on this phone. Nothing new to add." | `restore_history_page.dart` | Keep |
| Offer rows: progress bar with "Receiving (x of y)" / "Adding messages (x of y)", Pause, Resume, Try again, "Stopped", and an error per row | `TransferTile` | Keep (shared row) |
| No offers: the "From your other devices" section is hidden. The prototype always draws one | `restore_history_page.dart` | Keep |
| System Back does nothing on the after-sign-in step | `PopScope(canPop: !afterSignIn)` | Keep |
| Leaving the step clears `postSignInProvider`, or the router keeps sending you back | `RestoreStep.finish` | Keep (connector) |
| Reading `_redirectFor`: while `postSignInProvider` is `offerRestore`, every location but `/restore` redirects to `/restore`, so "I have a recovery secret" looks like it never reaches the recovery page. Not confirmed by running; the page tests use a stub router | `core/router/app_router.dart` | Check in Part B; let the recovery page through |
| Copy: footer. Prototype "You can restore later from You, Backup."; app "…from Settings, Backup." | `restore_history_page.dart` | Prototype wins (the new navigation) |

### New backend work
| Item | Why the design needs it | Engine / server / protocol | Size: S, M, L |
|---|---|---|---|
| Restore progress as a real percentage | "Runs with a percentage". `RestoreProgress` (`packages/helix_remote_engine/lib/src/backup/models.dart`) reports `added` and `existing` but no total. Optional: the stepped ring (`progress`, derive) needs nothing | Engine | S |

## Link this device (`link-device`)

Dart: `LinkThisDeviceScreen`, `LinkThisDeviceModel`, `LinkThisDeviceActions`.

Controller: `linkThisDeviceProvider` → `LinkThisDeviceController`
(`features/devices/application/devices_providers.dart`), over
`DevicesGateway.beginLink` (`devices_gateway.dart`).

### Model
| Field | Type | Tag | Comes from today | Notes |
|---|---|---|---|---|
| phase | `LinkThisDevicePhase` (`starting`, `waiting`, `confirming`, `approved`, `failed`) | have | `LinkThisDeviceState.step` (`LinkThisStep`; `finishing` is `approved`) | |
| qr | `HelixQrMatrix?` | have | `LinkThisDeviceState.qr` (`HelixQrMatrix`, `packages/helix_remote_ui/lib/src/view_models.dart`) | The prototype fades it when expired; the app hides it on any failure |
| checkNumber | `String?` | have | `LinkThisDeviceState.check` (`linkCheckNumber`, e.g. `482 913`) | The prototype's `72 914` is illustrative |
| countdown | `String?` | have | `linkCountdownProvider` (`9:41`, or `Expired`) | Interaction "Code timer" |
| error | `String?` | have | `LinkThisDeviceState.error` (`linkProblemText` or `describeFailure`) | |
| offerNewCode | `bool` | have | `LinkThisDeviceState.expired` | Button "Show a new code"; otherwise "Try again" |
| accountPhone | `String?` | have | `LinkProposalView.phoneMask` (`+88017*****01`; `features/devices/application/devices_models.dart`) | The prototype draws `+880 17•• ••0001`: reformatting is derive. Null shows "No phone number" |
| accountHelixName | `String?` | have | `LinkProposalView.helixName` (without `~`) | Row hidden when null |
| keyCode | `String` | have | `LinkProposalView.keyCode` (`a1b2 c3d4 e5f6 a7b8 c9d0`) | The prototype's `4821 9930 1175` is illustrative |

### Actions
| Action | Signature | Tag | Calls today | Notes |
|---|---|---|---|---|
| onOpen | `Future<void> Function()` | have | `LinkThisDeviceController.start` | The page calls it after its first frame; in Orbit, the connector |
| onNewCode | `Future<void> Function()` | have | `LinkThisDeviceController.start` | Interaction "Show a new code"; also "Try again" |
| onSimulateApproval | `void Function()` | demo | None | Interaction "Simulate approval (prototype only)" |
| onConfirmAccount | `void Function()` | have | `LinkThisDeviceController.confirmAccount` | Interaction "Yes, this is my account". Shows "Approved. Signing in..."; `postSignInProvider` was already set, so the router opens the restore step |
| onRejectAccount | `void Function()` | have | `LinkThisDeviceController.rejectAccount` | Interaction "No, cancel". The prototype goes back; the app stays and shows the declined message with "Show a new code" (open question) |
| onBack | `void Function()` | have | `context.pop()`; the confirm step's X calls `rejectAccount()` first | Leaving counts as no (`ref.onDispose` cancels the session) |

### Kept inside the screen
- The countdown text's styling; nothing else.

### Slots
None.

### The app does this, the prototype does not show it
| What | Where in the app | Suggestion |
|---|---|---|
| Starting: a progress bar before the code exists | `link_this_device_page.dart` | Add to the design (a placeholder QR) |
| Failures: offline, "The server did not accept that.", "That did not work.", "The approval could not be verified…", "You said that was not your account…", each with Try again or Show a new code | `LinkThisDeviceController._fail`, `linkProblemText` | Keep in the new style |
| "Is this your account?" times out after 5 minutes: "Nobody answered, so nothing was kept…" | `linkConfirmTimeoutProvider` | Keep |
| The countdown reaches "Expired" before the failure arrives: "Code expires in Expired." | `linkCountdownProvider` | Fix in the port: switch to the expired state at 0 |
| Leaving the page without linking takes back the restore-step request | `LinkThisDeviceController.build` (`onDispose`) | Keep (connector) |
| Signed in: `/link-device` redirects to home or the restore step | `_redirectFor` | Keep |
| Copy: expired. Prototype: "This code has expired. Show a new code to try again." App, on the new device: "That code has expired. Codes last ten minutes. Ask the new device to show a new one." (the approving side's wording) | `linkProblemText(LinkProblem.expired)` | Prototype wins |

### New backend work
None.

## Reset (`reset`)

Dart: `ResetScreen`, `ResetModel`, `ResetActions`.

### Model
| Field | Type | Tag | Comes from today | Notes |
|---|---|---|---|---|
| kind | `ResetKind` (`openElsewhere`, `keyMissing`, `cannotDecrypt`, `fine`) | derive | `authStateProvider` error: `EngineAlreadyRunning` (`core/platform/engine_lease.dart`) → `openElsewhere`; `KeyUnavailable` (`core/platform/app_storage.dart`) → `keyMissing`; any other error → `cannotDecrypt`; no error → `fine` | As `ResetScreen` decides (`shared/widgets/reset_screen.dart`) |

### Actions
| Action | Signature | Tag | Calls today | Notes |
|---|---|---|---|---|
| onTryAgain | `void Function()` | have | `ref.invalidate(runtimeProvider)` | `openElsewhere` only. The prototype's "Trying again…" toast is a demo stand-in |
| onReset | `Future<void> Function()` | have | `destructiveResetProvider()` (`DestructiveReset.call`, `core/engine/session_providers.dart`) | Interaction "Reset Orbit". Deletes the database, its key, the server choice and any parked link, then reopens; the router goes to sign-in |

### Kept inside the screen
- The "Type DELETE to confirm" field (interaction "Type DELETE"); the button
  is enabled when it matches. The app trims spaces; the prototype matches
  exactly.
- "Deleting…" on the button while `onReset` runs.

### Slots
None.

### The app does this, the prototype does not show it
| What | Where in the app | Suggestion |
|---|---|---|
| "Your local data is fine." when `/reset` is reached with no error (stale location) | `ResetScreen` | Keep in the new style |
| Any other startup failure is shown as "could not be decrypted" and offers the destructive reset | `ResetScreen` (any error that is not the two named types) | Add a "could not start" state with Try again (`StartupErrorScreen` exists, unused), or keep (open question) |
| A reset that fails says nothing; the button comes back | `_ConfirmReset._run` | Add an error line |

### New backend work
None.

## App lock (`lock`)

Dart: `LockScreen`, `LockModel`, `LockActions`.

This is the face of the lock only. When it locks (cold start, "Lock again"
time, calls) stays in `AppLock` and `AppLockGate`
(`core/security/app_lock.dart`); see `frame.md`.

### Model
| Field | Type | Tag | Comes from today | Notes |
|---|---|---|---|---|
| unlockWith | `String` | derive | `Platform.isWindows` (as `AppPaths.isWindows` in `core/platform/app_storage.dart`, which is `@visibleForTesting`) | "Windows Hello (your face, fingerprint or PIN)" on Windows, else "your fingerprint, face or phone PIN" |

### Actions
| Action | Signature | Tag | Calls today | Notes |
|---|---|---|---|---|
| onUnlock | `Future<bool> Function()` | have | `AppLock.unlock('Unlock Helix Remote')`, through `_unlockAction` | Interaction "Unlock". The reason string is what the system prompt shows |

### Kept inside the screen
- The button's spinner while the prompt is open.

### Slots
None.

### The app does this, the prototype does not show it
| What | Where in the app | Suggestion |
|---|---|---|
| The system prompt opens by itself when the lock appears | `_LockScreenState.initState` | Keep (the gate calls `onUnlock`) |
| A plain cover from the moment the session is up until the lock setting is read; if it cannot be read, the app locks anyway | `_Cover`, `AppLock.completeColdStart` | Keep (frame) |
| A live call lifts the lock | `AppLock.callInProgress` | Keep (frame) |
| A failed or cancelled prompt, or a phone that no longer has a screen lock, leaves the lock up with no message | `AppLock.unlock` | Add a line ("Not unlocked. Try again."), or keep |
| Behind the lock, nothing can be focused or read by a screen reader | `AppLockGate` (`ExcludeSemantics`, `ExcludeFocus`) | Keep |
| Copy: Windows. The app says "fingerprint, face or phone PIN" on Windows too | `_LockScreen` | Prototype wins (`unlockWith`) |

### New backend work
None.
