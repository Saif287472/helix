import 'package:helix_remote_ui/helix_remote_ui.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'admin_client.dart';
import 'screens/backup_tab.dart';
import 'screens/config_tab.dart';
import 'screens/dashboard_tab.dart';
import 'screens/guide/guide_wizard.dart';
import 'screens/invites_tab.dart';
import 'screens/users_tab.dart';
import 'screens/reports_tab.dart';
import 'screens/lock_screen.dart';
import 'screens/login_screen.dart';
import 'screens/logs_tab.dart';
import 'screens/ops_tab.dart';
import 'screens/settings_tab.dart';
import 'services/admin_preferences.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const HelixAdminApp());
}

class HelixAdminApp extends StatefulWidget {
  const HelixAdminApp({super.key});

  @override
  State<HelixAdminApp> createState() => _HelixAdminAppState();
}

class _HelixAdminAppState extends State<HelixAdminApp> {
  bool _isDarkMode = true;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Helix Admin',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: _isDarkMode ? ThemeMode.dark : ThemeMode.light,
      builder: (context, child) => Semantics(
        container: true,
        label: 'Helix Admin',
        child: FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: child!,
        ),
      ),
      home: MainAdminPage(
        isDarkMode: _isDarkMode,
        onDarkModeChanged: (v) => setState(() => _isDarkMode = v),
      ),
    );
  }
}

const _serverDependentTabs = {
  'dashboard',
  'config',
  'logs',
  'backup',
  'invites',
  'users',
  'reports',
  'ops',
};
const _defaultServerUrl = 'https://helix.agiletechbd.com';

class MainAdminPage extends StatefulWidget {
  const MainAdminPage({
    super.key,
    required this.isDarkMode,
    required this.onDarkModeChanged,
  });

  final bool isDarkMode;
  final ValueChanged<bool> onDarkModeChanged;

  @override
  State<MainAdminPage> createState() => _MainAdminPageState();
}

class _MainAdminPageState extends State<MainAdminPage> {
  AdminClient? _client;
  String _selectedTab = 'dashboard';
  bool _isLoading = false;
  bool _isConnecting = false;
  bool _isCheckingSavedSession = true;
  bool _showGuideUnauthenticated = false;

  /// Guide page to open next time the 'guide' tab is built. Reset to 0
  /// (Welcome) on every normal sidebar navigation.
  int _guideInitialPage = 0;
  static const _guideConnectAdminPageIndex = 6;

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

