part of '../main.dart';

class HelixRemoteApp extends StatefulWidget {
  const HelixRemoteApp({
    super.key,
    required this.root,
    this.embedded = false,
    this.onChangeServerUrl,
    this.initialInviteCode,
    this.initialPhoneNumber,
  });

  final RemoteCompositionRoot root;

  /// True when the process-level [HelixRemoteAppShell] already supplies the
  /// MaterialApp. Standalone construction remains supported for widget tests.
  final bool embedded;
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

  @override
  Widget build(BuildContext context) {
    final home = _buildBaseScreen();
    return widget.embedded ? home : HelixRemoteAppShell(home: home);
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

  void _update(VoidCallback change) => setState(change);
}
