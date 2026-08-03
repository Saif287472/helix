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
import 'package:helix_remote/widgets/country_code_picker.dart';
import 'package:helix_remote/widgets/onboarding_security_badges.dart';
import 'package:helix_remote_calls/helix_remote_calls.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Caps how far the device's system font-size/accessibility setting can
/// scale text, via the recommended `MaterialApp.builder` hook. Several
/// fixed-size layout elements (nav bar height, filter chip height, quick
/// action bubbles) don't grow with text scale, so leaving it unbounded
/// clips or overflows them once the system setting goes much past 1x - a
/// max around 1.3x still gives real accessibility benefit without that.
/// Never clamps below 1x, so a user who prefers smaller text still gets it.
Widget _clampTextScale(BuildContext context, Widget? child) {
  final mediaQuery = MediaQuery.of(context);
  return MediaQuery(
    data: mediaQuery.copyWith(
      textScaler: mediaQuery.textScaler.clamp(maxScaleFactor: 1.3),
    ),
    child: child!,
  );
}

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
  String? _pendingPhoneNumber;

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
      _pendingPhoneNumber = choice.phoneNumber;
      try {
        await _onConnectUrl(choice.serverUrl);
      } catch (e) {
        _pendingInviteCode = null;
        _pendingPhoneNumber = null;
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
        initialPhoneNumber: _pendingPhoneNumber,
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
      builder: _clampTextScale,
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
    this.initialPhoneNumber,
  });

  final RemoteCompositionRoot root;
  final Future<void> Function()? onChangeServerUrl;

  /// Invite code carried over from the first-launch server-choice screen
  /// (Helix Global or a personal server), so the create-account form is
  /// pre-filled and the user doesn't have to re-enter or re-paste it.
  final String? initialInviteCode;

  /// E.164 phone number carried over from the personal-server invite entry
  /// screen (the only place it's collected before this point), so the
  /// create-account form doesn't ask for it a second time.
  final String? initialPhoneNumber;

  @override
  State<HelixRemoteApp> createState() => _HelixRemoteAppState();
}

enum _CreateAccountStep { enterDetails, enterOtp, enterDisplayName }

