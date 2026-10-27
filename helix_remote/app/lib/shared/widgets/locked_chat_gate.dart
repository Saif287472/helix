import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/chat/chat_gateway.dart';
import 'package:helix_remote/core/security/locked_chats.dart';
import 'package:orbit_ui/orbit_ui.dart' as orbit;

/// Whether a chat is locked, live.
final chatLockedProvider = StreamProvider.family<bool, String>((
  ref,
  conversationId,
) async* {
  final gateway = await ref.watch(chatGatewayProvider.future);
  yield* gateway
      .watchChat(conversationId)
      .map((chat) => chat?.lockedAt != null);
});

/// Shows [child] (a screen of the chat [conversationId]) unless the chat is
/// locked and the phone's unlock has not been passed, in which case it shows
/// the cover and asks. While it lives it holds the access open, so going from
/// the Locked chats list to a chat, and into its media or settings, asks once.
class LockedChatGate extends ConsumerStatefulWidget {
  const LockedChatGate({
    super.key,
    required this.conversationId,
    required this.child,
  });

  final String conversationId;
  final Widget child;

  @override
  ConsumerState<LockedChatGate> createState() => _LockedChatGateState();
}

class _LockedChatGateState extends ConsumerState<LockedChatGate> {
  late final LockedChatAccess _access;
  bool _asked = false;

  @override
  void initState() {
    super.initState();
    _access = ref.read(lockedChatAccessProvider.notifier)..hold();
  }

  @override
  void dispose() {
    // After the frame: a provider may not change while the tree is torn down.
    final access = _access;
    Future.microtask(access.release);
    super.dispose();
  }

  void _ask() {
    unawaited(
      _access.unlock('Unlock to open this chat').then((ok) {
        if (!ok && mounted) setState(() => _asked = true);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final locked = ref.watch(chatLockedProvider(widget.conversationId));
    final open = ref.watch(lockedChatAccessProvider);
    final bg = orbit.OrbitTokens.of(context).bg;
    // Back out of the unlock (the app left the screen): ask again on return.
    ref.listen(lockedChatAccessProvider, (_, now) {
      if (!now) _asked = false;
    });
    // Until it is known whether the chat is locked, nothing of it is drawn.
    if (!locked.hasValue) return ColoredBox(color: bg);
    if (locked.value != true || open) return widget.child;
    if (!_asked) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_asked) {
          _asked = true;
          _ask();
        }
      });
    }
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        leading: BackButton(onPressed: () => Navigator.maybePop(context)),
      ),
      body: Center(
        child: orbit.OrbitLockedCover(
          title: 'This chat is locked',
          text: 'Unlock with your fingerprint, face or PIN to open it.',
          onUnlock: _ask,
        ),
      ),
    );
  }
}
