# Contract: people pages and groups

Prototype screens: `contact` (states: `contact`, `contact-keychanged`,
`contact-nokey`, `contact-blocked`, `contact-number`), `safety` (states:
`safety`, `safety-unverified`, `safety-changed`, `safety-none`), `scan`
(states: `scan`, `scan-nocamera`, `scan-contact`), `group-new` (states:
`group-new`, `group-new-picked`, `group-new-error`), `group-info` (states:
`group-info`, `group-info-owner`, `group-info-member`, `group-info-gone`),
`group-settings` (states: `group-settings`, `group-settings-member`),
`group-invite` (states: `group-invite`, `group-invite-empty`),
`group-requests` (states: `group-requests`, `group-requests-empty`),
`group-banned` (states: `group-banned`, `group-banned-empty`), `group-add`
(states: `group-add`), `group-join` (states: `group-join`,
`group-join-preview`, `group-join-approval`, `group-join-member`,
`group-join-done`, `group-join-pending`, `group-join-failed`).

Today's app: `features/people/presentation/` (contact info, safety number,
safety scan, `widgets/key_changed_banner.dart`, `widgets/person_sheets.dart`),
`features/people/application/` (`contact_info.dart`, `people_gateway.dart`,
`people_failures.dart`), `features/groups/presentation/**`,
`features/groups/application/**`, `core/people/people_names.dart`,
`core/groups/pending_member_copy.dart`, `shared/widgets/` (`qr_scanner_view`,
`mute_choice`, `pending_members_prompt`), and
`packages/helix_remote_ui/lib/src/` (`view_models.dart`,
`security_views.dart`).

- **Paths** are relative to `helix_remote/app/lib/`. Paths that start with
  `packages/` or `server/` are relative to `helix_remote/`.
- **Names.** The Orbit classes live in `orbit_ui`. They avoid the names of
  today's application classes (`ContactInfoActions`, `GroupActions`,
  `JoinRequestActions`). Where a name matches a widget in today's
  `presentation/` (`GroupInfoScreen`, `AddMembersScreen`, …), the old widget
  is deleted when Part B wires the new one.
- `shared/widgets/key_code_display.dart` is not used by these screens
  (devices uses it).

## Shared types

| Type | Tag | Comes from today | Notes |
|---|---|---|---|
| `TrustState`: `noKey`, `unverified`, `verified`, `keyChanged` | have | `features/people/application/contact_info.dart` | Built from `PersonRow.identityKey`, `identityVerified` and `identityChangedAt` |
| `MuteFor`: 8 hours, 1 week, Always | have | `shared/widgets/mute_choice.dart` | `contact_info.dart` has a second `MuteFor`: its "Always" is now + 100 years, the shared one is the year 9999. Part B keeps the shared one |
| `DisappearAfter`: Off, 24 hours, 7 days, 90 days | have | `contact_info.dart` | Groups use `kGroupDisappearingChoices` in `features/groups/presentation/group_info_screen.dart`, with the same four values. Part B keeps one list |
| `ReportReason`, `PersonReport` | have | `contact_info.dart` | Mapped to the server's `ReportCategory` |
| `RenameOutcome` | have | `contact_info.dart` | `savedEverywhere`, `savedInHelix`, `needsPhonePermission`, `phoneRefused` |
| `GroupMemberRole`, `GroupWho`, `GroupPermissions` | have | `features/groups/application/group_models.dart` | |
| `MemberAction` | have | `features/groups/application/group_info.dart` | Make admin, Remove admin, Make owner, Remove from group, Remove and ban |
| `GroupResult`: `ok`, `message` | have | `features/groups/application/group_actions.dart` | Every group change answers with a sentence; the screen shows it as a toast |
| `PersonEntryView`: `id`, `account`, `title`, `whenLabel`, `avatar` | have | `features/groups/application/group_invites.dart` | One row of join requests or bans |
| `HelixAvatarModel`, `HelixPersonNames`, `HelixPersonItem`, `HelixQrMatrix` | have | `packages/helix_remote_ui/lib/src/view_models.dart` | |

## Member picker (a part of `group-new` and `group-add`)

Dart: `MemberPicker`, `MemberPickerModel`, `MemberPickerActions`.

### Model

| Field | Type | Tag | Comes from today | Notes |
|---|---|---|---|---|
| `candidates` | `List<HelixPersonItem>` | have | `groupCandidatesProvider` (`features/groups/application/create_group.dart`): `GroupCandidate.account`, `.names` | Blocked people are already left out |
| `candidates[].image` | `ImageProvider?` | derive | `peopleDirectoryProvider` → `PeopleDirectory.imageOf(account)` (`core/people/people_names.dart`) | `GroupCandidate` carries no picture today |
| `selected` | `List<String>` | have | `CreateGroupState.selected` (new group); widget state in `AddMembersScreen` (add members) | In pick order; the chips show them |
| `exclude` | `Set<String>` | have | `groupInfoProvider(id)` → `GroupInfoView.members[].account` | Add members only |
| `loading` | `bool` | have | `groupCandidatesProvider` is loading | |
| `loadFailed` | `bool` | have | `groupCandidatesProvider` has an error | |

### Actions

