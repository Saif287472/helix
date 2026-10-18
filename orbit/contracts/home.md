# Contract: home

Prototype screens: `home` (states: `chats`, `chats-groups`, `chats-unread`, `chats-menu`, `chats-select`, `chats-search`, `chats-search-synced`, `chats-search-q`, `chats-search-num`, `chats-search-short`, `chats-search-none`, `chats-empty`, `calls`, `calls-search`, `calls-empty`), `archived` (states: `archived`, `archived-empty`), `people` (states: `people`)
Today's app: `features/home/presentation/home_screen.dart`, `features/home/application/…`, `features/chats/presentation/…`, `features/chats/application/…`, `features/calls/presentation/calls_tab.dart`, `features/calls/presentation/dial_pad.dart`, `features/calls/application/call_log.dart`, `features/people/presentation/people_search_screen.dart`, `features/people/application/people_search.dart`, `phone_book_sync.dart`, `people_gateway.dart`, `shared/widgets/people_search_panel.dart`, `shared/widgets/phone_book_sync_host.dart`

Paths are under `helix_remote/app/lib/` unless they start with `packages/`
(under `helix_remote/`). Elsewhere:
- the window panes, toasts and Esc: `frame.md`;
- contact info: `people_groups.md`;
- call details and the call screen: `calls.md`;
- the privacy checkup behind the attention dot: `you.md`.

Home is one screen in two parts, the Chats tab and the Calls tab. Both
use the people panel. Each part has its own model and actions, so its
connector can stay in its own feature (features never import each other).

## Shared types

| Type | Tag | Comes from today | Notes |
|---|---|---|---|
| `ListStatus`: `loading`, `failed`, `ready` | have | the `AsyncValue` of each list's provider | One enum for every list on this page |
| `HomeTab`: `chats`, `calls` | derive | `features/home/application/home_tab.dart`, minus `settings` | As in `frame.md` |
| `ChatFilter`: `all`, `unread`, `groups`, with `matches(HelixChatListItem)` | derive | `unreadCount > 0`; `avatar.isGroup`, which `chatAvatarOf` (`core/chat/chat_naming.dart`) sets for every group | Lives in `orbit_ui`. No new field and no engine change (design change 1) |
| `MuteFor`: 8 hours, 1 week, Always | have | `shared/widgets/mute_choice.dart` | As in `people_groups.md` |
| `PeopleSearchMode`: `chats`, `calls` | have | `shared/widgets/people_search_panel.dart` | |
| `HelixChatListItem`, `HelixCallLogItem`, `HelixPersonItem`, `HelixMessageSearchResult`, `HelixAvatarModel` | have | `packages/helix_remote_ui/lib/src/view_models.dart` | One field is added: `HelixPersonItem.verified` (People panel) |

## Home (`home`)

Dart: `HomeScreen`, `HomeModel`, `HomeActions`.

### Model
| Field | Type | Tag | Comes from today | Notes |
|---|---|---|---|---|
| `me` | `HelixAvatarModel` | have | Name: `selfAccountProvider` → `HelixProfileSummary.displayName` (`features/home/application/chat_list_provider.dart`). Picture: `profileAvatarProvider` (`core/platform/profile_image_source.dart`) | The round picture in both tab headers. The same picture and name as You's `avatar` (`you.md`). Today Home does not show it; the Settings tab header does |
| `meNeedsAttention` | `bool` | derive | `YouModel.needsAttention` (`you.md`): any of the five checks is not ok. Inputs: `backupSummaryProvider` (`features/backup/application/backup_providers.dart`), `devicesProvider` (`features/devices/application/devices_providers.dart`), `accountOverviewProvider` (`features/settings/application/account_providers.dart`), `appLockViewProvider` (`features/settings/application/settings_providers.dart`) | The amber dot, and ", privacy checkup needs attention" in the button's label. Home may not import those features, so Part B puts the checkup summary in `core/` and both screens read it |
| `chats` | `ChatsTabModel` | | Chats tab, below | |
| `calls` | `CallsTabModel` | | Calls tab, below | |

### Actions
| Action | Signature | Tag | Calls today | Notes |
|---|---|---|---|---|
| `onOpenYou` | `void Function()` | derive | Today Settings is the third tab (`SettingsTab`, `HomeTab.settings`). `frame.md` adds the You route | Tap the profile picture |
| `onTabChanged` | `void Function(HomeTab tab)` | derive | Today `_HomeScreenState._tab` (`home_screen.dart`) | Tap a dock tab; swipe between tabs. Only the frame listens: on a window it brings back the right pane for that list |

