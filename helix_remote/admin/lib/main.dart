import 'package:helix_remote_ui/helix_remote_ui.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'admin_client.dart';
import 'screens/dashboard_tab.dart';
import 'screens/invites_tab.dart';
import 'screens/users_tab.dart';
import 'screens/lock_screen.dart';
import 'screens/login_screen.dart';
import 'screens/ops_tab.dart';
import 'services/admin_preferences.dart';
import 'theme/app_theme.dart';

import 'widgets/launch_skeleton_widget.dart';

void main() {
  runApp(const HelixAdminApp());
}

class HelixAdminApp extends StatefulWidget {
  const HelixAdminApp({super.key});

  @override
  State<HelixAdminApp> createState() => _HelixAdminAppState();
}

class _HelixAdminAppState extends State<HelixAdminApp> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Helix Admin',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      // Light only, unconditionally. Dark mode is deferred for this product,
      // and the previous `darkTheme: AppTheme.dark` was `AppTheme.dark = light`
      // - so selecting dark mode rendered the light theme while pretending
      // otherwise. With no `darkTheme` and a pinned `ThemeMode.light` there is
      // no longer a way to ask for a theme that does not exist.
      themeMode: ThemeMode.light,
      builder: (context, child) => Semantics(
        container: true,
        label: 'Helix Admin',
        child: FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: child!,
        ),
      ),
      home: const MainAdminPage(),
    );
  }
}

/// The four tabs that need a live server connection. Matches the nav, the
/// bottom bar, and the desktop pill row.
const _serverDependentTabs = {'dashboard', 'invites', 'users', 'ops'};
/// Intentionally empty: the login form must never pre-fill a specific
/// self-hoster's domain, or an operator can believe they are pointed at the
/// server they are actually administering. The saved URL from a previous
/// session is what pre-fills this field (see `_loadPreferences`).
const _defaultServerUrl = '';

class MainAdminPage extends StatefulWidget {
  const MainAdminPage({super.key});

  @override
  State<MainAdminPage> createState() => _MainAdminPageState();
}

class _MainAdminPageState extends State<MainAdminPage> {
  AdminClient? _client;
  String _selectedTab = 'dashboard';
  bool _isLoading = false;
  bool _isConnecting = false;
  bool _isCheckingSavedSession = true;
  LaunchStatus _launchStatus = LaunchStatus.deploying;
  AdminPreferences? _prefs;
  bool _appLockEnabled = false;
  bool _isUnlocked = false;
  bool _needsSetup = false;
  Timer? _urlDebounce;

  final _urlController = TextEditingController(text: _defaultServerUrl);
  final _passwordController = TextEditingController();
  final _federationDomainController = TextEditingController();
  final _federationAddressController = TextEditingController();
  final _federationDirectoryController = TextEditingController();

  Map<String, dynamic>? _metrics;
  Map<String, dynamic>? _config;
  ServerLogs _logs = const ServerLogs.empty();
  String? _errorMessage;

  /// Round-trip time of the most recent metrics call, in milliseconds.
  /// Null until one has actually been measured - the dashboard renders
  /// "Latency: —" rather than inventing a plausible number.
  int? _latencyMs;

  /// Polls the Logs screen while it's live.
  Timer? _logPollTimer;
  StreamSubscription<String>? _logStreamSub;

  /// The live socket, kept so it can be closed. Cancelling [_logStreamSub]
  /// alone leaves the underlying connection open.
  LogStreamHandle? _logStreamHandle;

  bool _logAutoRefresh = false;

  /// How many of the lines already in the buffer the server is about to
  /// replay when a log stream opens. See [_setLogAutoRefresh].
  int _logReplayCursor = 0;

  @override
  void initState() {
    super.initState();
    _urlController.addListener(_onUrlChanged);
    _loadPreferences();
  }

  void _onUrlChanged() {
    _urlDebounce?.cancel();
    _urlDebounce = Timer(const Duration(milliseconds: 500), () {
      if (mounted && _client == null) {
        _checkSetupStatus();
      }
    });
  }