| Action | Signature | Tag | Calls today | Notes |
|---|---|---|---|---|
| `onToggle` | `void Function(String account)` | have | `CreateGroupController.toggle`; `AddMembersScreen._toggle` | New group refuses a pick past 1,023 people with an error |
| `onLookup` | `Future<({HelixPersonItem? found, String? error})> Function(String query)` | have | `candidateLookupProvider` → `CandidateLookup.find` (`create_group.dart`) | A number or `~name`. Spends one discovery lookup; the engine remembers whoever it finds |

### Kept inside the screen

- The search text, and the filter on name, number, `~name`, nickname and
  phone-book name (as `MemberPicker` does today).
- Whether to offer the "Find “…” on Orbit" row (7 or more number characters,
  or `~` and one more character), its spinner, picking the person it finds
  and clearing the search.
- "That person is already in this group." when the person found is in
  `exclude`.

### Slots

None.

### The app does this, the prototype does not show it

| What | Where in the app | Suggestion |
|---|---|---|
| Empty list: "Nobody here yet. Type a phone number or a ~name to find someone on Helix." | `features/groups/presentation/widgets/member_picker.dart` | Add to the design |
| A spinner while the people load, and "Your people could not be loaded." | same | Keep today's behaviour in the new style |
| Lookup refusals: "You blocked this person. Unblock them to add them.", offline, "Too many attempts. Try again in a little while." | `CandidateLookup.find`, `group_errors.dart` | Keep, as toasts |

## Contact info (`contact`)

Dart: `ContactScreen`, `ContactModel`, `ContactActions`.

### Model

| Field | Type | Tag | Comes from today | Notes |
|---|---|---|---|---|
| `accountId` | `String` | have | The route, `PeoplePaths.person(id)` (`shared/navigation/people_paths.dart`) | |
| `name` | `String` | have | `contactPersonProvider(id)` → `ContactPerson.name.display` (`features/people/application/contact_info.dart`) | With no row, `ContactPerson.unknown(id)`: "Helix user 1a2b3c4d" |
| `avatar` | `HelixAvatarModel` | have | `ContactPerson.name.avatar` (`core/people/people_names.dart`) | A picture only when this device has one. People's own photos depend on photo sharing (`you.md`) |
| `secondary` | `String?` | have | `ContactPerson.numberLabel ?? name.names.secondary` | The number, else the `~name`. Null for `contact-number` |
| `about` | `String?` | have | `contactAboutProvider(id)` | Filled after `refreshProfile` (below) |
| `trust` | `TrustState` | have | `ContactPerson.trust` | Drives the seal, the key-changed banner and the Encryption subtitle |
| `blocked` | `bool` | have | `ContactPerson.name.blocked` | |
| `blockedByThem` | `bool` | derive | Engine `PeopleService.watchBlocksMe` (`packages/helix_remote_engine/lib/src/features/people_service.dart`). The app reads it only in `peerBlocksMeProvider` (`features/conversation/application/conversation_header.dart`), which the people feature may not import | Add `PeopleGateway.watchBlocksMe`, or move the provider to `core/people/`. The prototype does not draw it; see the questions |
| `nickname` | `String?` | have | `ContactPerson.name.names.nickname` | The Rename subtitle |
| `numberLabel` | `String?` | have | `ContactPerson.numberLabel` | Null hides the phone row and the rename footer |
| `helixName` | `String?` | have | `ContactPerson.name.helixName` | |
| `muted` | `bool` | have | `contactChatProvider(id)` → `ContactChatSettings.muted` | |
| `muteLabel` | `String?` | have | `ContactChatSettings.muteLabel` | "Always" or "Until 14:05"; the prototype draws only "Always" |
| `disappearing` | `DisappearAfter` | have | `DisappearAfter.of(ContactChatSettings.disappearingSeconds)` | |
| `commonGroups` | `List<({String id, String title})>` | have | `commonGroupsProvider(id)` → `GroupSummary` (`features/people/application/people_gateway.dart`) | |
| `loading` | `bool` | have | `contactPersonProvider(id)` is loading | |
| `loadFailed` | `bool` | have | `contactPersonProvider(id)` has an error | |

### Actions

| Action | Signature | Tag | Calls today | Notes |
|---|---|---|---|---|
| `onMessage` | `Future<void> Function()` | have | `ContactInfoActions.openChat` | Creates the direct chat if needed |
| `onCall` | `Future<String?> Function({required bool video})` | have | `ContactInfoActions.startCall` → `conversationSeamsProvider.startCall` | Null when the call started, else the sentence to show |
| `onRename` | `Future<RenameOutcome> Function(String? name)` | have | `ContactInfoActions.rename` | Blank clears the nickname |
| `onSaveToPhoneContacts` | `Future<RenameOutcome> Function(String name)` | have | `ContactInfoActions.savePhoneName` | After "Allow": asks the system for permission, then saves |
| `onMute` | `Future<void> Function(MuteFor? length)` | have | `ContactInfoActions.mute` | Null unmutes |
| `onSetDisappearing` | `Future<void> Function(DisappearAfter after)` | have | `ContactInfoActions.setDisappearing` | |
| `onOpenSharedMedia` | `Future<bool> Function()` | have | `ContactInfoActions.openSharedMedia` | False when it could not open |
| `onOpenSafetyNumber` | `void Function()` | have | Pushes `PeoplePaths.safetyNumber(id)` | Also the banner's "Review" |
| `onOpenGroup` | `Future<void> Function(String groupId)` | have | `ContactInfoActions.openGroup` | |
| `onBlock` | `Future<bool> Function()` | have | `ContactInfoActions.block` | Calls the server. Today a failure throws and nothing is said; the connector catches it |
| `onUnblock` | `Future<bool> Function()` | have | `ContactInfoActions.unblock` | Same |
| `onReport` | `Future<bool> Function(PersonReport report)` | have | `ContactInfoActions.report` | False when it could not be sent |

