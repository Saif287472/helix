import 'package:flutter/material.dart';

import 'package:orbit_ui/src/components/avatar.dart';
import 'package:orbit_ui/src/components/bars.dart';
import 'package:orbit_ui/src/components/button.dart';
import 'package:orbit_ui/src/components/chat_rows.dart';
import 'package:orbit_ui/src/components/chip_tag.dart';
import 'package:orbit_ui/src/components/fab.dart';
import 'package:orbit_ui/src/components/icon_button.dart';
import 'package:orbit_ui/src/components/overlays.dart';
import 'package:orbit_ui/src/components/page_parts.dart';
import 'package:orbit_ui/src/components/state_kit.dart';
import 'package:orbit_ui/src/icons/orbit_glyph.dart';
import 'package:orbit_ui/src/icons/orbit_icons.dart';
import 'package:orbit_ui/src/models/view_models.dart';
import 'package:orbit_ui/src/screens/home/home_models.dart';
import 'package:orbit_ui/src/screens/home/people_panel.dart';
import 'package:orbit_ui/src/theme/motion.dart';
import 'package:orbit_ui/src/theme/orbit_metrics.dart';
import 'package:orbit_ui/src/theme/orbit_text.dart';
import 'package:orbit_ui/src/theme/orbit_tokens.dart';

