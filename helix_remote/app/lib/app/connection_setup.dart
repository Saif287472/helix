part of '../main.dart';

class _ServerChoiceHost extends StatefulWidget {
  const _ServerChoiceHost({required this.onChoice});

  final void Function(Object? choice) onChoice;

  @override
  State<_ServerChoiceHost> createState() => _ServerChoiceHostState();
}

class _ServerChoiceHostState extends State<_ServerChoiceHost> {
  bool _pushed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_pushed) return;
    _pushed = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final result = await Navigator.of(
        context,
      ).pushReplacementNamed<Object?, Object?>(RemoteRoutes.serverChoice);
      widget.onChoice(result);
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: HelixSkeleton(width: 192, height: 24)),
    );
  }
}

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
    ).pushNamed<Object?>(RemoteRoutes.serverChoice);
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
                        connectError!,
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

// ---------------------------------------------------------------------------
// Server URL entry screen (manual "change server" path for already-onboarded
// installs; the first-launch flow uses ServerChoiceScreen instead)
// ---------------------------------------------------------------------------

class _ServerUrlEntryScreen extends StatefulWidget {
  const _ServerUrlEntryScreen({
    required this.onConnect,
    this.initialError,
    this.initialUrl,
  });

  final Future<void> Function(String url) onConnect;
  final String? initialError;
  final String? initialUrl;

  @override
  State<_ServerUrlEntryScreen> createState() => _ServerUrlEntryScreenState();
}

class _ServerUrlEntryScreenState extends State<_ServerUrlEntryScreen> {
  final _urlController = TextEditingController();
  bool _connecting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _error = widget.initialError;
    _urlController.text = widget.initialUrl ?? '';
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final url = _urlController.text.trim();
    if (url.isEmpty || _connecting) return;
    setState(() {
      _connecting = true;
      _error = null;
    });
    try {
      await widget.onConnect(url);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
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
                    const Icon(Icons.dns_outlined, size: 64),
                    const SizedBox(height: 16),
                    Text(
                      HelixLocalizations.of(context).connectServer2,
                      style: theme.textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      HelixLocalizations.of(context).enterUrlHelixRemoteBackend,
                      style: theme.textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    TextField(
                      controller: _urlController,
                      enabled: !_connecting,
                      decoration: InputDecoration(
                        labelText: 'Server URL',
                        hintText: 'https://xxxx.ngrok-free.dev',
                        border: const OutlineInputBorder(),
                        errorText: _error,
                        errorMaxLines: 4,
                      ),
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _connect(),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _connecting ? null : _connect,
                        icon: _connecting
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.link),
                        label: Text(_connecting ? 'Connecting…' : 'Connect'),
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

// ---------------------------------------------------------------------------
// Main app — shown once the root is built and URL is confirmed
// ---------------------------------------------------------------------------