When the screen opens, the connector calls `ContactInfoActions.refreshProfile(id)`
once (have). It is not a screen action.

### Kept inside the screen

- The Rename dialog, and "Save in your phone contacts too?" when `onRename`
  answers `needsPhonePermission`.
- The mute sheet (on switch on) and the disappearing sheet.
- The block confirmation; unblock happens at once.
- The report sheet of reasons, then the optional note dialog.
- "Send a message first. A safety number needs both of your keys." when
  `trust` is `noKey`.
- The result toasts: "Saved." and the other rename outcomes, "Blocked.",
  "Unblocked.", "Reported. No messages were sent with the report."
- Rule kept from `helix_remote/app/test/people_rules_test.dart`: a toast or error never
  contains a name or a number. The prototype's toasts already follow it.

### Slots

None.

### The app does this, the prototype does not show it

| What | Where in the app | Suggestion |
|---|---|---|
| A spinner while the person loads, and "This person could not be loaded. Go back and try again." | `features/people/presentation/contact_info_screen.dart` | Keep today's behaviour in the new style |
| A person with no row yet: "Helix user 1a2b3c4d", no number, trust `noKey` | `ContactPerson.unknown` | Keep; no new state needed |
| "Saved in Helix. Your phone did not let Helix change your contacts." | `_rename`, `RenameOutcome.phoneRefused` | Keep (SCREENS.md lists it; the prototype script never shows it) |
| The phone-contacts question only when permission is missing, and never on Windows | `ContactInfoActions.rename` | Keep the app's rule. The prototype asks every time the person has a number |
| A call that cannot start says why: "This person has blocked you. You can't message or call them.", "You blocked this person. Unblock them to call." | `_call`, `features/calls/application/call_copy.dart` | Keep, as toasts |
| "Shared media could not be opened." | `_sharedMedia` | Keep |
| "The report could not be sent. Try again in a moment." | `_report` | Keep |
| A block or unblock that fails (offline) says nothing: the error is not caught | `_block` | Add a toast, for example "That did not work. Check your connection and try again." |
| The person blocked you (ADR-030): this page does not say so, and the Message and call tiles stay | Only the conversation says it (`conversation_header.dart`) | Add to the design: "<Name> has blocked you." under the name, and hide the call tiles as the chat does |

### Copy that differs in meaning

| Where | Prototype | App | Suggestion |
|---|---|---|---|
| Block dialog | "They will not be able to message or call you. Orbit tells them that you blocked them." | "…and will not be told that you blocked them." | The prototype is right. Since ADR-030 the blocked person's devices get a `block_change` envelope. Fix the app's copy in Part B |
| Report sheet | "Orbit only learns who you reported and why. No messages are sent with the report." | "Why are you reporting this person? Helix's operators are told about the account. No messages are sent with the report." | The optional note is sent too. Suggest: "Orbit learns who you reported, why, and your note. No messages are sent with the report." |

### New backend work

None.

## Safety number (`safety`)

Dart: `SafetyNumberScreen`, `SafetyNumberModel`, `SafetyNumberActions`.

### Model

| Field | Type | Tag | Comes from today | Notes |
|---|---|---|---|---|
| `name` | `String` | have | `contactPersonProvider(id)` → `ContactPerson.name.display` | |
| `trust` | `TrustState` | have | `ContactPerson.trust` | `keyChanged` shows the banner; `verified` shows the mark and "Mark as not verified" |
| `groups` | `List<String>?` | have | `safetyNumberProvider(id)` → `SafetyNumberData.groups` (`people_gateway.dart`) | 12 groups of 5 digits. Null is "No safety number yet" |
| `qr` | `HelixQrMatrix?` | have | `SafetyNumberData.qrMatrix` | The app encodes it; the UI draws modules |
| `loading` | `bool` | have | `safetyNumberProvider(id)` is loading | |
| `loadFailed` | `bool` | have | `safetyNumberProvider(id)` has an error | |

### Actions

| Action | Signature | Tag | Calls today | Notes |
|---|---|---|---|---|
| `onScan` | `void Function()` | have | Pushes `PeoplePaths.scan(id)` | |
| `onSetVerified` | `Future<void> Function(bool verified)` | have | `ContactInfoActions.setVerified` | |

### Kept inside the screen

Nothing beyond drawing the model.

### Slots

None.

### The app does this, the prototype does not show it

| What | Where in the app | Suggestion |
|---|---|---|
| A spinner while the number is worked out | `features/people/presentation/safety_number_screen.dart` | Keep |
| "The safety number could not be worked out. Try again." (no retry button) | same | Keep, and add a Retry button |