/// `home` (`prototype/js/screens/home.js`): the Chats and Calls tabs, which
/// swipe into each other, under the floating dock and its round button.
///
/// Each tab opens on its wordmark header; Chats has the All / Unread /
/// Groups filters, pinned chats first, swipes (right pins, left archives
/// with Undo), long-press selection, and its search (chats, the people
/// panel, messages). Calls has the quick row (Call, Keypad, two recent
/// people), the log, and its people search.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.model,
    this.actions = const HomeActions(),
    this.start = const HomeStart(),
  });

  final HomeModel model;
  final HomeActions actions;
  final HomeStart start;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late HomeTab _tab = widget.start.tab;
  late final _pages = PageController(initialPage: _tab.index);
  late ChatFilter _filter = widget.start.filter;

  /// A list of the person's own chosen in place of a built-in filter.
  String? _list;
  late bool _searching = widget.start.searching;
  late bool _callSearching = widget.start.callSearching;
  late final _query = TextEditingController(text: widget.start.query);
  final _callQuery = TextEditingController();
  late final Set<String> _selected = {...widget.start.selected};

  /// The search was opened by the person (not the preview's start state),
  /// so its field takes the focus.
  var _focusSearch = false;

  HomeActions get _a => widget.actions;

  @override
  void initState() {
    super.initState();
    final s = widget.start;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (s.menu) _chatsMenu();
      final toast = s.toast;
      if (toast != null) showOrbitToast(context, toast, stay: true);
    });
  }

  @override
  void dispose() {
    _pages.dispose();
    _query.dispose();
    _callQuery.dispose();
    super.dispose();
  }

  void _goTab(HomeTab t) {
    setState(() => _tab = t);
    _a.onTabChanged?.call(t);
    _pages.animateToPage(
      t.index,
      duration: OrbitMotion.allowed(context)
          ? OrbitTokens.of(context).motion.page
          : Duration.zero,
      curve: OrbitTokens.of(context).motion.curve,
    );
  }

  void _chatsMenu() {
    final n = widget.model.chats.archivedCount;
    showOrbitMenu(context, [
      OrbitMenuItem(
        icon: OrbitIcons.usersThree,
        label: 'New group',
        onTap: _a.onNewGroup,
      ),
      OrbitMenuItem(
        icon: OrbitIcons.linkSimple,
        label: 'Join a group with a link',
        onTap: _a.onJoinGroup,
      ),
      OrbitMenuItem.divider,
      OrbitMenuItem(
        icon: OrbitIcons.archive,
        label: n > 0 ? 'Archived chats ($n)' : 'Archived chats',
        onTap: _a.onOpenArchived,
      ),
      if (_a.onOpenLocked != null && widget.model.chats.lockedCount > 0)
        OrbitMenuItem(
          icon: OrbitIcons.lock,
          label: 'Locked chats',
          onTap: _a.onOpenLocked,
        ),
    ]);
  }

  void _toggle(String id) => setState(
    () => _selected.contains(id) ? _selected.remove(id) : _selected.add(id),
  );

  void _clear() => setState(_selected.clear);

  void _archive(Set<String> ids) {
    _a.onSetArchived?.call(ids, archived: true);
    showOrbitToast(
      context,
      'Chat archived',
      actionLabel: 'Undo',
      onAction: () => _a.onSetArchived?.call(ids, archived: false),
    );
  }

  void _delete(Set<String> ids) {
    final n = ids.length;
    showOrbitDialog(
      context,
      title: n > 1 ? 'Delete $n chats?' : 'Delete this chat?',
      text:
          'The messages are removed from this device. People you chatted '
          'with keep their copies.',
      actions: [
        const OrbitDialogAction('Cancel'),
        OrbitDialogAction(
          'Delete',
          kind: OrbitButtonKind.danger,
          onPressed: () {
            _a.onDelete?.call(ids);
            _clear();
          },
        ),
      ],
    );
  }

  void _muteSheet(Set<String> ids, {required bool withUnmute}) {
    void run(MuteFor? m) {
      _a.onMute?.call(ids, m);
      _clear();
    }

    showOrbitSheet(
      context,
      title: 'Mute notifications',
      items: [
        OrbitMenuItem(
          icon: OrbitIcons.bellSlash,
          label: '8 hours',
          onTap: () => run(MuteFor.eightHours),
        ),
        OrbitMenuItem(
          icon: OrbitIcons.bellSlash,
          label: '1 week',
          onTap: () => run(MuteFor.week),
        ),
        OrbitMenuItem(
          icon: OrbitIcons.bellSlash,
          label: 'Always',
          onTap: () => run(MuteFor.always),
        ),
        if (withUnmute)
          OrbitMenuItem(
            icon: OrbitIcons.speakerHigh,
            label: 'Unmute',
            onTap: () => run(null),
          ),
      ],
    );
  }

  void _selectionMenu() {
    final chats = widget.model.chats.chats
        .where((c) => _selected.contains(c.id))
        .toList();
    final ids = {..._selected};
    final allPinned = chats.every((c) => c.pinned);
    final allFavourite = chats.every((c) => c.favourite);
    final allMuted = chats.every((c) => c.muted);
    final anyMuted = chats.any((c) => c.muted);
    final anyUnread = chats.any((c) => c.unreadCount > 0);
    showOrbitMenu(context, [
      OrbitMenuItem(
        icon: OrbitIcons.pushPin,
        label: allPinned ? 'Unpin' : 'Pin',
        onTap: () {
          _a.onSetPinned?.call(ids, pinned: !allPinned);
          _clear();
        },
      ),
      if (_a.onSetFavourite != null)
        OrbitMenuItem(
          icon: OrbitIcons.star,
          label: allFavourite ? 'Remove from favourites' : 'Add to favourites',
          onTap: () {
            _a.onSetFavourite?.call(ids, favourite: !allFavourite);
            _clear();
          },
        ),
      if (_a.onSetLocked != null)
        OrbitMenuItem(
          icon: OrbitIcons.lock,
          label: 'Lock chat',
          onTap: () {
            _a.onSetLocked?.call(ids, locked: true);
            _clear();
            showOrbitToast(
              context,
              ids.length > 1
                  ? 'Chats locked. Find them in Locked chats.'
                  : 'Chat locked. Find it in Locked chats.',
            );
          },
        ),
      if (_a.onCreateList != null && _a.onSetOnList != null)
        OrbitMenuItem(
          icon: OrbitIcons.list,
          label: 'Add to list',
          onTap: () => _listSheet(ids, chats),
        ),
      OrbitMenuItem(
        icon: OrbitIcons.bellSlash,
        label: allMuted
            ? 'Unmute'
            : anyMuted
            ? 'Mute or unmute'
            : 'Mute',
        onTap: () => _muteSheet(ids, withUnmute: anyMuted),
      ),
      if (anyUnread)
        OrbitMenuItem(
          icon: OrbitIcons.checks,
          label: 'Mark as read',
          onTap: () {
            _a.onMarkRead?.call(ids);
            _clear();
          },
        ),
    ]);
  }

  /// Which lists the selected chats are on, a tick where all of them are; a
  /// touch puts them on, or takes them off, and New list makes one holding them.
  void _listSheet(Set<String> ids, List<HelixChatListItem> chats) {
    final lists = widget.model.chats.lists;
    showOrbitSheet(
      context,
      title: 'Add to list',
      items: [
        for (final l in lists)
          () {
            final all = chats.every((c) => c.lists.contains(l.id));
            return OrbitMenuItem(
              icon: OrbitIcons.list,
              label: l.name,
              on: all,
              onTap: () {
                _a.onSetOnList?.call(ids, l.id, member: !all);
                _clear();
              },
            );
          }(),
        if (lists.isNotEmpty) OrbitMenuItem.divider,
        OrbitMenuItem(
          icon: OrbitIcons.plus,
          label: 'New list',
          onTap: () => _newList(ids),
        ),
      ],
    );
  }

  /// Asks for a name and makes the list, holding [ids] when given.
  void _newList(Set<String> ids) => showOrbitInputDialog(
    context,
    title: 'New list',
    label: 'List name',
    maxLength: 24,
    confirmLabel: 'Create',
    onConfirm: (name) async {
      final error = await _a.onCreateList?.call(name, ids);
      if (!mounted) return;
      if (error != null) {
        showOrbitToast(context, error, error: true);
      } else {
        _clear();
      }
    },
  );

  void _listMenu(HelixChatList l) => showOrbitSheet(
    context,
    title: l.name,
    items: [
      if (_a.onRenameList != null)
        OrbitMenuItem(
          icon: OrbitIcons.pencilSimple,
          label: 'Rename',
          onTap: () => showOrbitInputDialog(
            context,
            title: 'Rename list',
            label: 'List name',
            value: l.name,
            maxLength: 24,
            onConfirm: (name) async {
              final error = await _a.onRenameList?.call(l.id, name);
              if (error != null && mounted) {
                showOrbitToast(context, error, error: true);
              }
            },
          ),
        ),
      if (_a.onDeleteList != null)
        OrbitMenuItem(
          icon: OrbitIcons.trash,
          label: 'Delete list',
          sub: 'The chats on it stay',
          danger: true,
          onTap: () {
            _a.onDeleteList?.call(l.id);
            if (_list == l.id) setState(() => _list = null);
          },
        ),
    ],
  );

  void _callSheet(HelixCallLogItem c) => showOrbitSheet(
    context,
    title: c.title,
    items: [
      OrbitMenuItem(
        icon: OrbitIcons.phone,
        label: 'Voice call',
        onTap: () => _a.onCall?.call(c.id, video: false),
      ),
      OrbitMenuItem(
        icon: OrbitIcons.videoCamera,
        label: 'Video call',
        onTap: () => _a.onCall?.call(c.id, video: true),
      ),
      OrbitMenuItem(
        icon: OrbitIcons.trash,
        label: 'Delete from call history',
        danger: true,
        onTap: () => _deleteCall(c),
      ),
    ],
  );

  void _deleteCall(HelixCallLogItem c) => showOrbitDialog(
    context,
    title: 'Delete from call history?',
    text: c.count > 1
        ? 'These ${c.count} calls with ${c.title} will be removed from your '
              'call history.'
        : 'This call with ${c.title} will be removed from your call history.',
    actions: [
      const OrbitDialogAction('Cancel'),
      OrbitDialogAction(
        'Delete',
        kind: OrbitButtonKind.danger,
        onPressed: () => _a.onDeleteCalls?.call(c.id),
      ),
    ],
  );

  void _dialPad() => showOrbitDialPad(
    context,
    onFind: (number) {
      setState(() {
        _callSearching = true;
        _callQuery.text = number;
      });
      _a.onCallSearchChanged?.call(number);
      _a.people.onQueryChanged?.call(number);
    },
  );

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final hideDock = _selected.isNotEmpty || _searching || _callSearching;
    final top = MediaQuery.paddingOf(context).top;
    return ColoredBox(
      color: t.bg,
      child: Stack(
        children: [
          Padding(
            padding: EdgeInsets.only(top: top),
            child: PageView(
              controller: _pages,
              physics: hideDock
                  ? const NeverScrollableScrollPhysics()
                  : const PageScrollPhysics(),
              onPageChanged: (i) {
                setState(() => _tab = HomeTab.values[i]);
                _a.onTabChanged?.call(_tab);
              },
              children: [_chatsPane(t), _callsPane(t)],
            ),
          ),
          if (!hideDock)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: OrbitDockArea(
                dock: OrbitDock(
                  items: [
                    OrbitDockItem(
                      icon: OrbitIcons.chatsCircle,
                      label: 'Chats',
                      on: _tab == HomeTab.chats,
                      onTap: () => _goTab(HomeTab.chats),
                    ),
                    OrbitDockItem(
                      icon: OrbitIcons.phone,
                      label: 'Calls',
                      on: _tab == HomeTab.calls,
                      onTap: () => _goTab(HomeTab.calls),
                    ),
                  ],
                ),
                fab: OrbitFab(
                  icon: _tab == HomeTab.chats
                      ? OrbitIcons.chatCircleDots
                      : OrbitIcons.phonePlus,
                  iconWeight: OrbitIconWeight.bold,
                  tooltip: _tab == HomeTab.chats ? 'New chat' : 'New call',
                  size: 62,
                  onPressed: () => setState(() {
                    _focusSearch = true;
                    if (_tab == HomeTab.chats) {
                      _searching = true;
                      _query.clear();
                    } else {
                      _callSearching = true;
                    }
                  }),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _header(OrbitTokens t, {required bool chats}) {
    final m = widget.model;
    if (chats && _selected.isNotEmpty) {
      return OrbitAppBar(
        title: '${_selected.length} selected',
        selection: true,
        lead: OrbitAppBarLead.close,
        leadTooltip: 'Cancel selection',
        onLead: _clear,
        actions: [
          OrbitIconButton(
            icon: OrbitIcons.archive,
            tooltip: 'Archive chats',
            color: t.onInverse,
            onPressed: () {
              final ids = {..._selected};
              _clear();
              _archive(ids);
            },
          ),
          OrbitIconButton(
            icon: OrbitIcons.trash,
            tooltip: 'Delete chats',
            color: t.onInverse,
            onPressed: () => _delete({..._selected}),
          ),
          OrbitIconButton(
            icon: OrbitIcons.dotsThreeVertical,
            tooltip: 'More options',
            color: t.onInverse,
            onPressed: _selectionMenu,
          ),
        ],
      );
    }
    return OrbitTabHeader(
      actions: [
        OrbitIconButton(
          icon: OrbitIcons.magnifyingGlass,
          tooltip: 'Search',
          onPressed: () => setState(() {
            _focusSearch = true;
            chats ? _searching = true : _callSearching = true;
          }),
        ),
        if (chats)
          OrbitIconButton(
            icon: OrbitIcons.dotsThreeVertical,
            tooltip: 'More options',
            onPressed: _chatsMenu,
          ),
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: OrbitMePicture(
            avatar: m.me,
            attention: m.meNeedsAttention,
            onPressed: _a.onOpenYou,
          ),
        ),
      ],
    );
  }

  Widget _searchBar(
    OrbitTokens t, {
    required String hint,
    required TextEditingController controller,
    required VoidCallback onClose,
    required ValueChanged<String> onChanged,
  }) => OrbitAppBar(
    leadTooltip: 'Close search',
    onLead: onClose,
    background: t.bg,
    rule: false,
    titleWidget: OrbitSearchField(
      hint: hint,
      controller: controller,
      autofocus: _focusSearch,
      onChanged: onChanged,
      onSubmitted: (_) => _a.people.onLookUp?.call(),
    ),
  );

  // ---------------------------------------------------------------- chats

  Widget _chatsPane(OrbitTokens t) {
    final m = widget.model.chats;
    if (_searching) {
      final s = m.search;
      final q = _query.text.trim();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _searchBar(
            t,
            hint: 'Search chats, messages and people',
            controller: _query,
            onClose: () {
              setState(() => _searching = false);
              _query.clear();
              _a.onSearchChanged?.call('');
            },
            onChanged: (v) {
              setState(() {});
              _a.onSearchChanged?.call(v);
              _a.people.onQueryChanged?.call(v);
            },
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 40),
              children: [
                if (q.isNotEmpty && s.chats.isNotEmpty) ...[
                  const OrbitListLabel('Chats'),
                  for (final c in s.chats)
                    OrbitChatListTile(
                      item: c,
                      showArchived: true,
                      onTap: () => _a.onOpenChat?.call(c.id),
                    ),
                ],
                PeoplePanel(model: s.people, actions: _a.people),
                if (q.isNotEmpty && s.messages.isNotEmpty) ...[
                  const OrbitListLabel('Messages'),
                  for (final h in s.messages) _MessageHit(hit: h, actions: _a),
                ],
              ],
            ),
          ),
        ],
      );
    }
    final header = _header(t, chats: true);
    Widget page(List<Widget> body, {Widget? above}) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        ?above,
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 120),
            children: body,
          ),
        ),
      ],
    );
    switch (m.status) {
      case ListStatus.loading:
        return page([const OrbitSkeleton(count: 8, label: 'Loading chats')]);
      case ListStatus.failed:
        return page([
          const OrbitLoadFailed(title: 'Your chats could not be loaded.'),
        ]);
      case ListStatus.ready:
    }
    if (m.chats.isEmpty) {
      return page([
        if (m.archivedCount > 0)
          OrbitEmptyState(
            icon: OrbitIcons.archive,
            title: 'All your chats are archived',
            text: 'They are kept in Archived chats, out of the way.',
            action: OrbitButton(
              label: 'Open archived chats',
              kind: OrbitButtonKind.secondary,
              icon: OrbitIcons.archive,
              onPressed: _a.onOpenArchived ?? () {},
            ),
          )
        else
          OrbitEmptyState(
            icon: OrbitIcons.chatsCircle,
            title: 'No chats yet',
            text:
                'Search for a name or a number to start a secure '
                'conversation. Anyone on Orbit can message you unless you '
                'block them.',
            action: OrbitButton(
              label: 'Find people',
              icon: OrbitIcons.magnifyingGlass,
              iconWeight: OrbitIconWeight.bold,
              onPressed: () => setState(() => _searching = true),
            ),
          ),
      ]);
    }
    int count(ChatFilter f) => m.chats.where(f.matches).length;
    final lists = widget.model.chats.lists;
    final list = lists.where((l) => l.id == _list).firstOrNull;
    final shown = m.chats
        .where(
          list == null ? _filter.matches : (c) => c.lists.contains(list.id),
        )
        .toList();
    final ordered = [
      ...shown.where((c) => c.pinned),
      ...shown.where((c) => !c.pinned),
    ];
    final chips = Padding(
      padding: const EdgeInsets.fromLTRB(
        OrbitSpace.gutter,
        2,
        OrbitSpace.gutter,
        8,
      ),
      // Four chips do not fit a narrow phone: they slide sideways.
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final (i, f) in ChatFilter.values.indexed) ...[
              if (i > 0) const SizedBox(width: 8),
              OrbitChip(
                label: f.label,
                on: list == null && _filter == f,
                height: 36,
                count: f == ChatFilter.all ? null : count(f),
                onTap: () => setState(() {
                  _filter = f;
                  _list = null;
                }),
              ),
            ],
            for (final l in lists) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onLongPress: () => _listMenu(l),
                child: OrbitChip(
                  label: l.name,
                  on: list?.id == l.id,
                  height: 36,
                  count: m.chats.where((c) => c.lists.contains(l.id)).length,
                  onTap: () => setState(() => _list = l.id),
                ),
              ),
            ],
            if (_a.onCreateList != null && lists.length < 10) ...[
              const SizedBox(width: 8),
              OrbitChip(
                label: 'New list',
                icon: OrbitIcons.plus,
                on: false,
                height: 36,
                onTap: () => _newList(const {}),
              ),
            ],
          ],
        ),
      ),
    );
    final none = list != null
        ? const OrbitEmptyState(
            icon: OrbitIcons.list,
            title: 'Nothing on this list',
            text:
                'Touch and hold a chat, open the menu and choose Add to list. '
                'Touch and hold the list’s name to rename or delete it.',
          )
        : _filter == ChatFilter.unread
        ? const OrbitEmptyState(
            icon: OrbitIcons.checks,
            title: 'No unread chats',
            text:
                'You’re all caught up. New messages show up here until you '
                'read them.',
          )
        : _filter == ChatFilter.favourites
        ? const OrbitEmptyState(
            icon: OrbitIcons.star,
            title: 'No favourite chats',
            text:
                'Touch and hold a chat, open the menu and choose Add to '
                'favourites. They are kept here, ready to open.',
          )
        : OrbitEmptyState(
            icon: OrbitIcons.usersThree,
            title: 'No groups yet',
            text: 'Start a group from the menu, or join one with a link.',
            action: OrbitButton(
              label: 'New group',
              icon: OrbitIcons.usersThree,
              iconWeight: OrbitIconWeight.bold,
              onPressed: _a.onNewGroup ?? () {},
            ),
          );
    return page(above: chips, [
      if (ordered.isEmpty) none,
      for (final c in ordered)
        OrbitSwipeRow(
          key: ValueKey(c.id),
          start: _selected.isNotEmpty
              ? null
              : OrbitSwipeAction(
                  icon: OrbitIcons.pushPin,
                  label: c.pinned ? 'Unpin' : 'Pin',
                  onSwiped: () =>
                      _a.onSetPinned?.call({c.id}, pinned: !c.pinned),
                ),
          end: _selected.isNotEmpty
              ? null
              : OrbitSwipeAction(
                  icon: OrbitIcons.archive,
                  label: 'Archive',
                  onSwiped: () => _archive({c.id}),
                ),
          child: OrbitChatListTile(
            item: c,
            background: t.bg,
            selected: _selected.contains(c.id) || c.id == m.openChatId,
            onTap: () => _selected.isNotEmpty
                ? _toggle(c.id)
                : _a.onOpenChat?.call(c.id),
            onLongPress: () => _toggle(c.id),
          ),
        ),
    ]);
  }

  // ---------------------------------------------------------------- calls

  Widget _callsPane(OrbitTokens t) {
    final m = widget.model.calls;
    if (_callSearching) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _searchBar(
            t,
            hint: 'Search people',
            controller: _callQuery,
            onClose: () {
              setState(() => _callSearching = false);
              _callQuery.clear();
              _a.onCallSearchChanged?.call('');
            },
            onChanged: (v) {
              setState(() {});
              _a.onCallSearchChanged?.call(v);
              _a.people.onQueryChanged?.call(v);
            },
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 40),
              children: [
                PeoplePanel(
                  model: m.search,
                  actions: _a.peopleCalls ?? _a.people,
                ),
              ],
            ),
          ),
        ],
      );
    }
    final quick = _QuickRow(
      people: m.quick,
      onCall: () => setState(() => _callSearching = true),
      onKeypad: _dialPad,
      onPerson: (p) => _a.onCall?.call(p.peerId, video: false),
    );
    final body = switch (m.status) {
      ListStatus.loading => <Widget>[
        quick,
        const OrbitSkeleton(
          count: 6,
          kind: OrbitSkeletonKind.person,
          label: 'Loading calls',
        ),
      ],
      ListStatus.failed => <Widget>[
        quick,
        const OrbitLoadFailed(title: 'Your calls could not be loaded.'),
      ],
      ListStatus.ready when m.calls.isEmpty => <Widget>[
        quick,
        const OrbitEmptyState(
          icon: OrbitIcons.phone,
          title: 'No calls yet',
          text: 'Calls you make and receive will show up here.',
        ),
      ],
      ListStatus.ready => <Widget>[
        quick,
        const OrbitListLabel('Recent'),
        for (final c in m.calls)
          OrbitSwipeRow(
            key: ValueKey(c.id),
            color: t.danger,
            end: OrbitSwipeAction(
              icon: OrbitIcons.trash,
              label: 'Delete',
              onSwiped: () => _deleteCall(c),
            ),
            child: OrbitCallLogTile(
              item: c,
              background: t.bg,
              onTap: () => _a.onOpenCall?.call(c.id),
              onLongPress: () => _callSheet(c),
              onCallBack: () => _a.onCallBack?.call(c.id),
            ),
          ),
      ],
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(t, chats: false),
        Expanded(
          child: ListView(
            padding: EdgeInsets.only(
              bottom: m.status == ListStatus.ready && m.calls.isNotEmpty
                  ? 120
                  : 0,
            ),
            children: body,
          ),
        ),
      ],
    );
  }
}

