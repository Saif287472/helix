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
import 'package:helix_remote/screens/invite_entry_screen.dart';
import 'package:helix_remote/screens/server_choice_screen.dart';
import 'package:helix_remote/services/android_call_runtime_service.dart';
import 'package:helix_remote/services/app_logger.dart';
import 'package:helix_remote/services/local_notification_service.dart';
import 'package:helix_remote/services/onboarding_state_store.dart';
import 'package:helix_remote/services/server_url_store.dart';
import 'package:helix_remote/widgets/onboarding_security_badges.dart';
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

enum _BootState { loading, needsServerChoice, needsUrl, offline, running }

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
  String _currentServerUrl = kHelixGlobalServerUrl;
  String? _pendingInviteCode;

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
        // Back-compat: any install that ever saved a server URL already
        // completed setup under the pre-first-launch-screen flow, so it
        // must never see the new choice screen retroactively.
        await OnboardingStateStore.instance.markFirstLaunchCompleted();
        await _buildAndApplyRoot(savedUrl);
        return;
      }

      // Fall back to compile-time --dart-define values (CI / dev scripts)
      try {
        final dartConfig = RemoteDevelopmentConfig.fromDartDefine(
          databaseDirectory: _dbDir,
          attachmentCacheDir: _cacheDir,
        );
        await OnboardingStateStore.instance.markFirstLaunchCompleted();
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
        // No dart-define config — fall through to the first-launch flow
      }

      final firstLaunchDone = await OnboardingStateStore.instance
          .isFirstLaunchCompleted();
      if (mounted) {
        setState(() {
          _bootState = firstLaunchDone
              ? _BootState.offline
              : _BootState.needsServerChoice;
        });
      }
    } catch (e, st) {
      AppLogger.instance.error('bootstrap', '$e', st);
      if (mounted) {
        setState(() {
          _initialUrlError = e.toString();
          _bootState = _BootState.needsServerChoice;
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

  /// Handles the result popped from [ServerChoiceScreen]: either a chosen
  /// server + invite (Global or personal), or the user continuing offline
  /// (including simply backing out without choosing anything).
  Future<void> _onServerChoiceMade(Object? choice) async {
    await OnboardingStateStore.instance.markFirstLaunchCompleted();
    _initialUrlError = null;
    if (choice is ServerInviteChoice) {
      _pendingInviteCode = choice.inviteCode;
      try {
        await _onConnectUrl(choice.serverUrl);
      } catch (e) {
        _pendingInviteCode = null;
        if (mounted) {
          setState(() {
            _initialUrlError = e.toString();
            _bootState = _BootState.offline;
          });
        }
      }
      return;
    }
    if (mounted) setState(() => _bootState = _BootState.offline);
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
        initialInviteCode: _pendingInviteCode,
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
      home: _buildBootHome(),
    );
  }

  Widget _buildBootHome() {
    switch (_bootState) {
      case _BootState.loading:
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      case _BootState.needsServerChoice:
        return _ServerChoiceHost(onChoice: _onServerChoiceMade);
      case _BootState.offline:
        return _OfflineShellScreen(
          onServerChoiceMade: _onServerChoiceMade,
          connectError: _initialUrlError,
        );
      case _BootState.needsUrl:
        return _ServerUrlEntryScreen(
          onConnect: _onConnectUrl,
          initialError: _initialUrlError,
          initialUrl: _currentServerUrl,
        );
      case _BootState.running:
        // Handled above before reaching this switch.
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
  }
}

// ---------------------------------------------------------------------------
// First-launch server choice — shown once, replaced by _BootState.offline or
// _BootState.running after a choice is made.
// ---------------------------------------------------------------------------

/// Hosts [ServerChoiceScreen] as the very first route so it can rely on its
/// normal push/pop-based result flow even when nothing else has been pushed
/// yet. Uses `pushReplacement` so there is no route left underneath it to
/// accidentally navigate back to.
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
      final result = await Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const ServerChoiceScreen()),
      );
      widget.onChoice(result);
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
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
    final result = await Navigator.of(context).push<Object?>(
      MaterialPageRoute(builder: (_) => const ServerChoiceScreen()),
    );
    onServerChoiceMade(result);
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
                    Icon(
                      Icons.cloud_off_outlined,
                      size: 64,
                      color: theme.colorScheme.outline,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'You\'re browsing offline',
                      style: theme.textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No server is connected, so messaging, calls, and '
                      'contacts aren\'t available yet. Connect a server '
                      'anytime to get started.',
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
                        label: const Text('Connect a server'),
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
  const HelixRemoteApp({
    super.key,
    required this.root,
    this.onChangeServerUrl,
    this.initialInviteCode,
  });

  final RemoteCompositionRoot root;
  final Future<void> Function()? onChangeServerUrl;

  /// Invite code carried over from the first-launch server-choice screen
  /// (Helix Global or a personal server), so the create-account form is
  /// pre-filled and the user doesn't have to re-enter or re-paste it.
  final String? initialInviteCode;

  @override
  State<HelixRemoteApp> createState() => _HelixRemoteAppState();
}

enum _SetupPath { choose, createAccount }

enum _CreateAccountStep { enterDetails, enterOtp }

class _HelixRemoteAppState extends State<HelixRemoteApp>
    with WidgetsBindingObserver {
  RemoteStartupState _startupState = RemoteStartupState.idle;
  String? _errorMessage;
  String? _registrationError;
  String? _displayNameError;
  String? _phoneError;
  String? _inviteError;
  String? _otpError;
  bool _initializing = false;
  bool _registering = false;
  bool _sendingCode = false;
  _SetupPath _setupPath = _SetupPath.choose;
  _CreateAccountStep _createAccountStep = _CreateAccountStep.enterDetails;
  RemoteCallStatus? _activeCallStatus;
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _inviteController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
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
    final initialInvite = widget.initialInviteCode;
    if (initialInvite != null && initialInvite.isNotEmpty) {
      _inviteController.text = initialInvite;
      _setupPath = _SetupPath.createAccount;
    }
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
    _phoneController.dispose();
    _inviteController.dispose();
    _otpController.dispose();
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
                      subtitle: 'Register with your phone number.',
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
            if (_createAccountStep == _CreateAccountStep.enterOtp) {
              _createAccountStep = _CreateAccountStep.enterDetails;
              _otpController.clear();
              _otpError = null;
              return;
            }
            _setupPath = _SetupPath.choose;
            _registrationError = null;
            _displayNameError = null;
            _phoneError = null;
            _inviteError = null;
            _phoneController.clear();
            _inviteController.clear();
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
                child: _createAccountStep == _CreateAccountStep.enterDetails
                    ? _buildAccountDetailsStep()
                    : _buildOtpStep(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAccountDetailsStep() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Deep-linked invite signups (widget.initialInviteCode) skip
        // ServerChoiceScreen entirely and land here directly, so this
        // onboarding highlight is repeated here rather than relying solely
        // on the choice screen showing it first.
        const OnboardingSecurityBadge(),
        const SizedBox(height: 16),
        TextField(
          controller: _phoneController,
          enabled: !_sendingCode,
          decoration: InputDecoration(
            labelText: 'Phone number',
            hintText: 'e.g. +15551234567',
            border: const OutlineInputBorder(),
            helperText: RemoteAccountValidation.phoneNumberRules,
            errorText: _phoneError,
          ),
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _inviteController,
          enabled: !_sendingCode,
          decoration: InputDecoration(
            labelText: 'Invite code',
            border: const OutlineInputBorder(),
            errorText: _inviteError,
          ),
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _displayNameController,
          enabled: !_sendingCode,
          decoration: InputDecoration(
            labelText: 'Display name',
            hintText: 'e.g. Hasan',
            border: const OutlineInputBorder(),
            helperText: RemoteAccountValidation.displayNameRules,
            errorText: _displayNameError,
          ),
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _sendVerificationCode(),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _sendingCode ? null : _sendVerificationCode,
            icon: _sendingCode
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sms_outlined),
            label: Text(
              _sendingCode ? 'Sending code…' : 'Send verification code',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOtpStep() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'We sent a code to ${RemoteAccountValidation.normalizePhoneNumber(_phoneController.text)}. '
          'Since real SMS delivery isn\'t available yet, check your '
          'notifications for it.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        const OtpPlaceholderNotice(),
        const SizedBox(height: 16),
        TextField(
          controller: _otpController,
          enabled: !_registering,
          decoration: InputDecoration(
            labelText: 'Verification code',
            border: const OutlineInputBorder(),
            errorText: _otpError ?? _registrationError,
          ),
          keyboardType: TextInputType.number,
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
            label: Text(_registering ? 'Creating account…' : 'Create account'),
          ),
        ),
      ],
    );
  }

  Future<void> _sendVerificationCode() async {
    if (_sendingCode) return;
    final phoneNumber = RemoteAccountValidation.normalizePhoneNumber(
      _phoneController.text,
    );
    final displayName = RemoteAccountValidation.normalizeDisplayName(
      _displayNameController.text,
    );
    final inviteCode = _inviteController.text.trim();
    final phoneError = RemoteAccountValidation.phoneNumberError(phoneNumber);
    final displayNameError = RemoteAccountValidation.displayNameError(
      displayName,
    );
    final inviteError = inviteCode.isEmpty
        ? 'Invite code cannot be empty.'
        : null;
    if (phoneError != null || displayNameError != null || inviteError != null) {
      setState(() {
        _phoneError = phoneError;
        _displayNameError = displayNameError;
        _inviteError = inviteError;
        _errorMessage = phoneError ?? displayNameError ?? inviteError;
      });
      return;
    }

    setState(() {
      _sendingCode = true;
      _phoneError = null;
      _displayNameError = null;
      _inviteError = null;
      _errorMessage = null;
    });

    try {
      await widget.root.requestOtp(phoneNumber);
      if (mounted) {
        setState(() => _createAccountStep = _CreateAccountStep.enterOtp);
      }
    } catch (e, st) {
      AppLogger.instance.warn('auth', 'OTP request failed: $e', st);
      if (mounted) {
        setState(() {
          _phoneError = _formatRegistrationError(e);
          _errorMessage = _phoneError;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _sendingCode = false;
        });
      }
    }
  }

  Future<void> _register() async {
    if (_registering) return;
    final otpCode = _otpController.text.trim();
    if (otpCode.isEmpty) {
      setState(() => _otpError = 'Verification code cannot be empty.');
      return;
    }

    setState(() {
      _registering = true;
      _otpError = null;
      _registrationError = null;
      _errorMessage = null;
    });

    try {
      await widget.root.registerAndLogin(
        phoneNumber: RemoteAccountValidation.normalizePhoneNumber(
          _phoneController.text,
        ),
        displayName: RemoteAccountValidation.normalizeDisplayName(
          _displayNameController.text,
        ),
        otpCode: otpCode,
        inviteCode: _inviteController.text.trim(),
      );
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
