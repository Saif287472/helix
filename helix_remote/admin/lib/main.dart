import 'package:flutter/material.dart';
import 'admin_client.dart';

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
          background: Color(0xFF0F0F16),
          error: Color(0xFFFF3366),
        ),
        useMaterial3: true,
      ),
      home: const MainAdminPage(),
    );
  }
}

class MainAdminPage extends StatefulWidget {
  const MainAdminPage({super.key});

  @override
  State<MainAdminPage> createState() => _MainAdminPageState();
}

class _MainAdminPageState extends State<MainAdminPage> {
  AdminClient? _client;
  String _selectedTab = 'dashboard';
  bool _isLoading = false;

  final _urlController = TextEditingController(text: 'http://127.0.0.1:8080');
  final _tokenController = TextEditingController();
  final _federationDomainController = TextEditingController();
  final _federationAddressController = TextEditingController();
  final _federationDirectoryController = TextEditingController();

  Map<String, dynamic>? _metrics;
  Map<String, dynamic>? _config;
  List<String> _logs = [];
  String? _errorMessage;

  @override
  void dispose() {
    _urlController.dispose();
    _tokenController.dispose();
    _federationDomainController.dispose();
    _federationAddressController.dispose();
    _federationDirectoryController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final client = AdminClient(
      baseUrl: _urlController.text.trim(),
      token: _tokenController.text.trim(),
    );

    final ok = await client.verifyLogin();
    if (ok) {
      setState(() {
        _client = client;
        _isLoading = false;
      });
      _refreshData();
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Invalid backend URL or admin token.';
      });
    }
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

  @override
  Widget build(BuildContext context) {
    if (_client == null) {
      return _buildLoginScreen();
    }
    return Scaffold(
      body: Row(
        children: [
          _buildSidebar(),
          Expanded(child: _buildMainContent()),
        ],
      ),
    );
  }

  Widget _buildLoginScreen() {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0F0F16), Color(0xFF1E0B36)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            child: Card(
              elevation: 12,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              color: const Color(0xFF161624).withOpacity(0.9),
              child: Container(
                width: 420,
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(
                      Icons.admin_panel_settings,
                      size: 64,
                      color: Color(0xFF00E5FF),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'HELIX SERVER ADMIN',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Secure self-hosted dashboard operations.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: Colors.white70),
                    ),
                    const SizedBox(height: 32),
                    TextField(
                      controller: _urlController,
                      decoration: const InputDecoration(
                        labelText: 'Backend Server URL',
                        prefixIcon: Icon(Icons.dns),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _tokenController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Admin API Token',
                        prefixIcon: Icon(Icons.lock),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (_errorMessage != null) ...[
                      Text(
                        _errorMessage!,
                        style: const TextStyle(
                          color: Color(0xFFFF3366),
                          fontSize: 13,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                    ],
                    ElevatedButton(
                      onPressed: _isLoading ? null : _login,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF8A2BE2),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'AUTHENTICATE',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.5,
                                color: Colors.white,
                              ),
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
                const Text(
                  'Helix Panel',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
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
          _sidebarItem(Icons.menu_book, 'Self-Hosting Guide', 'guide'),
          const Spacer(),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.white60),
            title: const Text(
              'Logout',
              style: TextStyle(color: Colors.white60),
            ),
            onTap: () {
              setState(() {
                _client = null;
                _metrics = null;
                _config = null;
                _logs = [];
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _sidebarItem(IconData icon, String title, String tabId) {
    final isSelected = _selectedTab == tabId;
    return InkWell(
      onTap: () {
        setState(() => _selectedTab = tabId);
        _refreshData();
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF8A2BE2).withOpacity(0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: isSelected
              ? Border.all(color: const Color(0xFF8A2BE2).withOpacity(0.4))
              : null,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected ? const Color(0xFF00E5FF) : Colors.white70,
            ),
            const SizedBox(width: 16),
            Text(
              title,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white70,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainContent() {
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
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refreshData),
          const SizedBox(width: 16),
        ],
      ),
      body: _isLoading && _metrics == null
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(24.0),
              child: _getTabWidget(),
            ),
    );
  }

  Widget _getTabWidget() {
    switch (_selectedTab) {
      case 'dashboard':
        return _buildDashboardTab();
      case 'config':
        return _buildConfigTab();
      case 'logs':
        return _buildLogsTab();
      case 'backup':
        return _buildBackupTab();
      case 'guide':
        return _buildGuideTab();
      default:
        return const Center(child: Text('Tab not found'));
    }
  }

  Widget _buildDashboardTab() {
    if (_metrics == null) {
      return const Center(child: Text('No metrics available. Click refresh.'));
    }
    final tblCounts = _metrics!['table_counts'] as Map? ?? {};
    final ws = _metrics!['websocket'] as Map? ?? {};

    return GridView.count(
      crossAxisCount: MediaQuery.of(context).size.width > 1200 ? 3 : 2,
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      childAspectRatio: 1.6,
      children: [
        _metricCard(
          'Active Devices Connections',
          '${ws['connected_devices'] ?? 0}',
          Icons.wifi,
          Colors.green,
        ),
        _metricCard(
          'Registered User Accounts',
          '${tblCounts['accounts'] ?? 0}',
          Icons.people,
          const Color(0xFF00E5FF),
        ),
        _metricCard(
          'Mailbox Encrypted Messages',
          '${tblCounts['messages'] ?? 0}',
          Icons.mail,
          const Color(0xFF8A2BE2),
        ),
        _metricCard(
          'Quarantined Security Events',
          '${tblCounts['quarantine_events'] ?? 0}',
          Icons.security,
          Colors.orange,
        ),
        _metricCard(
          'Outbox Delivery Retry Queue',
          '${tblCounts['outbox'] ?? 0}',
          Icons.sync_problem,
          const Color(0xFFFF3366),
        ),
        _metricCard(
          'Database Status Check',
          _metrics!['database_quick_check_ok'] == true
              ? 'HEALTHY'
              : 'UNHEALTHY',
          Icons.offline_bolt,
          Colors.green,
        ),
      ],
    );
  }

  Widget _metricCard(String title, String val, IconData icon, Color accent) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: const Color(0xFF161624),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 14, color: Colors.white70),
                ),
                Icon(icon, color: accent),
              ],
            ),
            Text(
              val,
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfigTab() {
    if (_config == null) {
      return const Center(child: Text('No configuration available.'));
    }
    return SingleChildScrollView(
      child: Card(
        color: const Color(0xFF161624),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Server Configuration Properties',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),
              _configField('Server ID', _config!['server_id'] ?? 'unknown'),
              _configField(
                'Server Public Key',
                _config!['server_public_key'] ?? 'unknown',
              ),
              _configField(
                'Server Running Port',
                _config!['port'] ?? 'unknown',
              ),
              _configField('Host Address Bound', _config!['host'] ?? 'unknown'),
              _configField('Database Path', _config!['db_path'] ?? 'unknown'),
              _configField(
                'Attachments Path',
                _config!['attachments_dir'] ?? 'unknown',
              ),
              _configField(
                'Push Notifications Configured',
                _config!['push_configured'] == true ? 'ENABLED' : 'DISABLED',
              ),
              _configField(
                'TURN Server Configured',
                _config!['turn_configured'] == true ? 'ENABLED' : 'DISABLED',
              ),
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),
              _buildFederationControls(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFederationControls() {
    final federation =
        (_config!['federation'] as Map<String, dynamic>?) ?? const {};
    final enabled = federation['worldwide_mode'] == true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Worldwide Mode',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Switch(
              value: enabled,
              onChanged: (value) => _setWorldwideMode(value),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _federationDomainController,
          decoration: const InputDecoration(labelText: 'Federation domain'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _federationAddressController,
          decoration: const InputDecoration(labelText: 'Public server address'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _federationDirectoryController,
          decoration: const InputDecoration(labelText: 'Directory server URL'),
        ),
      ],
    );
  }

  Widget _configField(String label, String val) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          SelectableText(
            val,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              fontFamily: 'monospace',
              color: Color(0xFF00E5FF),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogsTab() {
    return Card(
      color: const Color(0xFF08080C),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Live Server Console Logs (Last 100)',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _refreshData,
                ),
              ],
            ),
            const Divider(),
            Expanded(
              child: _logs.isEmpty
                  ? const Center(
                      child: Text(
                        'No logs available.',
                        style: TextStyle(color: Colors.white38),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _logs.length,
                      itemBuilder: (context, index) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text(
                            _logs[index],
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 13,
                              color: Colors.greenAccent,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackupTab() {
    return Center(
      child: Container(
        width: 500,
        child: Card(
          color: const Color(0xFF161624),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.settings_backup_restore,
                  size: 64,
                  color: Color(0xFF8A2BE2),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Automated Maintenance & Snapshot Backups',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Creates a clean snapshot of the server database using SQLite "VACUUM INTO". File is saved in the backups directory.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 32),
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : _triggerBackup,
                  icon: const Icon(Icons.backup),
                  label: const Text('TRIGGER SNAPSHOT BACKUP'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF8A2BE2),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGuideTab() {
    return SingleChildScrollView(
      child: Card(
        color: const Color(0xFF161624),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Self-Hosting Guide',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF00E5FF),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Helix is designed to be fully self-hostable. Follow these general steps to deploy your home server:',
                style: TextStyle(fontSize: 14, color: Colors.white70),
              ),
              const SizedBox(height: 24),
              _guideStep(
                '1. Provision VPS Server',
                'Purchase a minimalist Virtual Private Server (VPS) from providers like DigitalOcean, Linode, Hetzner, or AWS. We recommend at least 1GB RAM and 1 vCPU running Ubuntu 22.04 LTS.',
              ),
              _guideStep(
                '2. Install Docker Environment',
                'Install Docker Engine and Docker Compose on the host machine to easily pull and run containerized server instances.',
              ),
              _guideStep(
                '3. Configure Docker Compose',
                'Create a docker-compose.yml file detailing backend services, volume paths, rate limit parameters, and environment config variable settings.',
              ),
              _guideStep(
                '4. Leverage External AI Assistants',
                'Use AI models (like Claude, Gemini, or ChatGPT) as operations support to write custom bash scripts, configure Nginx reverse proxies, establish SSL certificates with Let\'s Encrypt, or set up cron jobs for automated system-level backups.',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _guideStep(String title, String desc) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            desc,
            style: const TextStyle(
              fontSize: 13,
              color: Colors.white70,
              height: 1.5,
            ),
          ),
          const Divider(height: 24),
        ],
      ),
    );
  }
}
