// lib/ui/widgets/trusted_devices_sheet.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_domain/core/constants.dart';
import 'package:helix_domain/domain/models.dart';
import 'package:helix/providers/app_providers.dart';
import 'package:helix/ui/app_router.dart';

class TrustedDevicesSheet extends ConsumerStatefulWidget {
  const TrustedDevicesSheet({super.key});

  @override
  ConsumerState<TrustedDevicesSheet> createState() =>
      _TrustedDevicesSheetState();
}

class _TrustedDevicesSheetState extends ConsumerState<TrustedDevicesSheet> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final presence = ref.watch(trustedPeersWithPresenceProvider);

    final online = presence.where((e) => e.nearbyMatch != null).toList();
    final offline = presence.where((e) => e.nearbyMatch == null).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.9,
      expand: false,
      builder: (ctx, scrollCtrl) => Column(
        children: [
          // Handle
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 8),
            child: Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Row(
              children: [
                Icon(
                  Icons.verified_user_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Text(
                  'Trusted Devices',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: presence.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        'No trusted devices yet.\nVerify a contact\'s identity in a chat to add them.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withAlpha(160),
                        ),
                      ),
                    ),
                  )
                : ListView(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    children: [
                      if (online.isNotEmpty) ...[
                        _SectionHeader(label: 'Online', theme: theme),
                        ...online.map(
                          (e) => _TrustedPeerTile(
                            peer: e.peer,
                            nearbyMatch: e.nearbyMatch,
                          ),
                        ),
                      ],
                      if (offline.isNotEmpty) ...[
                        if (online.isNotEmpty) const SizedBox(height: 8),
                        _SectionHeader(label: 'Offline', theme: theme),
                        ...offline.map(
                          (e) =>
                              _TrustedPeerTile(peer: e.peer, nearbyMatch: null),
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.theme});

  final String label;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurface.withAlpha(160),
        ),
      ),
    );
  }
}

class _TrustedPeerTile extends ConsumerStatefulWidget {
  const _TrustedPeerTile({required this.peer, required this.nearbyMatch});

  final KnownPeer peer;
  final Peer? nearbyMatch;

  @override
  ConsumerState<_TrustedPeerTile> createState() => _TrustedPeerTileState();
}

class _TrustedPeerTileState extends ConsumerState<_TrustedPeerTile> {
  bool _busy = false;

  bool get _isOnline => widget.nearbyMatch != null;

  Peer _buildSyntheticPeer() {
    final match = widget.nearbyMatch;
    return Peer(
      sessionId: match?.sessionId ?? '',
      displayName: widget.peer.lastPublicName,
      deviceSuffix: widget.peer.deviceSuffix,
      host: match?.host ?? widget.peer.lastHost,
      port: match?.port ?? widget.peer.lastPort,
      source: PeerSource.directIp,
      seenAt: DateTime.now(),
      protocolMajor: kProtocolMajor,
      protocolMinor: kProtocolMinor,
    );
  }

  Future<void> _connect() async {
    if (_busy) return;
    final peer = _buildSyntheticPeer();
    if (peer.host.isEmpty || peer.port == 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No known address for this device.')),
        );
      }
      return;
    }

    final navigator = Navigator.of(context);
    final profileSvc = ref.read(profileServiceProvider);
    final identity = profileSvc.identity;
    if (identity == null) return;
    final displayName = profileSvc.profile?.displayName ?? '';
    final sessionId = ref.read(sessionServiceProvider).sessionId;

    setState(() => _busy = true);
    bool canceled = false;
    BuildContext? dialogCtx;
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          dialogCtx = ctx;
          return AlertDialog(
            title: Text('Connecting to ${widget.peer.displayName}'),
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
      final request = result.request;
      if (request.status == RequestStatus.accepted && result.channel != null) {
        ref
            .read(messagingServiceProvider)
            .attachChannel(
              result.channel!.threadId,
              request.peerDisplayName,
              request.peerDeviceSuffix,
              result.channel!,
              request.peerSessionId,
              request.peerHost,
              request.peerPort,
            );
        if (mounted) {
          Navigator.of(context).pop(); // close sheet
          navigator.pushNamed('${AppRoutes.chat}/${result.channel!.threadId}');
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Request ${request.status.name}.')),
        );
      }
    } catch (e) {
      closeDialog();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not reach device: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendOneWay() async {
    if (_busy) return;
    final peer = _buildSyntheticPeer();
    if (peer.host.isEmpty || peer.port == 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No known address for this device.')),
        );
      }
      return;
    }

    final ctrl = TextEditingController();
    final message = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Message to ${widget.peer.displayName}'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 4,
          maxLength: 500,
          decoration: const InputDecoration(hintText: 'Type your message…'),
          onSubmitted: (_) => Navigator.of(ctx).pop(ctrl.text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    final text = message?.trim() ?? '';
    if (text.isEmpty || !mounted) return;

    setState(() => _busy = true);
    try {
      final profileSvc = ref.read(profileServiceProvider);
      final identity = profileSvc.identity;
      if (identity == null) return;
      final displayName = profileSvc.profile?.displayName ?? '';
      final sessionId = ref.read(sessionServiceProvider).sessionId;
      await ref
          .read(requestServiceProvider)
          .sendOneWayMessage(peer, identity, sessionId, displayName, text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('One-way message sent. No delivery receipt.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not send: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lastSeen = widget.peer.lastSeenAt;
    final lastSeenStr =
        '${lastSeen.day.toString().padLeft(2, '0')}/'
        '${lastSeen.month.toString().padLeft(2, '0')}/'
        '${lastSeen.year}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: Colors.teal.withAlpha(30),
                    child: Text(
                      widget.peer.displayName.isNotEmpty
                          ? widget.peer.displayName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Colors.teal,
                      ),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: _isOnline ? Colors.green : Colors.grey,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: theme.colorScheme.surface,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.peer.displayName,
                      style: theme.textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      _isOnline ? 'Online' : 'Last seen $lastSeenStr',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withAlpha(130),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (_busy)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else ...[
                IconButton(
                  icon: const Icon(Icons.send_outlined, size: 20),
                  tooltip: 'One-way message',
                  onPressed: _isOnline ? _sendOneWay : null,
                ),
                FilledButton.tonal(
                  onPressed: _isOnline ? _connect : () => _connect(),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    visualDensity: VisualDensity.compact,
                    foregroundColor: _isOnline
                        ? null
                        : theme.colorScheme.onSurface.withAlpha(80),
                    backgroundColor: _isOnline
                        ? null
                        : theme.colorScheme.surfaceContainerHighest,
                  ),
                  child: const Text('Connect'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
