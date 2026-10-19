import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:helix_remote/core/engine/runtime_providers.dart';
import 'package:helix_remote/core/people/people_names.dart';
import 'package:helix_remote/core/platform/contacts_access.dart';
import 'package:helix_remote/core/platform/phone_numbers.dart';
import 'package:helix_remote/core/platform/profile_image_source.dart';
import 'package:helix_remote/features/calls/application/call_log.dart';
import 'package:helix_remote/features/calls/calls_routes.dart';
import 'package:helix_remote/features/chats/application/chat_actions.dart';
import 'package:helix_remote/features/chats/application/chat_list_provider.dart';
import 'package:helix_remote/features/chats/application/chat_search.dart';
import 'package:helix_remote/features/home/application/chat_list_provider.dart'
    as home_providers;
import 'package:helix_remote/features/people/application/people_failures.dart';
import 'package:helix_remote/features/people/application/people_gateway.dart';
import 'package:helix_remote/features/people/application/people_search.dart';
import 'package:helix_remote/features/people/application/phone_book_sync.dart';
import 'package:helix_remote/shared/navigation/chat_locations.dart';
import 'package:helix_remote/shared/navigation/group_paths.dart';
import 'package:helix_remote/shared/navigation/people_paths.dart';
import 'package:helix_remote/shared/widgets/mute_choice.dart' as app_mute;
import 'package:orbit_ui/orbit_ui.dart' hide PhoneBookStatus;
import 'package:orbit_ui/orbit_ui.dart' as orbit;

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
    final runtimeAsync = ref.watch(runtimeProvider);
    if (runtimeAsync.isLoading || runtimeAsync.hasError) {
      return const orbit.HomeScreen(
        model: HomeModel(me: HelixAvatarModel(name: 'Helix')),
        actions: HomeActions(),
      );
    }
    final self = ref.watch(home_providers.selfAccountProvider).value;
    final avatarBytes = ref.watch(profileAvatarProvider).value;
    final me = HelixAvatarModel(
      name: (self == null || self.displayName.isEmpty)
          ? 'Helix'
          : self.displayName,
      image: avatarBytes == null ? null : MemoryImage(avatarBytes),
      colorIndex: HelixAvatarModel.colorIndexFor(
        (self?.accountId ?? '').isEmpty ? 'helix' : self!.accountId,
      ),
    );

    // ---- chats
    final chatListAsync = ref.watch(chatListProvider);
    final archivedAsync = ref.watch(archivedChatListProvider);
    final typing = ref.watch(chatTypingProvider).value ?? const {};
    final rawChats = chatListAsync.value ?? const <HelixChatListItem>[];
    final chats = [
      for (final c in rawChats)
        HelixChatListItem(
          id: c.id,
          title: c.title,
          avatar: c.avatar,
          preview: c.preview,
          timeLabel: c.timeLabel,
          unreadCount: c.unreadCount,
          hasMention: c.hasMention,
          markedUnread: c.markedUnread,
          pinned: c.pinned,
          muted: c.muted,
          archived: c.archived,
          typingLabel: typing[c.id] ?? c.typingLabel,
          online: c.online,
          verified: c.verified,
        ),
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
      people: _peoplePanel(
        ref,
        searchQuery,
        PeopleSearchMode.chats,
        contactPermission: true,
      ),
    );

    // ---- calls
    final callEntries = ref.watch(callLogProvider).value ?? const [];
    final peopleDir =
        ref.watch(peopleDirectoryProvider).value ?? PeopleDirectory.empty;
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
    final callsSearch = _peoplePanel(
      ref,
      _callQuery,
      PeopleSearchMode.calls,
      contactPermission: true,
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
    );

    final model = HomeModel(
      me: me,
      meNeedsAttention: false,
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

    Future<String?> callPerson(String id, {required bool video}) =>
        peopleActions.startCall(id, video: video);

    final actions = HomeActions(
      onOpenYou: () => context.push('/settings'),
      onTabChanged: (_) {},
      onOpenChat: (id, {messageId}) {
        context.push(chatLocation(id, messageId: messageId));
      },
      onSetPinned: (ids, {required pinned}) =>
          chatActions.pin(ids, pinned: pinned),
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
      onCallBack: (id) async {
        final entry = callEntries.firstWhere(
          (e) => e.id == id,
          orElse: () => callEntries.first,
        );
        final outcome = await callActions.callBack(
          entry.peer,
          video: entry.video,
        );
        return outcome.started
            ? null
            : (outcome.message ?? 'The call could not be placed.');
      },
      onCall: (peerId, {required video}) async {
        return peopleActions.startCall(peerId, video: video);
      },
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
            callingCode: ref.read(ownCallingCodeProvider).value,
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
        onOpenPerson: (id) async {
          return peopleActions.startCall(id, video: false);
        },
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

  PeoplePanelModel _peoplePanel(
    WidgetRef ref,
    String text,
    PeopleSearchMode mode, {
    required bool contactPermission,
  }) {
    final query = PeopleQuery.parse(
      text,
      callingCode: ref.read(ownCallingCodeProvider).value,
    );
    final resultsAsync = ref.watch(peopleSearchProvider(text));
    final results = resultsAsync.value;
    final permission = ref.watch(contactsPermissionProvider).value;
    final sync = ref.watch(phoneBookSyncProvider);
    final lookupState = ref.watch(peopleLookupProvider);

    ContactsCard contactsCard;
    if (permission == null ||
        permission == ContactsPermission.unsupported ||
        permission == ContactsPermission.granted) {
      contactsCard = permission == ContactsPermission.granted
          ? ContactsCard.refresh
          : ContactsCard.hidden;
    } else if (permission == ContactsPermission.permanentlyDenied) {
      contactsCard = ContactsCard.openSettings;
    } else {
      contactsCard = ContactsCard.ask;
    }
    if (permission == ContactsPermission.granted) {
      contactsCard = ContactsCard.refresh;
    }
    if (permission != ContactsPermission.granted &&
        permission != ContactsPermission.permanentlyDenied &&
        permission != ContactsPermission.denied &&
        permission != ContactsPermission.notAsked) {
      contactsCard = ContactsCard.hidden;
    }

    orbit.PhoneBookStatus refreshStatus;
    switch (sync.status) {
      case PhoneBookStatus.syncing:
        refreshStatus = orbit.PhoneBookStatus.checking;
        break;
      case PhoneBookStatus.budgetExhausted:
        refreshStatus = orbit.PhoneBookStatus.limit;
        break;
      case PhoneBookStatus.failed:
        refreshStatus = orbit.PhoneBookStatus.failed;
        break;
      case PhoneBookStatus.synced:
        refreshStatus = orbit.PhoneBookStatus.done;
        break;
      default:
        refreshStatus = orbit.PhoneBookStatus.idle;
    }

    LookupPrompt prompt;
    if (query.helixName != null) {
      final name = query.raw.startsWith('~')
          ? query.raw
          : '~${query.helixName}';
      prompt = FindName(name);
    } else if (query.intent == SearchIntent.phone) {
      if (query.e164 == null) {
        prompt = const NeedFullNumber();
      } else {
        prompt = FindNumber(PhoneNumbers.display(query.e164!));
      }
    } else {
      prompt = const NoLookup();
    }

    LookupView lookupView;
    switch (lookupState.status) {
      case LookupStatus.idle:
        lookupView = LookupView.idle;
        break;
      case LookupStatus.searching:
        lookupView = LookupView.searching;
        break;
      case LookupStatus.notFound:
        lookupView = LookupView.notFound;
        break;
      case LookupStatus.self:
        lookupView = LookupView.self;
        break;
      case LookupStatus.failed:
        switch (lookupState.failure) {
          case PeopleFailure.rateLimited:
            lookupView = LookupView.rateLimited;
            break;
          case PeopleFailure.offline:
            lookupView = LookupView.offline;
            break;
          default:
            lookupView = LookupView.failed;
        }
        break;
      case LookupStatus.found:
        lookupView = LookupView.idle;
        break;
    }

    final groups = [
      for (final g in results?.groups ?? const <GroupSummary>[])
        PanelGroup(
          groupId: g.id,
          chatId: g.conversationId,
          title: g.title,
          avatar: HelixAvatarModel(
            name: g.title,
            isGroup: true,
            colorIndex: HelixAvatarModel.colorIndexFor(g.id),
          ),
        ),
    ];
    final people = [
      for (final p in results?.people ?? const <PersonName>[])
        HelixPersonItem(
          id: p.accountId,
          names: p.tileNames,
          image: p.image,
          about: null,
          online: false,
          blocked: p.blocked,
          verified: p.verified,
        ),
    ];

    PanelEmpty empty;
    if (results != null && results.isEmpty && lookupView == LookupView.idle) {
      if (query.isBrowse) {
        empty = PanelEmpty.nobodyYet;
      } else if (prompt is NoLookup) {
        empty = PanelEmpty.noMatches;
      } else {
        empty = PanelEmpty.none;
      }
    } else {
      empty = PanelEmpty.none;
    }
    if (results != null &&
        results.people.isEmpty &&
        results.groups.isEmpty &&
        !query.isBrowse) {
      // avoid nobodyYet for searches
    }

    return PeoplePanelModel(
      query: text,
      mode: mode,
      status: resultsAsync.isLoading
          ? ListStatus.loading
          : resultsAsync.hasError
          ? ListStatus.failed
          : ListStatus.ready,
      contacts: contactsCard,
      refresh: refreshStatus,
      found: sync.found,
      lookupPrompt: prompt,
      lookup: lookupView,
      groups: groups,
      people: people,
      empty: empty,
    );
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
