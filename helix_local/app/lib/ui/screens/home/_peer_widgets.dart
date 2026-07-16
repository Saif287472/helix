part of 'home_screen.dart';

class _PeerSliver extends StatelessWidget {
  const _PeerSliver({
    required this.peers,
    required this.favoriteIds,
    required this.offlineIds,
    required this.forceFavorite,
  });

  final List<Peer> peers;
  final Set<String> favoriteIds;
  final Set<String> offlineIds;
  final bool forceFavorite;

  @override
  Widget build(BuildContext context) {
    final isGrid = MediaQuery.sizeOf(context).width >= 840;
    if (!isGrid) {
      return SliverList(
        delegate: SliverChildBuilderDelegate(
          (ctx, i) => _AnimatedPeerItem(
            index: i,
            child: _PeerTile(
              peer: peers[i],
              isFavorite:
                  forceFavorite || favoriteIds.contains(peers[i].sessionId),
              isOffline: offlineIds.contains(peers[i].sessionId),
              favoriteIds: favoriteIds,
            ),
          ),
          childCount: peers.length,
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: HelixTokens.space12),
      sliver: SliverGrid.builder(
        itemCount: peers.length,
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 420,
          mainAxisExtent: 168,
          crossAxisSpacing: HelixTokens.space12,
          mainAxisSpacing: HelixTokens.space12,
        ),
        itemBuilder: (ctx, i) => _AnimatedPeerItem(
          index: i,
          child: _PeerTile(
            peer: peers[i],
            isFavorite:
                forceFavorite || favoriteIds.contains(peers[i].sessionId),
            isOffline: offlineIds.contains(peers[i].sessionId),
            favoriteIds: favoriteIds,
          ),
        ),
      ),
    );
  }
}

class _AnimatedPeerItem extends StatefulWidget {
  const _AnimatedPeerItem({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<_AnimatedPeerItem> createState() => _AnimatedPeerItemState();
}

class _AnimatedPeerItemState extends State<_AnimatedPeerItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _offset;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: HelixTokens.normal,
    );
    _offset = Tween(
      begin: const Offset(0.08, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final reduceMotion = MediaQuery.disableAnimationsOf(context);
      if (reduceMotion) {
        _controller.value = 1;
      } else {
        Future<void>.delayed(Duration(milliseconds: 50 * widget.index), () {
          if (mounted) _controller.forward();
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(position: _offset, child: widget.child),
    );
  }
}

class _SearchingIndicator extends StatelessWidget {
  const _SearchingIndicator();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        children: [
          const LinearProgressIndicator(),
          const SizedBox(height: 6),
          Text(
            'Searching for peers…',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withAlpha(160),
            ),
          ),
        ],
      ),
    );
  }
}

