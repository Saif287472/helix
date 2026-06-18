part of 'chat_screen.dart';

mixin _ChatMessageActionsMixin on _ChatScreenBase {
  // ---------------------------------------------------------------------------
  // Verify identity — safety number bottom sheet
  // ---------------------------------------------------------------------------

  void _showVerifyIdentitySheet(ChatThread thread) {
    final ownFp =
        ref.read(profileServiceProvider).identity?.staticPublicKeyFingerprint ??
        '';
    final peerFp = thread.peerStaticKeyFingerprint;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _VerifyIdentitySheet(
        ownFingerprintRaw: ownFp,
        peerFingerprint: peerFp,
        peerDisplayName: thread.peerDisplayName,
        peerDeviceSuffix: thread.peerDeviceSuffix,
        peerHost: thread.peerHost,
        peerPort: thread.peerPort,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Export thread — AES-256-GCM encrypted, password-derived via Argon2id
  // ---------------------------------------------------------------------------

  Future<void> _exportThread(ChatThread thread) async {
    final passwordCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Set export password'),
        content: TextField(
          controller: passwordCtrl,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Password',
            helperText: 'You will need this to open the exported file.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Export'),
          ),
        ],
      ),
    );
    final password = passwordCtrl.text;
    passwordCtrl.dispose();
    if (confirmed != true || password.isEmpty || !mounted) return;

    final buf = StringBuffer();
    for (final msg in thread.messages) {
      if (msg.isSystem) continue;
      final t = msg.timestamp;
      final timeStr =
          '[${t.hour.toString().padLeft(2, '0')}:'
          '${t.minute.toString().padLeft(2, '0')} '
          '${t.day.toString().padLeft(2, '0')}/'
          '${t.month.toString().padLeft(2, '0')}/'
          '${t.year}]';
      final sender = msg.origin == MessageOrigin.local
          ? 'You'
          : thread.peerDisplayName;
      if (msg.isDeleted) {
        buf.writeln('$timeStr $sender: (deleted)');
      } else if (msg.isFile) {
        buf.writeln(
          '$timeStr $sender: [File: ${msg.fileName ?? 'unknown'} (${msg.mimeType ?? 'application/octet-stream'})]',
        );
      } else {
        buf.writeln('$timeStr $sender: ${msg.text}');
      }
    }
    final plaintext = utf8.encode(buf.toString());

    final rng = math.Random.secure();
    final salt = Uint8List.fromList(
      List<int>.generate(kSaltBytes, (_) => rng.nextInt(256)),
    );
    final argon2 = crypto.Argon2id(
      memory: kArgon2Memory,
      parallelism: kArgon2Parallelism,
      iterations: kArgon2Time,
      hashLength: kArgon2HashLength,
    );
    final derivedKey = await argon2.deriveKey(
      secretKey: crypto.SecretKey(utf8.encode(password)),
      nonce: salt,
    );

    final aesGcm = crypto.AesGcm.with256bits();
    final nonce = aesGcm.newNonce();
    final secretBox = await aesGcm.encrypt(
      plaintext,
      secretKey: derivedKey,
      nonce: nonce,
    );

    final output = BytesBuilder(copy: false);
    output.add(salt);
    output.add(nonce);
    output.add(secretBox.cipherText);
    output.add(secretBox.mac.bytes);

    final dir = await getTemporaryDirectory();
    final safeName = thread.peerDisplayName.replaceAll(RegExp(r'\W'), '_');
    final file = File('${dir.path}/helix_${safeName}_export.whis');
    await file.writeAsBytes(output.toBytes());
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/octet-stream')],
        subject: 'Encrypted chat export — ${thread.peerDisplayName}',
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Context menu
  // ---------------------------------------------------------------------------

  void _showContextMenu(ChatMessage message) {
    final isLocal = message.origin == MessageOrigin.local;
    final copyEnabled =
        ref.read(profileServiceProvider).profile?.copyEnabled ?? false;
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.reply),
              title: const Text('Reply'),
              onTap: () {
                Navigator.pop(ctx);
                setState(() => _replyTo = message);
                _focusNode.requestFocus();
              },
            ),
            ListTile(
              leading: const Icon(Icons.add_reaction_outlined),
              title: const Text('React'),
              onTap: () {
                Navigator.pop(ctx);
                _showEmojiPicker(message);
              },
            ),
            if (isLocal && !message.isDeleted && !message.isFile)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showEditDialog(message);
                },
              ),
            if (isLocal && !message.isDeleted)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text(
                  'Delete',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  ref
                      .read(messagingServiceProvider)
                      .deleteMessage(widget.threadId, message.messageId);
                },
              ),
            if (copyEnabled && !message.isDeleted && !message.isFile)
              ListTile(
                leading: const Icon(Icons.copy_outlined),
                title: const Text('Copy'),
                onTap: () {
                  Navigator.pop(ctx);
                  _copyWithWarning(message.text);
                },
              ),
            ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: const Text('Select'),
              onTap: () {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Message selected. Multi-select coming soon.',
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showEmojiPicker(ChatMessage message) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: _kReactionEmoji.map((emoji) {
              final myReactions = message.reactions[emoji] ?? {};
              final alreadyReacted = myReactions.contains(MessageOrigin.local);
              return GestureDetector(
                onTap: () {
                  Navigator.pop(ctx);
                  ref
                      .read(messagingServiceProvider)
                      .sendReaction(
                        widget.threadId,
                        message.messageId,
                        emoji,
                        remove: alreadyReacted,
                      );
                },
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: alreadyReacted
                        ? Theme.of(context).colorScheme.primary.withAlpha(40)
                        : Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                    border: alreadyReacted
                        ? Border.all(
                            color: Theme.of(context).colorScheme.primary,
                          )
                        : null,
                  ),
                  child: Text(emoji, style: const TextStyle(fontSize: 28)),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  void _showEditDialog(ChatMessage message) {
    final ctrl = TextEditingController(text: message.text);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit message'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 6,
          minLines: 1,
          decoration: const InputDecoration(hintText: 'Edit your message…'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final newText = ctrl.text.trim();
              Navigator.pop(ctx);
              if (newText.isNotEmpty && newText != message.text) {
                ref
                    .read(messagingServiceProvider)
                    .editMessage(widget.threadId, message.messageId, newText);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Clipboard copy (with warning)
  // ---------------------------------------------------------------------------

  Future<void> _copyWithWarning(String text) async {
    final confirmed = await _showConfirmDialog(
      context,
      title: 'Copy to clipboard?',
      body:
          'Clipboard contents may be read by other apps. '
          'Helix will attempt to clear the clipboard after 30 seconds.',
      confirmLabel: 'Copy',
      destructive: false,
    );
    if (!confirmed) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Copied. Will clear in 30 seconds.')),
      );
    }
    Timer(const Duration(seconds: 30), () async {
      final current = await Clipboard.getData(Clipboard.kTextPlain);
      if (current?.text == text) {
        await Clipboard.setData(const ClipboardData(text: ''));
      }
    });
  }
}
