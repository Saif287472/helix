part of '../main.dart';

// ---------------------------------------------------------------------------
// Offline shell — shown when the user chose (or previously chose) to
// continue without a server connected.
// ---------------------------------------------------------------------------

class _OfflineShellScreen extends StatelessWidget {
  const _OfflineShellScreen({
    required this.onServerChoiceMade,
    this.connectError,
  });

  final void Function(Object? choice) onServerChoiceMade;
  final String? connectError;

  Future<void> _connect(BuildContext context) async {
    final result = await Navigator.of(
      context,
    ).pushNamed<Object?>(RemoteRoutes.setup);
    onServerChoiceMade(result);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(HelixLocalizations.of(context).appTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Padding(
                padding: HelixInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.cloud_off_outlined,
                      size: 64,
                      color: theme.colorScheme.outline,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      HelixLocalizations.of(context).browsingOffline,
                      style: theme.textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      HelixLocalizations.of(
                        context,
                      ).noServerConnectedSoMessaging,
                      style: theme.textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    if (connectError != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        RemoteUserErrorCopy.scrubDomain(connectError!),
                        style: TextStyle(color: theme.colorScheme.error),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => _connect(context),
                        icon: const Icon(Icons.link),
                        label: Text(
                          HelixLocalizations.of(context).connectServer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