  Future<void> _checkSetupStatus([String? rawUrl]) async {
    final targetUrl = _normalizeServerUrl(rawUrl ?? _urlController.text);
    if (targetUrl.isEmpty) return;
    try {
      final status = await AdminClient.checkSetupStatus(targetUrl);
      if (!mounted) return;
      setState(() {
        _needsSetup = status.needsSetup;
        _errorMessage = null;
      });
    } catch (e) {
      // Surfaced, not swallowed. This call is what decides whether a fresh
      // server offers the first-time password form, so a failure here means an
      // operator is silently looking at the normal sign-in form for a server
      // that has no admin password yet.
      if (!mounted) return;
      setState(() {
        _needsSetup = false;
        _errorMessage =
            'Could not reach $targetUrl to check whether this server needs '
            'first-time setup.';
      });
    }
  }

  Future<void> _loadPreferences() async {
    final prefs = await AdminPreferences.load();
    if (!mounted) return;
    final appLockEnabled = prefs.appLockEnabled;
    final savedUrl = prefs.serverUrl;
    setState(() {
      _prefs = prefs;
      _appLockEnabled = appLockEnabled;
      _isUnlocked = !appLockEnabled;
      if (savedUrl != null && savedUrl.isNotEmpty) {
        _urlController.text = savedUrl;
      }
    });
    if (!appLockEnabled) {
      _attemptAutoConnect();
    } else {
      _checkSetupStatus();
      setState(() => _isCheckingSavedSession = false);
    }
  }

  /// Reconnects with the saved token from a previous successful connect.
  Future<void> _attemptAutoConnect() async {
    final prefs = _prefs;
    if (prefs == null) {
      if (mounted) setState(() => _isCheckingSavedSession = false);
      return;
    }
    final url = prefs.serverUrl;
    final token = await prefs.loadAdminToken();
    if (url == null || url.isEmpty || token == null || token.isEmpty) {
      if (mounted) setState(() => _isCheckingSavedSession = false);
      return;
    }

    _passwordController.text = token;
    setState(() {
      _isConnecting = true;
      _isCheckingSavedSession = true;
      _launchStatus = LaunchStatus.deploying;
    });

    // Step 1: Deploying Helix Admin…
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    setState(() => _launchStatus = LaunchStatus.retrievingData);

    // Step 2: Retrieving user data…
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    setState(() => _launchStatus = LaunchStatus.connecting);

    // Step 3: Connecting to the server…
    final client = AdminClient(baseUrl: url, token: token);
    
    AdminLoginStatus status;
    try {
      status = await client.verifyLoginDetailed().timeout(
        const Duration(seconds: 4),
        onTimeout: () => AdminLoginStatus.unreachable,
      );
    } catch (_) {
      status = AdminLoginStatus.unreachable;
    }

    if (!mounted) return;

    switch (status) {
      case AdminLoginStatus.ok:
        // Step 4: Validating user account…
        setState(() => _launchStatus = LaunchStatus.validating);
        await Future.delayed(const Duration(milliseconds: 300));
        if (!mounted) return;

        // Step 5: Syncing…
        setState(() => _launchStatus = LaunchStatus.syncing);
        await Future.delayed(const Duration(milliseconds: 300));
        if (!mounted) return;

        setState(() {
          _client = client;
          _isConnecting = false;
          _isCheckingSavedSession = false;
          _errorMessage = null;
        });
        _refreshData();

      case AdminLoginStatus.unauthorized:
        await prefs.clearAdminToken();
        if (!mounted) return;
        _passwordController.clear();
        setState(() {
          _isConnecting = false;
          _isCheckingSavedSession = false;
          _errorMessage =
              'Session expired or admin password changed. Please sign in again.';
        });

      case AdminLoginStatus.unreachable:
        setState(() {
          _isConnecting = false;
          _launchStatus = LaunchStatus.unreachable;
          _errorMessage =
              "Could not reach server. Check the URL and connection, then try again.";
        });
    }
  }