### Kept inside the screen
- The current tab (it starts on Chats), the dock, and the pager swipe
  (phone only). The tab's scroll position survives a switch (today
  `HomeTabKeepAlive`).
- The round button: on Chats it opens the chat search, on Calls the people
  search. It hides while selecting or searching, with the dock.
- The wordmark.

### Slots
None. On a window the chat or the call details opens in the frame's right
pane (`frame.md`). Home only reports which row is open (`openChatId`,
`openCallId`).

### The app does this, the prototype does not show it
| What | Where in the app | Suggestion |
|---|---|---|
| Three tabs, with Settings as the third | `HomeScreen`, `_HomeBar` | Drop (design change 6) |
| Nothing else. The kit's connectivity and update banners (`HelixBannerKind`) and the unread total (`unreadCountProvider`) exist but are not shown | `packages/helix_remote_ui/lib/src/settings_banners.dart`, `features/home/application/chat_list_provider.dart` | Keep them off ("Never draw these" in `SCREENS.md`) |

### New backend work
| Item | Why the design needs it | Engine / server / protocol | Size: S, M, L |
|---|---|---|---|
| None | | | |

## Chats tab (a part of `home`)

Dart: `ChatsTab`, `ChatsTabModel`, `ChatsTabActions`.

### Model
| Field | Type | Tag | Comes from today | Notes |
|---|---|---|---|---|
| `chats` | `List<HelixChatListItem>` | have | `chatListProvider` (`features/chats/application/chat_list_provider.dart`); `typingLabel` from `chatTypingProvider` | Pinned first, then newest (`ConversationsDao.watchList`). Today each row watches its own typing label, so typing never rebuilds 5,000 rows. In Orbit the connector merges them and a row skips its rebuild when its item is equal |
| `status` | `ListStatus` | have | `chatListProvider` | |
| `archivedCount` | `int` | derive | `archivedChatListProvider` length | "Archived chats (N)" in the ⋮ menu (design change 2). Replaces `HelixArchivedRow` |
| `openChatId` | `String?` | have | `ChatsTab._active` (`chats_tab.dart`, widget state today) | Window only: the open chat's row stays marked. The frame owns it in Orbit |
| `search` | `ChatSearchModel` | | below | While the search is open |

`ChatSearchModel`:

| Field | Type | Tag | Comes from today | Notes |
|---|---|---|---|---|
| `query` | `String` | have | `ChatSearchResults.query` (`features/chats/application/chat_search.dart`) | The text these results answer. They arrive 250 ms after typing stops |
| `status` | `ListStatus` | have | `chatSearchResultsProvider` | |
| `chats` | `List<HelixChatListItem>` | have | `ChatSearchResults.chats` | Active and archived chats whose title matches; archived ones show the archive flag |
| `messages` | `List<ChatSearchHit>` (`result`, `chatId`, `messageId`) | have | `ChatSearchResults.messages` → `MessageHit` (`result: HelixMessageSearchResult`, `conversationId`, `messageId`) | The snippet emphasises the match (`HelixHighlightedText`) |
| `people` | `PeoplePanelModel` (mode `chats`) | | People panel, below | Between Chats and Messages |

