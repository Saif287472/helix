import 'package:flutter/material.dart';
import 'package:helix_remote/app/remote_account_validation.dart';
import 'package:helix_remote/app/remote_config.dart';
import 'package:helix_remote/app/remote_rest_client.dart';
import 'package:helix_remote/widgets/country_code_picker.dart';

/// Result of successfully validating a personal server + invite combo, with
/// the phone number collected alongside it on the same screen.
class ServerInviteChoice {
  const ServerInviteChoice({
    required this.serverUrl,
    required this.inviteCode,
    this.phoneNumber,
    this.serverName,
  });

  final String serverUrl;
  final String inviteCode;

  /// Display name the server's admin chose, when they set one. Null means
  /// unnamed, and the server is identified by its address instead.
  final String? serverName;

  /// E.164 phone number, or null for the Helix Global path (which doesn't
  /// collect one here - there's no "which server" step to attach it to).
  final String? phoneNumber;
}

/// "Personal server" first-launch path: the admin who invited you shares a
/// single combined `<server_address>/join?invite=<code>` link, and this is
/// also the only screen that ever needs to ask "which server" - so the
/// phone number is collected here too, rather than asking for the invite
/// code a second time on a later screen.
class InviteEntryScreen extends StatefulWidget {
  const InviteEntryScreen({super.key});

  @override
  State<InviteEntryScreen> createState() => _InviteEntryScreenState();
}

class _InviteEntryScreenState extends State<InviteEntryScreen> {
  final _linkController = TextEditingController();
  final _nationalNumberController = TextEditingController();
  Country _selectedCountry = kDefaultCountry;
  bool _checking = false;
  String? _error;
  String? _phoneError;

  @override
  void dispose() {
    _linkController.dispose();
    _nationalNumberController.dispose();
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

  /// Combines [_selectedCountry]'s dial code with the entered national
  /// digits into an E.164 number, stripping a leading `0` (the common
  /// local-dialing prefix, e.g. "01712345678") that must not appear after
  /// the country code.
  String get _phoneNumber {
    final digits = _nationalNumberController.text.replaceAll(
      RegExp(r'[^\d]'),
      '',
    );
    final national = digits.startsWith('0') ? digits.substring(1) : digits;
    return '${_selectedCountry.dialCode}$national';
  }

  Future<void> _continue() async {
    if (_checking) return;
    final parsed = _parse(_linkController.text);
    final phoneNumber = _phoneNumber;
    final phoneError = RemoteAccountValidation.phoneNumberError(phoneNumber);
    if (parsed == null || phoneError != null) {
      setState(() {
        _error = parsed == null
            ? 'Paste the full link your admin shared, e.g. '
                  'https://your-server.example/join?invite=CODE.'
            : null;
        _phoneError = phoneError;
      });
      return;
    }

    setState(() {
      _checking = true;
      _error = null;
      _phoneError = null;
    });

    HelixRemoteRestClientImpl? client;
    try {
      final restBaseUri = RemoteDevelopmentConfig.restBaseUriFromServerUrl(
        parsed.serverUrl,
      );
      client = HelixRemoteRestClientImpl(
        baseUri: restBaseUri,
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
      if (!mounted) return;

      // When the admin has named their server, confirm which one this
      // invite is for before joining - the name is the whole reason they
      // set one, and a link pasted from a chat is worth double-checking.
      // Servers with no name behave exactly as before and join straight
      // through.
      final serverName = (lookup['server_name'] as String? ?? '').trim();
      if (serverName.isNotEmpty) {
        final confirmed = await _confirmJoin(serverName, parsed.serverUrl);
        if (!confirmed || !mounted) return;
      }

      if (mounted) {
        Navigator.of(context).pop(
          ServerInviteChoice(
            serverUrl: parsed.serverUrl,
            inviteCode: parsed.inviteCode,
            phoneNumber: phoneNumber,
            serverName: serverName.isEmpty ? null : serverName,
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

  /// Names the server the invite belongs to and asks the user to confirm.
  Future<bool> _confirmJoin(String serverName, String serverUrl) async {
    final host = Uri.tryParse(serverUrl)?.host ?? serverUrl;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Join this server?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              serverName,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              host,
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(dialogContext).hintColor,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Your invite is for this server. Only continue if you '
              'recognise it.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Join'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
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
                        labelText: 'Server invitation code',
                        hintText:
                            'https://your-server.example/join?invite=CODE',
                        border: const OutlineInputBorder(),
                        errorText: _error,
                        errorMaxLines: 4,
                      ),
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 16),
                    PhoneNumberInput(
                      country: _selectedCountry,
                      onCountryChanged: (country) =>
                          setState(() => _selectedCountry = country),
                      numberController: _nationalNumberController,
                      enabled: !_checking,
                      errorText: _phoneError,
                      errorMaxLines: 3,
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