  void _handleUnlocked() {
    setState(() => _isUnlocked = true);
    _attemptAutoConnect();
  }

  Future<void> _setAppLockEnabled(bool value) async {
    if (value) {
      final supported = await LocalAuthentication().isDeviceSupported();
      if (!supported) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No biometric or device PIN/pattern/password is set up. Set '
              'one up in your device settings first, then try again.',
            ),
          ),
        );
        return;
      }
    }
    await _prefs?.setAppLockEnabled(value);
    if (!mounted) return;
    setState(() => _appLockEnabled = value);
  }

  @override
  void dispose() {
    _urlDebounce?.cancel();
    _urlController.removeListener(_onUrlChanged);
    _closeLogStream();
    _logPollTimer?.cancel();
    _latencyPollTimer?.cancel();
    _urlController.dispose();
    _passwordController.dispose();
    _federationDomainController.dispose();
    _federationAddressController.dispose();
    _federationDirectoryController.dispose();
    super.dispose();
  }

  static const _logPollInterval = Duration(seconds: 3);

  /// Number of tail lines the server replays when a log stream opens. Mirrors
  /// `logSink?.tail(50)` in the backend's `/logs/stream` handler.
  static const _logReplayBurst = 50;

  void _closeLogStream() {
    _logStreamSub?.cancel();
    _logStreamSub = null;
    final handle = _logStreamHandle;
    _logStreamHandle = null;
    if (handle != null) {
      // Fire-and-forget: the socket teardown must not block the UI, and the
      // handle swallows its own teardown errors.
      handle.close();
    }
  }

  void _startLogPollFallback() {
    if (_logPollTimer == null && _logAutoRefresh) {
      _logPollTimer = Timer.periodic(
        _logPollInterval,
        (_) => _refreshLogs(),
      );
    }
  }

  void _setLogAutoRefresh(bool enabled) {
    setState(() => _logAutoRefresh = enabled);
    _logPollTimer?.cancel();
    _logPollTimer = null;
    _closeLogStream();
    if (!enabled) return;

    final client = _client;
    if (client == null) {
      _startLogPollFallback();
      _refreshLogs();
      return;
    }

    try {
      final handle = client.streamLogs();
      _logStreamHandle = handle;
      // The server replays the last [_logReplayBurst] lines the moment the
      // socket opens, and those are already in the buffer below - so start
      // the cursor at the tail and skip the lines that match, instead of
      // appending a duplicate copy of everything just fetched.
      _logReplayCursor =
          (_logs.lines.length - _logReplayBurst).clamp(0, _logs.lines.length);
      _logStreamSub = handle.lines.listen(
        (line) {
          if (!mounted) return;
          setState(() {
            if (_logReplayCursor < _logs.lines.length) {
              if (_logs.lines[_logReplayCursor] == line) {
                _logReplayCursor++;
                return;
              }
              // Diverged: the buffer is no longer a prefix of the replay, so
              // stop trying to align and just append from here.
              _logReplayCursor = _logs.lines.length;
            }
            _logs = ServerLogs(
              lines: [..._logs.lines, line],
              source: _logs.source,
              message: _logs.message,
              filePath: _logs.filePath,
            );
          });
        },
        onError: (_) => _startLogPollFallback(),
        // A clean server-side close ends the stream without an error. Without
        // this the console would keep claiming "LIVE STREAMING..." over frozen
        // data, so fall back to polling just as an error does.
        onDone: _startLogPollFallback,
      );
    } catch (_) {
      _startLogPollFallback();
    }
    _refreshLogs();
  }

  Future<void> _refreshLogs() async {
    final client = _client;
    if (client == null) return;
    try {
      final logs = await client.getLogs();
      if (!mounted) return;
      setState(() => _logs = logs);
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Failed to load logs: $e');
    }
  }

  Future<void> _connect() async {
    setState(() {
      _isConnecting = true;
      _errorMessage = null;
    });

    final url = _normalizeServerUrl(_urlController.text);
    _urlController.text = url;
    final secret = _passwordController.text.trim();
    final client = AdminClient(
      baseUrl: url,
      token: secret,
    );

    final status = await client.verifyLoginDetailed();
    if (!mounted) return;
    if (status == AdminLoginStatus.ok) {
      await _prefs?.setServerUrl(url);
      await _prefs?.saveAdminToken(secret);
      setState(() {
        _client = client;
        _isConnecting = false;
        _needsSetup = false;
        _selectedTab = 'dashboard';
        _errorMessage = null;
      });
      _refreshData();
    } else {
      await _checkSetupStatus(url);
      setState(() {
        _isConnecting = false;
        _errorMessage = status == AdminLoginStatus.unauthorized
            ? 'Invalid server URL or admin password.'
            : "Could not reach server. Check the URL and connection, then try again.";
      });
    }
  }

  Future<void> _handleSetupPassword(String password) async {
    setState(() {
      _isConnecting = true;
      _errorMessage = null;
    });
    final url = _normalizeServerUrl(_urlController.text);
    _urlController.text = url;
    try {
      await AdminClient.setupAdminPassword(url, password);
      if (!mounted) return;
      _passwordController.text = password;
      final client = AdminClient(baseUrl: url, token: password);
      await _prefs?.setServerUrl(url);
      await _prefs?.saveAdminToken(password);
      setState(() {
        _client = client;
        _isConnecting = false;
        _needsSetup = false;
        _selectedTab = 'dashboard';
        _errorMessage = null;
      });
      _refreshData();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isConnecting = false;
        _errorMessage = e is AdminRequestException
            ? e.message
            : 'Failed to configure admin password: $e';
      });
    }
  }

  void _disconnect() {
    unawaited(_prefs?.clearAdminToken());
    _logPollTimer?.cancel();
    _logStreamSub?.cancel();
    _latencyPollTimer?.cancel();
    _logStreamSub = null;
    _logAutoRefresh = false;
    _passwordController.clear();
    setState(() {
      _client = null;
      _metrics = null;
      _config = null;
      _logs = const ServerLogs.empty();
      _errorMessage = null;
    });
    _checkSetupStatus();
  }

  String _normalizeServerUrl(String raw) {
    var url = raw.trim();
    if (url.isEmpty) return url;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  Timer? _latencyPollTimer;

  Future<void> _refreshData() async {
    if (_client == null) return;
    setState(() => _isLoading = true);
    try {
      final sw = Stopwatch()..start();
      final metrics = await _client!.getMetrics();
      final config = await _client!.getConfig();
      final logs = await _client!.getLogs();
      sw.stop();
      final elapsed = sw.elapsedMilliseconds;
      setState(() {
        _latencyMs = elapsed > 0 ? elapsed : null;
        _metrics = metrics;
        _config = config;
        final federation = config['federation'] as Map<String, dynamic>?;
        _federationDomainController.text =
            federation?['domain'] as String? ?? '';
        _federationAddressController.text =
            federation?['public_base_url'] as String? ?? '';
        _federationDirectoryController.text =
            federation?['directory_url'] as String? ?? '';
        _logs = logs;
        _isLoading = false;
      });
      _startLatencyPollTimer();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  void _startLatencyPollTimer() {
    _latencyPollTimer?.cancel();
    _latencyPollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (_client != null && mounted) {
        _pingLatency();
      }
    });
  }

  Future<void> _pingLatency() async {
    final client = _client;
    if (client == null) return;
    try {
      final sw = Stopwatch()..start();
      await client.getMetrics();
      sw.stop();
      if (!mounted) return;
      setState(() {
        final elapsed = sw.elapsedMilliseconds;
        _latencyMs = elapsed > 0 ? elapsed : null;
      });
    } catch (_) {
      // A failed probe leaves the last good measurement in place rather than
      // overwriting it with a guess.
    }
  }

  Future<void> _triggerBackup() async {
    if (_client == null) return;
    setState(() => _isLoading = true);
    try {
      final res = await _client!.triggerBackup();
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Backup successful! File saved to: ${res['backup_file']}',
          ),
          backgroundColor: Colors.green,
        ),
      );
      _refreshData();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Backup failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<String> _saveServerName(String name) async {
    final client = _client;
    if (client == null) {
      throw const AdminRequestException('Not connected to a server.');
    }
    final stored = await client.setServerName(name);
    if (mounted) {
      setState(() {
        final config = _config;
        if (config != null) config['server_name'] = stored;
      });
    }
    return stored;
  }

  Future<void> _setWorldwideMode(bool enabled) async {
    if (_client == null) return;
    setState(() => _isLoading = true);
    try {
      await _client!.setWorldwideMode(
        enabled: enabled,
        domain: _federationDomainController.text.trim(),
        address: _federationAddressController.text.trim(),
        directoryUrl: _federationDirectoryController.text.trim(),
      );
      await _refreshData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enabled ? 'Worldwide Mode enabled.' : 'Worldwide Mode disabled.',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  static const double _mobileBreakpoint = 700;
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    if (_prefs == null || _isCheckingSavedSession) {
      return LaunchSkeletonWidget(
        status: _launchStatus,
        serverUrl: _urlController.text,
        onConnectDifferentServer: () {
          setState(() {
            _isCheckingSavedSession = false;
            _isConnecting = false;
          });
        },
        onRetry: () => _attemptAutoConnect(),
      );
    }
    if (_appLockEnabled && !_isUnlocked) {
      return LockScreen(onUnlocked: _handleUnlocked);
    }
    if (_client == null) {
      // No self-hosting guide here. The guide belongs to the helix-remote
      // welcome / sign-in flow (`HostGuideStep` in
      // app/lib/screens/setup/steps/host_guide_step.dart), which is the only
      // place an operator meets it. The copy in this console was a leftover
      // from the pre-redesign design.
      return LoginScreen(
        urlController: _urlController,
        passwordController: _passwordController,
        isConnecting: _isConnecting,
        errorMessage: _errorMessage,
        needsSetup: _needsSetup,
        onSignIn: _connect,
        onSetupPassword: _handleSetupPassword,
        onCheckUrl: () => _checkSetupStatus(),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < _mobileBreakpoint;
        return Scaffold(
          key: _scaffoldKey,
          appBar: _buildAppBar(isMobile),
          drawer: null,
          bottomNavigationBar: isMobile
              ? NavigationBar(
                  selectedIndex: switch (_selectedTab) {
                    'dashboard' => 0,
                    'users' => 1,
                    'invites' => 2,
                    'ops' || 'logs' || 'reports' || 'config' || 'backup' => 3,
                    _ => 0,
                  },
                  onDestinationSelected: (idx) {
                    final targetTab = switch (idx) {
                      0 => 'dashboard',
                      1 => 'users',
                      2 => 'invites',
                      3 => 'ops',
                      _ => 'dashboard',
                    };
                    setState(() => _selectedTab = targetTab);
                    if (_serverDependentTabs.contains(targetTab)) {
                      _refreshData();
                    }
                  },
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.dashboard_outlined),
                      selectedIcon: Icon(Icons.dashboard),
                      label: 'Overview',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.people_outline),
                      selectedIcon: Icon(Icons.people),
                      label: 'Users',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.local_activity_outlined),
                      selectedIcon: Icon(Icons.local_activity),
                      label: 'Invites',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.settings_outlined),
                      selectedIcon: Icon(Icons.settings),
                      label: 'Ops & Logs',
                    ),
                  ],
                )
              : null,
          body: _buildBody(isMobile: isMobile),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar(bool isMobile) {
    return AppBar(
      automaticallyImplyLeading: false,
      title: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Color(0xFF10B981),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _config?['server_name'] as String? ?? 'Helix Server',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          if (!isMobile) ...[
            const SizedBox(width: 32),
            _buildDesktopNavPill('Overview', 'dashboard', Icons.dashboard_outlined),
            const SizedBox(width: 8),
            _buildDesktopNavPill('Users & Devices', 'users', Icons.people_outline),
            const SizedBox(width: 8),
            _buildDesktopNavPill('Invites', 'invites', Icons.local_activity_outlined),
            const SizedBox(width: 8),
            _buildDesktopNavPill('Ops & Logs', 'ops', Icons.settings_outlined),
          ],
        ],
      ),
      actions: [
        // Sign Out lives here now. It used to live on a Settings tab that the
        // redesigned nav no longer reaches, which left no way to disconnect
        // except deep inside Ops > Config. The connected host is the header
        // title to its left, so the two facts sit together.
        Tooltip(
          message: 'Sign out of $_connectedHostLabel',
          child: IconButton(
            key: const Key('header_sign_out_button'),
            onPressed: _disconnect,
            icon: const Icon(Icons.logout, size: 20),
            color: const Color(0xFF64748B),
          ),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  /// The host this console is pointed at, for the sign-out tooltip.
  String get _connectedHostLabel {
    final host = Uri.tryParse(_urlController.text)?.host;
    return (host == null || host.isEmpty) ? 'this server' : host;
  }

  Widget _buildDesktopNavPill(String label, String tabId, IconData icon) {
    final isSelected = switch (_selectedTab) {
      'dashboard' => tabId == 'dashboard',
      'users' => tabId == 'users',
      'invites' => tabId == 'invites',
      _ => _selectedTab == tabId,
    };

    return InkWell(
      onTap: () {
        setState(() {
          _selectedTab = tabId;
        });
        if (_client != null && _serverDependentTabs.contains(tabId)) {
          _refreshData();
        }
      },
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? HelixColorTokens.cFF8A2BE2.withValues(alpha: 0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: isSelected
              ? Border.all(color: HelixColorTokens.cFF8A2BE2.withValues(alpha: 0.6))
              : Border.all(color: Colors.transparent),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? context.accentColor : context.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? context.textPrimary : context.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody({required bool isMobile}) {
    final showFullPageSpinner =
        _isLoading &&
        _metrics == null &&
        _serverDependentTabs.contains(_selectedTab);
    if (showFullPageSpinner) {
      return const Center(child: HelixSkeleton(width: 192, height: 24));
    }
    return RefreshIndicator(
      onRefresh: () async {
        if (_client != null && _serverDependentTabs.contains(_selectedTab)) {
          await _refreshData();
        }
      },
      child: Padding(
        padding: HelixInsets.all(isMobile ? 16.0 : 24.0),
        child: _getTabWidget(),
      ),
    );
  }

  /// Builds the body for [_selectedTab].
  ///
  /// Only the four redesigned nav destinations are reachable. There used to be
  /// six more cases here (`config`, `logs`, `reports`, `backup`, `guide`,
  /// `settings`) that no navigation could ever select - the first three are
  /// Ops sub-tabs, and the last three were screens removed from the product.
  /// They are gone rather than left as dead branches, because a case nobody
  /// can reach is indistinguishable from a feature that is merely broken.
  Widget _getTabWidget() {
    switch (_selectedTab) {
      case 'dashboard':
        return DashboardTab(metrics: _metrics, latencyMs: _latencyMs);
      case 'ops':
        return OpsTab(
          client: _client!,
          logs: _logs,
          onRefreshLogs: _refreshLogs,
          autoRefreshLogs: _logAutoRefresh,
          onAutoRefreshLogsChanged: _setLogAutoRefresh,
          config: _config,
          onSetWorldwideMode: _setWorldwideMode,
          onSaveServerName: _saveServerName,
          serverHost: Uri.tryParse(_urlController.text)?.host,
          isLoading: _isLoading,
          onTriggerBackup: _triggerBackup,
          onSignOut: _disconnect,
          appLockEnabled: _appLockEnabled,
          onAppLockChanged: (value) => _setAppLockEnabled(value),
          initialSubTab: 'reports',
        );
      case 'invites':
        return InvitesTab(client: _client!);
      case 'users':
        return UsersTab(client: _client!);
      default:
        return const Center(child: Text('Tab not found'));
    }
  }
}