### New backend work

None.

## Scan code (`scan`)

Dart: `ScanCodeScreen`, `ScanCodeModel`, `ScanCodeActions`.

### Model

| Field | Type | Tag | Comes from today | Notes |
|---|---|---|---|---|
| `mode` | `ScanMode` (`safetyNumber`, `contact`) | derive | Safety number: the route `PeoplePaths.scan(id)`. Contact: no route today | `contact` is opened from "Scan someone's code" (You → share your code, `you.md`); it needs a route without an account id |
| `hasCamera` | `bool` | have | `qrScannerBuilderProvider` is not null (`shared/widgets/qr_scanner_view.dart`) | False on Windows: `scan-nocamera` |

### Actions

| Action | Signature | Tag | Calls today | Notes |
|---|---|---|---|---|
| `onCode` (safety number) | `Future<bool> Function(String text)` | derive | The steps are in `SafetyScanScreen._onText` (presentation): `safetyNumberProvider(id).future` → `SafetyNumberData.matchesQrText(text)`, then `ContactInfoActions.setVerified(id, verified: true)` | True on a match. Move the steps into `ContactInfoActions` |
| `onCode` (contact) | `Future<String?> Function(String text)` | derive | Nothing today. Would read the person's code and find them with `PeopleGateway.findByHelixName`, then `ContactInfoActions.openChat` | Null when the chat opened, else the sentence. Depends on the code format `you.md` settles; if the code is more than a `~name`, this becomes **server** |
| Simulate a match / a mismatch | — | demo | — | Prototype only |

### Kept inside the screen

- Ignoring new codes while one is being checked.
- On a match: "Verified. Your chat is private." and back to the safety number.
- On a mismatch: the "That code does not match" dialog, then scanning goes on.
- The hint for each mode.

### Slots

| Slot | What the app puts there | What the preview shows |
|---|---|---|
| `camera` | The `qrScannerBuilderProvider` builder: `CameraQrScanner` (`mobile_scanner`), which reports each QR text to `onCode` | The dark frame with corners and the moving beam |

### The app does this, the prototype does not show it

| What | Where in the app | Suggestion |
|---|---|---|
| Camera refused or broken: "The camera is not available. Allow camera access for Helix in your phone settings to scan a code." | `CameraQrScanner.errorBuilder` | Keep, in the dark scanner style |
| No camera in contact mode: the prototype's text is about comparing numbers, which does not fit | — | Add a contact-mode text, or hide "Scan someone's code" where there is no camera |

### Copy that differs in meaning

| Where | Prototype | App | Suggestion |
|---|---|---|---|
| Mismatch dialog | "…Make sure you scanned the right person's code, and compare the numbers instead if you are unsure." | "Make sure you are scanning the code on this person's own safety number screen. If it still does not match, do not trust this chat until you have compared the numbers another way." | Keep the app's warning ("do not trust this chat"), in the prototype's style |

### New backend work

None for the safety number. Contact mode: see `onCode` (contact).

## New group (`group-new`)

Dart: `NewGroupScreen`, `NewGroupModel`, `NewGroupActions`.

### Model

| Field | Type | Tag | Comes from today | Notes |
|---|---|---|---|---|
| `name` | `String` | have | `createGroupProvider` → `CreateGroupState.name` (`features/groups/application/create_group.dart`) | At most 100 characters (`kGroupNameMaxLength`) |
| `nameError` | `String?` | derive | `CreateGroupState.nameValid` | The prototype's `group-new-error`: tapping Create with no name shows "Enter a group name of 1 to 100 characters." Today the button is disabled instead, so `create()` must set this error rather than return |
| `error` | `String?` | have | `CreateGroupState.error` | Over 1,024 people, or a create failure from `groupErrorText` |
| `picture` | `ImageProvider?` | have | `CreateGroupState.picture` (scaled PNG bytes) | |
| `picker` | `MemberPickerModel` | have | See the member picker | `selected` is `CreateGroupState.selected` |
| `creating` | `bool` | have | `CreateGroupState.creating` | The button's spinner |

### Actions

| Action | Signature | Tag | Calls today | Notes |
|---|---|---|---|---|
| `onNameChanged` | `void Function(String name)` | have | `CreateGroupController.setName` | |
| `onChoosePicture` | `Future<void> Function()` | have | `CreateGroupController.pickPicture` → `groupPicturePickerProvider` (`group_picture.dart`) | Opens the phone's file picker |
| `onRemovePicture` | `void Function()` | have | `CreateGroupController.clearPicture` | |
| `onCreate` | `Future<({String groupId, String conversationId, List<String> notAddedNames})?> Function()` | have | `CreateGroupController.create` → `CreatedGroupInfo` | Null on failure (see `error`). Names come from `groupCandidatesProvider` |
| `onOpenGroupChat` | `void Function(String groupId, String conversationId)` | have | `groupChatLocationProvider` (`group_navigation.dart`), replacing this page; else `GroupPaths.info(groupId)` | After the "not added" dialog |
| picker actions | `MemberPickerActions` | have | See the member picker | |

### Kept inside the screen

- The picture sheet when a picture is set ("Choose another picture",
  "Remove picture").
- The "Some people were not added" dialog.

### Slots

None.

