import 'package:flutter/widgets.dart';
import 'package:orbit_ui/orbit_ui.dart';

/// The Home keys (`prototype/js/screens/home.js`) on the sample data, with
/// the prototype's search logic, so typing in the preview's searches works.

const _known = [
  'nadia',
  'arif',
  'sadia',
  'tanvir',
  'ammu',
  'abbu',
  'rumana',
  'karim',
];

/// `peoplePanel(q, mode, st)` from the prototype, as a model.
PeoplePanelModel peopleFor(
  String q,
  PeopleSearchMode mode, {
  String contacts = 'ask',
  LookupView lookup = LookupView.idle,
  bool nobody = false,
}) {
  final query = q.trim();
  final all = OrbitFakes.people.values.where((p) => p.id != 'unknown').toList();
  if (query.isEmpty) {
    final card = switch (contacts) {
      'ask' => ContactsCard.ask,
      'denied' => ContactsCard.openSettings,
      _ => ContactsCard.refresh,
    };
    final status = switch (contacts) {
      'checking' => PhoneBookStatus.checking,
      'limit' => PhoneBookStatus.limit,
      'done' => PhoneBookStatus.done,
      'failed' => PhoneBookStatus.failed,
      _ => PhoneBookStatus.idle,
    };
    return PeoplePanelModel(
      mode: mode,
      contacts: card,
      refresh: status,
      found: 7,
      empty: nobody ? PanelEmpty.nobodyYet : PanelEmpty.none,
      people: nobody
          ? const []
          : [for (final id in _known) OrbitFakes.people[id]!],
    );
  }
  final lc = query.toLowerCase();
  final digits = query.replaceAll(RegExp(r'[^\d+]'), '');
  final looksNumber =
      RegExp(r'^[+\d][\d\s-]*$').hasMatch(query) &&
      digits.replaceAll('+', '').length >= 3;
  final isName = query.startsWith('~') && query.length > 1;
  final plainWord = RegExp(
    r'^[a-z][a-z0-9._]{2,}$',
    caseSensitive: false,
  ).hasMatch(query);
  LookupPrompt prompt = const NoLookup();
  if (isName) {
    prompt = FindName(query);
  } else if (looksNumber) {
    final intl = query.startsWith('+');
    final national = digits.replaceFirst(RegExp('^0'), '');
    final complete = intl ? digits.length >= 12 : national.length >= 10;
    final shown = intl
        ? query
        : '+880 ${national.substring(0, 4.clamp(0, national.length))} '
              '${national.length > 4 ? national.substring(4) : ''}';
    prompt = complete ? FindNumber(shown) : const NeedFullNumber();
  } else if (plainWord) {
    prompt = FindName('~$lc');
  }
  final groups = [
    for (final c in OrbitFakes.chats)
      if (c.id.startsWith('group:') && c.title.toLowerCase().contains(lc))
        PanelGroup(
          groupId: c.id.substring(6),
          chatId: c.id,
          title: c.title,
          avatar: c.avatar,
        ),
  ];
  final qDigits = lc.replaceAll(RegExp(r'\D'), '');
  final people = [
    for (final p in all)
      if (p.names.display.toLowerCase().contains(lc) ||
          (p.names.number ?? '')
              .replaceAll(RegExp(r'\D'), '')
              .contains(qDigits.isEmpty ? 'x' : qDigits))
        p,
  ];
  final nothing =
      lookup == LookupView.idle &&
      prompt is NoLookup &&
      groups.isEmpty &&
      people.isEmpty;
  return PeoplePanelModel(
    query: query,
    mode: mode,
    lookupPrompt: prompt,
    lookup: lookup,
    groups: groups,
    people: people,
    empty: nothing && !looksNumber && !isName
        ? PanelEmpty.noMatches
        : PanelEmpty.none,
  );
}

/// `chatSearch(st)` from the prototype.
ChatSearchModel chatSearchFor(
  String q, {
  String contacts = 'ask',
  LookupView lookup = LookupView.idle,
  bool nobody = false,
}) {
  final query = q.trim();
  final lc = query.toLowerCase();
  final hits = <ChatSearchHit>[];
  if (query.isNotEmpty) {
    for (final entry in OrbitFakes.conversations.entries) {
      final chat = OrbitFakes.chats.where((c) => c.id == entry.key).firstOrNull;
      if (chat == null) continue;
      for (final it in entry.value.whereType<HelixMessageItem>()) {
        final m = it.message;
        final c = m.content;
        if (c is! HelixTextContent) continue;
        final at = c.text.toLowerCase().indexOf(lc);
        if (at < 0) continue;
        hits.add(
          ChatSearchHit(
            chatId: chat.id,
            messageId: m.id,
            title: chat.title,
            avatar: chat.avatar,
            timeLabel: m.timeLabel,
            who: m.outgoing
                ? 'You'
                : m.authorName ?? chat.title.split(' ').first,
            text: HelixHighlightedText(c.text, [HelixTextRange(at, lc.length)]),
          ),
        );
      }
    }
  }
  return ChatSearchModel(
    query: query,
    chats: query.isEmpty
        ? const []
        : [
            for (final c in [...OrbitFakes.chats, ...OrbitFakes.archived])
              if (c.title.toLowerCase().contains(lc)) c,
          ],
    messages: hits,
    people: peopleFor(
      query,
      PeopleSearchMode.chats,
      contacts: contacts,
      lookup: lookup,
      nobody: nobody,
    ),
  );
}

