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
      appBar: AppBar(title: Text(HelixLocalizations.of(context).startupError)),
      body: Center(
        child: Padding(
          padding: HelixInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                size: 64,
                color: HelixStatusColors.danger,
              ),
              const SizedBox(height: 16),
              Text(
                HelixLocalizations.of(context).failedStart,
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
                label: Text(HelixLocalizations.of(context).retry),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResetScreen() {
    return Scaffold(
      appBar: AppBar(title: Text(HelixLocalizations.of(context).resetRequired)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: HelixInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.warning_amber,
                  size: 64,
                  color: HelixStatusColors.caution,
                ),
                const SizedBox(height: 16),
                Text(
                  HelixLocalizations.of(context).databaseKeyMissing,
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  HelixLocalizations.of(context).existingDatabaseWasFoundBut,
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
                      label: Text(
                        HelixLocalizations.of(context).resetHelixRemote,
                      ),
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
        title: Text(HelixLocalizations.of(context).confirmDestructiveReset),
        content: Text(
          HelixLocalizations.of(context).willPermanentlyDeleteAllLocal,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(HelixLocalizations.of(context).cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(HelixLocalizations.of(context).deleteReset),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await widget.root.performReset();
    if (mounted) _startBoot();
  }
}
