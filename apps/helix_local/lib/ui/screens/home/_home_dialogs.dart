part of 'home_screen.dart';

// ---------------------------------------------------------------------------
// Shared helpers (used by home tab and chat screen)
// ---------------------------------------------------------------------------

Future<bool> handleExistingActiveThread(
  BuildContext context,
  WidgetRef ref,
  Peer peer,
) async {
  final existing = ref
      .read(messagingServiceProvider)
      .findActiveThreadForPeer(peer);
  if (existing == null) return false;

  final choice = await showDialog<String>(
    context: context,
    builder: (dialogCtx) => AlertDialog(
      title: const Text('Already connected'),
      content: Text(
        '${existing.peerDisplayName} already has an active secure chat. '
        'Open that chat, or disconnect it before starting another flow.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogCtx).pop('cancel'),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogCtx).pop('disconnect'),
          child: const Text('Disconnect'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogCtx).pop('open'),
          child: const Text('Open chat'),
        ),
      ],
    ),
  );

  if (!context.mounted) return true;
  switch (choice) {
    case 'open':
      Navigator.of(context).pushNamed('${AppRoutes.chat}/${existing.threadId}');
      return true;
    case 'disconnect':
      await ref.read(messagingServiceProvider).endConnection(existing.threadId);
      return false;
    default:
      return true;
  }
}

Future<String?> showIpPortDialog({
  required BuildContext context,
  required String title,
  required String actionLabel,
  List<String>? ownAddresses,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _IpPortDialog(
      title: title,
      actionLabel: actionLabel,
      ownAddresses: ownAddresses,
    ),
  );
}

class _IpPortDialog extends StatefulWidget {
  const _IpPortDialog({
    required this.title,
    required this.actionLabel,
    this.ownAddresses,
  });

  final String title;
  final String actionLabel;
  final List<String>? ownAddresses;

  @override
  State<_IpPortDialog> createState() => _IpPortDialogState();
}

class _IpPortDialogState extends State<_IpPortDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text.trim());

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ownAddresses = widget.ownAddresses;
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (ownAddresses != null && ownAddresses.isNotEmpty) ...[
              Text('Your device', style: theme.textTheme.labelMedium),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: ownAddresses
                      .map(
                        (addr) => SelectableText(
                          addr,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontFamily: 'monospace',
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
              const SizedBox(height: 16),
              Text('Connect to', style: theme.textTheme.labelMedium),
              const SizedBox(height: 6),
            ],
            TextField(
              controller: _controller,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'IP address and port',
                hintText: '192.168.1.20:42424',
              ),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.actionLabel)),
      ],
    );
  }
}

Future<String?> showOneWayMessageDialog(
  BuildContext context, {
  required String recipientName,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _OneWayMessageDialog(recipientName: recipientName),
  );
}

class _OneWayMessageDialog extends StatefulWidget {
  const _OneWayMessageDialog({required this.recipientName});
  final String recipientName;

  @override
  State<_OneWayMessageDialog> createState() => _OneWayMessageDialogState();
}

class _OneWayMessageDialogState extends State<_OneWayMessageDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Message ${widget.recipientName}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            minLines: 3,
            maxLines: 5,
            maxLength: kMaxMessageBytes,
            decoration: const InputDecoration(
              hintText: 'Important information...',
              alignLabelWithHint: true,
            ),
          ),
          Text(
            'This sends once without connecting. No delivery or read receipt.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: () {
            final text = _controller.text.trim();
            Navigator.of(context).pop(text.isEmpty ? null : text);
          },
          icon: const Icon(Icons.send_outlined, size: 18),
          label: const Text('Send'),
        ),
      ],
    );
  }
}

Future<void> sendOneWayMessageToPeer(
  BuildContext context,
  WidgetRef ref,
  Peer peer,
  String message,
) async {
  final profileSvc = ref.read(profileServiceProvider);
  final identity = profileSvc.identity;
  if (identity == null) return;
  final displayName = profileSvc.profile?.displayName ?? '';
  final sessionId = ref.read(sessionServiceProvider).sessionId;

  try {
    await ref
        .read(requestServiceProvider)
        .sendOneWayMessage(peer, identity, sessionId, displayName, message);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('One-way message sent. No delivery receipt.'),
        ),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not send: $e')));
    }
  }
}
