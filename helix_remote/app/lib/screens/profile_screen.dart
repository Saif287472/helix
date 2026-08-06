import 'package:helix_remote_ui/helix_remote_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:helix_remote/app/composition_root.dart';
import 'package:helix_remote/app/remote_account_validation.dart';
import 'package:helix_remote/app/remote_error_copy.dart';
import 'package:helix_remote/app/remote_messaging_service.dart';
import 'package:helix_remote/app/remote_rest_client.dart';

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
  bool _savingName = false;
  String? _nameError;

  @override
  void initState() {
    super.initState();
    _displayNameCtrl = TextEditingController(
      text: widget.messagingService.currentDisplayName ?? '',
    );
  }

  @override
  void dispose() {
    _displayNameCtrl.dispose();
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
    } catch (e) {
      if (mounted) {
        setState(
          () => _nameError = e is RemoteRestException
              ? RemoteUserErrorCopy.profileUpdateFailure(e)
              : 'Could not save. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _savingName = false);
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
        padding: HelixInsets.all(24),
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
                    // The rate-limit message ("...once every 30 days. Try
                    // again on <date>.") is longer than a plain validation
                    // label - errorMaxLines defaults to null, which
                    // truncates to one line with an ellipsis instead of
                    // wrapping (see the phone field's identical fix).
                    errorMaxLines: 3,
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

          // Account ID (read-only)
          Text('Account ID', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Container(
            padding: HelixInsets.symmetric(horizontal: 12, vertical: 14),
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