### The app does this, the prototype does not show it

| What | Where in the app | Suggestion |
|---|---|---|
| "A group holds at most 1024 people." | `CreateGroupController.toggle` | Keep |
| Create failures under the name (offline, server busy, too many attempts) | `groupErrorText(…, context: GroupContext.create)` | Keep |
| A file that is not an image, or is too big after scaling, is ignored without a word | `FileGroupPicturePicker.pick` | Add a toast: "That picture could not be used." |

### Copy that differs in meaning

| Where | Prototype | App | Suggestion |
|---|---|---|---|
| "Some people were not added" (and the add-members refusal) | "<Name> only lets people they know add them to groups." | The same | The server refuses when their "who can add me" is Contacts **or Nobody**, or when they blocked you (`mayAddToGroup`, `server/lib/src/modules/people/module.dart`), and a create does not return the reason. Suggest: "<Name>'s settings do not let you add them to groups. Send them an invite link from the group's page." |

### New backend work

None.

## Group info (`group-info`)

Dart: `GroupInfoScreen`, `GroupInfoModel`, `GroupInfoActions`.

### Model

| Field | Type | Tag | Comes from today | Notes |
|---|---|---|---|---|
| `groupId` | `String` | have | The route, `GroupPaths.info(id)` | |
| `status` | `loading`, `failed`, `gone`, `ready` | have | `groupInfoProvider(id)` (`features/groups/application/group_info.dart`); `null` data is `gone` | `gone` is `group-info-gone` |
| `title` | `String` | have | `GroupInfoView.title` | "New group" until the group key arrives |
| `nameArriving` | `bool` | have | `GroupSnapshot.nameUnavailable` | |
| `avatar` | `HelixAvatarModel` | have | `GroupInfoView.avatar`, with the bytes of `groupPictureProvider(GroupInfoView.pictureKey)` (`group_picture.dart`) | The picture is end-to-end encrypted |
| `memberCountLabel` | `String` | have | `GroupInfoView.memberCountLabel` | |
| `homeServer` | `String?` | have | `GroupSnapshot.homeServer` | "N members · on <server>" |
| `description` | `String?` | have | `GroupSnapshot.description` | |
| `isOwner` | `bool` | have | `GroupSnapshot.isOwner` | Delete group |
| `canAdminister` | `bool` | have | `GroupSnapshot.canAdminister` | Disappearing choice, settings, links, requests, bans |
| `canEditInfo` | `bool` | have | `GroupSnapshot.canEditInfo` | The picture and "Edit group info". Also true for members when the group lets everyone edit |
| `canAddMembers` | `bool` | have | `GroupSnapshot.canAddMembers` | Same rule for "Add members" |
| `disappearingSeconds` | `int?` | have | `GroupSnapshot.disappearingSeconds` | |
| `disappearingLabel` | `String` | derive | `disappearingLabel()` in `features/groups/presentation/group_info_screen.dart` | Move it to `application/`. It also names timers set elsewhere ("3 days") |
| `joinRequestCount` | `int` | have | `joinRequestsProvider(id)` (`group_invites.dart`), its length | Admins only |
| `members` | `List<GroupMemberView>` | have | `GroupInfoView.members`: `title` ("You"), `subtitle` ("Not confirmed · Admin · <server> · <number>"), `role`, `actions`, `unconfirmed` | Owner first, then admins, then by name |
| `members[].avatar.image` | `ImageProvider?` | derive | `PeopleDirectory.imageOf(account)` | `GroupMemberView.avatar` has no picture today |
| `pending` | `List<PendingMemberView>` | have | `pendingMembersProvider(id)` (`group_pending.dart`): `title` ("Confirm <name>?"), `explanation`, `canRemove` | The "Confirm Karim Uncle?" card |

### Actions

| Action | Signature | Tag | Calls today | Notes |
|---|---|---|---|---|
| `onChoosePicture` | `Future<GroupResult> Function()` | have | `GroupActions.chooseAndSetPicture` | |
| `onRemovePicture` | `Future<GroupResult> Function()` | have | `GroupActions.setPicture(id, null)` | |
| `onSaveInfo` | `Future<GroupResult> Function(String name, String description)` | have | `GroupActions.rename`, then `GroupActions.setDescription`, each only when changed; stops at the first failure | The steps are in `_GroupBody._editInfo` today; the connector takes them over |
| `onSetDisappearing` | `Future<GroupResult> Function(int? seconds)` | have | `GroupActions.setDisappearing` | Sends a timer notice to the group (`ChatsService.setDisappearing`) |
| `onMemberAction` | `Future<GroupResult> Function(String account, MemberAction action)` | have | `GroupActions.setRole` (admin, member, owner), `GroupActions.removeMember`, `GroupActions.ban` | The server allows only the owner to make an owner, and the old owner becomes an admin |
| `onConfirmPending` | `Future<GroupResult> Function(String account)` | have | `GroupActions.confirmMember` | |
| `onRemovePending` | `Future<GroupResult> Function(String account)` | have | `GroupActions.removeMember` | |
| `onOpenSettings`, `onOpenInviteLinks`, `onOpenJoinRequests`, `onOpenBanned`, `onAddMembers` | `void Function()` | have | Push `GroupPaths.settings`, `.invite`, `.requests`, `.banned`, `.addMembers` (`shared/navigation/group_paths.dart`) | |
| `onLeave` | `Future<GroupResult> Function()` | have | `GroupActions.leave` | Back to Chats only when it worked |
| `onDelete` | `Future<GroupResult> Function()` | have | `GroupActions.deleteGroup` | Same |
| `onRetry` | `void Function()` | have | Invalidates `groupSnapshotProvider(id)` | |

