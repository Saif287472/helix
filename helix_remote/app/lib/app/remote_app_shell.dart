part of '../main.dart';

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

class _HelixRemoteAppState extends State<HelixRemoteApp>
    with WidgetsBindingObserver {
  late RemoteStartupState _startupState;
  String? _errorMessage;
  bool _initializing = false;
  RemoteCallStatus? _activeCallStatus;
  StreamSubscription<RemoteStartupState>? _stateSub;
  StreamSubscription<RemoteCallStatus?>? _callSub;
  // _activeCallStatus is updated without setState to avoid recreating HomeScreen
  // on every call state change (which caused a double call-screen push bug).
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  String? _lastConnectivitySignature;

  @override
  void initState() {
    super.initState();
    _startupState = widget.root.startupState;
    _errorMessage = widget.root.lastError;
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
      final inCall =
          status != null &&
          !(status.state == RemoteCallState.ringing &&
              status.direction == kCallDirectionIncoming);
      unawaited(
        AndroidCallRuntimeService.setCallActive(
          active: inCall,
          keepScreenOn: inCall && status.isVideo,
        ),
      );
    });
    _connectivitySub = Connectivity().onConnectivityChanged.listen(
      _onConnectivityChanged,
    );
    _startBoot();
  }

  @override
  void didUpdateWidget(HelixRemoteApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.root != widget.root) {
      _stateSub?.cancel();
      _startupState = widget.root.startupState;
      _errorMessage = widget.root.lastError;
      _stateSub = widget.root.startupStateChanges.listen((state) {
        if (!mounted) return;
        setState(() {
          _startupState = state;
          _errorMessage = widget.root.lastError;
        });
      });
      _startBoot();
    }
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
    if (widget.root.startupState == RemoteStartupState.ready ||
        widget.root.startupState == RemoteStartupState.authenticatedAndSyncing) {
      if (mounted && _startupState != widget.root.startupState) {
        setState(() => _startupState = widget.root.startupState);
      }
      return;
    }
    _initializing = true;
    try {
      await widget.root.initialize();
      if (!mounted) return;
      final restored = await widget.root.tryRestoreSession();
      if (!mounted) return;
      if (restored) {
        await widget.root.startRuntime();
      }
      if (mounted) {
        setState(() => _startupState = widget.root.startupState);
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

  void _clearErrorMessage() {
    setState(() => _errorMessage = null);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stateSub?.cancel();
    _callSub?.cancel();
    _connectivitySub?.cancel();
    widget.root.dispose().ignore();
    AndroidCallRuntimeService.setCallActive(
      active: false,
      keepScreenOn: false,
    ).ignore();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _buildBaseScreen();

  Widget _buildBaseScreen() {
    switch (_startupState) {
      case RemoteStartupState.idle:
      case RemoteStartupState.loadingConfiguration:
      case RemoteStartupState.openingSecureStorage:
      case RemoteStartupState.firstRunInitialization:
      case RemoteStartupState.openingDatabase:
      case RemoteStartupState.restoringSession:
        return const Scaffold(
          body: Center(
            child: SplashStep(statusText: 'Deploying Helix…'),
          ),
        );

      case RemoteStartupState.unauthenticated:
        return SetupScreen(
          root: widget.root,
          onChangeServerUrl: widget.onChangeServerUrl != null
              ? (url) async {
                  await widget.onChangeServerUrl!();
                }
              : null,
          initialInviteCode: widget.initialInviteCode,
          initialPhoneNumber: widget.initialPhoneNumber,
        );

      case RemoteStartupState.authenticatedAndSyncing:
      case RemoteStartupState.ready:
        return _buildReadyScreen();

      case RemoteStartupState.recoverableFailure:
        return _buildErrorScreen();

      case RemoteStartupState.resetRequired:
        return _buildResetScreen();
    }
  }
}
