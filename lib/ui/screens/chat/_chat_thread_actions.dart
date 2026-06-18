part of 'chat_screen.dart';

mixin _ChatThreadActionsMixin on _ChatScreenBase {
  // ---------------------------------------------------------------------------
  // Other actions
  // ---------------------------------------------------------------------------

  Future<void> _clearThread() async {
    final confirmed = await _showConfirmDialog(
      context,
      title: 'Clear local thread?',
      body:
          'This removes all messages from your view only. '
          'The peer keeps their own copy.',
      confirmLabel: 'Clear',
      destructive: true,
    );
    if (!confirmed) return;
    await ref.read(messagingServiceProvider).clearThread(widget.threadId);
  }

  Future<void> _closeThread() async {
    final confirmed = await _showConfirmDialog(
      context,
      title: 'Delete local chat?',
      body:
          'This disconnects the chat and erases all messages from this device. '
          'The peer keeps their own copy.',
      confirmLabel: 'Delete chat',
      destructive: true,
    );
    if (!confirmed) return;
    await ref.read(messagingServiceProvider).closeThread(widget.threadId);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _endConnection() async {
    final confirmed = await _showConfirmDialog(
      context,
      title: 'Disconnect session?',
      body:
          'This closes the live encrypted session but keeps the local chat '
          'history so you can reconnect later.',
      confirmLabel: 'Disconnect',
      destructive: true,
    );
    if (!confirmed) return;
    await ref.read(messagingServiceProvider).endConnection(widget.threadId);
  }

  void _showInfoDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('About this chat'),
        content: const Text(
          'Messages exist only in this device\'s memory.\n\n'
          'Closing Helix erases all conversations permanently. '
          'Nothing is written to disk or sent to any server.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _sendNewRequest(ChatThread thread) async {
    final livePeers = ref.read(discoveryCoordinatorProvider).peers;
    final livePeer = livePeers
        .where(
          (p) =>
              (thread.peerSessionId.isNotEmpty &&
                  p.sessionId == thread.peerSessionId) ||
              (p.deviceSuffix == thread.peerDeviceSuffix &&
                  p.displayName == thread.peerDisplayName),
        )
        .firstOrNull;
    if (livePeer == null && (thread.peerHost.isEmpty || thread.peerPort <= 0)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Peer address is unavailable. Find the peer again from Home.',
            ),
          ),
        );
      }
      return;
    }
    final peer =
        livePeer ??
        Peer(
          sessionId: thread.peerSessionId,
          displayName: thread.peerDisplayName,
          deviceSuffix: thread.peerDeviceSuffix,
          host: thread.peerHost,
          port: thread.peerPort,
          source: PeerSource.directIp,
          seenAt: DateTime.now(),
          protocolMajor: kProtocolMajor,
          protocolMinor: kProtocolMinor,
        );
    final profileSvc = ref.read(profileServiceProvider);
    final identity = profileSvc.identity;
    if (identity == null) return;
    final displayName = profileSvc.profile?.displayName ?? '';
    final sessionId = ref.read(sessionServiceProvider).sessionId;
    final messaging = ref.read(messagingServiceProvider);
    final threadId = thread.threadId;
    bool canceled = false;
    BuildContext? dialogCtx;
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          dialogCtx = ctx;
          return AlertDialog(
            title: Text('Reconnecting to ${thread.peerDisplayName}'),
            content: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 16),
                Flexible(child: Text('Waiting for acceptance…')),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  canceled = true;
                  Navigator.of(ctx).pop();
                },
                child: const Text('Cancel'),
              ),
            ],
          );
        },
      ),
    );

    void closeDialog() {
      final ctx = dialogCtx;
      if (ctx != null && ctx.mounted) Navigator.of(ctx).pop();
    }

    messaging.injectSystemMessage(threadId, 'Reconnect request sent…');
    try {
      final result = await ref
          .read(requestServiceProvider)
          .sendRequest(
            peer,
            RequestSourceMethod.directIp,
            identity,
            sessionId,
            displayName,
            localTcpPort: ref.read(activeTcpPortProvider),
          );
      closeDialog();
      if (canceled || !mounted) return;
      if (result.request.status == RequestStatus.accepted &&
          result.channel != null) {
        messaging.attachChannel(
          result.channel!.threadId,
          result.request.peerDisplayName,
          result.request.peerDeviceSuffix,
          result.channel!,
          result.request.peerSessionId,
          result.request.peerHost,
          result.request.peerPort,
        );
        messaging.injectSystemMessage(threadId, 'Reconnected.');
      } else {
        messaging.injectSystemMessage(
          threadId,
          'Request ${result.request.status.name} by ${thread.peerDisplayName}.',
        );
      }
    } catch (e) {
      closeDialog();
      if (canceled || !mounted) return;
      messaging.injectSystemMessage(
        threadId,
        'Could not reach ${thread.peerDisplayName}.',
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Future<bool> _showConfirmDialog(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
  required bool destructive,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          style: destructive
              ? TextButton.styleFrom(foregroundColor: Colors.red)
              : null,
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}