/// Result of the last invite-code auto-validation (see `_validateInviteCode`
/// on the invite code field's focus loss). `null` means "not checked yet" -
/// distinct from a checked-and-failed state, so no icon shows until the
/// user has actually had a chance to enter something.
enum _InviteCheckState { checking, valid, invalid }

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
  /// Whether the last OTP request came back as a placeholder code (shown
  /// via local notification) rather than a real SMS - see
  /// `RemoteCompositionRegistration.requestOtp`. Defaults to true so the
  /// placeholder notice stays visible until a request actually completes.
  bool _otpIsPlaceholder = true;
  _CreateAccountStep _createAccountStep = _CreateAccountStep.enterDetails;
  /// Result of the last invite-code auto-validation, or null if the field
  /// hasn't been checked yet (e.g. still empty, or never blurred).
  _InviteCheckState? _inviteCheckState;
  String? _inviteCheckReason;
  Country _selectedCountry = kDefaultCountry;
  bool _prefilledInviteChecked = false;
  RemoteCallStatus? _activeCallStatus;
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _nationalNumberController =
      TextEditingController();
  final TextEditingController _inviteController = TextEditingController();
  final FocusNode _inviteFocusNode = FocusNode();
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
    _nationalNumberController.addListener(_syncPhoneController);
    final initialInvite = widget.initialInviteCode;
    if (initialInvite != null && initialInvite.isNotEmpty) {
      _inviteController.text = initialInvite;
    }
    final initialPhoneNumber = widget.initialPhoneNumber;
    if (initialPhoneNumber != null && initialPhoneNumber.isNotEmpty) {
      final split = splitE164PhoneNumber(initialPhoneNumber);
      _selectedCountry = split.country;
      _nationalNumberController.text = split.nationalNumber;
      _syncPhoneController();
    }
    _inviteFocusNode.addListener(() {
      if (!_inviteFocusNode.hasFocus) _validateInviteCode();
    });
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
    _nationalNumberController.dispose();
    _inviteController.dispose();
    _inviteFocusNode.dispose();
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
      builder: _clampTextScale,
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
        return _buildCreateAccountScreen();

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

  Widget _buildCreateAccountScreen() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create account'),
        leading: switch (_createAccountStep) {
          // Entry point of the (now single, deterministic) onboarding flow -
          // nothing to go back to. "Change server" lives in the body instead
          // of being conflated with the back gesture (see below).
          _CreateAccountStep.enterDetails => null,
          _CreateAccountStep.enterOtp => BackButton(
            onPressed: () {
              _unfocusForStepChange();
              setState(() {
                _createAccountStep = _CreateAccountStep.enterDetails;
                _otpController.clear();
                _otpError = null;
              });
            },
          ),
          _CreateAccountStep.enterDisplayName => BackButton(
            onPressed: () {
              _unfocusForStepChange();
              setState(() => _createAccountStep = _CreateAccountStep.enterOtp);
            },
          ),
        },
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: _buildCreateAccountStepSafely(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Wraps step construction in a try/catch so a bug in one of these steps
  /// shows an actual (if ugly) error on screen instead of a silent blank
  /// page - release builds strip the framework's own red error screen, so
  /// without this a thrown exception here is otherwise invisible.
  Widget _buildCreateAccountStepSafely() {
    try {
      return switch (_createAccountStep) {
        _CreateAccountStep.enterDetails => _buildAccountDetailsStep(),
        _CreateAccountStep.enterOtp => _buildOtpStep(),
        _CreateAccountStep.enterDisplayName => _buildDisplayNameStep(),
      };
    } catch (e, st) {
      AppLogger.instance.error('registration_ui', '$e', st);
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Something went wrong loading this screen.',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          SelectableText('$e'),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: () =>
                setState(() => _createAccountStep = _createAccountStep),
            child: const Text('Retry'),
          ),
        ],
      );
    }
  }

  Widget _buildAccountDetailsStep() {
    final theme = Theme.of(context);
    // Deep-linked/auto-issued invites (Helix Global, or a personal-server
    // link already validated on the choice screen) are pre-filled - check
    // it as soon as this step is actually on screen (which only happens
    // once _startupState reaches unauthenticated, so the composition
    // root's restClient is guaranteed ready) rather than waiting for the
    // user to focus and blur a field they never touched. Deferred a frame
    // so it never calls setState synchronously from within build().
    if (!_prefilledInviteChecked && _inviteController.text.isNotEmpty) {
      _prefilledInviteChecked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _validateInviteCode();
      });
    }
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
          controller: _inviteController,
          focusNode: _inviteFocusNode,
          enabled: !_sendingCode,
          decoration: InputDecoration(
            labelText: 'Server invitation code',
            border: const OutlineInputBorder(),
            errorText: _inviteError,
            suffixIcon: _buildInviteStatusIcon(),
          ),
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => _validateInviteCode(),
        ),
        const SizedBox(height: 16),
        PhoneNumberInput(
          country: _selectedCountry,
          onCountryChanged: (country) => setState(() {
            _selectedCountry = country;
            _syncPhoneController();
          }),
          numberController: _nationalNumberController,
          enabled: !_sendingCode,
          errorText: _phoneError,
          // _phoneError can be a server-provided message (e.g. the SMS
          // gateway's own rejection reason via _formatRegistrationError),
          // which is longer than a plain "Invalid number" label - without
          // this it truncates to one line with an ellipsis, hiding exactly
          // the detail needed to diagnose a delivery failure.
          errorMaxLines: 5,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _sendVerificationCode(),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed:
                (_sendingCode || _inviteCheckState != _InviteCheckState.valid)
                ? null
                : _sendVerificationCode,
            icon: _sendingCode
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sms_outlined),
            label: Text(_sendingCode ? 'Requesting code…' : 'Request OTP'),
          ),
        ),
        const SizedBox(height: 20),
        const Divider(),
        const SizedBox(height: 8),
        InkWell(
          onTap: widget.onChangeServerUrl,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
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
    );
  }

  /// Trailing icon for the invite-code field reflecting [_inviteCheckState]:
  /// nothing while untouched/empty, a spinner while checking, a green check
  /// once valid, or a tappable red icon (shows the specific reason in a
  /// snackbar) once known invalid.
  Widget? _buildInviteStatusIcon() {
    switch (_inviteCheckState) {
      case null:
        return null;
      case _InviteCheckState.checking:
        return const Padding(
          padding: EdgeInsets.all(12),
          child: SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      case _InviteCheckState.valid:
        return const Icon(Icons.check_circle, color: Colors.green);
      case _InviteCheckState.invalid:
        // Builder gives the onPressed callback a context from *inside* the
        // MaterialApp this State builds - `this.context` (the State's own
        // context) sits above that MaterialApp, so ScaffoldMessenger.of
        // would never find the ScaffoldMessenger the MaterialApp provides,
        // silently no-opping the tap instead of showing the reason.
        return Builder(
          builder: (context) => IconButton(
            icon: Icon(
              Icons.error,
              color: Theme.of(context).colorScheme.error,
            ),
            tooltip: _inviteCheckReason ?? 'Invalid invitation',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(_inviteCheckReason ?? 'Invalid invitation.'),
                ),
              );
            },
          ),
        );
    }
  }

  /// Recomputes the E.164 [_phoneController] value from [_selectedCountry]
  /// and whatever's currently in [_nationalNumberController] - the two
  /// fields the phone-number UI actually shows. A leading `0` is stripped
  /// since that's the common local-dialing prefix in national formats
  /// (e.g. "01712345678") that must not appear after the country code.
  void _syncPhoneController() {
    final digits = _nationalNumberController.text.replaceAll(
      RegExp(r'[^\d]'),
      '',
    );
    final national = digits.startsWith('0') ? digits.substring(1) : digits;
    _phoneController.text = '${_selectedCountry.dialCode}$national';
  }

  /// Pulls the bare code out of a pasted `.../join?invite=CODE` link - this
  /// field is labeled the same as the one on the personal-server entry
  /// screen, which *does* expect a full link, so admins share (and users
  /// paste) full links here too even though only the bare code is normally
  /// expected. Returns [raw] unchanged if it doesn't look like a link.
  String _extractInviteCode(String raw) {
    if (!raw.contains('invite=')) return raw;
    final withScheme = raw.startsWith('http://') || raw.startsWith('https://')
        ? raw
        : 'https://$raw';
    final code = Uri.tryParse(withScheme)?.queryParameters['invite'];
    return (code != null && code.isNotEmpty) ? code : raw;
  }

  /// Auto-validates the invite code against the server on focus loss (see
  /// the `_inviteFocusNode` listener in `initState`) - validates the
  /// invitation before sending the OTP, to avoid unnecessary verification
  /// attempts against an invite that was never going to work.
  Future<void> _validateInviteCode() async {
    final code = _extractInviteCode(_inviteController.text.trim());
    if (code != _inviteController.text) {
      _inviteController.value = TextEditingValue(
        text: code,
        selection: TextSelection.collapsed(offset: code.length),
      );
    }
    if (code.isEmpty) {
      if (mounted) {
        setState(() {
          _inviteCheckState = null;
          _inviteCheckReason = null;
        });
      }
      return;
    }
    setState(() {
      _inviteCheckState = _InviteCheckState.checking;
      _inviteCheckReason = null;
    });
    try {
      final result = await widget.root.lookupInvite(code);
      if (!mounted) return;
      if (result['valid'] == true) {
        setState(() {
          _inviteCheckState = _InviteCheckState.valid;
          _inviteCheckReason = null;
        });
      } else {
        setState(() {
          _inviteCheckState = _InviteCheckState.invalid;
          _inviteCheckReason = _inviteReasonText(result['reason'] as String?);
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _inviteCheckState = _InviteCheckState.invalid;
        _inviteCheckReason = e is RemoteRestException
            ? RemoteUserErrorCopy.registrationFailure(
                e,
                widget.root.devConfig.restBaseUri,
              )
            : 'Server is unavailable. Check your connection and try again.';
      });
    }
  }

  String _inviteReasonText(String? reason) {
    switch (reason) {
      case 'not_found':
        return 'Invitation not found.';
      case 'already_used':
        return 'Invitation already used.';
      case 'cancelled':
        return 'Invitation was cancelled.';
      case 'expired':
        return 'Invitation expired.';
      default:
        return 'This invitation is not valid.';
    }
  }

  Widget _buildOtpStep() {
    final phoneNumber = _phoneController.text;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _otpIsPlaceholder
              ? 'We sent a code to $phoneNumber. Since real SMS delivery '
                    'isn\'t available yet, check your notifications for it.'
              : 'We texted a verification code to $phoneNumber. It may '
                    'take a moment to arrive.',
          textAlign: TextAlign.center,
        ),
        if (_otpIsPlaceholder) ...[
          const SizedBox(height: 12),
          const OtpPlaceholderNotice(),
        ],
        const SizedBox(height: 16),
        TextField(
          controller: _otpController,
          enabled: !_registering,
          decoration: InputDecoration(
            labelText: 'Verification code',
            border: const OutlineInputBorder(),
            errorText: _otpError,
          ),
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _continueToDisplayNameStep(),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _continueToDisplayNameStep,
            icon: const Icon(Icons.arrow_forward),
            label: const Text('Verify'),
          ),
        ),
      ],
    );
  }

  /// Format-checks the OTP field and moves to the display-name step. The
  /// code is only actually verified server-side once registration
  /// completes (see `_completeRegistration`) - that's the same call that
  /// consumes it, and there's no separate verify-only endpoint. A wrong or
  /// expired code surfaces as an error there and sends the user back to
  /// this step to fix it.
  void _continueToDisplayNameStep() {
    final otpCode = _otpController.text.trim();
    if (otpCode.isEmpty) {
      setState(() => _otpError = 'Verification code cannot be empty.');
      return;
    }
    _unfocusForStepChange();
    setState(() {
      _otpError = null;
      _createAccountStep = _CreateAccountStep.enterDisplayName;
    });
  }

  /// Closes the keyboard before swapping `_createAccountStep`'s TextField
  /// out from under it. Without this, Android's on-screen keyboard can get
  /// stuck showing the outgoing field's layout (e.g. the OTP step's numeric
  /// pad) instead of picking up the next field's - typing still lands in
  /// the right place, but the wrong keys are on screen until the keyboard
  /// is dismissed and reopened some other way.
  void _unfocusForStepChange() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  Widget _buildDisplayNameStep() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'What should people see as your name?',
          style: Theme.of(context).textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _displayNameController,
          enabled: !_registering,
          decoration: InputDecoration(
            labelText: 'Display name (optional)',
            hintText: 'e.g. Hasan',
            border: const OutlineInputBorder(),
            helperText: RemoteAccountValidation.displayNameRules,
            errorText: _displayNameError ?? _registrationError,
          ),
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _completeRegistration(skip: false),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _registering
                ? null
                : () => _completeRegistration(skip: false),
            icon: _registering
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.person_add_outlined),
            label: Text(_registering ? 'Creating account…' : 'Save'),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _registering ? null : _confirmSkipDisplayName,
          child: const Text('Skip'),
        ),
      ],
    );
  }

  Future<void> _confirmSkipDisplayName() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Skip display name?'),
        content: const Text(
          'No display name was provided. Your phone number will be used '
          'as your display name until you change it in Settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Skip'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _completeRegistration(skip: true);
    }
  }

  Future<void> _sendVerificationCode() async {
    if (_sendingCode) return;
    if (_inviteCheckState != _InviteCheckState.valid) {
      // Reachable via the phone field's keyboard "done" action even though
      // the Request OTP button is disabled for the same reason - re-check
      // rather than silently doing nothing.
      _validateInviteCode();
      return;
    }
    final phoneNumber = _phoneController.text;
    final phoneError = RemoteAccountValidation.phoneNumberError(phoneNumber);
    if (phoneError != null) {
      setState(() {
        _phoneError = phoneError;
        _errorMessage = phoneError;
      });
      return;
    }

    setState(() {
      _sendingCode = true;
      _phoneError = null;
      _errorMessage = null;
    });

    try {
      final isPlaceholder = await widget.root.requestOtp(phoneNumber);
      if (mounted) {
        _unfocusForStepChange();
        setState(() {
          _otpIsPlaceholder = isPlaceholder;
          _createAccountStep = _CreateAccountStep.enterOtp;
        });
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

  /// Completes registration with whatever's in `_displayNameController`, or
  /// (when [skip] is true) the phone number itself.
  Future<void> _completeRegistration({required bool skip}) async {
    if (_registering) return;
    final otpCode = _otpController.text.trim();
    final phoneNumber = _phoneController.text;
    final displayName = skip
        ? phoneNumber
        : RemoteAccountValidation.normalizeDisplayName(
            _displayNameController.text,
          );
    if (!skip) {
      final displayNameError = RemoteAccountValidation.displayNameError(
        displayName,
      );
      if (displayNameError != null) {
        setState(() => _displayNameError = displayNameError);
        return;
      }
    }

    setState(() {
      _registering = true;
      _displayNameError = null;
      _registrationError = null;
      _errorMessage = null;
    });

    try {
      await widget.root.registerAndLogin(
        phoneNumber: phoneNumber,
        displayName: displayName,
        otpCode: otpCode,
        inviteCode: _inviteController.text.trim(),
      );
    } catch (e, st) {
      AppLogger.instance.warn('auth', 'Registration failed: $e', st);
      if (mounted) {
        _unfocusForStepChange();
        setState(() {
          _registrationError = _formatRegistrationError(e);
          _errorMessage = _registrationError;
          // A stale/wrong/expired OTP code is the most likely cause of a
          // failure this late - send the user back to fix it instead of
          // leaving them stuck re-submitting the same bad code from the
          // display-name step.
          _createAccountStep = _CreateAccountStep.enterOtp;
          _otpError = _registrationError;
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