### Actions
| Action | Signature | Tag | Calls today | Notes |
|---|---|---|---|---|
| `onOpenChat` | `void Function(String chatId, {String? messageId})` | have | `context.push(chatLocation(id, messageId: …))` (`chat_list_view.dart`, `chat_search_view.dart`). On a window, `ChatsTab.detailBuilder` | Tap a chat row; tap a chat or message in the search (it jumps to the message). On a window it opens on the right |
| `onSetPinned` | `Future<void> Function(Set<String> ids, {required bool pinned})` | have | `ChatActions.pin` (`features/chats/application/chat_actions.dart`) | Swipe right; ⋮ Pin or Unpin in the selection bar |
| `onSetArchived` | `Future<void> Function(Set<String> ids, {required bool archived})` | have | `ChatActions.archive` | Swipe left, and Archive in the selection bar. The screen shows "Chat archived" with Undo; Undo calls it again with `archived: false`. Today only the swipe shows the toast |
| `onMute` | `Future<void> Function(Set<String> ids, MuteFor? length)` | have | `ChatActions.mute` | ⋮ Mute in the selection bar. Null unmutes |
| `onMarkRead` | `Future<void> Function(Set<String> ids)` | have | `ChatActions.markRead` | ⋮ Mark as read. Sends read receipts when the setting allows |
| `onDelete` | `Future<void> Function(Set<String> ids)` | have | `ChatActions.delete` | After the screen's dialog |
| `onNewGroup` | `void Function()` | have | `context.push(GroupPaths.create)` (`chats_tab.dart`, `_ChatsMenu.newGroup`) | ⋮ New group; the Groups filter's empty-state button |
| `onJoinGroup` | `void Function()` | have | `context.push(GroupPaths.join)` | ⋮ Join a group with a link |
| `onOpenArchived` | `void Function()` | have | `context.push(ChatRoutes.archived)` (today `HelixArchivedRow.onTap`) | ⋮ Archived chats (N) |
| `onSearchChanged` | `void Function(String text)` | have | `chatSearchQueryProvider.notifier.set` (`chat_search.dart`), and the people panel's `onQueryChanged` | Type in the search. × and ← send `''` |
| `people` | `PeoplePanelActions` | | People panel, below | |

### Kept inside the screen
- **The search:** open or closed, the field and its focus. The round button
  and "Find people" (the empty state) open it. Enter calls
  `people.onLookUp`.
- **Filters:** the chosen chip (it starts on All), the filtering and the
  chip counts, all through `ChatFilter.matches`. The empty states:
  - Unread: "No unread chats".
  - Groups: "No groups yet", with New group (`onNewGroup`).
- **The ⋮ menu:** New group, Join a group with a link, a divider, Archived
  chats (N).
- **Selection:**
  - Long-press or right-click starts it; a tap adds or removes a row; ×
    ends it.
  - The bar: "N selected", Archive, Delete and ⋮. The ⋮ items come from the
    selected items: Pin or Unpin (all pinned); Mute, Unmute or "Mute or
    unmute"; Mark as read (any unread).
  - Today the selection is a global provider (`chatSelectionProvider`)
    shared with Archived chats. In Orbit each screen keeps its own.
- **Swipes:** a 30% threshold; no swipe while selecting.
- **Prompts:** the mute sheet, and the delete dialog ("Delete this chat?" or
  "Delete N chats?").
- **Back:** it closes the selection, then the search, before it leaves the
  app (today `PopScope` in `chats_tab.dart`).

### Slots
None.

### The app does this, the prototype does not show it
| What | Where in the app | Suggestion |
|---|---|---|
| Loading: 8 skeleton rows that announce "Loading chats" | `ChatListStates`, `HelixChatListSkeleton` | Keep, in the new style |
| "Your chats could not be loaded." with Retry | `ChatListStates` | Keep |
| No "No chats yet" while archived chats exist, so the Archived row could stay | `chats_tab.dart` (`hasArchived`) | Decide: the row is now in the menu (open question 1) |
| The search shows a spinner until results arrive, and "The search could not be run." on failure | `chat_search_view.dart` | Keep |
| Archive from the selection bar shows no toast or Undo | `ChatSelectionBar` | Add (the prototype has it) |

### New backend work
| Item | Why the design needs it | Engine / server / protocol | Size: S, M, L |
|---|---|---|---|
| None | Pin, archive, mute, read, delete, filters and search all exist | | |

## Calls tab (a part of `home`)

Dart: `CallsTab`, `CallsTabModel`, `CallsTabActions`.

### Model
| Field | Type | Tag | Comes from today | Notes |
|---|---|---|---|---|
| `calls` | `List<HelixCallLogItem>` | have | `callLogProvider` → `CallLogEntry.item` (`features/calls/application/call_log.dart`) | One row per person, direction and day, with "(N)". `id` is the newest call. The connector keeps each `CallLogEntry` to find its `peer` and `callIds` |
| `calls[].avatar.image` | `ImageProvider?` | derive | `PeopleDirectory.avatarOf(entry.peer)` (`core/people/people_names.dart`) | Today `buildCallLog` draws initials only |
| `status` | `ListStatus` | have | `callLogProvider` | |
| `quick` | `List<QuickPerson>` (`peerId`, `label`, `name`, `avatar`) | derive | `_QuickActions._recent` in `calls_tab.dart`: the two most recent different peers in `callLogProvider`. Picture from `PeopleDirectory.avatarOf` | The logic is in `presentation/` today; Part B moves it to `application/`. Today the bubbles show a person icon. `label` is the first name |
| `openCallId` | `String?` | derive | Nothing today: call details is a full page | Window only: the open row stays marked (`frame.md`) |
| `search` | `PeoplePanelModel` (mode `calls`) | | People panel, below | |

