// lib/ui/widgets/secret_code_search_sheet.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_local_domain/core/constants.dart';
import 'package:helix_local_domain/domain/models.dart';
import 'package:helix/providers/app_providers.dart';
import 'package:helix/ui/app_router.dart';

// ---------------------------------------------------------------------------
// State for the sheet
// ---------------------------------------------------------------------------

enum _SearchState { idle, searching, results, timeout, error }

class _SheetState {
  final _SearchState searchState;
  final List<Peer> results;
  final String? errorMessage;

  const _SheetState({
    this.searchState = _SearchState.idle,
    this.results = const [],
    this.errorMessage,
  });

  _SheetState copyWith({
    _SearchState? searchState,
    List<Peer>? results,
    String? errorMessage,
  }) => _SheetState(
    searchState: searchState ?? this.searchState,
    results: results ?? this.results,
    errorMessage: errorMessage ?? this.errorMessage,
  );
}

// ---------------------------------------------------------------------------
// Widget
// ---------------------------------------------------------------------------

class SecretCodeSearchSheet extends ConsumerStatefulWidget {
  const SecretCodeSearchSheet({super.key});

  @override
  ConsumerState<SecretCodeSearchSheet> createState() =>
      _SecretCodeSearchSheetState();
}

class _SecretCodeSearchSheetState extends ConsumerState<SecretCodeSearchSheet> {
  final _codeController = TextEditingController();
  final _codeFocus = FocusNode();
  bool _codeVisible = false;
  bool _ownCodeVisible = false;
  String? _ownCode;
  _SheetState _state = const _SheetState();
  Timer? _timeoutTimer;

  @override
  void initState() {
    super.initState();
    ref.read(profileServiceProvider).getSecretCode().then((code) {
      if (mounted) setState(() => _ownCode = code);
    });
  }

  @override
  void dispose() {
    _codeController.dispose();
    _codeFocus.dispose();
    _timeoutTimer?.cancel();
    super.dispose();
  }

  void _clearAndClose() {
    _codeController.clear();
    Navigator.of(context).pop();
  }

  Future<void> _search() async {
    final code = _codeController.text.trim();
    final profileService = ref.read(profileServiceProvider);
    final validationError = profileService.validateSecretCode(code);
    if (validationError != null) {
      setState(() {
        _state = _state.copyWith(
          searchState: _SearchState.error,
          errorMessage: validationError,
        );
      });
      return;
    }

    setState(() {
      _state = const _SheetState(searchState: _SearchState.searching);
    });

    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(kCodeSearchTimeout, () {
      if (mounted && _state.searchState == _SearchState.searching) {
        setState(() {
          _state = _state.copyWith(searchState: _SearchState.timeout);
        });
      }
    });

    List<Peer> results;
    try {
      results = await ref
          .read(discoveryCoordinatorProvider)
          .searchBySecretCode(code);
    } catch (_) {
      _timeoutTimer?.cancel();
      if (!mounted) return;
      setState(() {
        _state = _state.copyWith(
          searchState: _SearchState.error,
          errorMessage:
              'Search failed. Check that both devices are on the LAN.',
        );
      });
      return;
    }
    _timeoutTimer?.cancel();

    if (!mounted) return;
    setState(() {
      _state = _state.copyWith(
        searchState: results.isEmpty
            ? _SearchState.timeout
            : _SearchState.results,
        results: results,
      );
    });
  }

