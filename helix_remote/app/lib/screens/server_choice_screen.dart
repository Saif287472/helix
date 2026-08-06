import 'package:helix_remote_ui/helix_remote_ui.dart';
import 'package:flutter/material.dart';
import 'package:helix_remote/app/remote_config.dart';
import 'package:helix_remote/app/remote_rest_client.dart';
import 'package:helix_remote/screens/invite_entry_screen.dart';
import 'package:helix_remote/services/local_notification_service.dart';
import 'package:helix_remote/widgets/onboarding_security_badges.dart';

/// Returned when the user chooses to continue without connecting to a
/// server yet.
class ContinueOfflineChoice {
  const ContinueOfflineChoice();
}

/// First-launch, four-way choice: join the free shared Helix Global server,
/// connect to a personal server via an invite link, read about hosting your
/// own server, or continue offline for now. Pops with a [ServerInviteChoice]
/// (Global or personal server), a [ContinueOfflineChoice], or null if
/// dismissed without a choice.
class ServerChoiceScreen extends StatefulWidget {
  const ServerChoiceScreen({super.key});

  @override
  State<ServerChoiceScreen> createState() => _ServerChoiceScreenState();
}

class _ServerChoiceScreenState extends State<ServerChoiceScreen> {
  bool _requestingGlobalInvite = false;
  String? _error;

  Future<void> _chooseHelixGlobal() async {
    if (_requestingGlobalInvite) return;
    setState(() {
      _requestingGlobalInvite = true;
      _error = null;
    });
    HelixRemoteRestClientImpl? client;
    try {
      final config = RemoteDevelopmentConfig.helixGlobal(
        databaseDirectory: '',
        attachmentCacheDir: '',
      );
      client = HelixRemoteRestClientImpl(
        baseUri: config.restBaseUri,
        timeoutMs: 15000,
      );
      final response = await client.autoIssueGlobalInvite();
      final inviteCode = response['invite_code'] as String;
      await LocalNotificationService.showInviteCode(code: inviteCode);
      if (mounted) {
        Navigator.of(context).pop(
          ServerInviteChoice(
            serverUrl: kHelixGlobalServerUrl,
            inviteCode: inviteCode,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _error =
              'Could not get a Helix Global invite right now '
              '(${e.toString()}). Try again shortly, or pick another option.',
        );
      }
    } finally {
      client?.close();
      if (mounted) setState(() => _requestingGlobalInvite = false);
    }
  }

  Future<void> _choosePersonalServer() async {
    final result = await Navigator.of(context).push<ServerInviteChoice>(
      MaterialPageRoute(builder: (_) => const InviteEntryScreen()),
    );
    if (result != null && mounted) {
      Navigator.of(context).pop(result);
    }
  }

  Future<void> _chooseHostYourOwn() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const _HostYourOwnInfoScreen()));
  }

  void _chooseOffline() {
    Navigator.of(context).pop(const ContinueOfflineChoice());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Helix Remote')),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Padding(
                padding: HelixInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.hub_outlined, size: 64),
                    const SizedBox(height: 16),
                    Text(
                      'Welcome to Helix Remote',
                      style: theme.textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'How would you like to get started?',
                      style: theme.textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    const OnboardingSecurityBadge(),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        style: TextStyle(color: theme.colorScheme.error),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 32),
                    _ChoiceTile(
                      icon: Icons.public,
                      title: 'Helix Global',
                      subtitle:
                          'Free, shared server run by the Helix team. '
                          'Fastest way to get started.',
                      loading: _requestingGlobalInvite,
                      onTap: _requestingGlobalInvite
                          ? null
                          : _chooseHelixGlobal,
                    ),
                    const SizedBox(height: 12),
                    _ChoiceTile(
                      icon: Icons.link,
                      title: 'Join a personal server',
                      subtitle:
                          'Have an invite link from a friend or admin? '
                          'Connect using it.',
                      onTap: _requestingGlobalInvite
                          ? null
                          : _choosePersonalServer,
                    ),
                    const SizedBox(height: 12),
                    _ChoiceTile(
                      icon: Icons.dns_outlined,
                      title: 'Host your own server',
                      subtitle:
                          'Run Helix Remote on your own PC or VPS using '
                          'Helix Admin.',
                      onTap: _requestingGlobalInvite
                          ? null
                          : _chooseHostYourOwn,
                    ),
                    const SizedBox(height: 12),
                    _ChoiceTile(
                      icon: Icons.wifi_off_outlined,
                      title: 'Continue offline',
                      subtitle:
                          'Skip server setup for now. You can connect '
                          'later.',
                      onTap: _requestingGlobalInvite ? null : _chooseOffline,
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
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.loading = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onTap != null;
    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(
        alpha: enabled ? 1.0 : 0.5,
      ),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: HelixInsets.all(16),
          child: Row(
            children: [
              loading
                  ? const SizedBox.square(
                      dimension: 28,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(icon, size: 28, color: theme.colorScheme.primary),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(subtitle, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              if (enabled) const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _HostYourOwnInfoScreen extends StatelessWidget {
  const _HostYourOwnInfoScreen();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Host your own server')),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Padding(
                padding: HelixInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Icon(
                        Icons.dns_outlined,
                        size: 64,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Run your own Helix Remote server',
                      style: theme.textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Helix Admin is a free companion app that sets up and '
                      'manages a Helix Remote server on your own PC or a '
                      'rented VPS. You stay in full control of your data.',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '1. Install Helix Admin on the machine that will run '
                      'your server.\n'
                      '2. Follow its Self-Hosting Guide to install and '
                      'configure the backend.\n'
                      '3. Once it\'s running, Helix Admin gives you a '
                      'shareable invite link.\n'
                      '4. Come back here and choose "Join a personal '
                      'server" with that link.',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Back'),
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
}