### Actions
| Action | Signature | Tag | Calls today | Notes |
|---|---|---|---|---|
| `onOpenCall` | `void Function(String callId)` | have | `context.push(CallRoutes.detail(id))` (`calls_tab.dart`) | Tap a call row |
| `onCallBack` | `Future<String?> Function(String callId)` | have | `CallLogActions.callBack(entry.peer, video: entry.video)` → `PlaceCallOutcome` | The call icon on a row calls back the same way. Null when the call started; otherwise the sentence for a toast (`outcome.message`, else "The call could not be placed.") |
| `onCall` | `Future<String?> Function(String peerId, {required bool video})` | have | `CallLogActions.callBack(peer, video: …)` | Voice call and Video call in the row's sheet; a person in the quick row (voice) |
| `onDeleteCalls` | `Future<void> Function(String callId)` | have | `CallLogActions.delete(entry.callIds)` | After the screen's dialog, from the sheet or a left swipe. A folded row deletes all its calls |
| `search` | `PeoplePanelActions` | | People panel, below | |

### Kept inside the screen
- **The search:** open or closed, the field ("Search people") and its focus.
  The round button and the quick row's Call open it.
- **The row sheet:** long-press or right-click. Its title is the name; it
  holds Voice call, Video call, and Delete from call history.
- **The delete dialog:** "Delete from call history?", then "This call with
  <name> will be removed…", or "These N calls with <name>…" when
  `HelixCallLogItem.count` is more than 1. A left swipe asks the same.
- **The dial pad,** opened by the quick row's Keypad:
  - Digits, ⌫ ("Delete digit"), and a long-press on 0 for +; a haptic tick
    on each key.
  - The button turns on at 6 digits. It closes the pad, opens the people
    search and passes the number to `search.onQueryChanged`.
  - It never places a call.

### Slots
None.

### The app does this, the prototype does not show it
| What | Where in the app | Suggestion |
|---|---|---|
| Loading skeleton; "Your calls could not be loaded." with Retry | `_CallList` | Keep |
| A call that does not start shows a toast: the reason from `PlaceCallOutcome.message`, else "The call could not be placed." | `_CallsTabScreenState._call` | Keep (the reasons are listed in `calls.md`) |
| On the dial pad, a screen reader hears "0, hold for plus", and the typed number is a live region | `dial_pad.dart` | Keep |

### New backend work
| Item | Why the design needs it | Engine / server / protocol | Size: S, M, L |
|---|---|---|---|
| None | The call log, call-back and delete all exist (`CallsPort.watchLog`, `forget`, `startCallProvider`) | | |

## People panel (a part of `home` and `people`)

Dart: `PeoplePanel`, `PeoplePanelModel`, `PeoplePanelActions`.

It sits in the Chats search (mode `chats`, drawn inside that list), the
Calls search (mode `calls`) and the People page. Each host keeps its own
text.