/// Home on the sample data, recomputing the searches as the preview types.
class PreviewHome extends StatefulWidget {
  const PreviewHome({
    super.key,
    this.start = const HomeStart(),
    this.chats = OrbitFakes.chats,
    this.archivedCount = 3,
    this.chatStatus = ListStatus.ready,
    this.calls = OrbitFakes.calls,
    this.callStatus = ListStatus.ready,
    this.contacts = 'ask',
    this.lookup = LookupView.idle,
    this.nobody = false,
  });

  final HomeStart start;
  final List<HelixChatListItem> chats;
  final int archivedCount;
  final ListStatus chatStatus;
  final List<HelixCallLogItem> calls;
  final ListStatus callStatus;
  final String contacts;
  final LookupView lookup;
  final bool nobody;

  @override
  State<PreviewHome> createState() => _PreviewHomeState();
}

class _PreviewHomeState extends State<PreviewHome> {
  late String _q = widget.start.query;
  String _callQ = '';
  late var _lookup = widget.lookup;

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final quick = [
      for (final id in const ['nadia', 'ammu'])
        QuickPerson(
          peerId: id,
          label: OrbitFakes.people[id]!.names.display.split(' ').first,
          avatar: OrbitFakes.people[id]!.avatar,
        ),
    ];
    return HomeScreen(
      start: w.start,
      model: HomeModel(
        me: const HelixAvatarModel(name: OrbitFakes.meName),
        meNeedsAttention: true,
        chats: ChatsTabModel(
          chats: w.chats,
          status: w.chatStatus,
          archivedCount: w.archivedCount,
          search: chatSearchFor(
            _q,
            contacts: w.contacts,
            lookup: _lookup,
            nobody: w.nobody,
          ),
        ),
        calls: CallsTabModel(
          calls: w.calls,
          status: w.callStatus,
          quick: quick,
          search: peopleFor(
            _callQ,
            PeopleSearchMode.calls,
            contacts: w.contacts == 'ask' ? 'done' : w.contacts,
          ),
        ),
      ),
      actions: HomeActions(
        onSearchChanged: (v) => setState(() {
          _q = v;
          _lookup = LookupView.idle;
        }),
        onCallSearchChanged: (v) => setState(() => _callQ = v),
        people: PeoplePanelActions(
          onLookUp: () => setState(() => _lookup = LookupView.notFound),
        ),
      ),
    );
  }
}

final Map<String, WidgetBuilder> homePreviews = {
  'chats': (_) => const PreviewHome(),
  'chats-groups': (_) =>
      const PreviewHome(start: HomeStart(filter: ChatFilter.groups)),
  'chats-unread': (_) =>
      const PreviewHome(start: HomeStart(filter: ChatFilter.unread)),
  'chats-menu': (_) => const PreviewHome(start: HomeStart(menu: true)),
  'chats-select': (_) => const PreviewHome(
    start: HomeStart(selected: {'direct:arif', 'group:design'}),
  ),
  'chats-search': (_) => const PreviewHome(start: HomeStart(searching: true)),
  'chats-search-synced': (_) =>
      const PreviewHome(start: HomeStart(searching: true), contacts: 'done'),
  'chats-search-q': (_) =>
      const PreviewHome(start: HomeStart(searching: true, query: 'ar')),
  'chats-search-num': (_) => const PreviewHome(
    start: HomeStart(searching: true, query: '+880 1711 000002'),
  ),
  'chats-search-short': (_) => const PreviewHome(
    start: HomeStart(searching: true, query: '01711 000002'),
  ),
  'chats-search-none': (_) => const PreviewHome(
    start: HomeStart(searching: true, query: '+880 1711 000002'),
    lookup: LookupView.notFound,
  ),
  'chats-empty': (_) => const PreviewHome(chats: [], archivedCount: 0),
  'chats-loading': (_) => const PreviewHome(chatStatus: ListStatus.loading),
  'chats-error': (_) => const PreviewHome(chatStatus: ListStatus.failed),
  'chats-all-archived': (_) => const PreviewHome(chats: []),
  'chats-search-word': (_) =>
      const PreviewHome(start: HomeStart(searching: true, query: 'arifh')),
  'chats-search-nobody': (_) => const PreviewHome(
    start: HomeStart(searching: true),
    contacts: 'done',
    nobody: true,
  ),
  'chats-search-contacts-failed': (_) =>
      const PreviewHome(start: HomeStart(searching: true), contacts: 'failed'),
  'chats-search-lookup-failed': (_) => const PreviewHome(
    start: HomeStart(searching: true, query: '+880 1711 000002'),
    lookup: LookupView.failed,
  ),
  'chats-link-signed-in': (_) => const PreviewHome(
    start: HomeStart(
      toast:
          'You’re already signed in. Invite and recovery links are for '
          'setting up a new device.',
    ),
  ),
  'calls': (_) => const PreviewHome(start: HomeStart(tab: HomeTab.calls)),
  'calls-search': (_) => const PreviewHome(
    start: HomeStart(tab: HomeTab.calls, callSearching: true),
    contacts: 'done',
  ),
  'calls-empty': (_) => const PreviewHome(
    start: HomeStart(tab: HomeTab.calls),
    calls: [],
  ),
  'calls-loading': (_) => const PreviewHome(
    start: HomeStart(tab: HomeTab.calls),
    callStatus: ListStatus.loading,
  ),
  'archived': (_) => const ArchivedChatsScreen(
    model: ArchivedChatsModel(chats: OrbitFakes.archived),
  ),
  'archived-empty': (_) =>
      const ArchivedChatsScreen(model: ArchivedChatsModel()),
};
