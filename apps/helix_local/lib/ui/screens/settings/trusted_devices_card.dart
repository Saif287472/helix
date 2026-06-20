import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix/providers/identity_providers.dart'
    show knownPeersProvider, trustServiceProvider;
import 'package:helix/ui/screens/settings/settings_widgets.dart';

class TrustedDevicesCard extends ConsumerWidget {
  const TrustedDevicesCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final trusted =
        ref.watch(knownPeersProvider).value?.where((p) => p.trusted).toList() ??
        [];
    final trust = ref.read(trustServiceProvider);

    if (trusted.isEmpty) {
      return SettingsCard(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(
              children: [
                SettingsIcon(Icons.verified_user_outlined, color: Colors.teal),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    'No trusted devices yet. Open a chat → ⋮ → Verify identity to trust a device.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withAlpha(160),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return SettingsCard(
      children: trusted.map((peer) {
        final since =
            '${peer.firstSeenAt.day.toString().padLeft(2, '0')}/'
            '${peer.firstSeenAt.month.toString().padLeft(2, '0')}/'
            '${peer.firstSeenAt.year}';
        return ListTile(
          leading: CircleAvatar(
            radius: 20,
            backgroundColor: Colors.teal.withAlpha(30),
            child: Text(
              (peer.nickname ?? peer.lastPublicName).isNotEmpty
                  ? (peer.nickname ?? peer.lastPublicName)[0].toUpperCase()
                  : '?',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.teal,
              ),
            ),
          ),
          title: Text(peer.nickname ?? peer.lastPublicName),
          subtitle: Text('Trusted since $since', style: theme.textTheme.bodySmall),
          trailing: PopupMenuButton<String>(
            onSelected: (action) async {
              switch (action) {
                case 'rename':
                  final ctrl = TextEditingController(
                    text: peer.nickname ?? peer.lastPublicName,
                  );
                  final nick = await showDialog<String>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Rename device'),
                      content: TextField(
                        controller: ctrl,
                        autofocus: true,
                        decoration: const InputDecoration(labelText: 'Nickname'),
                        onSubmitted: (_) => Navigator.of(ctx).pop(ctrl.text),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(null),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.of(ctx).pop(ctrl.text),
                          child: const Text('Save'),
                        ),
                      ],
                    ),
                  );
                  ctrl.dispose();
                  if (nick != null && nick.trim().isNotEmpty) {
                    await trust.renamePeer(peer.fingerprint, nick.trim());
                  }
                case 'untrust':
                  await trust.untrustPeer(peer.fingerprint);
                case 'forget':
                  await trust.forgetPeer(peer.fingerprint);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rename', child: Text('Rename')),
              PopupMenuItem(value: 'untrust', child: Text('Remove trust')),
              PopupMenuItem(
                value: 'forget',
                child: Text('Forget device', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