  /// Polls the Logs screen while it's live.
  Timer? _logPollTimer;
  StreamSubscription<String>? _logStreamSub;
  bool _logAutoRefresh = false;

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
      });
    } catch (_) {}
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
    });
    final client = AdminClient(baseUrl: url, token: token);
    final status = await client.verifyLoginDetailed();
    if (!mounted) return;
    switch (status) {
      case AdminLoginStatus.ok:
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
          _isCheckingSavedSession = false;
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
    _logPollTimer?.cancel();
    _logStreamSub?.cancel();
    _urlController.dispose();
    _passwordController.dispose();
    _federationDomainController.dispose();
    _federationAddressController.dispose();
    _federationDirectoryController.dispose();
    super.dispose();
  }

  static const _logPollInterval = Duration(seconds: 3);

  void _setLogAutoRefresh(bool enabled) {
    setState(() => _logAutoRefresh = enabled);
    _logPollTimer?.cancel();
    _logStreamSub?.cancel();
    _logStreamSub = null;
    if (!enabled) return;

    final client = _client;
    if (client != null) {
      try {
        final stream = client.streamLogs();
        _logStreamSub = stream.listen(
          (line) {
            if (!mounted) return;
            setState(() {
              _logs = ServerLogs(
                lines: [..._logs.lines, line],
                source: _logs.source,
                message: _logs.message,
                filePath: _logs.filePath,
              );
            });
          },
          onError: (_) {
            if (_logPollTimer == null && _logAutoRefresh) {
              _logPollTimer = Timer.periodic(_logPollInterval, (_) => _refreshLogs());
            }
          },
        );
      } catch (_) {
        _logPollTimer = Timer.periodic(_logPollInterval, (_) => _refreshLogs());
      }
    } else {
      _logPollTimer = Timer.periodic(_logPollInterval, (_) => _refreshLogs());
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
    } catch (_) {
      // Periodic poll failure is suppressed until manual refresh.
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

  void _openConnectGuide() {
    setState(() {
      _selectedTab = 'guide';
      _guideInitialPage = _guideConnectAdminPageIndex;
    });
  }

  Future<void> _refreshData() async {
    if (_client == null) return;
    setState(() => _isLoading = true);
    try {
      final metrics = await _client!.getMetrics();
      final config = await _client!.getConfig();
      final logs = await _client!.getLogs();
      setState(() {
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
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
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
      return Scaffold(
        backgroundColor: HelixColorTokens.cFF0F0F16,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(
                Icons.radar,
                size: 64,
                color: HelixColorTokens.cFF00E5FF,
              ),
              SizedBox(height: 24),
              CircularProgressIndicator(
                color: HelixColorTokens.cFF8A2BE2,
              ),
            ],
          ),
        ),
      );
    }
    if (_appLockEnabled && !_isUnlocked) {
      return LockScreen(onUnlocked: _handleUnlocked);
    }
    if (_client == null) {
      if (_showGuideUnauthenticated) {
        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: 'Back to Sign In',
              onPressed: () => setState(() => _showGuideUnauthenticated = false),
            ),
            title: const Text('SELF-HOSTING GUIDE'),
          ),
          body: const GuideWizard(),
        );
      }
      return LoginScreen(
        urlController: _urlController,
        passwordController: _passwordController,
        isConnecting: _isConnecting,
        errorMessage: _errorMessage,
        needsSetup: _needsSetup,
        onSignIn: _connect,
        onSetupPassword: _handleSetupPassword,
        onCheckUrl: () => _checkSetupStatus(),
        onOpenGuide: () => setState(() => _showGuideUnauthenticated = true),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < _mobileBreakpoint;
        return Scaffold(
          key: _scaffoldKey,
          appBar: _buildAppBar(),
          drawer: isMobile
              ? Drawer(
                  backgroundColor: context.sunkenSurface,
                  child: SafeArea(child: _buildSidebarContent(inDrawer: true)),
                )
              : null,
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
                      icon: Icon(Icons.terminal_outlined),
                      selectedIcon: Icon(Icons.terminal),
                      label: 'Ops & Logs',
                    ),
                  ],
                )
              : null,
          body: isMobile
              ? _buildBody(isMobile: true)
              : Row(
                  children: [
                    Container(
                      width: 260,
                      color: context.sunkenSurface,
                      padding: HelixInsets.symmetric(vertical: 24),
                      child: _buildSidebarContent(inDrawer: false),
                    ),
                    Expanded(child: _buildBody(isMobile: false)),
                  ],
                ),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              _selectedTab.toUpperCase(),
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                letterSpacing: 1.5,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: Color(0xFF059669),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                const Text(
                  '23ms',
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: Color(0xFF059669),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        if (_serverDependentTabs.contains(_selectedTab))
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshData,
            tooltip: 'Refresh data',
          ),
        const SizedBox(width: 16),
      ],
    );
  }

  Widget _buildSidebarContent({required bool inDrawer}) {
    void selectTab(String tabId) {
      setState(() {
        _selectedTab = tabId;
        _guideInitialPage = 0;
      });
      if (_client != null && _serverDependentTabs.contains(tabId)) {
        _refreshData();
      }
      if (inDrawer) {
        _scaffoldKey.currentState?.closeDrawer();
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: HelixInsets.symmetric(horizontal: 24),
          child: Row(
            children: [
              Icon(Icons.radar, color: context.accentColor),
              const SizedBox(width: 12),
              const Flexible(
                child: Text(
                  'Helix Panel',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        _sidebarItem(Icons.dashboard, 'Dashboard', 'dashboard', selectTab),
        _sidebarItem(Icons.settings, 'Configurations', 'config', selectTab),
        _sidebarItem(Icons.terminal, 'Log Tailing', 'logs', selectTab),
        _sidebarItem(
          Icons.backup,
          'Maintenance & Backups',
          'backup',
          selectTab,
        ),
        _sidebarItem(Icons.mail_outline, 'Invites', 'invites', selectTab),
        _sidebarItem(Icons.people_outline, 'Users', 'users', selectTab),
        _sidebarItem(Icons.flag_outlined, 'Reports', 'reports', selectTab),
        _sidebarItem(Icons.menu_book, 'Self-Hosting Guide', 'guide', selectTab),
        _sidebarItem(Icons.tune, 'Settings', 'settings', selectTab),
        const Spacer(),
        Material(
          color: Colors.transparent,
          child: ListTile(
            key: const Key('sidebar_sign_out_button'),
            leading: const Icon(
              Icons.logout,
              color: HelixColorTokens.cFFFF3366,
            ),
            title: const Text(
              'Sign Out',
              style: TextStyle(
                color: HelixColorTokens.cFFFF3366,
                fontWeight: FontWeight.bold,
              ),
            ),
            onTap: () {
              _disconnect();
              if (inDrawer) {
                _scaffoldKey.currentState?.closeDrawer();
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _sidebarItem(
    IconData icon,
    String title,
    String tabId,
    ValueChanged<String> onSelect,
  ) {
    final isSelected = _selectedTab == tabId;
    return InkWell(
      onTap: () => onSelect(tabId),
      child: Container(
        margin: HelixInsets.symmetric(horizontal: 12, vertical: 4),
        padding: HelixInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? HelixColorTokens.cFF8A2BE2.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: isSelected
              ? Border.all(
                  color: HelixColorTokens.cFF8A2BE2.withValues(alpha: 0.4),
                )
              : null,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected ? context.accentColor : context.textSecondary,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isSelected
                      ? context.textPrimary
                      : context.textSecondary,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
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
    return Padding(
      padding: HelixInsets.all(isMobile ? 16.0 : 24.0),
      child: _getTabWidget(),
    );
  }

  Widget _getTabWidget() {
    switch (_selectedTab) {
      case 'dashboard':
        return DashboardTab(metrics: _metrics);
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
          initialSubTab: 'reports',
        );
      case 'config':
        return ConfigTab(
          config: _config,
          federationDomainController: _federationDomainController,
          federationAddressController: _federationAddressController,
          federationDirectoryController: _federationDirectoryController,
          onSetWorldwideMode: _setWorldwideMode,
          onSaveServerName: _saveServerName,
          serverHost: Uri.tryParse(_urlController.text)?.host,
        );
      case 'logs':
        return LogsTab(
          logs: _logs,
          onRefresh: _refreshLogs,
          autoRefreshEnabled: _logAutoRefresh,
          onAutoRefreshChanged: _setLogAutoRefresh,
        );
      case 'backup':
        return BackupTab(isLoading: _isLoading, onTriggerBackup: _triggerBackup);
      case 'invites':
        return InvitesTab(client: _client!);
      case 'users':
        return UsersTab(client: _client!);
      case 'reports':
        return ReportsTab(client: _client!);
      case 'guide':
        return GuideWizard(initialPage: _guideInitialPage);
      case 'settings':
        return SettingsTab(
          isDarkMode: widget.isDarkMode,
          onDarkModeChanged: widget.onDarkModeChanged,
          serverUrl: _urlController.text,
          onSignOut: _disconnect,
          onOpenConnectGuide: _openConnectGuide,
          appLockEnabled: _appLockEnabled,
          onAppLockChanged: (value) => _setAppLockEnabled(value),
        );
      default:
        return const Center(child: Text('Tab not found'));
    }
  }
}
