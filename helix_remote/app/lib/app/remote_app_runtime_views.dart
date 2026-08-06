part of '../main.dart';

extension _RemoteAppRuntimeViews on _HelixRemoteAppState {
  Widget _buildReadyScreen() {
    return HomeScreen(
      root: widget.root,
      onChangeServerUrl: widget.onChangeServerUrl,
    );
  }

  Widget _buildErrorScreen() {
    return Scaffold(
      appBar: AppBar(title: const Text('Startup Error')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                'Failed to start',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage ?? 'Unknown error',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () {
                  _update(() => _errorMessage = null);
                  _startBoot();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResetScreen() {
    return Scaffold(
      appBar: AppBar(title: const Text('Reset Required')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.warning_amber, size: 64, color: Colors.orange),
                const SizedBox(height: 16),
                Text(
                  'Database key is missing',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'An existing database was found but its encryption key is not '
                  'available in secure storage. A destructive reset is required '
                  'to continue.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                // Builder gives onPressed a context from *inside* the
                // MaterialApp this State builds - see the matching comment
                // on the Skip button in _buildDisplayNameStep.
                SizedBox(
                  width: double.infinity,
                  child: Builder(
                    builder: (context) => FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.error,
                      ),
                      onPressed: () => _confirmedReset(context),
                      icon: const Icon(Icons.delete_forever_outlined),
                      label: const Text('Reset Helix Remote'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmedReset(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm destructive reset'),
        content: const Text(
          'This will permanently delete all local account data, the encrypted '
          'database, and all stored keys. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete and reset'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await widget.root.performReset();
    if (mounted) _startBoot();
  }
}
