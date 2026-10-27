import 'package:flutter/material.dart';

import 'package:orbit_ui/src/components/bars.dart';
import 'package:orbit_ui/src/components/button.dart';
import 'package:orbit_ui/src/components/chat_rows.dart';
import 'package:orbit_ui/src/components/icon_button.dart';
import 'package:orbit_ui/src/components/overlays.dart';
import 'package:orbit_ui/src/components/page_parts.dart';
import 'package:orbit_ui/src/components/state_kit.dart';
import 'package:orbit_ui/src/icons/orbit_icons.dart';
import 'package:orbit_ui/src/models/view_models.dart';
import 'package:orbit_ui/src/screens/home/home_models.dart';
import 'package:orbit_ui/src/theme/orbit_tokens.dart';

/// What the Locked chats screen shows. [unlocked] is whether the person has
/// passed the phone's own unlock; until then nothing of the chats is drawn.
class LockedChatsModel {
  const LockedChatsModel({
    this.chats = const [],
    this.status = ListStatus.ready,
    this.unlocked = false,
    this.openChatId,
  });

  final List<HelixChatListItem> chats;
  final ListStatus status;
  final bool unlocked;
  final String? openChatId;
}

class LockedChatsActions {
  const LockedChatsActions({
    this.onOpenChat,
    this.onRemoveLock,
    this.onUnlock,
    this.onBack,
  });

  final void Function(String chatId)? onOpenChat;

  /// Takes the lock off the chats: they go back to the chat list.
  final Future<void> Function(Set<String> ids)? onRemoveLock;

  /// Asks for the phone's own unlock (fingerprint, face, PIN).
  final VoidCallback? onUnlock;
  final VoidCallback? onBack;
}

/// What stands where locked content would be until the phone's unlock has
/// been passed: a lock, a sentence and the button that asks for it. Shared by
/// the Locked chats screen and a locked chat opened from a notification or a
/// link.
class OrbitLockedCover extends StatelessWidget {
  const OrbitLockedCover({
    super.key,
    required this.onUnlock,
    this.title = 'Locked',
    this.text =
        'Unlock with your fingerprint, face or PIN to see locked chats.',
  });

  final VoidCallback? onUnlock;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => OrbitEmptyState(
    icon: OrbitIcons.lock,
    title: title,
    text: text,
    action: OrbitButton(
      label: 'Unlock',
      icon: OrbitIcons.lockSimpleOpen,
      onPressed: onUnlock ?? () {},
    ),
  );
}

/// The locked chats: behind the unlock, listed like the archived ones. A
/// long press selects, and the app bar offers Remove lock.
class LockedChatsScreen extends StatefulWidget {
  const LockedChatsScreen({
    super.key,
    required this.model,
    this.actions = const LockedChatsActions(),
  });

  final LockedChatsModel model;
  final LockedChatsActions actions;

  @override
  State<LockedChatsScreen> createState() => _LockedChatsScreenState();
}

class _LockedChatsScreenState extends State<LockedChatsScreen> {
  final _selected = <String>{};

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final m = widget.model;
    final a = widget.actions;
    final top = MediaQuery.paddingOf(context).top;
    final selecting = m.unlocked && _selected.isNotEmpty;
    final bar = selecting
        ? OrbitAppBar(
            title: '${_selected.length} selected',
            selection: true,
            lead: OrbitAppBarLead.close,
            leadTooltip: 'Cancel selection',
            onLead: () => setState(_selected.clear),
            actions: [
              OrbitIconButton(
                icon: OrbitIcons.lockSimpleOpen,
                tooltip: 'Remove lock',
                color: t.onInverse,
                onPressed: () {
                  final ids = {..._selected};
                  setState(_selected.clear);
                  a.onRemoveLock?.call(ids);
                  showOrbitToast(
                    context,
                    ids.length > 1 ? 'Chats unlocked' : 'Chat unlocked',
                  );
                },
              ),
            ],
          )
        : OrbitAppBar(
            title: 'Locked chats',
            onLead: a.onBack ?? () => Navigator.maybePop(context),
          );
    final body = !m.unlocked
        ? <Widget>[OrbitLockedCover(onUnlock: a.onUnlock)]
        : switch (m.status) {
            ListStatus.loading => <Widget>[
              const OrbitSkeleton(count: 3, label: 'Loading chats'),
            ],
            ListStatus.failed => <Widget>[
              const OrbitLoadFailed(title: 'Your chats could not be loaded.'),
            ],
            ListStatus.ready when m.chats.isEmpty => <Widget>[
              const OrbitEmptyState(
                icon: OrbitIcons.lock,
                title: 'No locked chats',
                text:
                    'Touch and hold a chat on the Chats tab and choose Lock '
                    'chat. It moves here, out of sight.',
              ),
            ],
            ListStatus.ready => <Widget>[
              for (final c in m.chats)
                OrbitChatListTile(
                  key: ValueKey(c.id),
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