### Kept inside the screen

- The picture sheet, the "Edit group info" sheet and its fields, the
  disappearing sheet and the member sheet.
- The confirmations: make owner, remove, remove and ban, remove a pending
  member, leave, delete.
- The toasts with each `GroupResult.message`.

### Slots

None.

### The app does this, the prototype does not show it

| What | Where in the app | Suggestion |
|---|---|---|
| A spinner, and "This group could not be loaded." with Retry | `features/groups/presentation/group_info_screen.dart` | Keep |
| "The group's name is still arriving." | same | Keep |
| Toasts when this device is taken out while the page is open: "You were removed from this group.", "You left this group.", "This group was deleted." | `groupSignalsProvider`, `membershipEndedText` | Keep |
| "A member was added by the server roster. Confirm or remove them below." | `groupSignalsProvider` | Keep |
| The link-join reason on a pending card: "<Name> joined this group through its invite link, and nothing else vouches for them." | `core/groups/pending_member_copy.dart` | Keep; the prototype draws only the roster reason |
| "<Name> was confirmed. They get your messages in this group from now on." / "<Name> is no longer waiting for confirmation." | `GroupActions.confirmMember` | Keep |
| Failures as sentences: "Only an admin can do that in this group.", "The group was changed at the same time. Try again.", "This group is still being set up on your phone. Try again in a moment.", offline | `features/groups/application/group_errors.dart` | Keep, as toasts |
| Members see the picture, "Edit group info" and "Add members" when the group settings say Everyone | `canEditInfo`, `canAddMembers` | Keep the app's rule; the prototype's `group-info-member` should show them in that case |
| The whole member row opens the member sheet | `_MemberTile` | Either; the prototype uses the ⋮ button |

### New backend work

None.

## Group settings (`group-settings`)

Dart: `GroupSettingsScreen`, `GroupSettingsModel`, `GroupSettingsActions`.

### Model

| Field | Type | Tag | Comes from today | Notes |
|---|---|---|---|---|
| `status` | `loading`, `failed`, `gone`, `ready` | have | `groupInfoProvider(id)` | |
| `canChange` | `bool` | have | `GroupSnapshot.canAdminister` | False is `group-settings-member` |
| `permissions` | `GroupPermissions` | have | `GroupSnapshot.permissions`: `editInfo`, `addMembers`, `sendMessages` | Each `GroupWho.label`: "Everyone" or "Only admins" |

### Actions

| Action | Signature | Tag | Calls today | Notes |
|---|---|---|---|---|
| `onSetPermissions` | `Future<GroupResult> Function(GroupPermissions permissions)` | have | `GroupActions.setPermissions` | |
| `onRetry` | `void Function()` | have | Invalidates `groupSnapshotProvider(id)` | |

### Kept inside the screen

The choice sheet for each row.

### Slots

None.

### The app does this, the prototype does not show it

| What | Where in the app | Suggestion |
|---|---|---|
| A spinner, "This group could not be loaded." with Retry, and "You are not in this group" | `features/groups/presentation/group_settings_screen.dart` | Keep |
| A failure toast when a change is refused | `_Settings._choose` | Keep |

### New backend work

None.

## Invite with a link (`group-invite`)

Dart: `InviteLinksScreen`, `InviteLinksModel`, `InviteLinksActions`.

### Model

| Field | Type | Tag | Comes from today | Notes |
|---|---|---|---|---|
| `requiresApproval` | `bool` | have | `groupInviteProvider(id)` → `GroupInviteState.requiresApproval` (`group_invites.dart`) | Off by default in the app, on in the prototype; see the questions |
| `links` | `List<({String linkId, String url, bool requiresApproval})>` | have | `GroupInviteState.links` (`InviteLinkInfo`) | Newest first. Only the links made since the app started |
| `working` | `bool` | have | `GroupInviteState.working` | The Create spinner; also disables Revoke |
| `error` | `String?` | have | `GroupInviteState.error` | |
| `groupName` | `String` | have | `groupTitleProvider(id)` | For the share text |

### Actions

| Action | Signature | Tag | Calls today | Notes |
|---|---|---|---|---|
| `onSetApproval` | `void Function(bool value)` | have | `GroupInviteController.setRequiresApproval` | Applies to the next link |
| `onCreate` | `Future<void> Function()` | have | `GroupInviteController.create` | |
| `onShare` | `Future<void> Function(String linkId)` | have | `linkSharerProvider` → `LinkSharer.share` | "Join the group "<name>" on Helix: <link>" |
| `onCopy` | `Future<void> Function(String linkId)` | have | `LinkSharer.copy` | |
| `onRevoke` | `Future<void> Function(String linkId)` | have | `GroupInviteController.revoke` | |

### Kept inside the screen

The revoke confirmation and the "Link copied." toast.

### Slots

