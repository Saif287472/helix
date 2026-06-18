part of 'home_screen.dart';

// ---------------------------------------------------------------------------
// Tab 0 — Home
// ---------------------------------------------------------------------------

class _HomeTab extends ConsumerStatefulWidget {
  const _HomeTab();

  @override
  ConsumerState<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends ConsumerState<_HomeTab> {
  final _searchController = TextEditingController();
  String _peerFilter = '';
  bool _searching = false;
  Timer? _searchTimer;
  bool _autoRefreshDone = false;

  @override
  void dispose() {
    _searchController.dispose();
    _searchTimer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final session = ref.read(sessionStateProvider);
    if (session.phase == SessionPhase.active) {
      ref.read(discoveryCoordinatorProvider).restart().ignore();
    }
    if (mounted && !_searching) {
      setState(() => _searching = true);
      _searchTimer?.cancel();
      _searchTimer = Timer(const Duration(seconds: 10), () {
        if (mounted) setState(() => _searching = false);
      });
    }
    await Future.delayed(const Duration(milliseconds: 600));
  }

  void _openQrOptions() {
    if (isDesktop) {
      Navigator.of(context).pushNamed(AppRoutes.qrShare);
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.qr_code),
              title: const Text('Share my QR'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).pushNamed(AppRoutes.qrShare);
              },
            ),
            ListTile(
              leading: const Icon(Icons.qr_code_scanner),
              title: const Text('Scan QR'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).pushNamed(AppRoutes.qrScan);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _openSecretCodeSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => const SecretCodeSearchSheet(),
    );
  }

  void _openFindPeopleSheet() {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.vpn_key_outlined),
              title: const Text('Secret sentence'),
              subtitle: const Text('Find someone by shared passphrase'),
              onTap: () {
                Navigator.pop(ctx);
                _openSecretCodeSheet();
              },
            ),
            ListTile(
              leading: const Icon(Icons.qr_code_outlined),
              title: const Text('QR code'),
              subtitle: const Text('Share or scan a QR code'),
              onTap: () {
                Navigator.pop(ctx);
                _openQrOptions();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _openTrustedDevicesSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => const TrustedDevicesSheet(),
    );
  }

  Future<void> _openPrivateGroupDialog() async {
    final service = ref.read(groupServiceProvider);
    if (!service.isInitialized) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Identity is not configured yet. Please wait.')),
      );
      return;
    }

    final controller = TextEditingController(text: 'Private group');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New private group'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Group name'),
          textInputAction: TextInputAction.done,
          onSubmitted: (value) => Navigator.of(ctx).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty) return;

    try {
      final group = await service.createPrivateGroup(name: name);
      final code = service.buildGroupCode(group.groupId);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(group.name),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Group code'),
              const SizedBox(height: 8),
              SelectableText(code),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: code));
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Group code copied.')),
                );
              },
              child: const Text('Copy'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create group: $e')),
        );
      }
    }
  }

  Future<void> _openJoinGroupDialog() async {
    final service = ref.read(groupServiceProvider);
    if (!service.isInitialized) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Identity is not configured yet. Please wait.')),
      );
      return;
    }

    final controller = TextEditingController();
    final inviteCode = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Join group'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Invite code'),
          textInputAction: TextInputAction.done,
          onSubmitted: (value) => Navigator.of(ctx).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Join'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (inviteCode == null || inviteCode.trim().isEmpty) return;

    try {
      await service.connectAndJoin(inviteCode.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Join request sent successfully.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to join: $e')),
        );
      }
    }
  }

  Future<void> _openDirectIpDialog() async {
    final tcpPort = ref.read(activeTcpPortProvider);
    List<String>? ownAddresses;
    try {
      final interfaces = await NetworkInterface.list(
        includeLinkLocal: false,
        type: InternetAddressType.IPv4,
      );
      if (tcpPort > 0) {
        final addrs = <String>[];
        for (final iface in interfaces) {
          for (final addr in iface.addresses) {
            if (!addr.isLoopback) addrs.add('${addr.address}:$tcpPort');
          }
        }
        if (addrs.isNotEmpty) ownAddresses = addrs;
      }
    } catch (_) {}

    if (!mounted) return;

    final input = await showIpPortDialog(
      context: context,
      title: 'Connect by IP',
      actionLabel: 'Connect',
      ownAddresses: ownAddresses,
    );
    if (input == null || input.trim().isEmpty) return;

    final target = _parseHostPort(input.trim());
    if (target == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter the address as IP:port.')),
        );
      }
      return;
    }

    final profileSvc = ref.read(profileServiceProvider);
    final identity = profileSvc.identity;
    if (identity == null) return;
    final displayName = profileSvc.profile?.displayName ?? '';
    final sessionId = ref.read(sessionServiceProvider).sessionId;

    final peer = Peer(
      sessionId: '',
      displayName: target.$1,
      deviceSuffix: 'direct',
      host: target.$1,
      port: target.$2,
      source: PeerSource.directIp,
      seenAt: DateTime.now(),
      protocolMajor: kProtocolMajor,
      protocolMinor: kProtocolMinor,
    );

    if (!mounted) return;
    if (await handleExistingActiveThread(context, ref, peer)) return;
    if (!mounted) return;

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
      if (!mounted) return;
      if (result.request.status == RequestStatus.accepted &&
          result.channel != null) {
        ref
            .read(messagingServiceProvider)
            .attachChannel(
              result.channel!.threadId,
              result.request.peerDisplayName,
              result.request.peerDeviceSuffix,
              result.channel!,
              result.request.peerSessionId,
              result.request.peerHost,
              result.request.peerPort,
            );
        Navigator.of(
          context,
        ).pushNamed('${AppRoutes.chat}/${result.channel!.threadId}');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Request ${result.request.status.name}.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  (String, int)? _parseHostPort(String raw) {
    final trimmed = raw.trim();
    final idx = trimmed.lastIndexOf(':');
    if (idx <= 0 || idx == trimmed.length - 1) return null;
    final host = trimmed.substring(0, idx).trim();
    final port = int.tryParse(trimmed.substring(idx + 1).trim());
    if (host.isEmpty || port == null || port <= 0 || port > 65535) {
      return null;
    }
    return (host, port);
  }

  bool _matchesFilter(Peer peer) {
    final query = _peerFilter.trim().toLowerCase();
    if (query.isEmpty) return true;
    return peer.displayName.toLowerCase().contains(query) ||
        peer.deviceSuffix.toLowerCase().contains(query);
  }

  Future<void> _dismissWelcomeBanner() async {
    await ref
        .read(profileServiceProvider)
        .updatePreferences(homeWelcomeDismissed: true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profileAsync = ref.watch(profileProvider);
    final peersAsync = ref.watch(nearbyPeersProvider);
    final favoriteIds = ref.watch(favoritePeersProvider);
    final favoritesAsync = ref.watch(favoritePeerListProvider);
    final groupsAsync = ref.watch(groupSnapshotsProvider);
    final groupService = ref.read(groupServiceProvider);
    final isGroupServiceInitialized = groupService.isInitialized;

    ref.listen<SessionState>(sessionStateProvider, (_, next) {
      if (!_autoRefreshDone && next.phase == SessionPhase.active) {
        _autoRefreshDone = true;
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) _refresh();
        });
      }
    });

    return RefreshIndicator(
      onRefresh: _refresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Profile card ───────────────────────────────────────────
                  profileAsync.when(
                    data: (profile) => _ProfileCard(
                      profile: profile,
                      onToggleDiscoverability: (v) async {
                        final next = v
                            ? DiscoverabilityState.discoverable
                            : DiscoverabilityState.hidden;
                        await ref
                            .read(profileServiceProvider)
                            .updateDiscoverability(next);
                        await ref
                            .read(discoveryCoordinatorProvider)
                            .updateDiscoverability(v);
                      },
                      onOpenQr: _openQrOptions,
                      onRefresh: _refresh,
                    ),
                    loading: () => const LinearProgressIndicator(),
                    error: (e, _) => Text('Error: $e'),
                  ),
                  const ConnectivityBanner(),
                  profileAsync.maybeWhen(
                    data: (profile) => profile.homeWelcomeDismissed
                        ? const SizedBox.shrink()
                        : _WelcomeBanner(onDismiss: _dismissWelcomeBanner),
                    orElse: () => const SizedBox.shrink(),
                  ),
                  peersAsync.when(
                    data: (_) => const SizedBox.shrink(),
                    loading: () => const SizedBox.shrink(),
                    error: (e, _) => _DiscoveryWarningBanner(error: '$e'),
                  ),
                  const SizedBox(height: 16),

                  // ── Find people + Direct connect ───────────────────────────
                  Row(
                    children: [
                      Expanded(
                        child: _ActionCard(
                          icon: Icons.people_alt_outlined,
                          title: 'Find people',
                          subtitle: 'Secret sentence, QR, nearby search',
                          onTap: _openFindPeopleSheet,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _ActionCard(
                          icon: Icons.cable_outlined,
                          title: 'Direct connect',
                          subtitle: 'Connect using IP and port',
                          onTap: _openDirectIpDialog,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // ── Quick tools ────────────────────────────────────────────
                  Text(
                    'Quick tools',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _QuickToolsCard(
                    tools: [
                      _QuickTool(
                        icon: Icons.verified_user_outlined,
                        label: 'Trusted',
                        onTap: _openTrustedDevicesSheet,
                      ),
                      _QuickTool(
                        icon: Icons.group_add_outlined,
                        label: 'New group',
                        onTap: isGroupServiceInitialized
                            ? _openPrivateGroupDialog
                            : null,
                      ),
                      _QuickTool(
                        icon: Icons.group_outlined,
                        label: 'Join group',
                        onTap: isGroupServiceInitialized
                            ? _openJoinGroupDialog
                            : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // ── Groups ─────────────────────────────────────────────────
                  groupsAsync.when(
                    data: (groups) => groups.isEmpty
                        ? const SizedBox.shrink()
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Groups',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              _HomeGroupsCard(groups: groups),
                              const SizedBox(height: 20),
                            ],
                          ),
                    loading: () => const SizedBox.shrink(),
                    error: (_, _) => const SizedBox.shrink(),
                  ),

                  // ── Nearby peers + search ──────────────────────────────────
                  Text(
                    'Nearby peers',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SearchBar(
                    controller: _searchController,
                    leading: const Icon(Icons.search),
                    hintText: 'Search peers',
                    padding: const WidgetStatePropertyAll(
                      EdgeInsets.symmetric(horizontal: 16),
                    ),
                    trailing: [
                      if (_peerFilter.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.close),
                          tooltip: 'Clear search',
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _peerFilter = '');
                          },
                        ),
                    ],
                    onChanged: (value) => setState(() => _peerFilter = value),
                  ),
                  const SizedBox(height: 12),

                  // Favourites section header (only when there are visible favs)
                  favoritesAsync.when(
                    data: (favs) {
                      final livePeers = peersAsync.value ?? <Peer>[];
                      final liveIds =
                          livePeers.map((p) => p.sessionId).toSet();
                      final visibleFavs = favs
                          .where((fav) => liveIds.contains(fav.sessionId))
                          .where(_matchesFilter)
                          .toList();
                      if (visibleFavs.isEmpty) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          'Suggested',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurface.withAlpha(160),
                          ),
                        ),
                      );
                    },
                    loading: () => const SizedBox.shrink(),
                    error: (_, _) => const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),

          // ── Favourite peers currently visible on the network ───────────────
          favoritesAsync.when(
            data: (favs) {
              final livePeers = peersAsync.value ?? [];
              final liveBySession = {
                for (final p in livePeers) p.sessionId: p,
              };
              final visibleFavs = favs
                  .where((fav) => liveBySession.containsKey(fav.sessionId))
                  .where(_matchesFilter)
                  .toList();
              if (visibleFavs.isEmpty) {
                return const SliverToBoxAdapter(child: SizedBox.shrink());
              }
              return _PeerSliver(
                peers: visibleFavs
                    .map((fav) => liveBySession[fav.sessionId] ?? fav)
                    .toList(),
                favoriteIds: favoriteIds,
                offlineIds: const {},
                forceFavorite: true,
              );
            },
            loading: () =>
                const SliverToBoxAdapter(child: SizedBox.shrink()),
            error: (_, _) =>
                const SliverToBoxAdapter(child: SizedBox.shrink()),
          ),

          if (_searching)
            const SliverToBoxAdapter(child: _SearchingIndicator()),

          // ── Live peer list (excluding already-shown favourites) ─────────────
          peersAsync.when(
            data: (peers) {
              final threads = ref.read(threadsProvider);
              final activeSessions = {
                for (final t in threads.values)
                  if (t.status == ThreadStatus.active) t.peerSessionId,
              };

              final sorted = [...peers]
                ..sort((a, b) {
                  final aActive = activeSessions.contains(a.sessionId) ? 0 : 1;
                  final bActive = activeSessions.contains(b.sessionId) ? 0 : 1;
                  if (aActive != bActive) return aActive.compareTo(bActive);
                  return b.seenAt.compareTo(a.seenAt);
                });

              final favIds = ref.read(favoritePeersProvider);
              final nonFavPeers = sorted
                  .where((p) => !favIds.contains(p.sessionId))
                  .where(_matchesFilter)
                  .toList();

              if (nonFavPeers.isEmpty) {
                return SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyPeers(onFindPeople: _openFindPeopleSheet),
                );
              }
              return _PeerSliver(
                peers: nonFavPeers,
                favoriteIds: favoriteIds,
                offlineIds: const {},
                forceFavorite: false,
              );
            },
            loading: () => const SliverToBoxAdapter(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              ),
            ),
            error: (e, _) => SliverToBoxAdapter(
              child: _DiscoveryWarningBanner(error: '$e'),
            ),
          ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Profile card
// ---------------------------------------------------------------------------

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.profile,
    required this.onToggleDiscoverability,
    required this.onOpenQr,
    required this.onRefresh,
  });

  final Profile profile;
  final ValueChanged<bool> onToggleDiscoverability;
  final VoidCallback onOpenQr;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final discoverable =
        profile.discoverability == DiscoverabilityState.discoverable;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withAlpha(120),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 32,
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Text(
                profile.displayName.isNotEmpty
                    ? profile.displayName.characters.first.toUpperCase()
                    : '?',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () => onToggleDiscoverability(!discoverable),
                    borderRadius: BorderRadius.circular(8),
                    child: DiscoverabilityBadge(state: profile.discoverability),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: IconButton(
                icon: const Icon(Icons.qr_code_2_outlined),
                tooltip: 'QR code',
                onPressed: onOpenQr,
              ),
            ),
            if (isDesktop) ...[
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh discovery',
                onPressed: onRefresh,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Action cards (Find people / Direct connect)
// ---------------------------------------------------------------------------

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withAlpha(120),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      icon,
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 14,
                    color: theme.colorScheme.onSurface.withAlpha(120),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withAlpha(160),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Quick tools card
// ---------------------------------------------------------------------------

class _QuickTool {
  const _QuickTool({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
}

class _QuickToolsCard extends StatelessWidget {
  const _QuickToolsCard({required this.tools});

  final List<_QuickTool> tools;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withAlpha(120),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          children: [
            for (int i = 0; i < tools.length; i++) ...[
              if (i > 0)
                VerticalDivider(
                  width: 1,
                  color: theme.colorScheme.outlineVariant.withAlpha(120),
                ),
              Expanded(child: _QuickToolCell(tool: tools[i])),
            ],
          ],
        ),
      ),
    );
  }
}

