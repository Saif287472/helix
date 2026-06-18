part of 'chat_screen.dart';

// ---------------------------------------------------------------------------
// Verify Identity bottom sheet
// ---------------------------------------------------------------------------

class _VerifyIdentitySheet extends ConsumerStatefulWidget {
  const _VerifyIdentitySheet({
    required this.ownFingerprintRaw,
    required this.peerFingerprint,
    required this.peerDisplayName,
    required this.peerDeviceSuffix,
    required this.peerHost,
    required this.peerPort,
  });

  final String ownFingerprintRaw;
  final String peerFingerprint;
  final String peerDisplayName;
  final String peerDeviceSuffix;
  final String peerHost;
  final int peerPort;

  @override
  ConsumerState<_VerifyIdentitySheet> createState() =>
      _VerifyIdentitySheetState();
}

class _VerifyIdentitySheetState extends ConsumerState<_VerifyIdentitySheet> {
  Future<String?> _showTrustDialog() async {
    final ctrl = TextEditingController(text: widget.peerDisplayName);
    final result = await showDialog<String>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Text('Trust this device'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'The safety phrase confirms ${widget.peerDisplayName}\'s '
              'cryptographic identity — it cannot be spoofed by someone '
              'who only knows your secret sentence. '
              'Give this device a private nickname:',
              style: Theme.of(dCtx).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Nickname',
                helperText:
                    'Only you can see this — replaces their display name.',
              ),
              onSubmitted: (_) => Navigator.of(dCtx).pop(ctrl.text),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dCtx).pop(null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dCtx).pop(ctrl.text),
            child: const Text('Trust'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return result;
  }

  Future<String?> _showNicknameDialog(String initial) async {
    final ctrl = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Text('Rename device'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Nickname',
            helperText: 'Only you can see this name.',
          ),
          onSubmitted: (_) => Navigator.of(dCtx).pop(ctrl.text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dCtx).pop(null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dCtx).pop(ctrl.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final knownPeers = ref.watch(knownPeersProvider).value ?? const [];
    final trust = ref.read(trustServiceProvider);
    final fp = widget.peerFingerprint;

    final trustedEntry = knownPeers
        .where((p) => p.fingerprint == fp && p.trusted)
        .firstOrNull;
    final isTrusted = trustedEntry != null;

    final phrase = buildVerificationPhrase(widget.ownFingerprintRaw, fp);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Icon(
                Icons.verified_user_outlined,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Text(
                'Verify identity',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Call ${widget.peerDisplayName} and read this phrase aloud. '
            'Matching words confirm cryptographic identity — your secret '
            'sentence helps you find each other, but only this phrase '
            'proves who you\'re talking to.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withAlpha(160),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withAlpha(80),
              border: Border.all(
                color: theme.colorScheme.primary.withAlpha(60),
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Safety phrase',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        phrase,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                          height: 1.4,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy_outlined, size: 18),
                      tooltip: 'Copy phrase',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: phrase));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Phrase copied to clipboard'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 8),
          const SizedBox(height: 8),
          if (isTrusted) ...[
            Row(
              children: [
                const Icon(Icons.verified_user, size: 16, color: Colors.teal),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Trusted as "${trustedEntry.nickname}"',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.teal,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    final nick = await _showNicknameDialog(
                      trustedEntry.nickname ?? widget.peerDisplayName,
                    );
                    if (nick != null && nick.trim().isNotEmpty && mounted) {
                      await trust.renamePeer(fp, nick.trim());
                    }
                  },
                  child: const Text('Rename'),
                ),
                TextButton(
                  onPressed: () async {
                    await trust.untrustPeer(fp);
                  },
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  child: const Text('Remove trust'),
                ),
              ],
            ),
          ] else ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.verified_user_outlined, size: 16),
                label: const Text('Trust this device'),
                onPressed: () async {
                  final nav = Navigator.of(context);
                  final nick = await _showTrustDialog();
                  if (nick == null || nick.trim().isEmpty || !mounted) return;
                  if (!trust.isKnown(fp)) {
                    await trust.markKnown(
                      fp,
                      widget.peerDisplayName,
                      widget.peerDeviceSuffix,
                      widget.peerHost,
                      widget.peerPort,
                    );
                  }
                  if (!mounted) return;
                  await trust.trustPeer(fp, nick.trim());
                  // Pop before the stream fires to avoid rebuilding a
                  // disposing widget.
                  nav.pop();
                },
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Trusting saves this device\'s cryptographic identity with '
              'a private nickname — visible only to you.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withAlpha(120),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}