None.

### The app does this, the prototype does not show it

| What | Where in the app | Suggestion |
|---|---|---|
| Links are kept only in memory. After a restart the page is empty, and earlier links still work but can no longer be revoked from any device | `GroupInviteState`; the server has no list route | Add a line to the design ("Links made before Orbit last started are not listed"), or build the list (below) |
| An error line under Create (not allowed, offline) | `features/groups/presentation/group_invite_screen.dart` | Keep |
| Links can expire (the engine takes `expiresAt`), but no screen offers it | `GroupsPort.createInviteLink` | Drop for now |

### New backend work

| Item | Why the design needs it | Engine / server / protocol | Size: S, M, L |
|---|---|---|---|
| List a group's live links (id, approval mode, made by, date; never the secret) | The page lists links to revoke. Today a link made before a restart, or on another device, can never be revoked | Server: `GET /v1/groups/{id}/invite-links` (the `invite_links` table exists); protocol DTO; engine method. The URL itself cannot be shown again, since the server keeps only its hash | M |

## Join requests (`group-requests`)

Dart: `JoinRequestsScreen`, `JoinRequestsModel`, `JoinRequestsActions`.

### Model

| Field | Type | Tag | Comes from today | Notes |
|---|---|---|---|---|
| `status` | `loading`, `failed`, `ready` | have | `joinRequestViewsProvider(id)` (`group_invites.dart`) | |
| `requests` | `List<PersonEntryView>` | have | `joinRequestViewsProvider(id)` | `whenLabel` is "Today, 14:05"; the prototype writes "today at 09:02" (style only). Refreshes when a request arrives |
| `requests[].avatar.image` | `ImageProvider?` | derive | `PeopleDirectory.imageOf(account)` | |

### Actions

| Action | Signature | Tag | Calls today | Notes |
|---|---|---|---|---|
| `onApprove` | `Future<GroupResult> Function(String requestId)` | have | `joinRequestActionsProvider` → `JoinRequestActions.approve` | Toast "<Name> joined the group." |
| `onReject` | `Future<GroupResult> Function(String requestId)` | have | `JoinRequestActions.reject` | Toast "<Name> was turned away." |
| `onRetry` | `void Function()` | have | Invalidates `joinRequestsProvider(id)` | |

### Kept inside the screen

The toasts.

### Slots

None.

### The app does this, the prototype does not show it

| What | Where in the app | Suggestion |
|---|---|---|
| A spinner, and "The requests could not be loaded. Only admins can see them." with Retry | `features/groups/presentation/join_requests_screen.dart` | Keep |
| A request another admin already answered: a failure toast, and the list reloads | `JoinRequestActions._answer` | Keep |

### New backend work

None.

## Banned people (`group-banned`)

Dart: `BannedPeopleScreen`, `BannedPeopleModel`, `BannedPeopleActions`.

### Model

| Field | Type | Tag | Comes from today | Notes |
|---|---|---|---|---|
| `status` | `loading`, `failed`, `ready` | have | `bannedViewsProvider(id)` (`group_invites.dart`) | |
| `bans` | `List<PersonEntryView>` | have | `bannedViewsProvider(id)`, over the engine's local `GroupsDao.bans` | Bans made on this device only, as the prototype already says |
| `bans[].avatar.image` | `ImageProvider?` | derive | `PeopleDirectory.imageOf(account)` | |

### Actions

| Action | Signature | Tag | Calls today | Notes |
|---|---|---|---|---|
| `onUnban` | `Future<GroupResult> Function(String account)` | have | `GroupActions.unban`, then invalidate `groupBansProvider(id)` | Toast "<Name> can join again." |
| `onRetry` | `void Function()` | have | Invalidates `groupBansProvider(id)` | |

### Kept inside the screen

The toast.

### Slots

None.

### The app does this, the prototype does not show it

| What | Where in the app | Suggestion |
|---|---|---|
| A spinner, and "The list could not be loaded." with Retry | `features/groups/presentation/banned_members_screen.dart` | Keep |
| An unban that fails says why | `_unban` | Keep |

### New backend work

| Item | Why the design needs it | Engine / server / protocol | Size: S, M, L |
|---|---|---|---|
| Optional: list a group's bans from the server | Only if bans made on other devices should be listed. The design as drawn does not need it | Server: `GET /v1/groups/{id}/bans` (the `bans` table exists); protocol; engine | S |

## Add members (`group-add`)

Dart: `AddMembersScreen`, `AddMembersModel`, `AddMembersActions`.

### Model

| Field | Type | Tag | Comes from today | Notes |
|---|---|---|---|---|
| `picker` | `MemberPickerModel` | have | See the member picker; `exclude` is the current members | |

### Actions

| Action | Signature | Tag | Calls today | Notes |
|---|---|---|---|---|
| `onAdd` | `Future<GroupResult> Function(List<String> accounts)` | have | `GroupActions.addMembers` | `ok`: toast ("Added 2 people." plus a line per person refused), then back. Not `ok`: the "No one was added" dialog with the reasons |
| picker actions | `MemberPickerActions` | have | See the member picker | |

### Kept inside the screen

- The selection (as `AddMembersScreen` keeps it today) and the Add
  spinner.
- The "No one was added" dialog.

