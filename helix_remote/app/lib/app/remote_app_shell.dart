part of '../main.dart';

class HelixRemoteApp extends StatefulWidget {
  const HelixRemoteApp({
    super.key,
    required this.root,
    this.onChangeServerUrl,
    this.onServerChoice,
    this.initialCode,
  });

  final RemoteCompositionRoot root;
  final Future<void> Function()? onChangeServerUrl;

  /// Completes a sign-in on another server than this root's (see
  /// `HelixRemoteBootstrap._onServerChoiceMade`).
  final Future<void> Function(Object? choice)? onServerChoice;

  /// An invite or recovery code from a link, for the sign-in page.
  final String? initialCode;

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
        widget.root.startupState ==
            RemoteStartupState.authenticatedAndSyncing) {
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

  /// What opening is actually doing right now, for the skeleton.
  String get _startupStatus => switch (_startupState) {
    RemoteStartupState.openingSecureStorage => 'Unlocking your keys…',
    RemoteStartupState.firstRunInitialization ||
    RemoteStartupState.openingDatabase => 'Opening your chats…',
    RemoteStartupState.restoringSession => 'Signing you in…',
    _ => 'Opening Helix…',
  };

  Widget _buildBaseScreen() {
    switch (_startupState) {
      case RemoteStartupState.idle:
      case RemoteStartupState.loadingConfiguration:
      case RemoteStartupState.openingSecureStorage:
      case RemoteStartupState.firstRunInitialization:
      case RemoteStartupState.openingDatabase:
      case RemoteStartupState.restoringSession:
        return StartupSkeleton(status: _startupStatus);

      case RemoteStartupState.unauthenticated:
        return SetupScreen(
          root: widget.root,
          onChoice: widget.onServerChoice,
          initialCode: widget.initialCode,
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