/// A message found by the Chats search: the chat's row with the time, and
/// "Sender: text" with the match in bold `--accent-ink`.
class _MessageHit extends StatelessWidget {
  const _MessageHit({required this.hit, required this.actions});

  final ChatSearchHit hit;
  final HomeActions actions;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final h = hit;
    final base = t.font.style(size: OrbitType.small, color: t.ink3);
    final strong = base.copyWith(
      color: t.accentInk,
      fontWeight: FontWeight.w700,
      fontVariations: const [FontVariation('wght', 700)],
    );
    final text = h.text.text;
    final spans = <TextSpan>[];
    var at = 0;
    for (final r in h.text.ranges) {
      if (r.start > at) spans.add(TextSpan(text: text.substring(at, r.start)));
      spans.add(
        TextSpan(
          text: text.substring(r.start, r.start + r.length),
          style: strong,
        ),
      );
      at = r.start + r.length;
    }
    if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
    return Semantics(
      button: true,
      child: InkWell(
        onTap: () => actions.onOpenChat?.call(h.chatId, messageId: h.messageId),
        hoverColor: t.hover,
        splashFactory: NoSplash.splashFactory,
        child: SizedBox(
          height: orbitRowHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: OrbitSpace.gutter),
            child: Row(
              children: [
                OrbitAvatar(avatar: h.avatar, size: 52),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: OrbitText(
                              h.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: t.font.style(
                                size: OrbitType.headline,
                                weight: 600,
                                color: t.ink,
                                letterSpacingEm: -0.01,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          OrbitText(
                            h.timeLabel,
                            style: t.mono.style(
                              size: OrbitType.meta,
                              color: t.ink3,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      OrbitText.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '${h.who}: ',
                              style: base.copyWith(
                                color: t.ink2,
                                fontWeight: FontWeight.w500,
                                fontVariations: const [
                                  FontVariation('wght', 500),
                                ],
                              ),
                            ),
                            ...spans,
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: base,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// `.quick` on the Calls tab: Call, Keypad and two recent people, 64px
/// columns 14px apart, 8px 16px 4px in, scrolling sideways. A tile is 56px,
/// corner 20, `--surface` with a `--line` edge and the icon at 23px in
/// `--accent`; the label at 12px weight 520 in `--ink-2`, 6px under it.
class _QuickRow extends StatelessWidget {
  const _QuickRow({
    required this.people,
    required this.onCall,
    required this.onKeypad,
    required this.onPerson,
  });

  final List<QuickPerson> people;
  final VoidCallback onCall;
  final VoidCallback onKeypad;
  final ValueChanged<QuickPerson> onPerson;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    Widget item(Widget top, String label, String tip, VoidCallback onTap) =>
        Tooltip(
          message: tip,
          excludeFromSemantics: true,
          child: Semantics(
            button: true,
            label: tip,
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: SizedBox(
                width: 64,
                child: Column(
                  children: [
                    top,
                    const SizedBox(height: 6),
                    OrbitText(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.font.style(
                        size: OrbitType.caption,
                        weight: 520,
                        color: t.ink2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
    Widget tile(OrbitGlyph icon, {OrbitIconWeight? weight}) => Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: t.surface,
        border: Border.all(color: t.line),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Center(
        child: OrbitIcon(icon, weight: weight, size: 23, color: t.accent),
      ),
    );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(
        OrbitSpace.gutter,
        8,
        OrbitSpace.gutter,
        4,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          item(tile(OrbitIcons.phonePlus), 'Call', 'Call', onCall),
          const SizedBox(width: 14),
          item(
            tile(OrbitIcons.dotsNine, weight: OrbitIconWeight.bold),
            'Keypad',
            'Keypad',
            onKeypad,
          ),
          for (final p in people) ...[
            const SizedBox(width: 14),
            item(
              OrbitAvatar(avatar: p.avatar, size: 56),
              p.label,
              'Call ${p.avatar.name}',
              () => onPerson(p),
            ),
          ],
        ],
      ),
    );
  }
}

/// The dial pad (`openDialPad` in `js/screens/home.js`): it never calls by
/// itself. Twelve 62px keys in three columns, 10px apart (corner 20,
/// `--surface`, a `--line` edge, the digit at 24px over its letters in mono
/// 9.5px); the number over them in mono 28px ("Enter a number" in
/// `--ink-4` at 18px while empty); a 64px green button that turns on at six
/// digits and hands the number to [onFind]; ⌫ beside it.
Future<void> showOrbitDialPad(
  BuildContext context, {
  required ValueChanged<String> onFind,
}) {
  final number = ValueNotifier('');
  return showOrbitSheet(
    context,
    body: _DialPad(number: number, onFind: onFind),
  ).whenComplete(number.dispose);
}

class _DialPad extends StatelessWidget {
  const _DialPad({required this.number, required this.onFind});

  final ValueNotifier<String> number;
  final ValueChanged<String> onFind;

  static const _keys = [
    ('1', ''),
    ('2', 'ABC'),
    ('3', 'DEF'),
    ('4', 'GHI'),
    ('5', 'JKL'),
    ('6', 'MNO'),
    ('7', 'PQRS'),
    ('8', 'TUV'),
    ('9', 'WXYZ'),
    ('*', ''),
    ('0', '+'),
    ('#', ''),
  ];

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    return ValueListenableBuilder<String>(
      valueListenable: number,
      builder: (context, n, _) {
        final ok = n.replaceAll(RegExp(r'\D'), '').length >= 6;
        return Padding(
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 56,
                child: Center(
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      n.isEmpty ? 'Enter a number' : n,
                      style: t.mono.style(
                        size: n.isEmpty ? 18 : 28,
                        weight: 500,
                        color: n.isEmpty ? t.ink4 : t.ink,
                        letterSpacingEm: 0.04,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              for (var row = 0; row < 4; row++) ...[
                if (row > 0) const SizedBox(height: 10),
                Row(
                  children: [
                    for (var col = 0; col < 3; col++) ...[
                      if (col > 0) const SizedBox(width: 10),
                      Expanded(child: _key(t, _keys[row * 3 + col])),
                    ],
                  ],
                ),
              ],
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(width: 48),
                  const SizedBox(width: 28),
                  Opacity(
                    opacity: ok ? 1 : 0.4,
                    child: Tooltip(
                      message: 'Find on Orbit',
                      excludeFromSemantics: true,
                      child: Semantics(
                        button: true,
                        enabled: ok,
                        label: 'Find on Orbit',
                        child: GestureDetector(
                          onTap: ok
                              ? () {
                                  Navigator.of(context).pop();
                                  onFind(n);
                                }
                              : null,
                          child: Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: t.callLive,
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: OrbitIcon(
                                OrbitIcons.phone,
                                weight: OrbitIconWeight.fill,
                                size: 24,
                                color: t.onAccent,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 28),
                  SizedBox(
                    width: 48,
                    child: Visibility(
                      visible: n.isNotEmpty,
                      maintainSize: true,
                      maintainAnimation: true,
                      maintainState: true,
                      child: OrbitIconButton(
                        icon: OrbitIcons.backspace,
                        tooltip: 'Delete digit',
                        onPressed: () => number.value = n.isEmpty
                            ? n
                            : n.substring(0, n.length - 1),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _key(OrbitTokens t, (String, String) k) => Semantics(
    button: true,
    label: k.$1 == '0' ? '0, hold for plus' : k.$1,
    excludeSemantics: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => number.value += k.$1,
      onLongPress: k.$1 == '0' ? () => number.value += '+' : null,
      child: Container(
        height: 62,
        decoration: BoxDecoration(
          color: t.surface,
          border: Border.all(color: t.line),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              k.$1,
              style: t.font.style(size: 24, weight: 500, color: t.ink),
            ),
            SizedBox(
              height: 11,
              child: Text(
                k.$2,
                style: t.mono.style(
                  size: 9.5,
                  color: t.ink4,
                  letterSpacingEm: 0.12,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// ------------------------------------------------------------- archived

/// `ArchivedChatsModel` (`contracts/home.md`).
class ArchivedChatsModel {
  const ArchivedChatsModel({
    this.chats = const [],
    this.status = ListStatus.ready,
    this.openChatId,
  });

  final List<HelixChatListItem> chats;
  final ListStatus status;
  final String? openChatId;
}

/// `ArchivedChatsActions` (`contracts/home.md`).
class ArchivedChatsActions {
  const ArchivedChatsActions({
    this.onOpenChat,
    this.onSetArchived,
    this.onMute,
    this.onMarkRead,
    this.onDelete,
    this.onBack,
  });

  final void Function(String chatId)? onOpenChat;
  final Future<void> Function(Set<String> ids, {required bool archived})?
  onSetArchived;
  final Future<void> Function(Set<String> ids, MuteFor? length)? onMute;
  final Future<void> Function(Set<String> ids)? onMarkRead;
  final Future<void> Function(Set<String> ids)? onDelete;
  final VoidCallback? onBack;
}

/// `archived` (`js/screens/home.js`): the archived chats. A swipe to the
/// left unarchives (with Undo); selection offers Unarchive, Delete and ⋮.
class ArchivedChatsScreen extends StatefulWidget {
  const ArchivedChatsScreen({
    super.key,
    required this.model,
    this.actions = const ArchivedChatsActions(),
  });

  final ArchivedChatsModel model;
  final ArchivedChatsActions actions;

  @override
  State<ArchivedChatsScreen> createState() => _ArchivedChatsScreenState();
}

class _ArchivedChatsScreenState extends State<ArchivedChatsScreen> {
  final _selected = <String>{};

  void _unarchive(Set<String> ids) {
    widget.actions.onSetArchived?.call(ids, archived: false);
    showOrbitToast(
      context,
      'Chat unarchived',
      actionLabel: 'Undo',
      onAction: () => widget.actions.onSetArchived?.call(ids, archived: true),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final m = widget.model;
    final a = widget.actions;
    final top = MediaQuery.paddingOf(context).top;
    final bar = _selected.isEmpty
        ? OrbitAppBar(
            title: 'Archived chats',
            onLead: a.onBack ?? () => Navigator.maybePop(context),
          )
        : OrbitAppBar(
            title: '${_selected.length} selected',
            selection: true,
            lead: OrbitAppBarLead.close,
            leadTooltip: 'Cancel selection',
            onLead: () => setState(_selected.clear),
            actions: [
              OrbitIconButton(
                icon: OrbitIcons.trayArrowUp,
                tooltip: 'Unarchive chats',
                color: t.onInverse,
                onPressed: () {
                  final ids = {..._selected};
                  setState(_selected.clear);
                  _unarchive(ids);
                },
              ),
              OrbitIconButton(
                icon: OrbitIcons.trash,
                tooltip: 'Delete chats',
                color: t.onInverse,
                onPressed: () {
                  final ids = {..._selected};
                  showOrbitDialog(
                    context,
                    title: ids.length > 1
                        ? 'Delete ${ids.length} chats?'
                        : 'Delete this chat?',
                    text:
                        'The messages are removed from this device. People '
                        'you chatted with keep their copies.',
                    actions: [
                      const OrbitDialogAction('Cancel'),
                      OrbitDialogAction(
                        'Delete',
                        kind: OrbitButtonKind.danger,
                        onPressed: () {
                          a.onDelete?.call(ids);
                          setState(_selected.clear);
                        },
                      ),
                    ],
                  );
                },
              ),
              OrbitIconButton(
                icon: OrbitIcons.dotsThreeVertical,
                tooltip: 'More options',
                color: t.onInverse,
                onPressed: () {
                  final ids = {..._selected};
                  showOrbitMenu(context, [
                    OrbitMenuItem(
                      icon: OrbitIcons.bellSlash,
                      label: 'Mute…',
                      onTap: () => a.onMute?.call(ids, MuteFor.eightHours),
                    ),
                    OrbitMenuItem(
                      icon: OrbitIcons.checks,
                      label: 'Mark as read',
                      onTap: () => a.onMarkRead?.call(ids),
                    ),
                  ]);
                },
              ),
            ],
          );
    final body = switch (m.status) {
      ListStatus.loading => <Widget>[
        const OrbitSkeleton(count: 3, label: 'Loading chats'),
      ],
      ListStatus.failed => <Widget>[
        const OrbitLoadFailed(title: 'Your chats could not be loaded.'),
      ],
      ListStatus.ready when m.chats.isEmpty => <Widget>[
        const OrbitEmptyState(
          icon: OrbitIcons.archive,
          title: 'No archived chats',
          text: 'Chats you archive stay here until you unarchive them.',
        ),
      ],
      ListStatus.ready => <Widget>[
        for (final c in m.chats)
          OrbitSwipeRow(
            key: ValueKey(c.id),
            end: OrbitSwipeAction(
              icon: OrbitIcons.trayArrowUp,
              label: 'Unarchive',
              onSwiped: () => _unarchive({c.id}),
            ),
            child: OrbitChatListTile(
              item: c,
              background: t.bg,
              selected: _selected.contains(c.id) || c.id == m.openChatId,
              onTap: () => _selected.isNotEmpty
                  ? setState(
                      () => _selected.contains(c.id)
                          ? _selected.remove(c.id)
                          : _selected.add(c.id),
                    )
                  : a.onOpenChat?.call(c.id),
              onLongPress: () => setState(() => _selected.add(c.id)),
            ),
          ),
      ],
    };
    return ColoredBox(
      color: t.bg,
      child: Padding(
        padding: EdgeInsets.only(top: top),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            bar,
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(top: 6),
                children: body,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