### Model
| Field | Type | Tag | Comes from today | Notes |
|---|---|---|---|---|
| `query` | `String` | derive | `PeopleQuery.parse(text).raw` (`features/people/application/people_search.dart`) | The text this model answers |
| `mode` | `PeopleSearchMode` | have | `PeopleSearchPanel.mode` | `chats`: a tap opens the chat. `calls`: a tap calls, and each row adds voice and video buttons |
| `status` | `ListStatus` | have | `peopleSearchProvider(text)` | |
| `contacts` | `ContactsCard`: `hidden`, `ask`, `openSettings`, `refresh` | have | `contactsPermissionProvider` → `ContactsPermission` (`phone_book_sync.dart`, `core/platform/contacts_access.dart`). `unsupported` gives `hidden`; `notAsked` or `denied` gives `ask`; `permanentlyDenied` gives `openSettings`; `granted` gives `refresh` | Only with nothing typed. Windows is `unsupported`: no card and no Refresh row |
| `refresh` | `PhoneBookStatus`, plus `found` (`int`) | have | `phoneBookSyncProvider` → `PhoneBookSyncState.status`, `.found` | The Refresh row's subtitle. Not tappable while checking |
| `lookupPrompt` | `LookupPrompt`: `none`, `needFullNumber`, `findNumber(String shown)`, `findName(String name)` | have | `PeopleQuery.parse(text, callingCode: ownCallingCodeProvider)` → `intent`, `e164`, `helixName`, `canLookUp`; `PhoneNumbers.display(e164)` (`core/platform/phone_numbers.dart`) | See "Copy that differs in meaning" |
| `lookup` | `LookupView`: `idle`, `searching`, `found(HelixPersonItem)`, `notFound`, `self`, `rateLimited`, `offline`, `failed` | have | `peopleLookupProvider` → `LookupState.status`, `.failure` (`PeopleFailure`, `people_failures.dart`). It is `idle` unless `LookupState.answers(parsed)` | `found` is not drawn when that person is already in `people` |
| `groups` | `List<PanelGroup>` (`groupId`, `chatId`, `title`, `avatar`) | have | `peopleSearchProvider(text).groups` → `GroupSummary` (`people_gateway.dart`) | Text searches only. The avatar is built as `chatAvatarOf` builds a group's |
| `people` | `List<HelixPersonItem>` | have | `peopleSearchProvider(text).people` → `PersonName.toItem()` (`core/people/people_names.dart`) | Never blocked people or yourself. With nothing typed: everyone with a phone-book name, nickname or profile name |
| `HelixPersonItem.verified` | `bool`, new field, default `false` | derive | `PersonName.verified` | The seal after the name |
| `peopleLabel` | `String` | derive | `PeopleQuery.isBrowse`: "People on Helix" when browsing, else "People". The count is `people.length` | |
| `empty` | `PanelEmpty`: `none`, `nobodyYet`, `noMatches` | derive | `PeopleSearchResults.isEmpty` and no found lookup (`people_search_panel.dart`) | |

### Actions
| Action | Signature | Tag | Calls today | Notes |
|---|---|---|---|---|
| `onQueryChanged` | `void Function(String text)` | have | Today the host passes its text as `PeopleSearchPanel(query: …)`, which watches `peopleSearchProvider(text)` | Typing; the dial pad's number |
| `onLookUp` | `void Function()` | have | `PeopleSearchPanel.submit(ref, text)` → `peopleLookupProvider.notifier.lookUp(PeopleQuery.parse(…))`; the Find row calls `lookUp` | Enter in the search; tap "Find … on Helix". The only network lookup: each number spends one unit of the daily budget |
| `onAllowContacts` | `Future<void> Function()` | have | `contactsPermissionProvider.notifier.request()` | The system dialog; when granted, it syncs at once |
| `onOpenContactsSettings` | `Future<void> Function()` | have | `contactsPermissionProvider.notifier.openSettings()` | "Open settings" on the card |
| `onRefreshContacts` | `Future<void> Function()` | have | `phoneBookSyncProvider.notifier.syncNow()` | |
| `onOpenPerson` | `Future<String?> Function(String accountId)` | have | `chats`: `PeopleActions.openChat` (it creates the chat when there is none). `calls`: `PeopleActions.startCall(id, video: false)` | Tap a person. Returns a sentence for a toast when a call does not start |
| `onCallPerson` | `Future<String?> Function(String accountId, {required bool video})` | have | `PeopleActions.startCall` → `ConversationSeams.startCall` → `placeCallProvider` | The voice and video buttons (mode `calls`) |
| `onOpenContactInfo` | `void Function(String accountId)` | have | `context.push(PeoplePaths.person(id))` (`PersonResultTile.onLongPress`) | Long-press a person |
| `onOpenGroup` | `void Function(String groupId)` | have | `PeopleActions.openGroup(GroupSummary)` | Tap a group |

### Kept inside the screen
- The order of the rows: the card or Refresh row, the lookup prompt or
  result, Groups, People, the empty notice.
- The subtitle sentences for each `refresh` and `lookup` value.

### Slots
None.

