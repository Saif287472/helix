import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:helix_remote/features/chats/application/locked_access.dart';
import 'package:helix_remote/features/chats/application/chat_actions.dart';
import 'package:helix_remote/features/chats/application/chat_list_provider.dart';
import 'package:helix_remote/shared/navigation/chat_locations.dart';
import 'package:orbit_ui/models.dart' show HelixChatListItem;
import 'package:orbit_ui/orbit_ui.dart' as orbit;

/// The locked chats: nothing of them is drawn until the phone's own unlock
/// has been passed, and the access is held for as long as this screen (and a
/// chat opened from it) lives.
class LockedChatsScreen extends ConsumerStatefulWidget {
  const LockedChatsScreen({super.key});

  @override
  ConsumerState<LockedChatsScreen> createState() => _LockedChatsScreenState();
}

class _LockedChatsScreenState extends ConsumerState<LockedChatsScreen> {
  late final LockedChatAccess _access;
  bool _asked = false;

  @override
  void initState() {
    super.initState();
    _access = ref.read(lockedChatAccessProvider.notifier)..hold();
  }

  @override
  void dispose() {
    final access = _access;
    Future.microtask(access.release);
    super.dispose();
  }

  void _unlock() => unawaited(_access.unlock());

  @override
  Widget build(BuildContext context) {
    final unlocked = ref.watch(lockedChatAccessProvider);
    ref.listen(lockedChatAccessProvider, (_, now) {
      if (!now) _asked = false;
    });
    if (!unlocked && !_asked) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_asked) {
          _asked = true;
          _unlock();
        }
      });
    }
    final async = ref.watch(lockedChatListProvider);
    final status = async.isLoading
        ? orbit.ListStatus.loading
        : async.hasError
        ? orbit.ListStatus.failed
        : orbit.ListStatus.ready;
    final typing = ref.watch(chatTypingProvider).value ?? const {};
    final chats = [
      for (final c in async.value ?? const <HelixChatListItem>[])
        c.copyWith(typingLabel: typing[c.id]),
    ];
    final actions = ref.read(chatActionsProvider);
    return orbit.LockedChatsScreen(
      model: orbit.LockedChatsModel(
        chats: chats,
        status: status,
        unlocked: unlocked,
      ),
      actions: orbit.LockedChatsActions(
        onOpenChat: (id) => context.push(chatLocation(id)),
        onRemoveLock: (ids) async {
          await actions.setLocked(ids, locked: false);
        },
        onUnlock: _unlock,
        onBack: () => Navigator.maybePop(context),
      ),
    );
  }
}
