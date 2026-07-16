import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:helix_remote/app/composition_root.dart';
import 'package:helix_remote/app/remote_account_validation.dart';
import 'package:helix_remote/app/remote_config.dart';
import 'package:helix_remote/app/remote_error_copy.dart';
import 'package:helix_remote/app/remote_rest_client.dart';
import 'package:helix_remote/screens/home_screen.dart';
import 'package:helix_remote/services/android_call_runtime_service.dart';
import 'package:helix_remote/services/app_logger.dart';
import 'package:helix_remote/services/local_notification_service.dart';
import 'package:helix_remote/services/server_url_store.dart';
import 'package:helix_remote_calls/helix_remote_calls.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

void main() {
  FlutterError.onError = (details) {
    debugPrint('[Helix ERROR] ${details.exception}');
    debugPrint('[Helix STACK] ${details.stack}');
    AppLogger.instance.error('flutter', '${details.exception}', details.stack);
  };

  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      await AppLogger.instance.init('helix_remote');
      await LocalNotificationService.init();
      runApp(const HelixRemoteBootstrap());
    },
    (error, stack) {
      debugPrint('[Helix UNCAUGHT] $error');
      debugPrint('[Helix STACK] $stack');
      AppLogger.instance.error('uncaught', '$error', stack);
    },
  );
}

// ---------------------------------------------------------------------------
// Bootstrap — owns URL setup and root lifecycle
// ---------------------------------------------------------------------------

enum _BootState { loading, needsUrl, running }

const _kDefaultServerUrl = 'https://helix.agiletechbd.com';

class HelixRemoteBootstrap extends StatefulWidget {
  const HelixRemoteBootstrap({super.key});

  @override
  State<HelixRemoteBootstrap> createState() => _HelixRemoteBootstrapState();
}

class _HelixRemoteBootstrapState extends State<HelixRemoteBootstrap> {
  _BootState _bootState = _BootState.loading;
  RemoteCompositionRoot? _root;
  String? _initialUrlError;
  String _dbDir = '';
  String _cacheDir = '';
  String _currentServerUrl = _kDefaultServerUrl;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      _dbDir = p.join(appDir.path, 'helix_remote_db');
      _cacheDir = p.join(appDir.path, 'attachments_cache');

      // Prefer URL saved at runtime (entered by the user)
      final savedUrl = await ServerUrlStore.instance.load();
      if (savedUrl != null && savedUrl.isNotEmpty) {
        await _buildAndApplyRoot(savedUrl);
        return;
      }

      // Fall back to compile-time --dart-define values (CI / dev scripts)
      try {
        final dartConfig = RemoteDevelopmentConfig.fromDartDefine(
          databaseDirectory: _dbDir,
          attachmentCacheDir: _cacheDir,
        );
        final root = RemoteCompositionRoot.production(
          databaseDirectory: _dbDir,
          devConfig: dartConfig,
        );
        if (mounted) {
          setState(() {
            _root = root;
            _bootState = _BootState.running;
          });
        }
        return;
      } catch (_) {
        // No dart-define config — fall through to URL entry
      }

