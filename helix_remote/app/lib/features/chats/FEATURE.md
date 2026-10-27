# chats

The Chats tab: the chat list, its selection mode, the archived list and the
search that finds chats, messages and (through a seam) people.

```
application/
  chat_list_mapper.dart     ConversationListItem -> HelixChatListItem (naming
                            rule, previews, ticks, sender prefix, badges)
  chat_list_provider.dart   chatListProvider, archivedChatListProvider (both
                            StreamProviders over the engine's watchChats),
                            chatTypingProvider (kept apart so typing rebuilds
                            one row, not the list)
  chat_actions.dart         pin / favourite / archive / mute / delete / mark read
  chat_selection.dart       the ticked chats
  chat_search.dart          debounced search: chats by name + FTS messages
presentation/
  chats_tab.dart            the tab (its own Scaffold: selection and search
                            replace the app bar)
  chat_list_view.dart       SliverFixedExtentList rows, swipe actions
                            (start = pin, end = archive), selection bar
  chat_search_view.dart     results; `PeopleSearchBuilder` is the seam
  archived_chats_screen.dart
chats_routes.dart           `/archived-chats`
```

Shared helpers it uses live in `core/chat/` (the gateway, `chat_naming.dart`, `message_semantics.dart`), because the
conversation needs the same ones and features may not import each other.

## Seams

- **People search** (A2b): `ChatsTab(peopleResults: ..., onSearchSubmitted:
  ...)`. The router passes `PeopleSearchPanel(mode: chats, embedded: true)`
  and `PeopleSearchPanel.submit` (the keyboard's search key looks a typed
  number or `~name` up); a tap opens (or starts) the conversation. With
  nothing typed (the search, or the new chat button) the panel shows alone:
  the "Allow contacts" card or "Refresh contacts", and the people on Helix.
- **Menu**: New group and Join a group with a link (`GroupPaths`).
- Naming: `peopleDirectoryProvider` (`core/people/people_names.dart`) is the one source.

## Rules kept

Fixed row extent (`HelixChatListTile.extentFor`), only rows on screen are
built (`test/chat_performance_test.dart`: 5,000 chats), every IconButton has
a tooltip, no colours of its own, plain English literals.

## Favourites

The selection menu's "Add to favourites" / "Remove from favourites" (`ChatActions.favourite` ->
`ChatsService.setFavourite`) flags chats privately (`conversations.favourite_at`, schema 6; never sent). The
list shows a small star on a favourite and has a **Favourites** filter beside All, Unread and Groups.

## Lists

The person's own lists ("Work", "Family") are chips after the built-in filters. They are private
to the device and never sent. `chatListsProvider` and `chatListMembershipProvider` read them
(`ChatsService.watchChatLists`, `watchChatListMembers`); `ChatActions.createList`, `renameList`,
`deleteList` and `setOnList` change them and turn the engine's refusals (a name of 1 to 24
characters, no duplicates, at most ten lists) into the sentence the sheet shows. Selecting chats and
choosing Add to list puts them on a list; touching and holding a chip renames or deletes it (the
chats stay). `HelixChatListItem.copyWith` is how the live bits (typing, lists) are put on a row, so
no field is dropped on the way to the screen. Lists are not in a backup yet.

## Locked chats

A chat can be locked from the selection menu (Lock chat) or its settings. It then leaves the chat
list, the global search, starred messages, the GIF tray and the unread badge (all in the database
queries, not in the screens), and is listed on the Locked chats screen (`/locked-chats`, offered in the
⋮ menu only while some are locked). `core/security/locked_chats.dart` holds the access: it is opened by
the phone's own unlock (`DeviceAuthenticator`), shut again when the app leaves the screen and when the
last screen showing locked content closes. `shared/widgets/locked_chat_gate.dart` wraps every chat
route (the chat, its media, settings, forward, info, shared media), so a notification, a link or a
restored back stack asks for the unlock too. Locking needs a screen lock on the phone; unlocking does
not. The engine marks notices from a locked chat (`IncomingNotice.locked`) and the notification code
then shows no name, text or account label. The flag is kept in a backup. It is an access gate, not
extra encryption (see `PRIVACY_CLAIM_MATRIX.md`).
