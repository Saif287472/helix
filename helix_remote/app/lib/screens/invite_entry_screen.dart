import 'package:flutter/material.dart';
import 'package:helix_remote/app/remote_config.dart';
import 'package:helix_remote/app/remote_rest_client.dart';

/// Result of successfully validating a personal server + invite combo.
class ServerInviteChoice {
  const ServerInviteChoice({required this.serverUrl, required this.inviteCode});

  final String serverUrl;
  final String inviteCode;
}

/// "Personal server" first-launch path: the admin who invited you shares a
/// single combined `<server_address>/join?invite=<code>` link. This screen
/// parses it, validates the server address, and confirms the invite is
/// still redeemable before handing control back to the caller.
class InviteEntryScreen extends StatefulWidget {
  const InviteEntryScreen({super.key});

  @override
  State<InviteEntryScreen> createState() => _InviteEntryScreenState();
}

class _InviteEntryScreenState extends State<InviteEntryScreen> {
  final _linkController = TextEditingController();
  bool _checking = false;
  String? _error;

  @override
  void dispose() {
    _linkController.dispose();
    super.dispose();
  }

  ({String serverUrl, String inviteCode})? _parse(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final withScheme =
        trimmed.startsWith('http://') || trimmed.startsWith('https://')
        ? trimmed
        : 'https://$trimmed';
    final uri = Uri.tryParse(withScheme);
    if (uri == null || uri.host.isEmpty) return null;
    final inviteCode = uri.queryParameters['invite'];
    if (inviteCode == null || inviteCode.isEmpty) return null;
    final serverUrl = uri.replace(path: '', query: '', fragment: '').toString();
    return (serverUrl: serverUrl, inviteCode: inviteCode);
  }

  Future<void> _continue() async {
    if (_checking) return;
    final parsed = _parse(_linkController.text);
    if (parsed == null) {
      setState(() {
        _error =
            'Paste the full link your admin shared, e.g. '
            'https://your-server.example/join?invite=CODE.';
      });
      return;
    }

    setState(() {
      _checking = true;
      _error = null;
    });

    HelixRemoteRestClientImpl? client;
    try {
      final config = RemoteDevelopmentConfig.fromServerUrl(
        parsed.serverUrl,
        databaseDirectory: '',
        attachmentCacheDir: '',
      );
      client = HelixRemoteRestClientImpl(
        baseUri: config.restBaseUri,
        timeoutMs: 15000,
      );
      final lookup = await client.lookupInvite(inviteCode: parsed.inviteCode);
      if (lookup['valid'] != true) {
        if (mounted) {
          setState(
            () => _error =
                'That invite code is invalid or has expired. Ask your '
                'admin for a new one.',
          );
        }
        return;
      }
      if (mounted) {
        Navigator.of(context).pop(
          ServerInviteChoice(
            serverUrl: parsed.serverUrl,
            inviteCode: parsed.inviteCode,
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      client?.close();
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Connect to a personal server')),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.link, size: 64),
                    const SizedBox(height: 16),
                    Text(
                      'Paste your invite link',
                      style: theme.textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'The admin of the server you\'re joining shares a link '
                      'like https://their-server.example/join?invite=CODE.',
                      style: theme.textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    TextField(
                      controller: _linkController,
                      enabled: !_checking,
                      decoration: InputDecoration(
                        labelText: 'Server address & invite link',
                        hintText:
                            'https://your-server.example/join?invite=CODE',
                        border: const OutlineInputBorder(),
                        errorText: _error,
                        errorMaxLines: 4,
                      ),
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _continue(),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _checking ? null : _continue,
                        icon: _checking
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.arrow_forward),
                        label: Text(_checking ? 'Checking…' : 'Continue'),
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
