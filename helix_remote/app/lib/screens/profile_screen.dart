import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:helix_remote/app/composition_root.dart';
import 'package:helix_remote/app/remote_account_validation.dart';
import 'package:helix_remote/app/remote_messaging_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.root,
    required this.messagingService,
  });
  final RemoteCompositionRoot root;
  final RemoteMessagingService messagingService;
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final TextEditingController _displayNameCtrl;
  late final TextEditingController _usernameCtrl;
  bool _savingName = false;
  bool _savingUsername = false;
  String? _nameError;
  String? _usernameError;

  @override
  void initState() {
    super.initState();
    _displayNameCtrl = TextEditingController(
      text: widget.messagingService.currentDisplayName ?? '',
    );
    _usernameCtrl = TextEditingController(
      text: widget.messagingService.currentUsername ?? '',
    );
  }

  @override
  void dispose() {
    _displayNameCtrl.dispose();
    _usernameCtrl.dispose();
    super.dispose();
  }

  String get _accountId => widget.messagingService.currentAccountId ?? '';

  Future<void> _saveDisplayName() async {
    final name = RemoteAccountValidation.normalizeDisplayName(
      _displayNameCtrl.text,
    );
    final error = RemoteAccountValidation.displayNameError(name);
    if (error != null) {
      setState(() => _nameError = error);
      return;
    }
    setState(() {
      _savingName = true;
      _nameError = null;
    });
    try {
      await widget.root.restClient.updateDisplayName(name);
      widget.messagingService.setDisplayName(name);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Display name updated')));
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _nameError =
              'Could not save. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _savingName = false);
    }
  }

  Future<void> _saveUsername() async {
    final name = RemoteAccountValidation.normalizeUsername(_usernameCtrl.text);
    final error = RemoteAccountValidation.usernameError(name);
    if (error != null) {
      setState(() => _usernameError = error);
      return;
    }
    setState(() {
      _savingUsername = true;
      _usernameError = null;
    });
    try {
      await widget.root.restClient.changeUsername(name);
      if (mounted) {
        _usernameCtrl.text = name;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Username updated')));
        setState(() {});
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _usernameError =
              'Could not save. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _savingUsername = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final displayName = widget.messagingService.currentDisplayName ?? '';
    final initials = displayName.isNotEmpty
        ? displayName.substring(0, displayName.length.clamp(1, 2)).toUpperCase()
        : '?';

    return Scaffold(
      appBar: AppBar(
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        title: Text(
          'Profile',
          style: TextStyle(color: cs.onPrimary, fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // Avatar
          Center(
            child: CircleAvatar(
              radius: 48,
              backgroundColor: cs.primary,
              child: Text(
                initials,
                style: TextStyle(
                  color: cs.onPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 32),

          // Display name
          Text('Display name', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _displayNameCtrl,
                  decoration: InputDecoration(
                    hintText: 'Your name shown to contacts',
                    border: const OutlineInputBorder(),
                    errorText: _nameError,
                  ),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _saveDisplayName(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _savingName ? null : _saveDisplayName,
                child: _savingName
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save'),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Username
          Text('Username', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _usernameCtrl,
                  decoration: InputDecoration(
                    hintText: 'Used for search',
                    prefixText: '@',
                    border: const OutlineInputBorder(),
                    helperText: RemoteAccountValidation.usernameRules,
                    errorText: _usernameError,
                  ),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _saveUsername(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _savingUsername ? null : _saveUsername,
                child: _savingUsername
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save'),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Account ID (read-only)
          Text('Account ID', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              border: Border.all(color: cs.outlineVariant),
              borderRadius: BorderRadius.circular(4),
              color: cs.surfaceContainerHighest,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _accountId,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, size: 18),
                  tooltip: 'Copy account ID',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _accountId));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Account ID copied')),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Share your account ID with others so they can add you as a contact.',
            style: theme.textTheme.bodySmall?.copyWith(color: cs.outline),
          ),
        ],
      ),
    );
  }
}