class _QuickToolCell extends StatelessWidget {
  const _QuickToolCell({required this.tool});

  final _QuickTool tool;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: tool.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: tool.onTap != null
                    ? theme.colorScheme.primaryContainer
                    : theme.colorScheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(
                tool.icon,
                size: 22,
                color: tool.onTap != null
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface.withAlpha(80),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              tool.label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: tool.onTap != null
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.onSurface.withAlpha(80),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Groups card
// ---------------------------------------------------------------------------

class _HomeGroupsCard extends StatelessWidget {
  const _HomeGroupsCard({required this.groups});

  final List<GroupSnapshot> groups;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withAlpha(120),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (int i = 0; i < groups.take(3).length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                indent: 68,
                color: theme.colorScheme.outlineVariant.withAlpha(80),
              ),
            _GroupRow(group: groups[i]),
          ],
        ],
      ),
    );
  }
}

class _GroupRow extends StatelessWidget {
  const _GroupRow({required this.group});

  final GroupSnapshot group;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => Navigator.of(context)
          .pushNamed('${AppRoutes.group}/${group.groupId}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                group.isPublicLobby
                    ? Icons.forum_outlined
                    : Icons.lock_outline,
                size: 20,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    group.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '${group.memberCount} member${group.memberCount == 1 ? '' : 's'}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withAlpha(160),
                    ),
                  ),
                ],
              ),
            ),
            if (group.hostFingerprint.isNotEmpty)
              Icon(
                Icons.hub_outlined,
                size: 18,
                color: theme.colorScheme.onSurface.withAlpha(120),
              ),
            const SizedBox(width: 4),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 14,
              color: theme.colorScheme.onSurface.withAlpha(120),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Welcome banner
// ---------------------------------------------------------------------------

class _WelcomeBanner extends StatelessWidget {
  const _WelcomeBanner({required this.onDismiss});
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return AnimatedContainer(
      duration: reduceMotion ? Duration.zero : HelixTokens.normal,
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withAlpha(180),
        borderRadius: BorderRadius.circular(HelixTokens.radius12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.radar, color: theme.colorScheme.onPrimaryContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Discovery is local',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Helix listens on your current network. Use QR, secret sentence, or direct IP when broadcast discovery is unavailable.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Dismiss',
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}
