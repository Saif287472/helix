part of '../main.dart';

enum _BootState { loading, signIn, running }

class HelixRemoteBootstrap extends StatefulWidget {
  const HelixRemoteBootstrap({super.key, this.initialLink});

  final HelixDeepLink? initialLink;

  @override
  State<HelixRemoteBootstrap> createState() => _HelixRemoteBootstrapState();
}

class _HelixRemoteBootstrapState extends State<HelixRemoteBootstrap> {
  _BootState _bootState = _BootState.loading;
  RemoteCompositionRoot? _root;
  String? _signInError;
  String _dbDir = '';
  String _cacheDir = '';
  bool _recoveryMode = false;

  /// An invite or recovery code from a link, waiting for the sign-in page.
  String? _pendingCode;
  StreamSubscription<HelixDeepLink>? _linkSub;

  @override
  void initState() {
    super.initState();
    _pendingCode = widget.initialLink?.setupCode;
    _linkSub = HelixLinkChannel.instance.links.listen(_onLink);
    _boot();
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    super.dispose();
  }

  /// A link tapped while the app is open. Invite and recovery codes go to the
  /// sign-in page; a signed-in app has no use for one.
  void _onLink(HelixDeepLink link) {
    final code = link.setupCode;
    if (code == null || !mounted) return;
    final root = _root;
    final signedIn =
        root != null &&
        (root.startupState == RemoteStartupState.ready ||
            root.startupState == RemoteStartupState.authenticatedAndSyncing);
    if (signedIn) {
      final context = HelixRemoteAppShell.navigatorKey.currentContext;
      if (context != null) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text(
              'You are already signed in. Sign out first to use this code.',
            ),
          ),
        );
      }
      return;
    }
    setState(() => _pendingCode = code);
  }

  Future<void> _boot() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      _dbDir = p.join(appDir.path, 'helix_remote_db');
      _cacheDir = p.join(appDir.path, 'attachments_cache');

      // A server this device signed in to before: open it, and with it the
      // account (HelixRemoteApp restores the session from the device).
      final savedUrl = await ServerUrlStore.instance.load();
      if (savedUrl != null && savedUrl.isNotEmpty) {
        _applyRoot(_rootFor(savedUrl));
        return;
      }

      // Compile-time --dart-define values (CI / dev scripts).
      try {
        final dartConfig = RemoteDevelopmentConfig.fromDartDefine(
          databaseDirectory: _dbDir,
          attachmentCacheDir: _cacheDir,
        );
        _applyRoot(
          RemoteCompositionRoot.production(
            databaseDirectory: _dbDir,
            devConfig: dartConfig,
          ),
        );
        return;
      } catch (_) {
        // No dart-define config: a fresh install signs in.
      }
      if (mounted) setState(() => _bootState = _BootState.signIn);
    } catch (e, st) {
      AppLogger.instance.error('bootstrap', '$e', st);
      if (mounted) {
        setState(() {
          _signInError = RemoteUserErrorCopy.scrubDomain(e.toString());
          _bootState = _BootState.signIn;
        });
      }
    }
  }

  RemoteCompositionRoot _rootFor(String url) =>
      RemoteCompositionRoot.production(
        databaseDirectory: _dbDir,
        devConfig: RemoteDevelopmentConfig.fromServerUrl(
          url,
          databaseDirectory: _dbDir,
          attachmentCacheDir: _cacheDir,
        ),
      );

  void _applyRoot(RemoteCompositionRoot root) {
    if (!mounted) return;
    setState(() {
      _root = root;
      _bootState = _BootState.running;
    });
  }

  /// Finishes a sign-in the sign-in pages could not finish themselves: the
  /// app had no root for that server yet (first launch, or a different server
  /// than the saved one). Any current root is closed first - two roots must
  /// never hold the database at once.
  Future<void> _onServerChoiceMade(Object? choice) async {
    final (serverUrl, signIn) = switch (choice) {
      ServerPasswordChoice c => (
        c.serverUrl,
        (RemoteCompositionRoot root) =>
            root.signInWithPasswordKeys(lookup: c.lookup, keys: c.keys),
      ),
      ServerRecoveryChoice c => (
        c.serverUrl,
        (RemoteCompositionRoot root) => root.recoverAccount(
          accountId: c.accountId,
          recoveryCode: c.recoveryCode,
          phoneHash: c.phoneHash,
          phoneNumber: c.phoneNumber,
          otpCode: c.otpCode,
          otpChallengeId: c.otpChallengeId,
        ),
      ),
      ServerInviteChoice c => (
        c.serverUrl,
        (RemoteCompositionRoot root) => root.registerAndLogin(
          phoneNumber: c.phoneNumber!,
          phoneHashOverride: c.phoneHash,
          displayName: c.displayName!,
          otpCode: c.otpCode!,
          otpChallengeId: c.otpChallengeId,
          inviteCode: c.inviteCode,
          tosAccepted: c.tosAccepted,
          tosVersion: c.tosVersion,
        ),
      ),
      _ => (null, null),
    };
    if (serverUrl == null || signIn == null) return;

    final previous = _root;
    setState(() {
      _root = null;
      _bootState = _BootState.loading;
      _pendingCode = null;
      _recoveryMode = false;
      _signInError = null;
    });
    await previous?.dispose();

    RemoteCompositionRoot? root;
    try {
      root = _rootFor(serverUrl);
      await root.initialize();
      await signIn(root);
      await ServerUrlStore.instance.save(serverUrl);
      _applyRoot(root);
    } catch (e) {
      await root?.dispose();
      final conflict =
          e is RemoteRestException &&
          e.serverCode == RemoteApiErrorCodes.phoneAlreadyRegistered;
      if (!mounted) return;
      setState(() {
        _recoveryMode = conflict;
        _signInError = conflict
            ? null
            : switch (choice) {
                ServerPasswordChoice _ => passwordSignInErrorMessage(e),
                _ =>
                  e is RemoteRestException
                      ? RemoteUserErrorCopy.registrationFailure(
                          e,
                          Uri.parse(serverUrl),
                        )
                      : RemoteUserErrorCopy.scrubDomain(e.toString()),
              };
        _bootState = _BootState.signIn;
      });
    }
  }

  /// Signing out (or leaving a server) closes the root and starts over on
  /// the sign-in page.
  Future<void> _onChangeServerUrl() async {
    final oldRoot = _root;
    setState(() {
      _root = null;
      _bootState = _BootState.loading;
      _recoveryMode = false;
    });
    await oldRoot?.dispose();
    await ServerUrlStore.instance.clear();
    if (mounted) {
      setState(() {
        _bootState = _BootState.signIn;
        _signInError = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_bootState) {
      case _BootState.running when _root != null:
        return HelixRemoteApp(
          root: _root!,
          onChangeServerUrl: _onChangeServerUrl,
          onServerChoice: _onServerChoiceMade,
          initialCode: _pendingCode,
        );
      case _BootState.signIn:
        return SetupScreen(
          // A new key per attempt, so a failed sign-in starts from a clean
          // page with its error rather than the finished state of the last.
          key: ValueKey<String>(
            'sign-in-$_recoveryMode-${_signInError.hashCode}',
          ),
          onChoice: _onServerChoiceMade,
          initialCode: _pendingCode,
          initialRecoveryMode: _recoveryMode,
          initialError: _signInError,
        );
      case _BootState.loading:
      case _BootState.running:
        return const StartupSkeleton();
    }
  }
}
