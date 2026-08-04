import 'dart:async';

import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'admin_client.dart';
import 'screens/backup_tab.dart';
import 'screens/config_tab.dart';
import 'screens/connect_server_screen.dart';
import 'screens/dashboard_tab.dart';
import 'screens/guide/guide_wizard.dart';
import 'screens/intro_screen.dart';
import 'screens/invites_tab.dart';
import 'screens/users_tab.dart';
import 'screens/lock_screen.dart';
import 'screens/logs_tab.dart';
import 'screens/settings_tab.dart';
import 'services/admin_preferences.dart';
import 'theme/app_theme.dart';
import 'widgets/locked_tab_placeholder.dart';

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
};
const _defaultServerUrl = 'http://127.0.0.1:8080';

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

  /// Guide page to open next time the 'guide' tab is built. Reset to 0
  /// (Welcome) on every normal sidebar navigation; only the "Where do I
  /// find this?" link in Settings sets it to the Connect Admin page.
  int _guideInitialPage = 0;

  static const _guideConnectAdminPageIndex = 6;

  AdminPreferences? _prefs;
  bool _introShown = false;
  bool _appLockEnabled = false;
  bool _isUnlocked = false;

  /// Whether the connect-server screen is showing over the shell. Shown as
  /// part of this widget's own build() (like the lock/intro screens) rather
  /// than pushed via Navigator, so it always reflects the current
  /// _client/_isConnecting/_errorMessage instead of a stale snapshot
  /// frozen at whatever they were the moment it was opened.
  bool _showConnectServer = false;

  final _urlController = TextEditingController(text: _defaultServerUrl);
  final _tokenController = TextEditingController();
  final _federationDomainController = TextEditingController();
  final _federationAddressController = TextEditingController();
  final _federationDirectoryController = TextEditingController();

  Map<String, dynamic>? _metrics;
  Map<String, dynamic>? _config;
  ServerLogs _logs = const ServerLogs.empty();
  String? _errorMessage;

  /// Polls the Logs screen while it's live. Lives here rather than in
  /// LogsTab so toggling it survives navigating between tabs.
  Timer? _logPollTimer;
  bool _logAutoRefresh = false;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await AdminPreferences.load();
    if (!mounted) return;
    final appLockEnabled = prefs.appLockEnabled;
    setState(() {
      _prefs = prefs;
      _introShown = prefs.introShown;
      _appLockEnabled = appLockEnabled;
      _isUnlocked = !appLockEnabled;
      _urlController.text = prefs.serverUrl ?? _defaultServerUrl;
    });
    if (!appLockEnabled) {
      _attemptAutoConnect();
    }
  }

  /// Reconnects with the token saved from a previous successful connect, so
  /// operators don't have to re-pair or retype the admin token every launch.
  /// A no-op if nothing (or an unusable URL) was saved yet.
  ///
  /// Only an explicit unauthorized response from the server counts as the
  /// token actually being dead - a network hiccup (weak signal, DNS blip,
  /// server briefly unreachable) must not delete a perfectly good saved
  /// token, or every flaky-connection launch would force a full re-pair.
  Future<void> _attemptAutoConnect() async {
    final prefs = _prefs;
    if (prefs == null) return;
    final url = prefs.serverUrl;
    final token = await prefs.loadAdminToken();
    if (url == null || url.isEmpty || token == null || token.isEmpty) return;

    // Fill the field up front so that even on a network failure below, the
    // saved token is right there ready for the user to just tap Reconnect.
    _tokenController.text = token;
    setState(() => _isConnecting = true);
    final client = AdminClient(baseUrl: url, token: token);
    final status = await client.verifyLoginDetailed();
    if (!mounted) return;
    switch (status) {
      case AdminLoginStatus.ok:
        setState(() {
          _client = client;
          _isConnecting = false;
        });
        _refreshData();
      case AdminLoginStatus.unauthorized:
        await prefs.clearAdminToken();
        if (!mounted) return;
        _tokenController.clear();
        setState(() {
          _isConnecting = false;
          _errorMessage =
              'Saved session expired or was revoked on the server. Please '
              'reconnect.';
        });
      case AdminLoginStatus.unreachable:
        setState(() {
          _isConnecting = false;
          _errorMessage =
              "Couldn't reach the saved server to restore your session. "
              'Check your connection, then tap Reconnect.';
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
    _logPollTimer?.cancel();
    _urlController.dispose();
    _tokenController.dispose();
    _federationDomainController.dispose();
    _federationAddressController.dispose();
    _federationDirectoryController.dispose();
    super.dispose();
  }

  /// How often the Logs screen pulls new lines while "Live" is on. Slow
  /// enough to be cheap on a small VPS, quick enough to feel live.
  static const _logPollInterval = Duration(seconds: 3);

  void _setLogAutoRefresh(bool enabled) {
    setState(() => _logAutoRefresh = enabled);
    _logPollTimer?.cancel();
    if (!enabled) return;
    _logPollTimer = Timer.periodic(_logPollInterval, (_) => _refreshLogs());
    _refreshLogs();
  }

  /// Refreshes only the log lines. Deliberately separate from
  /// [_refreshData]: the poll shouldn't drag metrics, config and the
  /// federation controllers along with it every few seconds, and it must
  /// not flip the shell into its full-page loading state.
  Future<void> _refreshLogs() async {
    final client = _client;
    if (client == null) return;
    try {
      final logs = await client.getLogs();
      if (!mounted) return;
      setState(() => _logs = logs);
    } catch (_) {
      // A failed poll is not worth interrupting the screen for - the next
      // tick will pick it up, and a hard failure still surfaces through
      // the manual refresh path.
    }
  }

  Future<void> _completeIntro() async {
    await _prefs?.setIntroShown(true);
    if (!mounted) return;
    setState(() => _introShown = true);
  }

  Future<void> _connect() async {
    setState(() {
      _isConnecting = true;
      _errorMessage = null;
    });

    final url = _normalizeServerUrl(_urlController.text);
    _urlController.text = url;
    final client = AdminClient(
      baseUrl: url,
      token: _tokenController.text.trim(),
    );

    final status = await client.verifyLoginDetailed();
    if (!mounted) return;
    if (status == AdminLoginStatus.ok) {
      await _prefs?.setServerUrl(url);
      await _prefs?.saveAdminToken(_tokenController.text.trim());
      setState(() {
        _client = client;
        _isConnecting = false;
      });
      _refreshData();
    } else {
      setState(() {
        _isConnecting = false;
        _errorMessage = status == AdminLoginStatus.unauthorized
            ? 'Invalid backend URL or admin token.'
            : "Couldn't reach that server. Check the URL and your "
                  'connection, then try again.';
      });
    }
  }

  void _disconnect() {
    unawaited(_prefs?.clearAdminToken());
    // Stop polling immediately - the timer would otherwise keep firing
    // against a server this app is no longer authenticated to.
    _logPollTimer?.cancel();
    _logAutoRefresh = false;
    setState(() {
      _client = null;
      _metrics = null;
      _config = null;
      _logs = const ServerLogs.empty();
      _errorMessage = null;
    });
  }

  /// Tolerates the common paste mistakes new users make with a server URL:
  /// stray whitespace, a missing scheme, and a trailing slash.
  String _normalizeServerUrl(String raw) {
    var url = raw.trim();
    if (url.isEmpty) return url;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'http://$url';
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

  /// Below this width there's no room for a fixed 260px sidebar next to
  /// content, so the shell switches to an AppBar hamburger + Drawer.
  static const double _mobileBreakpoint = 700;

  final _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    if (_prefs == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_appLockEnabled && !_isUnlocked) {
      return LockScreen(onUnlocked: _handleUnlocked);
    }
    if (!_introShown) {
      return IntroScreen(onGetStarted: _completeIntro);
    }
    if (_showConnectServer) {
      return ConnectServerScreen(
        urlController: _urlController,
        tokenController: _tokenController,
        isConnected: _client != null,
        isConnecting: _isConnecting,
        errorMessage: _errorMessage,
        onConnect: _connect,
        onDisconnect: _disconnect,
        onBack: () => setState(() => _showConnectServer = false),
        onOpenConnectGuide: () {
          setState(() => _showConnectServer = false);
          _openConnectGuide();
        },
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
          body: isMobile
              ? _buildBody(isMobile: true)
              : Row(
                  children: [
                    Container(
                      width: 260,
                      color: context.sunkenSurface,
                      padding: const EdgeInsets.symmetric(vertical: 24),
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
      title: Text(
        _selectedTab.toUpperCase(),
        style: const TextStyle(
          letterSpacing: 1.5,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
      actions: [
        if (_serverDependentTabs.contains(_selectedTab))
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refreshData),
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
          padding: const EdgeInsets.symmetric(horizontal: 24),
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
        _sidebarItem(
          Icons.menu_book,
          'Self-Hosting Guide',
          'guide',
          selectTab,
        ),
        _sidebarItem(Icons.tune, 'Settings', 'settings', selectTab),
        const Spacer(),
        if (_client != null) ...[
          const Divider(),
          ListTile(
            leading: Icon(Icons.link_off, color: context.textSecondary),
            title: Text(
              'Disconnect',
              style: TextStyle(color: context.textSecondary),
            ),
            onTap: () {
              _disconnect();
              if (inDrawer) {
                _scaffoldKey.currentState?.closeDrawer();
              }
            },
          ),
        ],
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
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF8A2BE2).withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: isSelected
              ? Border.all(
                  color: const Color(0xFF8A2BE2).withValues(alpha: 0.4),
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
                  color: isSelected ? context.textPrimary : context.textSecondary,
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
      return const Center(child: CircularProgressIndicator());
    }
    return Padding(
      padding: EdgeInsets.all(isMobile ? 16.0 : 24.0),
      child: _getTabWidget(),
    );
  }

  Widget _getTabWidget() {
    switch (_selectedTab) {
      case 'dashboard':
        return _client == null ? _lockedTab() : DashboardTab(metrics: _metrics);
      case 'config':
        return _client == null
            ? _lockedTab()
            : ConfigTab(
                config: _config,
                federationDomainController: _federationDomainController,
                federationAddressController: _federationAddressController,
                federationDirectoryController: _federationDirectoryController,
                onSetWorldwideMode: _setWorldwideMode,
              );
      case 'logs':
        return _client == null
            ? _lockedTab()
            : LogsTab(
                logs: _logs,
                onRefresh: _refreshLogs,
                autoRefreshEnabled: _logAutoRefresh,
                onAutoRefreshChanged: _setLogAutoRefresh,
              );
      case 'backup':
        return _client == null
            ? _lockedTab()
            : BackupTab(isLoading: _isLoading, onTriggerBackup: _triggerBackup);
      case 'invites':
        return _client == null ? _lockedTab() : InvitesTab(client: _client!);
      case 'users':
        return _client == null ? _lockedTab() : UsersTab(client: _client!);
      case 'guide':
        return GuideWizard(initialPage: _guideInitialPage);
      case 'settings':
        return SettingsTab(
          isDarkMode: widget.isDarkMode,
          onDarkModeChanged: widget.onDarkModeChanged,
          urlController: _urlController,
          isConnected: _client != null,
          onOpenConnectServer: () =>
              setState(() => _showConnectServer = true),
          onDisconnect: _disconnect,
          onOpenConnectGuide: _openConnectGuide,
          appLockEnabled: _appLockEnabled,
          onAppLockChanged: (value) => _setAppLockEnabled(value),
        );
      default:
        return const Center(child: Text('Tab not found'));
    }
  }

  Widget _lockedTab() {
    return LockedTabPlaceholder(
      onGoToSettings: () => setState(() => _selectedTab = 'settings'),
    );
  }
}
