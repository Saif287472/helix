import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:helix_remote/core/people/people_names.dart';
import 'package:helix_remote/core/router/app_router.dart';
import 'package:helix_remote/core/platform/profile_image_source.dart';
import 'package:helix_remote/features/calls/application/call_log.dart';
import 'package:helix_remote/features/calls/calls_routes.dart';
import 'package:helix_remote/features/chats/application/chat_actions.dart';
import 'package:helix_remote/features/chats/application/chat_list_provider.dart';
import 'package:helix_remote/features/chats/application/chat_search.dart';
import 'package:helix_remote/features/home/application/chat_list_provider.dart'
    as home_providers;
import 'package:helix_remote/features/people/application/people_gateway.dart';
import 'package:helix_remote/features/people/application/people_search.dart';
import 'package:helix_remote/features/people/application/phone_book_sync.dart';
import 'package:helix_remote/shared/navigation/chat_locations.dart';
import 'package:helix_remote/shared/navigation/group_paths.dart';
import 'package:helix_remote/shared/navigation/people_paths.dart';
import 'package:helix_remote/shared/widgets/mute_choice.dart' as app_mute;
import 'package:helix_remote/shared/you_checkup.dart';
import 'package:helix_remote/shared/widgets/orbit_people_panel.dart';
import 'package:orbit_ui/orbit_ui.dart' hide PhoneBookStatus;

/// Connector: watches the app's providers and draws `orbit_ui`'s `HomeScreen`.
class OrbitHomeConnector extends ConsumerStatefulWidget {
  const OrbitHomeConnector({super.key});

  @override
  ConsumerState<OrbitHomeConnector> createState() => _OrbitHomeConnectorState();
}

class _OrbitHomeConnectorState extends ConsumerState<OrbitHomeConnector> {
  String _callQuery = '';

