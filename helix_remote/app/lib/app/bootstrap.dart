part of '../main.dart';

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

  @override
  Widget build(BuildContext context) {
    if (_bootState == _BootState.running && _root != null) {
      return HelixRemoteApp(
        root: _root!,
        embedded: true,
        onChangeServerUrl: _onChangeServerUrl,
        initialInviteCode: _pendingInviteCode,
        initialPhoneNumber: _pendingPhoneNumber,
      );
    }
    return _buildBootHome();
  }

  Widget _buildBootHome() {
    switch (_bootState) {
      case _BootState.loading:
        return const Scaffold(
          body: Center(child: HelixSkeleton(width: 192, height: 24)),
        );
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
        return const Scaffold(
          body: Center(child: HelixSkeleton(width: 192, height: 24)),
        );
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
