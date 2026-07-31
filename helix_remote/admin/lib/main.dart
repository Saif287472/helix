import 'package:flutter/material.dart';
import 'admin_client.dart';
import 'screens/backup_tab.dart';
import 'screens/config_tab.dart';
import 'screens/dashboard_tab.dart';
import 'screens/guide/guide_wizard.dart';
import 'screens/intro_screen.dart';
import 'screens/invites_tab.dart';
import 'screens/logs_tab.dart';
import 'screens/settings_tab.dart';
import 'services/admin_preferences.dart';
import 'widgets/locked_tab_placeholder.dart';

void main() {
  runApp(const HelixAdminApp());
}

class HelixAdminApp extends StatelessWidget {
  const HelixAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Helix Admin',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F0F16),
        cardColor: const Color(0xFF161624),
        primaryColor: const Color(0xFF8A2BE2),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF8A2BE2),
          secondary: Color(0xFF00E5FF),
          surface: Color(0xFF161624),
          error: Color(0xFFFF3366),
        ),
        useMaterial3: true,
      ),
      home: const MainAdminPage(),
    );
  }
}

const _serverDependentTabs = {'dashboard', 'config', 'logs', 'backup', 'invites'};
const _defaultServerUrl = 'http://127.0.0.1:8080';

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
  bool _isDarkMode = true;

  AdminPreferences? _prefs;
  bool _introShown = false;

  final _urlController = TextEditingController(text: _defaultServerUrl);
  final _tokenController = TextEditingController();
  final _federationDomainController = TextEditingController();
  final _federationAddressController = TextEditingController();
  final _federationDirectoryController = TextEditingController();

  Map<String, dynamic>? _metrics;
  Map<String, dynamic>? _config;
  List<String> _logs = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await AdminPreferences.load();
    if (!mounted) return;
    setState(() {
      _prefs = prefs;
      _introShown = prefs.introShown;
      _urlController.text = prefs.serverUrl ?? _defaultServerUrl;
    });
  }

  @override
  void dispose() {
    _urlController.dispose();
    _tokenController.dispose();
    _federationDomainController.dispose();
    _federationAddressController.dispose();
    _federationDirectoryController.dispose();
    super.dispose();
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

    final url = _urlController.text.trim();
    final client = AdminClient(baseUrl: url, token: _tokenController.text.trim());

    final ok = await client.verifyLogin();
    if (!mounted) return;
    if (ok) {
      await _prefs?.setServerUrl(url);
      setState(() {
        _client = client;
        _isConnecting = false;
      });
      _refreshData();
    } else {
      setState(() {
        _isConnecting = false;
        _errorMessage = 'Invalid backend URL or admin token.';
      });
    }
  }

  void _disconnect() {
    setState(() {
      _client = null;
      _metrics = null;
      _config = null;
      _logs = [];
      _errorMessage = null;
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
        _federationDomainController.text = federation?['domain'] as String? ?? '';
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Backup failed: $e'), backgroundColor: Colors.red));
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

  @override
  Widget build(BuildContext context) {
    if (_prefs == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_introShown) {
      return IntroScreen(onGetStarted: _completeIntro);
    }
    return Theme(
      data: _isDarkMode ? ThemeData.dark() : ThemeData.light(),
      child: Scaffold(
        body: Row(
          children: [
            _buildSidebar(),
            Expanded(child: _buildMainContent()),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 260,
      color: const Color(0xFF0B0B12),
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                const Icon(Icons.radar, color: Color(0xFF00E5FF)),
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
          _sidebarItem(Icons.dashboard, 'Dashboard', 'dashboard'),
          _sidebarItem(Icons.settings, 'Configurations', 'config'),
          _sidebarItem(Icons.terminal, 'Log Tailing', 'logs'),
          _sidebarItem(Icons.backup, 'Maintenance & Backups', 'backup'),
          _sidebarItem(Icons.mail_outline, 'Invites', 'invites'),
          _sidebarItem(Icons.menu_book, 'Self-Hosting Guide', 'guide'),
          _sidebarItem(Icons.tune, 'Settings', 'settings'),
          const Spacer(),
          if (_client != null) ...[
            const Divider(),
            ListTile(
              leading: const Icon(Icons.link_off, color: Colors.white60),
              title: const Text(
                'Disconnect',
                style: TextStyle(color: Colors.white60),
              ),
              onTap: _disconnect,
            ),
          ],
        ],
      ),
    );
  }

  Widget _sidebarItem(IconData icon, String title, String tabId) {
    final isSelected = _selectedTab == tabId;
    return InkWell(
      onTap: () {
        setState(() => _selectedTab = tabId);
        if (_client != null && _serverDependentTabs.contains(tabId)) {
          _refreshData();
        }
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF8A2BE2).withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: isSelected
              ? Border.all(color: const Color(0xFF8A2BE2).withValues(alpha: 0.4))
              : null,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected ? const Color(0xFF00E5FF) : Colors.white70,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white70,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    final showFullPageSpinner =
        _isLoading && _metrics == null && _serverDependentTabs.contains(_selectedTab);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0F16),
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
      ),
      body: showFullPageSpinner
          ? const Center(child: CircularProgressIndicator())
          : Padding(padding: const EdgeInsets.all(24.0), child: _getTabWidget()),
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
            : LogsTab(logs: _logs, onRefresh: _refreshData);
      case 'backup':
        return _client == null
            ? _lockedTab()
            : BackupTab(isLoading: _isLoading, onTriggerBackup: _triggerBackup);
      case 'invites':
        return _client == null ? _lockedTab() : InvitesTab(client: _client!);
      case 'guide':
        return const GuideWizard();
      case 'settings':
        return SettingsTab(
          isDarkMode: _isDarkMode,
          onDarkModeChanged: (v) => setState(() => _isDarkMode = v),
          urlController: _urlController,
          tokenController: _tokenController,
          isConnected: _client != null,
          isConnecting: _isConnecting,
          errorMessage: _errorMessage,
          onConnect: _connect,
          onDisconnect: _disconnect,
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
