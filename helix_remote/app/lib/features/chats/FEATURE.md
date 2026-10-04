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
  chat_actions.dart         pin / archive / mute / delete / mark read
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

Shared helpers it uses live in `core/chat/` (the gateway, `ChatPeople`
naming, `chat_naming.dart`, `message_semantics.dart`), because the
conversation needs the same ones and features may not import each other.

## Seams

- **People search** (A2b): `ChatsTab(peopleResults: (context, query) => ...)`.
  The router passes it in `app_router.dart`; the widget must not scroll.
- Naming: `chatPeopleProvider` (`core/chat/chat_people.dart`) is the only
  adapter onto the people table; the people feature's helper replaces it by
  replacing that provider.

## Rules kept

Fixed row extent (`HelixChatListTile.extentFor`), only rows on screen are
built (`test/chat_performance_test.dart`: 5,000 chats), every IconButton has
a tooltip, no colours of its own, plain English literals.
