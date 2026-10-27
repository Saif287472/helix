import 'package:flutter/material.dart';

import 'package:orbit_ui/src/components/avatar.dart';
import 'package:orbit_ui/src/components/list_rows.dart';
import 'package:orbit_ui/src/components/page_parts.dart';
import 'package:orbit_ui/src/components/pages.dart';
import 'package:orbit_ui/src/components/state_kit.dart';
import 'package:orbit_ui/src/icons/orbit_icons.dart';
import 'package:orbit_ui/src/models/view_models.dart';
import 'package:orbit_ui/src/screens/home/home_models.dart' show ListStatus;
import 'package:orbit_ui/src/theme/orbit_metrics.dart';
import 'package:orbit_ui/src/theme/orbit_text.dart';
import 'package:orbit_ui/src/theme/orbit_tokens.dart';

/// One starred message in the list: the chat it is in, who wrote it, what it
/// says and when.
class StarredItem extends HelixValue {
  const StarredItem({
    required this.chatId,
    required this.messageId,
    required this.title,
    required this.avatar,
    required this.who,
    required this.text,
    this.timeLabel = '',
  });

  final String chatId;
  final String messageId;

  /// The chat's name.
  final String title;
  final HelixAvatarModel avatar;

  /// "You", or the sender's first name.
  final String who;

  /// What the message says on one line ("Photo" for a picture).
  final String text;
  final String timeLabel;

  @override
  List<Object?> get props => [
    chatId,
    messageId,
    title,
    avatar,
    who,
    text,
    timeLabel,
  ];
}

class StarredModel {
  const StarredModel({this.items = const [], this.status = ListStatus.ready});

  /// The most recently starred first.
  final List<StarredItem> items;
  final ListStatus status;
}

class StarredActions {
  const StarredActions({this.onOpen, this.onRetry});

  /// Opens the chat at the message.
  final void Function(String chatId, String messageId)? onOpen;
  final VoidCallback? onRetry;
}

/// `starred`: every message you starred, across all your chats, the newest
/// star first. A row opens its chat at that message, where Unstar is in the
/// message's menu.
class StarredMessagesScreen extends StatelessWidget {
  const StarredMessagesScreen({
    super.key,
    required this.model,
    this.actions = const StarredActions(),
  });

  final StarredModel model;
  final StarredActions actions;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final m = model;
    return OrbitPage(
      title: 'Starred messages',
      children: [
        switch (m.status) {
          ListStatus.loading => const OrbitPageLoading(),
          ListStatus.failed => OrbitLoadFailed(
            title: 'Starred messages could not be loaded.',
            onRetry: actions.onRetry,
          ),
          ListStatus.ready when m.items.isEmpty => const OrbitEmptyState(
            icon: OrbitIcons.star,
            title: 'No starred messages',
            text:
                'Touch and hold a message and choose Star to keep it here. '
                'Only you can see what you star.',
          ),
          ListStatus.ready => Column(
            children: [
              for (final item in m.items)
                OrbitListRow(
                  title: item.title,
                  sub: '${item.who}: ${item.text}',
                  leading: OrbitAvatar(avatar: item.avatar, size: 44),
                  trailing: OrbitText(
                    item.timeLabel,
                    style: t.mono.style(size: OrbitType.meta, color: t.ink3),
                  ),
                  onTap: () =>
                      actions.onOpen?.call(item.chatId, item.messageId),
                ),
            ],
          ),
        },
      ],
    );
  }
}
