import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'app/composition_root.dart';
import 'app/remote_config.dart';
import 'screens/conversation_list_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final appDir = await getApplicationDocumentsDirectory();
  final dbDir = p.join(appDir.path, 'helix_remote_db');
  final cacheDir = p.join(appDir.path, 'attachments_cache');

  final devConfig = RemoteDevelopmentConfig.fromDartDefine(
    databaseDirectory: dbDir,
    attachmentCacheDir: cacheDir,
  );

  final root = RemoteCompositionRoot.production(
    databaseDirectory: dbDir,
    devConfig: devConfig,
  );

  runApp(HelixRemoteApp(root: root));
}

class HelixRemoteApp extends StatefulWidget {
  const HelixRemoteApp({super.key, required this.root});

  final RemoteCompositionRoot root;

  @override
  State<HelixRemoteApp> createState() => _HelixRemoteAppState();
}

class _HelixRemoteAppState extends State<HelixRemoteApp> {
  RemoteStartupState _startupState = RemoteStartupState.idle;
  String? _errorMessage;
  bool _initializing = false;

  @override
  void initState() {
    super.initState();
    _startBoot();
  }

  Future<void> _startBoot() async {
    if (_initializing) return;
    _initializing = true;
    try {
      await widget.root.initialize();
      final restored = await widget.root.tryRestoreSession();
      if (restored && mounted) {
        setState(() {
          _startupState = widget.root.startupState;
        });
      } else if (mounted) {
        setState(() {
          _startupState = widget.root.startupState;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _startupState = widget.root.startupState;
          _errorMessage = widget.root.lastError ?? e.toString();
        });
      }
    }
    _initializing = false;
  }

  @override
  void dispose() {
    widget.root.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: widget.root.config.displayName,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF166A64),
          brightness: Brightness.light,
        ),
      ),
      home: _buildScreen(),
    );
  }

  Widget _buildScreen() {
    switch (_startupState) {
      case RemoteStartupState.idle:
      case RemoteStartupState.loadingConfiguration:
      case RemoteStartupState.openingSecureStorage:
      case RemoteStartupState.firstRunInitialization:
      case RemoteStartupState.openingDatabase:
      case RemoteStartupState.restoringSession:
        return _buildLoadingScreen();

      case RemoteStartupState.unauthenticated:
        return _buildSetupScreen();

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

  Widget _buildSetupScreen() {
    final usernameController = TextEditingController();
    return Scaffold(
      appBar: AppBar(title: Text(widget.root.config.displayName)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_outlined, size: 64),
              const SizedBox(height: 16),
              Text(
                'Welcome to Helix Remote',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'Backend: ${widget.root.devConfig.restBaseUri}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 24),
              TextField(
                controller: usernameController,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () async {
                  final username = usernameController.text.trim();
                  if (username.isEmpty) return;
                  try {
                    await widget.root.registerAndLogin(username);
                    if (mounted) {
                      setState(() {
                        _startupState = widget.root.startupState;
                      });
                    }
                  } catch (e) {
                    if (mounted) {
                      setState(() {
                        _errorMessage = e.toString();
                      });
                    }
                  }
                },
                icon: const Icon(Icons.login),
                label: const Text('Register & Sign In'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReadyScreen() {
    return ConversationListScreen(
      messagingService: widget.root.messagingService,
      root: widget.root,
    );
  }

  Widget _buildErrorScreen() {
    return Scaffold(
      appBar: AppBar(title: const Text('Startup Error')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                'Failed to start',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage ?? 'Unknown error',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () {
                  setState(() {
                    _startupState = RemoteStartupState.idle;
                    _errorMessage = null;
                  });
                  _startBoot();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResetScreen() {
    return Scaffold(
      appBar: AppBar(title: const Text('Reset Required')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.warning_amber, size: 64, color: Colors.orange),
              const SizedBox(height: 16),
              Text(
                'Database key is missing',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              const Text(
                'An existing database was found but its encryption key is not '
                'available in secure storage. A reset is required.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