  @override
  Widget build(BuildContext context) {
    final self = ref.watch(home_providers.selfAccountProvider).asData?.value;
    final avatarBytes = ref.watch(profileAvatarProvider).asData?.value;
    final me = HelixAvatarModel(
      name: (self == null || self.displayName.isEmpty)
          ? 'Orbit'
          : self.displayName,
      image: avatarBytes == null ? null : MemoryImage(avatarBytes),
      colorIndex: HelixAvatarModel.colorIndexFor(
        (self?.accountId ?? '').isEmpty ? 'helix' : self!.accountId,
      ),
    );

    // ---- chats
    final chatListAsync = ref.watch(chatListProvider);
    final archivedAsync = ref.watch(archivedChatListProvider);
    final typing = ref.watch(chatTypingProvider).asData?.value ?? const {};
    final rawChats = chatListAsync.value ?? const <HelixChatListItem>[];
    final lists = ref.watch(chatListsProvider).asData?.value ?? const [];
    final onLists =
        ref.watch(chatListMembershipProvider).asData?.value ?? const {};
    final chats = [
      for (final c in rawChats)
        c.copyWith(typingLabel: typing[c.id], lists: onLists[c.id]),
    ];
    final chatStatus = chatListAsync.isLoading
        ? ListStatus.loading
        : chatListAsync.hasError
        ? ListStatus.failed
        : ListStatus.ready;
    final archivedCount = archivedAsync.value?.length ?? 0;

    final searchQuery = ref.watch(chatSearchQueryProvider);
    final AsyncValue<ChatSearchResults> searchResultsAsync = ref.watch(
      chatSearchResultsProvider,
    );
    final searchStatus = searchResultsAsync.isLoading
        ? ListStatus.loading
        : searchResultsAsync.hasError
        ? ListStatus.failed
        : ListStatus.ready;
    final ChatSearchResults? searchResults = searchResultsAsync.value;
    final searchChats = searchResults?.chats ?? const <HelixChatListItem>[];
    final searchMessages = [
      for (final h in searchResults?.messages ?? const <MessageHit>[])
        ChatSearchHit(
          chatId: h.conversationId,
          messageId: h.messageId,
          title: h.result.chatTitle,
          avatar: h.result.avatar,
          timeLabel: h.result.timeLabel,
          who: h.result.senderLabel ?? '',
          text: h.result.snippet,
        ),
    ];
    final chatSearch = ChatSearchModel(
      query: searchResults?.query ?? searchQuery,
      status: searchStatus,
      chats: searchChats,
      messages: searchMessages,
      people: orbitPeoplePanelModel(ref, searchQuery, PeopleSearchMode.chats),
    );

    // ---- calls
    final callEntries = ref.watch(callLogProvider).asData?.value ?? const [];
    final peopleDir =
        ref.watch(peopleDirectoryProvider).asData?.value ??
        PeopleDirectory.empty;
    final calls = [
      for (final e in callEntries)
        HelixCallLogItem(
          id: e.item.id,
          title: e.item.title,
          avatar: peopleDir.avatarOf(e.peer),
          direction: e.item.direction,
          timeLabel: e.item.timeLabel,
          video: e.item.video,
          count: e.item.count,
          isGroup: e.item.isGroup,
          durationLabel: e.item.durationLabel,
        ),
    ];
    final callStatus = ref.watch(callLogProvider).isLoading
        ? ListStatus.loading
        : ref.watch(callLogProvider).hasError
        ? ListStatus.failed
        : ListStatus.ready;
    final quick = <QuickPerson>[];
    final seenPeers = <String>{};
    for (final e in callEntries) {
      if (seenPeers.add(e.peer)) {
        quick.add(
          QuickPerson(
            peerId: e.peer,
            label: e.item.title.split(' ').first,
            avatar: peopleDir.avatarOf(e.peer),
          ),
        );
        if (quick.length >= 2) break;
      }
    }
    final callsSearch = orbitPeoplePanelModel(
      ref,
      _callQuery,
      PeopleSearchMode.calls,
    );
    final callsTab = CallsTabModel(
      calls: calls,
      status: callStatus,
      quick: quick,
      search: callsSearch,
    );

    final chatsTab = ChatsTabModel(
      chats: chats,
      status: chatStatus,
      archivedCount: archivedCount,
      search: chatSearch,
      lists: lists,
    );

    final model = HomeModel(
      me: me,
      meNeedsAttention: ref.watch(youNeedsAttentionProvider),
      chats: chatsTab,
      calls: callsTab,
    );

    final chatActions = ref.read(chatActionsProvider);
    final callActions = ref.read(callLogActionsProvider);
    final peopleActions = ref.read(peopleActionsProvider);

    Future<String?> openPersonChat(String id) async {
      await peopleActions.openChat(id);
      return null;
    }

    /// Runs an action whose answer is one sentence to read, and reads it here:
    /// `HomeScreen` draws no toast for these.
    Future<String?> tell(Future<String?> Function() run) async {
      final message = await run();
      if (message != null && context.mounted) showOrbitToast(context, message);
      return null;
    }

    Future<String?> callPerson(String id, {required bool video}) =>
        tell(() => peopleActions.startCall(id, video: video));

    final actions = HomeActions(
      onOpenYou: () => context.push(AppRoutes.settings),
      onTabChanged: (_) {},
      onOpenChat: (id, {messageId}) {
        context.push(chatLocation(id, messageId: messageId));
      },
      onSetPinned: (ids, {required pinned}) =>
          chatActions.pin(ids, pinned: pinned),
      onSetFavourite: (ids, {required favourite}) =>
          chatActions.favourite(ids, favourite: favourite),
      onCreateList: chatActions.createList,
      onRenameList: chatActions.renameList,
      onDeleteList: chatActions.deleteList,
      onSetOnList: (ids, listId, {required member}) =>
          chatActions.setOnList(ids, listId, member: member),
      onSetArchived: (ids, {required archived}) =>
          chatActions.archive(ids, archived: archived),
      onMute: (ids, length) => chatActions.mute(ids, _mapMute(length)),
      onMarkRead: (ids) => chatActions.markRead(ids),
      onDelete: (ids) => chatActions.delete(ids),
      onNewGroup: () => context.push(GroupPaths.create),
      onJoinGroup: () => context.push(GroupPaths.join),
      onOpenArchived: () => context.push('/archived-chats'),
      onSearchChanged: (text) =>
          ref.read(chatSearchQueryProvider.notifier).set(text),
      onOpenCall: (id) => context.push(CallRoutes.detail(id)),
      onCallBack: (id) => tell(() async {
        // Never fall back to another row: that would call the wrong person.
        final entry = callEntries.where((e) => e.id == id).firstOrNull;
        if (entry == null) return 'That call is no longer in the list.';
        final outcome = await callActions.callBack(
          entry.peer,
          video: entry.video,
        );
        return outcome.started
            ? null
            : (outcome.message ?? 'The call could not be placed.');
      }),
      onCall: (peerId, {required video}) =>
          tell(() => peopleActions.startCall(peerId, video: video)),
      onDeleteCalls: (id) async {
        final entry = callEntries.firstWhere(
          (e) => e.id == id,
          orElse: () => callEntries.first,
        );
        await callActions.delete(entry.callIds);
      },
      onCallSearchChanged: (text) => setState(() => _callQuery = text),
      people: PeoplePanelActions(
        onQueryChanged: (text) =>
            ref.read(chatSearchQueryProvider.notifier).set(text),
        onLookUp: () {
          final parsed = PeopleQuery.parse(
            searchQuery,
            callingCode: ref.read(ownCallingCodeProvider).asData?.value,
          );
          ref.read(peopleLookupProvider.notifier).lookUp(parsed);
        },
        onAllowContacts: () =>
            ref.read(contactsPermissionProvider.notifier).request(),
        onOpenContactsSettings: () =>
            ref.read(contactsPermissionProvider.notifier).openSettings(),
        onRefreshContacts: () =>
            ref.read(phoneBookSyncProvider.notifier).syncNow(),
        onOpenPerson: openPersonChat,
        onCallPerson: callPerson,
        onOpenContactInfo: (id) => context.push(PeoplePaths.person(id)),
        onOpenGroup: (gid) =>
            peopleActions.openGroup(GroupSummary(id: gid, title: '')),
        onOpenSelf: (id) => unawaited(peopleActions.openChat(id)),
      ),
      peopleCalls: PeoplePanelActions(
        onQueryChanged: (text) => setState(() => _callQuery = text),
        onLookUp: () {},
        onAllowContacts: () =>
            ref.read(contactsPermissionProvider.notifier).request(),
        onOpenContactsSettings: () =>
            ref.read(contactsPermissionProvider.notifier).openSettings(),
        onRefreshContacts: () =>
            ref.read(phoneBookSyncProvider.notifier).syncNow(),
        onOpenPerson: (id) => callPerson(id, video: false),
        onCallPerson: callPerson,
        onOpenContactInfo: (id) => context.push(PeoplePaths.person(id)),
        onOpenGroup: (gid) =>
            peopleActions.openGroup(GroupSummary(id: gid, title: '')),
      ),
    );

    // calls search uses its own text; wire onCallSearchChanged to people query
    // (no separate provider; keep local via setState not possible here, so skip)

    return HomeScreen(model: model, actions: actions);
  }
}

app_mute.MuteFor? _mapMute(MuteFor? length) {
  if (length == null) return null;
  switch (length) {
    case MuteFor.eightHours:
      return app_mute.MuteFor.eightHours;
    case MuteFor.week:
      return app_mute.MuteFor.oneWeek;
    case MuteFor.always:
      return app_mute.MuteFor.always;
  }
}