### The app does this, the prototype does not show it
| What | Where in the app | Suggestion |
|---|---|---|
| "Nobody yet" / "Type a phone number or a ~Helix name to find someone." when you know nobody | `_RowView`, `_Kind.empty` | Add to the design |
| The Refresh row says "Your contacts could not be checked. Helix will try again later." after a failure | `_RefreshTile` | Add (`SCREENS.md` lists it; no prototype state draws it) |
| A lookup that fails for another reason: "Could not look this up" / "Something went wrong. Try again in a moment." | `_LookupResult` | Add |
| Alone (Calls search, People page): skeleton rows while loading, and "People could not be loaded. Open the app again to try." Inside the Chats search: nothing | `PeopleSearchPanel` (`embedded`) | Keep |
| The Find row stays above the lookup result. The prototype puts the result in its place | `PeopleSearchPanel.build` | The prototype's (style) |
| Contacts sync runs by itself: at sign-in, on resume, hourly, and 30 s after the address book changes. It runs at most every 12 h (1 h after a change), and not again on a day the budget ran short. It never asks for permission; its only visible trace is the Refresh row | `PhoneBookSyncHost`, `PhoneBookSyncController.syncIfDue` | Keep; nothing to draw |
| The permission is read again on resume, after the system settings | `PhoneBookSyncHost._sync` → `ContactsPermissionController.refresh` | Keep |

### New backend work
| Item | Why the design needs it | Engine / server / protocol | Size: S, M, L |
|---|---|---|---|
| None | Search, lookup and contact matching all exist (`PeopleGateway.findByNumber`, `findByHelixName`, `syncPhoneBook`) | | |

## Archived chats (`archived`)

Dart: `ArchivedChatsScreen`, `ArchivedChatsModel`, `ArchivedChatsActions`.

### Model
| Field | Type | Tag | Comes from today | Notes |
|---|---|---|---|---|
| `chats` | `List<HelixChatListItem>` | have | `archivedChatListProvider` (`chat_list_provider.dart`), with `chatTypingProvider` | Empty: "No archived chats" |
| `status` | `ListStatus` | have | `archivedChatListProvider` | |
| `openChatId` | `String?` | derive | Nothing today | Window only: Archived sits in the list pane (`frame.md`) |

### Actions
| Action | Signature | Tag | Calls today | Notes |
|---|---|---|---|---|
| `onOpenChat` | `void Function(String chatId)` | have | `context.push(chatLocation(id))` (`chat_list_view.dart`) | Tap a row |
| `onSetArchived` | `Future<void> Function(Set<String> ids, {required bool archived})` | have | `ChatActions.archive` | Swipe left, and Unarchive in the selection bar, with `archived: false`. The screen shows "Chat unarchived" with Undo (`archived: true`). Today only the swipe shows the toast |
| `onMute` | `Future<void> Function(Set<String> ids, MuteFor? length)` | have | `ChatActions.mute` | ⋮ in the selection bar |
| `onMarkRead` | `Future<void> Function(Set<String> ids)` | have | `ChatActions.markRead` | ⋮ in the selection bar |
| `onDelete` | `Future<void> Function(Set<String> ids)` | have | `ChatActions.delete` | After the screen's dialog |

### Kept inside the screen
- Selection, as on the Chats tab. The bar holds Unarchive chats, Delete
  chats and ⋮ (Mute, Mark as read). It has no Pin.
- The swipe goes left only (Unarchive).
- The mute sheet and the delete dialog.
- Back closes the selection first.

### Slots
None.

### The app does this, the prototype does not show it
| What | Where in the app | Suggestion |
|---|---|---|
| Loading skeleton; "Your chats could not be loaded." with Retry. Its Retry reloads the active list (`chatListProvider`), not the archived one | `ChatListStates` | Keep, and Part B retries `archivedChatListProvider` |
| The ⋮ menu shows "Mark as read" only when a selected chat is unread, and Mute, Unmute or "Mute or unmute" to match the selection. The prototype always shows "Mute…" and "Mark as read" | `ChatSelectionBar(archivedList: true)` | The app's |
| Unarchive from the selection bar shows no toast or Undo | `ChatSelectionBar` | Add (the prototype has it) |

### New backend work
| Item | Why the design needs it | Engine / server / protocol | Size: S, M, L |
|---|---|---|---|
| None | | | |

## People (`people`)

Dart: `PeopleSearchScreen`, `PeopleSearchModel`, `PeopleSearchActions`.
The app's screen of the same name is replaced.

