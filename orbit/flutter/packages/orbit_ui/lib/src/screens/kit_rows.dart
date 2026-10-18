import 'package:flutter/material.dart';

import 'package:orbit_ui/src/components/chat_rows.dart';
import 'package:orbit_ui/src/components/overlays.dart';
import 'package:orbit_ui/src/fakes/orbit_fakes.dart';
import 'package:orbit_ui/src/icons/orbit_icons.dart';
import 'package:orbit_ui/src/models/view_models.dart';
import 'package:orbit_ui/src/screens/kit_sheet.dart';
import 'package:orbit_ui/src/theme/orbit_tokens.dart';

/// `kit-rows` (`prototype/js/screens/states.js`): every chat-list and
/// call-log row in the prototype's sample data, as Home draws them.
class KitRowsScreen extends StatefulWidget {
  const KitRowsScreen({super.key});

  @override
  State<KitRowsScreen> createState() => _KitRowsScreenState();
}

class _KitRowsScreenState extends State<KitRowsScreen> {
  final _pinned = <String>{
    for (final c in OrbitFakes.chats)
      if (c.pinned) c.id,
  };

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    void archived() => showOrbitToast(
      context,
      'Chat archived',
      actionLabel: 'Undo',
      onAction: () {},
    );
    return OrbitKitPage(
      title: 'Rows',
      intro:
          'The chat list and call log rows, every kind of preview in the '
          'sample data. Swipe a row to see what is behind it.',
      children: [
        const OrbitKitLabel('Chats'),
        for (final c in OrbitFakes.chats)
          OrbitSwipeRow(
            start: OrbitSwipeAction(
              icon: OrbitIcons.pushPin,
              label: _pinned.contains(c.id) ? 'Unpin' : 'Pin',
              onSwiped: () => setState(
                () => _pinned.contains(c.id)
                    ? _pinned.remove(c.id)
                    : _pinned.add(c.id),
              ),
            ),
            end: OrbitSwipeAction(
              icon: OrbitIcons.archive,
              label: 'Archive',
              onSwiped: archived,
            ),
            child: OrbitChatListTile(
              item: _pinned.contains(c.id) == c.pinned
                  ? c
                  : _withPin(c, _pinned.contains(c.id)),
              background: t.bg,
              onTap: () {},
            ),
          ),
        const OrbitKitLabel('Selected'),
        OrbitChatListTile(
          item: OrbitFakes.chats.first,
          selected: true,
          onTap: () {},
        ),
        const OrbitKitLabel('Archived'),
        for (final c in OrbitFakes.archived)
          OrbitChatListTile(item: c, showArchived: true, onTap: () {}),
        const OrbitKitLabel('Calls'),
        for (final c in OrbitFakes.calls)
          OrbitSwipeRow(
            color: t.danger,
            end: OrbitSwipeAction(
              icon: OrbitIcons.trash,
              label: 'Delete',
              onSwiped: () {},
            ),
            child: OrbitCallLogTile(
              item: c,
              background: t.bg,
              onTap: () {},
              onCallBack: () {},
            ),
          ),
      ],
    );
  }

  static HelixChatListItem _withPin(HelixChatListItem c, bool on) =>
      HelixChatListItem(
        id: c.id,
        title: c.title,
        avatar: c.avatar,
        preview: c.preview,
        timeLabel: c.timeLabel,
        unreadCount: c.unreadCount,
        hasMention: c.hasMention,
        markedUnread: c.markedUnread,
        pinned: on,
        muted: c.muted,
        archived: c.archived,
        typingLabel: c.typingLabel,
        online: c.online,
        verified: c.verified,
      );
}
