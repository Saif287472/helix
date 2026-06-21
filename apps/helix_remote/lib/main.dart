import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:helix_remote/app/composition_root.dart';
import 'package:helix_remote/app/remote_config.dart';
import 'package:helix_remote/screens/call_screen.dart';
import 'package:helix_remote/screens/conversation_list_screen.dart';
import 'package:helix_remote_calls/helix_remote_calls.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final appDir = await getApplicationDocumentsDirectory();
    final dbDir = p.join(appDir.path, 'helix_remote_db');
    final cacheDir = p.join(appDir.path, 'attachments_cache');

    final devConfig = RemoteDevelopmentConfig.fromDartDefine(
      databaseDirectory: dbDir,
      attachmentCacheDir: cacheDir,
    );

    final root = RemoteCompositionRoot.production(
      databaseDirectory: dbDir,
      devConfig: devConfig,
    );

    runApp(HelixRemoteApp(root: root));
  } catch (error) {
    runApp(HelixRemoteConfigurationErrorApp(message: error.toString()));
  }
}

class HelixRemoteConfigurationErrorApp extends StatelessWidget {
  const HelixRemoteConfigurationErrorApp({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Helix Remote Configuration',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF166A64)),
      ),
      home: Scaffold(
        appBar: AppBar(title: const Text('Helix Remote')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.settings_outlined, size: 56),
                  const SizedBox(height: 16),
                  Text(
                    'Remote configuration required',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  Text(message),
                  const SizedBox(height: 20),
                  const Text(
                    'Start the app with one of the documented '
                    'HELIX_REMOTE_PROFILE launch commands in '
                    'docs/workflows/ENVIRONMENT.md.',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class HelixRemoteApp extends StatefulWidget {
  const HelixRemoteApp({super.key, required this.root});

  final RemoteCompositionRoot root;

  @override
  State<HelixRemoteApp> createState() => _HelixRemoteAppState();
}

enum _SetupPath { choose, createAccount }

class _HelixRemoteAppState extends State<HelixRemoteApp> {
  RemoteStartupState _startupState = RemoteStartupState.idle;
  String? _errorMessage;
  String? _registrationError;
  bool _initializing = false;
  bool _registering = false;
  _SetupPath _setupPath = _SetupPath.choose;
  RemoteCallStatus? _activeCallStatus;
  final TextEditingController _usernameController = TextEditingController();
  StreamSubscription<RemoteStartupState>? _stateSub;
  StreamSubscription<RemoteCallStatus?>? _callSub;

  @override
  void initState() {
    super.initState();
    _stateSub = widget.root.startupStateChanges.listen((state) {
      if (!mounted) return;
      setState(() {
        _startupState = state;
        _errorMessage = widget.root.lastError;
      });
    });
    _callSub = widget.root.callStatusChanges.listen((status) {
      if (!mounted) return;
      setState(() => _activeCallStatus = status);
    });
    _startBoot();
  }

  Future<void> _startBoot() async {
    if (_initializing) return;
    _initializing = true;
    try {
      await widget.root.initialize();
      if (!mounted) return;
      final restored = await widget.root.tryRestoreSession();
      if (!mounted) return;
      if (restored) {
        await widget.root.startRuntime();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = widget.root.lastError ?? e.toString());
      }
    } finally {
      _initializing = false;
    }
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _callSub?.cancel();
    _usernameController.dispose();
    widget.root.dispose().ignore();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: widget.root.config.displayName,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en')],
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF166A64),
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF166A64),
          brightness: Brightness.dark,
        ),
      ),
      highContrastTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF166A64),
          brightness: Brightness.light,
          contrastLevel: 1.0,
        ),
      ),
      highContrastDarkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF166A64),
          brightness: Brightness.dark,
          contrastLevel: 1.0,
        ),
      ),
      themeMode: ThemeMode.system,
      home: _buildScreen(),
    );
  }

  Widget _buildScreen() {
    final base = _buildBaseScreen();
    final callStatus = _activeCallStatus;
    if (callStatus != null &&
        (callStatus.state == RemoteCallState.ringing ||
            callStatus.state == RemoteCallState.offering ||
            callStatus.state == RemoteCallState.active) &&
        (_startupState == RemoteStartupState.ready ||
            _startupState == RemoteStartupState.authenticatedAndSyncing)) {
      return Stack(
        children: [
          base,
          Positioned.fill(child: _buildCallOverlay(callStatus)),
        ],
      );
    }
    return base;
  }

  Widget _buildCallOverlay(RemoteCallStatus callStatus) {
    return CallScreen(
      callStatus: callStatus,
      onAccept: callStatus.state == RemoteCallState.ringing
          ? () => widget.root.callService.acceptIncomingCall().ignore()
          : null,
      onDecline: () => widget.root.callService.endActiveCall().ignore(),
      onEnd: () => widget.root.callService.endActiveCall().ignore(),
      onMute: ({required bool muted}) =>
          widget.root.callService.setMuted(muted: muted).ignore(),
    );
  }

  Widget _buildBaseScreen() {
    switch (_startupState) {
      case RemoteStartupState.idle:
      case RemoteStartupState.loadingConfiguration:
      case RemoteStartupState.openingSecureStorage:
      case RemoteStartupState.firstRunInitialization:
      case RemoteStartupState.openingDatabase:
      case RemoteStartupState.restoringSession:
        return _buildLoadingScreen();

      case RemoteStartupState.unauthenticated:
        return _buildSetupScreen();

      case RemoteStartupState.authenticatedAndSyncing:
        return _buildSyncingScreen();

      case RemoteStartupState.ready:
        return _buildReadyScreen();

      case RemoteStartupState.recoverableFailure:
        return _buildErrorScreen();

      case RemoteStartupState.resetRequired:
        return _buildResetScreen();
    }
  }

  Widget _buildLoadingScreen() {
    return Scaffold(
      appBar: AppBar(title: Text(widget.root.config.displayName)),
      body: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Starting Helix Remote...'),
          ],
        ),
      ),
    );
  }

  Widget _buildSyncingScreen() {
    return Scaffold(
      appBar: AppBar(title: Text(widget.root.config.displayName)),
      body: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Syncing…'),
          ],
        ),
      ),
    );
  }

  Widget _buildSetupScreen() {
    switch (_setupPath) {
      case _SetupPath.choose:
        return _buildSetupChoiceScreen();
      case _SetupPath.createAccount:
        return _buildCreateAccountScreen();
    }
  }

  Widget _buildSetupChoiceScreen() {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.root.config.displayName)),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_outlined, size: 64),
                    const SizedBox(height: 16),
                    Text(
                      'Welcome to Helix Remote',
                      style: theme.textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'How would you like to continue?',
                      style: theme.textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    _SetupOptionTile(
                      icon: Icons.person_add_outlined,
                      title: 'Create new account',
                      subtitle: 'Register a new username on this server.',
                      onTap: () =>
                          setState(() => _setupPath = _SetupPath.createAccount),
                    ),
                    const SizedBox(height: 12),
                    _SetupOptionTile(
                      icon: Icons.restore_outlined,
                      title: 'Restore existing account unavailable',
                      subtitle:
                          'Fresh-device recovery is not enabled in this build. '
                          'Use an already signed-in device to keep access.',
                      enabled: false,
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

  Widget _buildCreateAccountScreen() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create account'),
        leading: BackButton(
          onPressed: () => setState(() {
            _setupPath = _SetupPath.choose;
            _registrationError = null;
            _usernameController.clear();
          }),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _usernameController,
                  enabled: !_registering,
                  decoration: InputDecoration(
                    labelText: 'Username',
                    border: const OutlineInputBorder(),
                    helperText: 'Letters, numbers, and underscores only.',
                    errorText: _registrationError,
                  ),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _register(),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _registering ? null : _register,
                    icon: _registering
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.person_add_outlined),
                    label: Text(
                      _registering ? 'Creating account…' : 'Create account',
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

  Future<void> _register() async {
    final username = _usernameController.text.trim();
    if (username.isEmpty || _registering) return;

    setState(() {
      _registering = true;
      _registrationError = null;
      _errorMessage = null;
    });

    try {
      await widget.root.registerAndLogin(username);
    } catch (e) {
      if (mounted) {
        setState(() {
          _registrationError = _formatRegistrationError(e);
          _errorMessage = _registrationError;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _registering = false;
        });
      }
    }
  }

  String _formatRegistrationError(Object error) {
    final backend = widget.root.devConfig.restBaseUri;
    final raw = error.toString();
    final backendHint =
        backend.host == 'localhost' || backend.host == '127.0.0.1'
        ? 'On a physical Android device, localhost points to the phone. '
              'Restart with --dart-define=HELIX_REMOTE_HOST=<your PC LAN IP> '
              'and make sure the backend is running.'
        : 'Make sure the backend is running at $backend and reachable from '
              'this device.';

    if (raw.contains('SocketException') ||
        raw.contains('Connection refused') ||
        raw.contains('Failed host lookup') ||
        raw.contains('Connection timed out')) {
      return 'Could not reach Helix Remote backend at $backend. $backendHint';
    }

    return 'Registration failed: $raw';
  }

  Widget _buildReadyScreen() {
    return ConversationListScreen(
      messagingService: widget.root.messagingService,
      root: widget.root,
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
                  setState(() => _errorMessage = null);
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
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.error,
                    ),
                    onPressed: _confirmedReset,
                    icon: const Icon(Icons.delete_forever_outlined),
                    label: const Text('Reset Helix Remote'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmedReset() async {
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

class _SetupOptionTile extends StatelessWidget {
  const _SetupOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconColor = enabled
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurface.withAlpha(120);
    final subtitleColor = enabled
        ? theme.colorScheme.onSurface.withAlpha(160)
        : theme.colorScheme.onSurface.withAlpha(120);
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, size: 32, color: iconColor),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: subtitleColor,
                      ),
                    ),
                  ],
                ),
              ),
              if (enabled)
                const Icon(Icons.chevron_right)
              else
                Text(
                  'Unavailable',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurface.withAlpha(140),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
