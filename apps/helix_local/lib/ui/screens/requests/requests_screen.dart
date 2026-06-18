// lib/ui/screens/requests/requests_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_local_domain/domain/models.dart';
import 'package:helix/providers/app_providers.dart';
import 'package:helix/providers/controllers/trust_service.dart';
import 'package:helix/ui/app_router.dart';

class RequestsScreen extends ConsumerStatefulWidget {
  const RequestsScreen({super.key});

  @override
  ConsumerState<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends ConsumerState<RequestsScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _matchesInbox(OneWayMessage m) {
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    return m.text.toLowerCase().contains(q) ||
        m.peerDisplayName.toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, ConnectionRequest> requests =
        ref.watch(pendingRequestsProvider);
    final inboxAsync = ref.watch(oneWayInboxProvider);
    final theme = Theme.of(context);

    final allInbox =
        inboxAsync.value ??
        ref.read(messagingServiceProvider).oneWayInbox;
    final inbox = allInbox.where(_matchesInbox).toList();

    final incoming =
        requests.values
            .where(
              (r) =>
                  r.direction == RequestDirection.incoming &&
                  r.status == RequestStatus.pending,
            )
            .toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    final outgoing =
        requests.values
            .where(
              (r) =>
                  r.direction == RequestDirection.outgoing &&
                  r.status == RequestStatus.pending,
            )
            .toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    if (allInbox.isEmpty && incoming.isEmpty && outgoing.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.notifications_none,
                size: 48,
                color: theme.colorScheme.onSurface.withAlpha(80),
              ),
              const SizedBox(height: 12),
              Text(
                'No pending requests.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withAlpha(160),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Connection requests from nearby peers will appear here.',
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        // ── Inbox (one-way messages) ────────────────────────────────────────
        if (allInbox.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              'Inbox',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurface.withAlpha(160),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: SearchBar(
              controller: _searchController,
              leading: const Icon(Icons.search),
              hintText: 'Search inbox',
              padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 16),
              ),
              trailing: [
                if (_query.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Clear',
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _query = '');
                    },
                  ),
              ],
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          ...inbox.map(
            (m) => _OneWayMessageCard(
              key: ValueKey(m.messageId),
              message: m,
              onDismiss: () => ref
                  .read(messagingServiceProvider)
                  .dismissOneWayMessage(m.messageId),
            ),
          ),
          if (inbox.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'No messages match "$_query".',
                style: theme.textTheme.bodySmall,
              ),
            ),
          const Divider(height: 24, indent: 16, endIndent: 16),
        ],
        // ── Incoming requests ───────────────────────────────────────────────
        if (incoming.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Incoming',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurface.withAlpha(160),
              ),
            ),
          ),
          ...incoming.map(
            (r) => IncomingRequestCard(key: ValueKey(r.requestId), request: r),
          ),
        ],
        // ── Outgoing requests ───────────────────────────────────────────────
        if (outgoing.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Outgoing',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurface.withAlpha(160),
              ),
            ),
          ),
          ...outgoing.map(
            (r) => OutgoingRequestCard(key: ValueKey(r.requestId), request: r),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// One-way message card (Inbox section)
// ---------------------------------------------------------------------------

class _OneWayMessageCard extends StatelessWidget {
  const _OneWayMessageCard({
    super.key,
    required this.message,
    required this.onDismiss,
  });

  final OneWayMessage message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timeStr =
        '${message.timestamp.hour.toString().padLeft(2, '0')}:'
        '${message.timestamp.minute.toString().padLeft(2, '0')}';
    final expired = message.isExpired;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: theme.colorScheme.tertiary.withAlpha(30),
                  child: Text(
                    message.peerDisplayName.isNotEmpty
                        ? message.peerDisplayName[0].toUpperCase()
                        : '?',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.tertiary,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        message.peerDisplayName,
                        style: theme.textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${message.peerDeviceSuffix} · $timeStr',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withAlpha(130),
                        ),
                      ),
                    ],
                  ),
                ),
                // Subject pill or expiry
                if (message.subject != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      message.subject!,
                      style: theme.textTheme.labelSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (expired)
                  Text(
                    'Expired',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Dismiss',
                  onPressed: onDismiss,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withAlpha(
                  expired ? 80 : 180,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                message.text,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: expired
                      ? theme.colorScheme.onSurface.withAlpha(100)
                      : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Incoming request card
// ---------------------------------------------------------------------------

class IncomingRequestCard extends ConsumerStatefulWidget {
  const IncomingRequestCard({super.key, required this.request});

  final ConnectionRequest request;

  @override
  ConsumerState<IncomingRequestCard> createState() =>
      _IncomingRequestCardState();
}

class _IncomingRequestCardState extends ConsumerState<IncomingRequestCard> {
  late Timer _timer;
  Duration _remaining = Duration.zero;
  bool _actioning = false;

  @override
  void initState() {
    super.initState();
    _remaining = widget.request.remaining;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _remaining = widget.request.remaining;
      });
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  Widget _buildBadge(ThemeData theme, TrustService trust, String fp) {
    if (widget.request.isPossibleImpersonation) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              size: 14,
              color: Colors.red,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                'Identity doesn\'t match your trusted contact with this name',
                style: theme.textTheme.labelSmall?.copyWith(color: Colors.red),
              ),
            ),
          ],
        ),
      );
    }

    if (trust.isTrusted(fp)) {
      final publicName = widget.request.peerDisplayName;
      final nick = trust.getPeer(fp)?.nickname ?? '';
      final nameDiffers = nick.toLowerCase() != publicName.toLowerCase();
      return Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(
          children: [
            const Icon(Icons.verified_user, size: 13, color: Colors.teal),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                nameDiffers ? 'Trusted · public name: $publicName' : 'Trusted',
                style: theme.textTheme.labelSmall?.copyWith(color: Colors.teal),
              ),
            ),
          ],
        ),
      );
    }

    if (trust.isKnown(fp)) {
      return Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(
          children: [
            Icon(
              Icons.history,
              size: 13,
              color: theme.colorScheme.onSurface.withAlpha(130),
            ),
            const SizedBox(width: 4),
            Text(
              'Previously connected',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurface.withAlpha(130),
              ),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  String get _countdownLabel {
    if (_remaining.isNegative || _remaining.inSeconds <= 0) return 'Expired';
    final s = _remaining.inSeconds;
    if (s >= 60) {
      final m = s ~/ 60;
      final sec = s % 60;
      return '${m}m ${sec.toString().padLeft(2, '0')}s';
    }
    return '${s}s';
  }

  String get _sourceLabel => switch (widget.request.source) {
    RequestSourceMethod.nearby => 'Nearby',
    RequestSourceMethod.secretCode => 'Secret sentence',
    RequestSourceMethod.directIp => 'Direct IP',
  };

  Future<void> _accept() async {
    setState(() => _actioning = true);
    final request = widget.request;
    final navigator = Navigator.of(context);
    try {
      final identity = ref.read(profileServiceProvider).identity;
      if (identity == null) {
        throw StateError('Local identity is not available.');
      }
      final sessionId = ref.read(sessionServiceProvider).sessionId;

      final channel = await ref
          .read(requestServiceProvider)
          .acceptRequest(request.requestId, identity, sessionId);

      if (channel == null) {
        throw StateError('Secure channel was not established.');
      }

      ref
          .read(messagingServiceProvider)
          .attachChannel(
            channel.threadId,
            request.peerDisplayName,
            request.peerDeviceSuffix,
            channel,
            request.peerSessionId,
            request.peerHost,
            request.peerPort,
          );

      ref.read(requestServiceProvider).closeRequestSocket(request.requestId);

      ref.read(pendingRequestsProvider.notifier).remove(request.requestId);

      if (navigator.mounted) {
        navigator.pushNamed('${AppRoutes.chat}/${channel.threadId}');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _actioning = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to accept: $e')));
      }
    }
  }

  Future<void> _reject() async {
    setState(() => _actioning = true);
    try {
      await ref
          .read(requestServiceProvider)
          .rejectRequest(widget.request.requestId);
      ref
          .read(pendingRequestsProvider.notifier)
          .remove(widget.request.requestId);
    } catch (e) {
      if (mounted) {
        setState(() => _actioning = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to reject: $e')));
      }
    }
  }

  Future<void> _block() async {
    final confirmed = await _confirmBlock(
      context,
      widget.request.peerDisplayName,
    );
    if (!confirmed || !mounted) return;
    setState(() => _actioning = true);
    try {
      ref
          .read(requestServiceProvider)
          .blockPeer(widget.request.peerStaticKeyFingerprint);
      ref
          .read(pendingRequestsProvider.notifier)
          .remove(widget.request.requestId);
    } catch (e) {
      if (mounted) {
        setState(() => _actioning = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to block: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isExpired = _remaining.isNegative || _remaining.inSeconds <= 0;

    ref.watch(knownPeersProvider); // rebuild when trust list changes
    final trust = ref.read(trustServiceProvider);
    final fp = widget.request.peerStaticKeyFingerprint;
    final peerName = trust.displayNameFor(fp, widget.request.peerDisplayName);
    final isTrusted = trust.isTrusted(fp);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: theme.colorScheme.primary.withAlpha(30),
                  child: Text(
                    peerName.isNotEmpty ? peerName[0].toUpperCase() : '?',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              peerName,
                              style: theme.textTheme.titleSmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isTrusted) ...[
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.verified_user,
                              size: 13,
                              color: Colors.teal,
                            ),
                          ],
                        ],
                      ),
                      _buildBadge(theme, trust, fp),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Chip(
                            label: Text(
                              widget.request.peerDeviceSuffix,
                              style: theme.textTheme.labelSmall,
                            ),
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                          ),
                          const SizedBox(width: 6),
                          Chip(
                            avatar: const Icon(Icons.wifi_outlined, size: 12),
                            label: Text(
                              _sourceLabel,
                              style: theme.textTheme.labelSmall,
                            ),
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Countdown
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Icon(
                      Icons.timer_outlined,
                      size: 14,
                      color: isExpired ? Colors.red : Colors.amber,
                    ),
                    Text(
                      _countdownLabel,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isExpired ? Colors.red : Colors.amber,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (!isExpired && !_actioning)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _reject,
                      icon: const Icon(Icons.close, size: 16),
                      label: const Text('Reject'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _accept,
                      icon: const Icon(Icons.check, size: 16),
                      label: const Text('Accept'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _block,
                    icon: const Icon(Icons.block, size: 20),
                    tooltip: 'Block this peer',
                    style: IconButton.styleFrom(foregroundColor: Colors.red),
                  ),
                ],
              )
            else if (_actioning)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else
              Center(
                child: Text(
                  'Expired',
                  style: TextStyle(color: Colors.red.withAlpha(180)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Outgoing request card
// ---------------------------------------------------------------------------

class OutgoingRequestCard extends ConsumerStatefulWidget {
  const OutgoingRequestCard({super.key, required this.request});

  final ConnectionRequest request;

  @override
  ConsumerState<OutgoingRequestCard> createState() =>
      _OutgoingRequestCardState();
}

class _OutgoingRequestCardState extends ConsumerState<OutgoingRequestCard> {
  late Timer _timer;
  Duration _remaining = Duration.zero;
  bool _cancelling = false;

  @override
  void initState() {
    super.initState();
    _remaining = widget.request.remaining;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _remaining = widget.request.remaining;
      });
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  String get _countdownLabel {
    if (_remaining.isNegative || _remaining.inSeconds <= 0) return 'Expired';
    final s = _remaining.inSeconds;
    return s >= 60
        ? '${s ~/ 60}m ${(s % 60).toString().padLeft(2, '0')}s'
        : '${s}s';
  }

  Future<void> _cancel() async {
    setState(() => _cancelling = true);
    try {
      await ref
          .read(requestServiceProvider)
          .cancelRequest(widget.request.requestId);
      ref
          .read(pendingRequestsProvider.notifier)
          .remove(widget.request.requestId);
    } catch (e) {
      if (mounted) {
        setState(() => _cancelling = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to cancel: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isExpired = _remaining.isNegative || _remaining.inSeconds <= 0;

    ref.watch(knownPeersProvider);
    final trust = ref.read(trustServiceProvider);
    final fp = widget.request.peerStaticKeyFingerprint;
    final peerName = trust.displayNameFor(fp, widget.request.peerDisplayName);
    final isTrusted = trust.isTrusted(fp);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: theme.colorScheme.primary.withAlpha(30),
              child: Text(
                peerName.isNotEmpty ? peerName[0].toUpperCase() : '?',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          peerName,
                          style: theme.textTheme.titleSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isTrusted) ...[
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.verified_user,
                          size: 13,
                          color: Colors.teal,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (!isExpired)
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      const SizedBox(width: 6),
                      Text(
                        isExpired ? 'No response' : 'Waiting...',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.timer_outlined,
                      size: 12,
                      color: isExpired ? Colors.red : Colors.amber,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _countdownLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isExpired ? Colors.red : Colors.amber,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_cancelling)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  TextButton(
                    onPressed: _cancel,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.red,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('Cancel'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Future<bool> _confirmBlock(BuildContext context, String name) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Block this peer?'),
      content: Text(
        'You will no longer receive connection requests from $name on this device. '
        'This can be undone by resetting Helix.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          child: const Text('Block'),
        ),
      ],
    ),
  );
  return result ?? false;
}
