import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/features/conversation/application/message_info.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// "Message info": when a message was sent, and when each person got it and
/// read it.
class MessageInfoScreen extends ConsumerWidget {
  const MessageInfoScreen({super.key, required this.rowid});

  final int rowid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(messageInfoProvider(rowid));
    return Scaffold(
      appBar: AppBar(title: const Text('Message info')),
      body: switch (info) {
        AsyncData(:final value) when value == null => const HelixEmptyState(
          icon: Icons.info_outline,
          title: 'Message not found',
          message: 'It may have been deleted.',
        ),
        AsyncData(:final value) => _Body(info: value!),
        AsyncError() => const HelixErrorState(
          message: 'The details could not be loaded.',
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.info});

  final MessageInfo info;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      children: [
        if (info.preview.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(HelixSpace.md),
            child: Text(
              info.preview,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
        ListTile(
          leading: const Icon(Icons.send_outlined),
          title: const Text('Sent'),
          subtitle: Text(info.sentLabel),
        ),
        const Divider(height: 1),
        for (final line in info.lines) ...[
          ListTile(
            leading: HelixAvatar(model: line.avatar, size: HelixAvatarSize.sm),
            title: Text(line.name),
            subtitle: Text(
              [
                if (line.readLabel != null) 'Read ${line.readLabel}',
                if (line.deliveredLabel != null)
                  'Delivered ${line.deliveredLabel}',
                if (line.readLabel == null && line.deliveredLabel == null)
                  'Not delivered yet',
              ].join('\n'),
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            isThreeLine: line.readLabel != null && line.deliveredLabel != null,
          ),
        ],
      ],
    );
  }
}