class _DiscoveryWarningBanner extends StatelessWidget {
  const _DiscoveryWarningBanner({required this.error});
  final String error;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.withAlpha(30),
        border: Border.all(color: Colors.amber.withAlpha(120)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_outlined,
            size: 16,
            color: Colors.amber,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Network discovery may be unavailable. '
              'Peers using secret sentences can still connect.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyPeers extends StatelessWidget {
  const _EmptyPeers({this.onFindPeople});

  final VoidCallback? onFindPeople;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.people_outline,
              size: 48,
              color: theme.colorScheme.onSurface.withAlpha(80),
            ),
            const SizedBox(height: 12),
            Text(
              'No peers found nearby.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withAlpha(160),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              isDesktop
                  ? 'Use refresh, secret sentence, QR, or direct IP to find someone.'
                  : 'Pull down to refresh, or use a secret sentence / QR to find someone.',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            if (onFindPeople != null) ...[
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: onFindPeople,
                icon: const Icon(Icons.person_add_outlined),
                label: const Text('Add first contact'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Peer tile (2.3: stale indicator, ping, favourite star)
// ---------------------------------------------------------------------------

class _PeerTile extends ConsumerWidget {
  const _PeerTile({
    required this.peer,
    required this.isFavorite,
    required this.isOffline,
    required this.favoriteIds,
  });

  final Peer peer;
  final bool isFavorite;
  final bool isOffline;
  final Set<String> favoriteIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final staleAge = DateTime.now().difference(peer.seenAt);
    final isStale = staleAge > kPeerStaleThreshold && !isOffline;
    final opacity = isOffline ? 0.45 : (isStale ? 0.65 : 1.0);
    final blockedPeers = ref.watch(blockedPeersProvider).value ?? const {};
    final requestSvc = ref.read(requestServiceProvider);
    final peerFingerprint = requestSvc.fingerprintForSession(peer.sessionId);

    final sourceLabel = switch (peer.source) {
      PeerSource.mdns => 'mDNS',
      PeerSource.udpBroadcast => 'Broadcast',
      PeerSource.secretCode => 'Secret sentence',
      PeerSource.directIp => 'Direct IP',
    };

    // Trust-aware display name: match by fingerprint (if known) or deviceSuffix.
    final knownPeers =
        ref.watch(knownPeersProvider).value ?? const <KnownPeer>[];
    final trust = ref.read(trustServiceProvider);
    KnownPeer? knownEntry = peerFingerprint != null
        ? trust.getPeer(peerFingerprint)
        : knownPeers.cast<KnownPeer?>().firstWhere(
            (p) => p!.deviceSuffix == peer.deviceSuffix,
            orElse: () => null,
          );
    final peerName =
        (knownEntry?.trusted == true && knownEntry?.nickname != null)
        ? knownEntry!.nickname!
        : peer.displayName;
    final isTrusted = knownEntry?.trusted == true;

    return Opacity(
      opacity: opacity,
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 460;
            return Padding(
              padding: const EdgeInsets.all(14),
              child: compact
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _PeerIdentity(
                          peer: peer,
                          displayName: peerName,
                          isTrusted: isTrusted,
                          sourceLabel: sourceLabel,
                          isOffline: isOffline,
                          staleAge: isStale ? staleAge : null,
                        ),
                        const SizedBox(height: 10),
                        _PeerActions(
                          compact: true,
                          isFavorite: favoriteIds.contains(peer.sessionId),
                          isBlocked:
                              peerFingerprint != null &&
                              blockedPeers.contains(peerFingerprint),
                          onFavorite: () => _toggleFavorite(ref),
                          onOneWay: () => _sendOneWayMessage(context, ref),
                          onConnect: () => _sendRequest(context, ref),
                          onBlock: peerFingerprint == null
                              ? null
                              : () => ref
                                    .read(requestServiceProvider)
                                    .blockPeer(peerFingerprint),
                          onUnblock: peerFingerprint == null
                              ? null
                              : () => ref
                                    .read(requestServiceProvider)
                                    .unblockPeer(peerFingerprint),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: _PeerIdentity(
                            peer: peer,
                            displayName: peerName,
                            isTrusted: isTrusted,
                            sourceLabel: sourceLabel,
                            isOffline: isOffline,
                            staleAge: isStale ? staleAge : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        _PeerActions(
                          compact: false,
                          isFavorite: favoriteIds.contains(peer.sessionId),
                          isBlocked:
                              peerFingerprint != null &&
                              blockedPeers.contains(peerFingerprint),
                          onFavorite: () => _toggleFavorite(ref),
                          onOneWay: () => _sendOneWayMessage(context, ref),
                          onConnect: () => _sendRequest(context, ref),
                          onBlock: peerFingerprint == null
                              ? null
                              : () => ref
                                    .read(requestServiceProvider)
                                    .blockPeer(peerFingerprint),
                          onUnblock: peerFingerprint == null
                              ? null
                              : () => ref
                                    .read(requestServiceProvider)
                                    .unblockPeer(peerFingerprint),
                        ),
                      ],
                    ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _toggleFavorite(WidgetRef ref) async {
    await ref.read(favoritePeersProvider.notifier).toggle(peer);
  }

  // ignore: unused_element
  Future<void> _ping(BuildContext context, WidgetRef ref) async {
    final coordinator = ref.read(discoveryCoordinatorProvider);
    final sessionSvc = ref.read(sessionServiceProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Pinging…'), duration: Duration(seconds: 1)),
    );
    final result = await coordinator.probeDirectIp(
      peer.host,
      peer.port,
      sessionSvc.sessionId,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result != null
              ? '${peer.displayName} is reachable.'
              : '${peer.displayName} did not respond.',
        ),
      ),
    );
  }

  Future<void> _sendRequest(BuildContext context, WidgetRef ref) async {
    if (await handleExistingActiveThread(context, ref, peer)) return;
    if (!context.mounted) return;

    final profileSvc = ref.read(profileServiceProvider);
    final identity = profileSvc.identity;
    if (identity == null) return;
    final displayName = profileSvc.profile?.displayName ?? '';
    final sessionId = ref.read(sessionServiceProvider).sessionId;

    bool canceled = false;
    BuildContext? dialogCtx;
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          dialogCtx = ctx;
          return AlertDialog(
            title: Text('Connecting to ${peer.displayName}'),
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
            RequestSourceMethod.nearby,
            identity,
            sessionId,
            displayName,
            localTcpPort: ref.read(activeTcpPortProvider),
          );
      closeDialog();
      if (canceled || !context.mounted) return;
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
        if (context.mounted) {
          Navigator.of(
            context,
          ).pushNamed('${AppRoutes.chat}/${result.channel!.threadId}');
        }
      } else if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Request ${request.status.name} by ${peer.displayName}.',
            ),
          ),
        );
      }
    } catch (e) {
      closeDialog();
      if (canceled || !context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  Future<void> _sendOneWayMessage(BuildContext context, WidgetRef ref) async {
    final message = await showOneWayMessageDialog(
      context,
      recipientName: peer.displayName,
    );
    if (message == null) return;
    if (!context.mounted) return;
    await sendOneWayMessageToPeer(context, ref, peer, message);
  }
}

class _PeerIdentity extends StatelessWidget {
  const _PeerIdentity({
    required this.peer,
    required this.displayName,
    required this.isTrusted,
    required this.sourceLabel,
    required this.isOffline,
    this.staleAge,
  });

  final Peer peer;
  final String displayName;
  final bool isTrusted;
  final String sourceLabel;
  final bool isOffline;
  final Duration? staleAge;

  String _formatStale(Duration age) {
    if (age.inSeconds < 60) return '${age.inSeconds}s ago';
    return '${age.inMinutes}m ago';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final avatarTag = peer.sessionId.isEmpty
        ? 'peer-avatar-${peer.host}:${peer.port}'
        : 'peer-avatar-${peer.sessionId}';
    return Row(
      children: [
        Hero(
          tag: avatarTag,
          child: CircleAvatar(
            radius: 22,
            backgroundColor: theme.colorScheme.primary.withAlpha(26),
            child: Text(
              displayName.isNotEmpty
                  ? displayName.characters.first.toUpperCase()
                  : '?',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  if (isTrusted)
                    const Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: Icon(
                        Icons.verified_user,
                        size: 13,
                        color: Colors.teal,
                      ),
                    ),
                  if (isOffline)
                    _MetaPill(
                      label: 'offline',
                      color: theme.colorScheme.error.withAlpha(180),
                    )
                  else if (staleAge != null)
                    _MetaPill(label: _formatStale(staleAge!)),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  _MetaPill(label: peer.deviceSuffix),
                  _MetaPill(label: sourceLabel),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PeerActions extends StatelessWidget {
  const _PeerActions({
    required this.compact,
    required this.isFavorite,
    required this.isBlocked,
    required this.onFavorite,
    required this.onOneWay,
    required this.onConnect,
    this.onBlock,
    this.onUnblock,
  });

  final bool compact;
  final bool isFavorite;
  final bool isBlocked;
  final VoidCallback onFavorite;
  final VoidCallback onOneWay;
  final VoidCallback onConnect;
  final VoidCallback? onBlock;
  final VoidCallback? onUnblock;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final starButton = IconButton(
      icon: Icon(
        isFavorite ? Icons.star : Icons.star_border,
        size: 20,
        color: isFavorite ? Colors.amber : null,
      ),
      tooltip: isFavorite ? 'Remove favourite' : 'Add to favourites',
      onPressed: onFavorite,
      visualDensity: VisualDensity.compact,
    );

    final blockButton = IconButton(
      icon: Icon(
        isBlocked ? Icons.block_flipped : Icons.block,
        size: 20,
        color: isBlocked ? colorScheme.error : null,
      ),
      tooltip: isBlocked ? 'Unblock' : 'Block',
      onPressed: isBlocked ? onUnblock : onBlock,
      visualDensity: VisualDensity.compact,
    );

    final oneWayButton = OutlinedButton.icon(
      onPressed: onOneWay,
      icon: const Icon(Icons.send_outlined, size: 18),
      label: Text(compact ? 'One-way' : 'Note'),
      style: OutlinedButton.styleFrom(
        minimumSize: Size(compact ? 0 : 96, 40),
        padding: const EdgeInsets.symmetric(horizontal: 12),
      ),
    );
    final connectButton = FilledButton.icon(
      onPressed: onConnect,
      icon: const Icon(Icons.link, size: 18),
      label: const Text('Connect'),
      style: FilledButton.styleFrom(
        minimumSize: Size(compact ? 0 : 112, 40),
        padding: const EdgeInsets.symmetric(horizontal: 14),
      ),
    );

    if (compact) {
      return Row(
        children: [
          starButton,
          blockButton,
          const Spacer(),
          oneWayButton,
          const SizedBox(width: 8),
          connectButton,
        ],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        starButton,
        blockButton,
        const SizedBox(width: 4),
        oneWayButton,
        const SizedBox(width: 8),
        connectButton,
      ],
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.label, this.color});
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color:
            color?.withAlpha(40) ??
            theme.colorScheme.surfaceContainerHighest.withAlpha(180),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: color?.withAlpha(120) ?? theme.colorScheme.outlineVariant,
        ),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}