  Future<void> _connect(Peer peer) async {
    final existing = ref
        .read(messagingServiceProvider)
        .findActiveThreadForPeer(peer);
    if (existing != null) {
      _clearAndClose();
      if (mounted) {
        Navigator.of(
          context,
        ).pushNamed('${AppRoutes.chat}/${existing.threadId}');
      }
      return;
    }

    final profileSvc = ref.read(profileServiceProvider);
    final identity = profileSvc.identity;
    if (identity == null) return;
    final displayName = profileSvc.profile?.displayName ?? '';
    final sessionId = ref.read(sessionServiceProvider).sessionId;
    final requestService = ref.read(requestServiceProvider);

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
      final result = await requestService.sendRequest(
        peer,
        RequestSourceMethod.secretCode,
        identity,
        sessionId,
        displayName,
        localTcpPort: ref.read(activeTcpPortProvider),
      );
      closeDialog();
      if (canceled || !mounted) return;
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
        _clearAndClose();
        Navigator.of(
          context,
        ).pushNamed('${AppRoutes.chat}/${result.channel!.threadId}');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Request ${result.request.status.name} by ${peer.displayName}.',
            ),
          ),
        );
      }
    } catch (e) {
      closeDialog();
      if (canceled || !mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to send request: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mediaQuery = MediaQuery.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: mediaQuery.viewInsets.bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        expand: false,
        builder: (context, scrollController) {
          return Column(
            children: [
              // Handle bar
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 4),
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurface.withAlpha(40),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Text(
                      'Search by Secret Sentence',
                      style: theme.textTheme.titleMedium,
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: _clearAndClose,
                      tooltip: 'Close',
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(20),
                  children: [
                    // Your device secret code
                    if (_ownCode != null) ...[
                      Text(
                        'Your device',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurface.withAlpha(140),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _ownCodeVisible ? _ownCode! : '••••••••••••',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.primary,
                                fontFamily: 'monospace',
                              ),
                              softWrap: true,
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              _ownCodeVisible
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              size: 18,
                            ),
                            tooltip: _ownCodeVisible ? 'Hide' : 'Show',
                            visualDensity: VisualDensity.compact,
                            onPressed: () => setState(
                              () => _ownCodeVisible = !_ownCodeVisible,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],
                    // Warning banner
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber.withAlpha(30),
                        border: Border.all(
                          color: Colors.amber.withAlpha(120),
                          width: 1,
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.warning_amber_outlined,
                            size: 16,
                            color: Colors.amber,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Weak codes may be guessed by someone '
                              'recording network traffic. Use a strong, '
                              'unique passphrase.',
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Code field
                    TextField(
                      controller: _codeController,
                      focusNode: _codeFocus,
                      obscureText: !_codeVisible,
                      decoration: InputDecoration(
                        labelText: 'Secret sentence',
                        hintText: 'e.g. blue forest flying high',
                        suffixIcon: IconButton(
                          icon: Icon(
                            _codeVisible
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          tooltip: _codeVisible ? 'Hide' : 'Show',
                          onPressed: () =>
                              setState(() => _codeVisible = !_codeVisible),
                        ),
                        errorText: _state.searchState == _SearchState.error
                            ? _state.errorMessage
                            : null,
                      ),
                      onSubmitted: (_) {
                        if (_state.searchState != _SearchState.searching) {
                          _search();
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    // Action buttons
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _clearAndClose,
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed:
                                _state.searchState == _SearchState.searching
                                ? null
                                : _search,
                            icon: _state.searchState == _SearchState.searching
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.search, size: 18),
                            label: const Text('Search'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    // Results area
                    _buildResultsArea(theme),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildResultsArea(ThemeData theme) {
    switch (_state.searchState) {
      case _SearchState.idle:
        return const SizedBox.shrink();

      case _SearchState.searching:
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 12),
                Text('Searching for peers...'),
              ],
            ),
          ),
        );

      case _SearchState.timeout:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Icon(
                  Icons.wifi_off,
                  size: 40,
                  color: theme.colorScheme.onSurface.withAlpha(80),
                ),
                const SizedBox(height: 12),
                Text(
                  'No response within the timeout window.',
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _search,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        );

      case _SearchState.error:
        return const SizedBox.shrink();

      case _SearchState.results:
        if (_state.results.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(
                    Icons.people_outline,
                    size: 40,
                    color: theme.colorScheme.onSurface.withAlpha(80),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No peers responded to this code.',
                    style: theme.textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_state.results.length} peer(s) found',
              style: theme.textTheme.labelMedium,
            ),
            const SizedBox(height: 8),
            ..._state.results.map(
              (peer) =>
                  _PeerResultTile(peer: peer, onConnect: () => _connect(peer)),
            ),
          ],
        );
    }
  }
}

class _PeerResultTile extends StatelessWidget {
  const _PeerResultTile({required this.peer, required this.onConnect});

  final Peer peer;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: theme.colorScheme.primary.withAlpha(30),
              child: Text(
                peer.displayName.isNotEmpty
                    ? peer.displayName[0].toUpperCase()
                    : '?',
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
                  Text(peer.displayName, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Chip(
                    label: Text(
                      peer.deviceSuffix,
                      style: theme.textTheme.labelSmall,
                    ),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            ElevatedButton(
              onPressed: onConnect,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
              ),
              child: const Text('Connect'),
            ),
          ],
        ),
      ),
    );
  }
}