### Model
| Field | Type | Tag | Comes from today | Notes |
|---|---|---|---|---|
| `panel` | `PeoplePanelModel` | have | `PeopleSearchScreen` → `PeopleSearchPanel(mode: …)` (`features/people/presentation/people_search_screen.dart`) | The mode comes from the route: `PeoplePaths.home` is `chats`; `PeoplePaths.search?mode=calls` is `calls` |

### Actions
| Action | Signature | Tag | Calls today | Notes |
|---|---|---|---|---|
| `panel` | `PeoplePanelActions` | have | People panel | Type in the search (`onQueryChanged`); tap a person (`onOpenPerson`) |

### Kept inside the screen
- The field "Name, number or ~Helix name", focused on open. Enter calls
  `onLookUp`.

### Slots
None.

### The app does this, the prototype does not show it
| What | Where in the app | Suggestion |
|---|---|---|
| The page is the whole panel: the contacts card, the lookup and groups. The prototype draws only the people and "No matches" | `PeopleSearchScreen` | Keep the app's: it is the same component as in the tabs |
| A `helix://contact/add?…` link opens this page empty. The link's account (`contactAccountId`) is parsed but never used, and nothing says why | `routeDeepLink` (`core/router/app_router.dart`), `HelixDeepLink` (`core/links/deep_link.dart`) | Open question 5 |
| The calls-mode route `/home/people/search?mode=calls` exists, but nothing opens it | `people_routes.dart` | Drop it, or leave it unused |

### New backend work
| Item | Why the design needs it | Engine / server / protocol | Size: S, M, L |
|---|---|---|---|
| None | | | |

## On a window (Home only)

| Behaviour | Today | Orbit |
|---|---|---|
| No swipe between tabs; the dock switches | `HomeScreen` uses an `IndexedStack` from 840 px | The same |
| A chat row opens the chat on the right and stays marked | `ChatsTab` two-pane, `activeChatId` | The same, through the frame |
| A call row opens call details on the right and stays marked | A full page | New: `openCallId` |
| A chat or message from the search, or a person's chat, opens on the right | A full page (`context.push`, `RouterConversationSeams.openChat`) | Route them through the frame |
| Archived chats replaces Home in the list pane | A full page | `frame.md` |
| Right-click starts a selection (chat row) or opens the sheet (call row) | No right-click; long-press only | Add; kept inside the screens |
| No contacts card and no Refresh row | `ContactsPermission.unsupported` on Windows | Keep. The prototype draws the card on a window |

## Copy that differs in meaning

| Where | Prototype | App | Suggestion |
|---|---|---|---|
| The contacts card | "…compares scrambled versions… Your contacts never leave your phone." | Also says "and you can still message anyone by their number or ~Helix name." | Keep the app's last clause |
| A number without a country code (`chats-search-short`) | Always the hint: type the whole number with the country code | Reads a leading 0 in your own number's country (`PhoneNumbers.normalize`, `guessNational`) and offers "Find +880 1711000002 on Helix". The hint shows only when that fails (no own number, or not a valid number) | Open question 3 |
| A plain word of 3 or more letters, such as "arif" | No lookup row | Also offers "Find ~arif on Helix" when the word could be a ~name | Open question 4 |
| `~` with any text | "Find ~x on Orbit" | Only for a valid name (`SetHelixNameRequest.pattern`: a letter, then 2 to 31 of a–z, 0–9, `_` or `.`) | The app's |
| Blocked people in the search | Listed, with "Blocked" in red | Never listed (`searchPeople` leaves them out) | Open question 2 |
| Archive or Unarchive of several chats | "Chat archived" / "Chat unarchived" | No toast | "N chats archived" / "N chats unarchived" when N is more than 1 |
| The ~name Find row | Subtitle "Looks up this ~Orbit name once." | No subtitle | The prototype's |

## Open questions for the product owner

1. **Everything archived.** What does the Chats tab show when every chat
   is archived? Today it hides "No chats yet" so the Archived row can
   stay, but that row is now in the ⋮ menu.
2. **Blocked people in search.** List them with "Blocked" (prototype), or
   leave them out (app)?
3. **Numbers without a country code.** Keep the app's rule (read in your
   own country), or require the country code (prototype)?
4. **Plain words.** Should "arif" also offer a ~name lookup, as the app
   does?
5. **Contact links.** Should `helix://contact/add` open that person,
   instead of an empty people search?
6. **The filter.** Should the chosen chip (All, Unread, Groups) be
   remembered after the app closes? This contract keeps it for the visit
   only.