      if (mounted) setState(() => _bootState = _BootState.needsUrl);
    } catch (e, st) {
      AppLogger.instance.error('bootstrap', '$e', st);
      if (mounted) {
        setState(() {
          _initialUrlError = e.toString();
          _bootState = _BootState.needsUrl;
        });
      }
    }
  }

  Future<void> _buildAndApplyRoot(String url) async {
    _currentServerUrl = url;
    final config = RemoteDevelopmentConfig.fromServerUrl(
      url,
      databaseDirectory: _dbDir,
      attachmentCacheDir: _cacheDir,
    );
    final root = RemoteCompositionRoot.production(
      databaseDirectory: _dbDir,
      devConfig: config,
    );
    if (mounted) {
      setState(() {
        _root = root;
        _bootState = _BootState.running;
      });
    }
  }

  Future<void> _onConnectUrl(String url) async {
    await ServerUrlStore.instance.save(url);
    try {
      await _buildAndApplyRoot(url);
    } catch (e) {
      await ServerUrlStore.instance.clear();
      rethrow;
    }
  }

  Future<void> _onChangeServerUrl() async {
    final oldRoot = _root;
    setState(() {
      _root = null;
      _bootState = _BootState.loading;
    });
    await oldRoot?.dispose();
    await ServerUrlStore.instance.clear();
    if (mounted) {
      setState(() {
        _bootState = _BootState.needsUrl;
        _initialUrlError = null;
      });
    }
  }

  static const _seedColor = Color(0xFF166A64);

  @override
  Widget build(BuildContext context) {
    if (_bootState == _BootState.running && _root != null) {
      return HelixRemoteApp(
        root: _root!,
        onChangeServerUrl: _onChangeServerUrl,
      );
    }
    return MaterialApp(
      title: 'Helix Remote',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en')],
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: _seedColor),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seedColor,
          brightness: Brightness.dark,
        ),
      ),
      themeMode: ThemeMode.system,
      home: _bootState == _BootState.loading
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : _ServerUrlEntryScreen(
              onConnect: _onConnectUrl,
              initialError: _initialUrlError,
              initialUrl: _currentServerUrl,
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Server URL entry screen
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
      appBar: AppBar(title: const Text('Helix Remote')),
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
                    const Icon(Icons.dns_outlined, size: 64),
                    const SizedBox(height: 16),
                    Text(
                      'Connect to Server',
                      style: theme.textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Enter the URL of your Helix Remote backend.',
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

class HelixRemoteApp extends StatefulWidget {
  const HelixRemoteApp({super.key, required this.root, this.onChangeServerUrl});

  final RemoteCompositionRoot root;
  final Future<void> Function()? onChangeServerUrl;

  @override
  State<HelixRemoteApp> createState() => _HelixRemoteAppState();
}

enum _SetupPath { choose, createAccount }

class _HelixRemoteAppState extends State<HelixRemoteApp>
    with WidgetsBindingObserver {
  RemoteStartupState _startupState = RemoteStartupState.idle;
  String? _errorMessage;
  String? _registrationError;
  String? _displayNameError;
  bool _initializing = false;
  bool _registering = false;
  _SetupPath _setupPath = _SetupPath.choose;
  RemoteCallStatus? _activeCallStatus;
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _displayNameController = TextEditingController();
  StreamSubscription<RemoteStartupState>? _stateSub;
  StreamSubscription<RemoteCallStatus?>? _callSub;
  // _activeCallStatus is updated without setState to avoid recreating HomeScreen
  // on every call state change (which caused a double call-screen push bug).
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  String? _lastConnectivitySignature;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _stateSub = widget.root.startupStateChanges.listen((state) {
      if (!mounted) return;
      setState(() {
        _startupState = state;
        _errorMessage = widget.root.lastError;
      });
    });
    _callSub = widget.root.callStatusChanges.listen((status) {
      if (!mounted) return;
      _activeCallStatus = status;
      unawaited(
        AndroidCallRuntimeService.setCallActive(
          active: status != null,
          keepScreenOn: status?.isVideo == true,
        ),
      );
    });
    _connectivitySub = Connectivity().onConnectivityChanged.listen(
      _onConnectivityChanged,
    );
    _startBoot();
  }

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    final hasNetwork = results.any((r) => r != ConnectivityResult.none);
    final signature =
        (results
                .where((r) => r != ConnectivityResult.none)
                .map((r) => r.name)
                .toList()
              ..sort())
            .join(',');
    final handoff =
        hasNetwork &&
        _lastConnectivitySignature != null &&
        signature != _lastConnectivitySignature;
    _lastConnectivitySignature = signature;
    if (_startupState == RemoteStartupState.ready ||
        _startupState == RemoteStartupState.authenticatedAndSyncing ||
        _startupState == RemoteStartupState.recoverableFailure) {
      try {
        widget.root.runtimeCoordinator.setNetworkAvailable(hasNetwork);
        if (handoff && _activeCallStatus != null) {
          widget.root.callService.restartIce().ignore();
        }
      } catch (_) {}
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        (_startupState == RemoteStartupState.ready ||
            _startupState == RemoteStartupState.authenticatedAndSyncing)) {
      try {
        widget.root.runtimeCoordinator.softSync().ignore();
      } catch (_) {}
    }
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
    } catch (e, st) {
      AppLogger.instance.error('boot', '$e', st);
      if (mounted) {
        setState(() => _errorMessage = widget.root.lastError ?? e.toString());
      }
    } finally {
      _initializing = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stateSub?.cancel();
    _callSub?.cancel();
    _connectivitySub?.cancel();
    _usernameController.dispose();
    _displayNameController.dispose();
    widget.root.dispose().ignore();
    AndroidCallRuntimeService.setCallActive(
      active: false,
      keepScreenOn: false,
    ).ignore();
    super.dispose();
  }

  static const _seedColor = Color(0xFF166A64);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: widget.root.config.displayName,
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en')],
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seedColor,
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seedColor,
          brightness: Brightness.dark,
        ),
      ),
      highContrastTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seedColor,
          brightness: Brightness.light,
          contrastLevel: 1.0,
        ),
      ),
      highContrastDarkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seedColor,
          brightness: Brightness.dark,
          contrastLevel: 1.0,
        ),
      ),
      themeMode: ThemeMode.system,
      home: _buildBaseScreen(),
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
                      title: 'Restore existing account',
                      subtitle:
                          'Link this device from a trusted device, then restore '
                          'your encrypted backup from Settings.',
                      enabled: false,
                    ),
                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: widget.onChangeServerUrl,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 10,
                          horizontal: 4,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.dns_outlined,
                              size: 18,
                              color: theme.colorScheme.outline,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                widget.root.devConfig.restBaseUri.authority,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.outline,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              'Change',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ],
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

  Widget _buildCreateAccountScreen() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create account'),
        leading: BackButton(
          onPressed: () => setState(() {
            _setupPath = _SetupPath.choose;
            _registrationError = null;
            _displayNameError = null;
            _usernameController.clear();
            _displayNameController.clear();
          }),
        ),
      ),
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
                    TextField(
                      controller: _usernameController,
                      enabled: !_registering,
                      decoration: InputDecoration(
                        labelText: 'Username',
                        hintText: 'e.g. hasan_dev',
                        border: const OutlineInputBorder(),
                        helperText: RemoteAccountValidation.usernameRules,
                        errorText: _registrationError,
                      ),
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _displayNameController,
                      enabled: !_registering,
                      decoration: InputDecoration(
                        labelText: 'Display name',
                        hintText: 'e.g. Hasan',
                        border: const OutlineInputBorder(),
                        helperText: RemoteAccountValidation.displayNameRules,
                        errorText: _displayNameError,
                      ),
                      textCapitalization: TextCapitalization.words,
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
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
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
        ),
      ),
    );
  }

  Future<void> _register() async {
    if (_registering) return;
    final username = RemoteAccountValidation.normalizeUsername(
      _usernameController.text,
    );
    final displayName = RemoteAccountValidation.normalizeDisplayName(
      _displayNameController.text,
    );
    final usernameError = RemoteAccountValidation.usernameError(username);
    final displayNameError = RemoteAccountValidation.displayNameError(
      displayName,
    );
    if (usernameError != null || displayNameError != null) {
      setState(() {
        _registrationError = usernameError;
        _displayNameError = displayNameError;
        _errorMessage = usernameError ?? displayNameError;
      });
      return;
    }

    setState(() {
      _registering = true;
      _registrationError = null;
      _displayNameError = null;
      _errorMessage = null;
    });

    try {
      await widget.root.registerAndLogin(username, displayName);
    } catch (e, st) {
      AppLogger.instance.warn('auth', 'Registration failed: $e', st);
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
    if (error is RemoteRestException) {
      return RemoteUserErrorCopy.registrationFailure(error, backend);
    }
    return RemoteUserErrorCopy.unknownRegistration();
  }

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

// ---------------------------------------------------------------------------
// Configuration error screen — kept for test compatibility
// ---------------------------------------------------------------------------

class HelixRemoteConfigurationErrorApp extends StatelessWidget {
  const HelixRemoteConfigurationErrorApp({super.key, required this.message});

  final String message;

  static const _seedColor = Color(0xFF166A64);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Helix Remote',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: _seedColor),
      ),
      home: Scaffold(
        appBar: AppBar(title: const Text('Helix Remote')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.settings_outlined, size: 64),
                const SizedBox(height: 16),
                const Text(
                  'Remote configuration required',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(message, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );
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