### Slots

None.

### The app does this, the prototype does not show it

| What | Where in the app | Suggestion |
|---|---|---|
| A partial add names each person refused: privacy, "<Name> is banned from this group. Unban them first.", "<Name> could not be found.", "<Name> is already in this group." | `GroupActions.addMembers`, `addRejectionText` | Keep, as one toast |
| The page opens for members too when the group lets everyone add | `GroupSnapshot.canAddMembers` | Keep |

### New backend work

None.

## Join a group (`group-join`)

Dart: `JoinGroupScreen`, `JoinGroupModel`, `JoinGroupActions`.

### Model

| Field | Type | Tag | Comes from today | Notes |
|---|---|---|---|---|
| `stage` | `JoinStage`: `input`, `loading`, `preview`, `joining`, `joined`, `pending`, `failed` | have | `joinByLinkProvider` → `JoinState.stage` (`group_invites.dart`) | |
| `initialLink` | `String?` | have | The route's `extra` from a shared link (`routeDeepLink` in `core/router/app_router.dart`) | The page previews it at once |
| `previewName` | `String` | have | `JoinState.preview.name` | Empty when the link did not open the name; drawn as "Group" |
| `previewNameMissing` | `bool` | have | `InvitePreviewInfo.name.isEmpty` | |
| `previewMemberCount` | `int` | have | `InvitePreviewInfo.memberCount` | |
| `previewDescription` | `String?` | have | `InvitePreviewInfo.description` | |
| `previewAvatar` | `HelixAvatarModel` | have | `InvitePreviewInfo.avatarPointer` → `groupPictureProvider` | |
| `requiresApproval` | `bool` | have | `InvitePreviewInfo.requiresApproval` | `group-join-approval`: "Ask to join" |
| `alreadyMember` | `bool` | have | `JoinState.alreadyMember` | `group-join-member` |
| `error` | `String?` | have | `JoinState.error` | `group-join-failed` |

### Actions

| Action | Signature | Tag | Calls today | Notes |
|---|---|---|---|---|
| `onContinue` | `Future<void> Function(String link)` | have | `JoinByLinkController.preview` | Previewing changes nothing on the server |
| `linkLooksRight` | `bool Function(String link)` | derive | `HelixDeepLink` parsing in `core/links/deep_link.dart` (kind `groupLink`) | The prototype checks the link before loading and stays on the field with a toast. Today a wrong link goes to the failed page |
| `onJoin` | `Future<void> Function()` | have | `JoinByLinkController.join` | Joined, or pending for an approval link |
| `onOpenGroup` | `void Function()` | have | `groupChatLocationProvider(groupConversationId(groupId))`, replacing this page; else `GroupPaths.info` | |
| `onRetry` | `void Function()` | have | `JoinByLinkController.reset` | Back to the link field |

### Kept inside the screen

- The link field and Paste (the clipboard, as the kit's paste does).
- The toast "That is not an Orbit group link. Check that you copied all of
  it." when `linkLooksRight` is false.
- Cancel and Done go back (frame).

### Slots

None.

### The app does this, the prototype does not show it

| What | Where in the app | Suggestion |
|---|---|---|
| "This link did not open the group's name. It may be cut off; you can still ask to join." | `features/groups/presentation/join_group_screen.dart` | Add to the design |
| Failure reasons beyond "expired": "This invite link is no longer valid. Ask for a new one.", "You cannot join this group." (banned), "You are already in this group, or already asked to join.", "This group is full: it holds 1,024 people.", offline, too many attempts | `groupErrorText(…, context: GroupContext.link)` | Keep; the failed page shows whichever applies |
| A link opened while signed out waits and opens after sign-in | `pendingLinkProvider` | Keep; nothing to draw |
| The already-a-member check gives up after 2 s and offers Join | `JoinByLinkController._isMember` | Keep |

### New backend work

None.

## Checked and found

| Capability | Found | Where |
|---|---|---|
| Report a person | Yes | `PeopleService.report` over `people.report` |
| Groups in common | Yes | `PeopleGateway.watchCommonGroups` (`people_gateway.dart`) |
| Group picture | Yes, end-to-end encrypted | `group_picture.dart`, `GroupsService.setAvatar` |
| Make owner | Yes; owner only, old owner becomes admin | `GroupActions.setRole`; groups `MODULE.md` |
| Ban and unban | Yes; the list is this device's own | `GroupsService.ban`, `.unban`, `.bans` (local); no server list route |
| Join requests and approval links | Yes | `GroupsPort.joinRequests`, `createInviteLink(requiresApproval:)` |
| Invite links | Yes, but no list after a restart | `GroupInviteState`; no `GET` route in `packages/helix_remote_protocol/lib/src/routes.dart` |
| Disappearing messages, chat and group | Yes; sends a timer notice to the chat | `ChatsService.setDisappearing` (engine `chats_service.dart`) |
| "Who can add me to groups" when creating or adding | Yes; refused people come back without being added | `PeopleApi.mayAddToGroup`; `CreatedGroupInfo.rejected`, `AddMembersOutcome.rejected` |
| They blocked me (ADR-030) | In the engine; the people feature does not read it | `PeopleService.watchBlocksMe`; `peerBlocksMeProvider` (conversation) |
