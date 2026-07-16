part of 'chat_screen.dart';

mixin _ChatComposerMixin on _ChatScreenBase {
  // ---------------------------------------------------------------------------
  // Typing indicator
  // ---------------------------------------------------------------------------

  void _onTextChanged(String text) {
    setState(() {});
    final messaging = ref.read(messagingServiceProvider);
    final profile = ref.read(profileServiceProvider).profile;
    if (profile?.typingIndicatorsEnabled != true) return;
    if (text.isNotEmpty && !_typingSent) {
      _typingSent = true;
      messaging.sendTyping(widget.threadId, isTyping: true);
    }
    _typingDebounce?.cancel();
    _typingDebounce = Timer(const Duration(seconds: 2), () {
      if (_typingSent) {
        _typingSent = false;
        messaging.sendTyping(widget.threadId, isTyping: false);
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Send
  // ---------------------------------------------------------------------------

  Future<void> _sendMessage(ChatThread thread) async {
    final text = _textController.text.trim();
    if (text.isEmpty || thread.status != ThreadStatus.active) return;
    _typingDebounce?.cancel();
    if (_typingSent) {
      _typingSent = false;
      ref
          .read(messagingServiceProvider)
          .sendTyping(widget.threadId, isTyping: false);
    }
    setState(() => _sending = true);
    final replyId = _replyTo?.messageId;
    _textController.clear();
    setState(() => _replyTo = null);
    try {
      await ref
          .read(messagingServiceProvider)
          .sendMessage(widget.threadId, text, replyToMessageId: replyId);
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Send failed: $e')));
        _textController.text = text;
        _textController.selection = TextSelection.collapsed(
          offset: _textController.text.length,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
        _refocusComposer();
      }
    }
  }

  // ---------------------------------------------------------------------------
  // File transfer
  // ---------------------------------------------------------------------------

  // ignore: unused_element
  Future<void> _pickAndSendFile(ChatThread thread) async {
    if (thread.status != ThreadStatus.active) return;
    final result = await FilePicker.pickFiles();
    if (!mounted || result == null || result.files.isEmpty) return;
    final picked = result.files.first;
    final path = picked.path;
    if (path == null) return;
    final file = File(path);
    final mimeType = _guessMime(picked.name);
    final fileSize = await file.length();
    if (!mounted) return;
    final messaging = ref.read(messagingServiceProvider);
    final channel = messaging.getChannel(widget.threadId);
    if (channel == null) return;
    const uuid = Uuid();
    final fileId = uuid.v4();
    final messageId = messaging.addFileMessage(
      threadId: widget.threadId,
      origin: MessageOrigin.local,
      fileId: fileId,
      fileName: picked.name,
      mimeType: mimeType,
      fileSize: fileSize,
      localFilePath: path,
    );
    _scrollToBottom();
    try {
      await ref
          .read(fileTransferServiceProvider)
          .sendFile(
            threadId: widget.threadId,
            messageId: messageId,
            fileId: fileId,
            file: file,
            mimeType: mimeType,
            channel: channel,
          );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('File send failed: $e')));
      }
    }
  }

  Future<void> _pickAndSendPrivateMediaNow(ChatThread thread) async {
    if (thread.status != ThreadStatus.active) return;
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const [
        'jpg',
        'jpeg',
        'png',
        'webp',
        'aac',
        'm4a',
        'opus',
        'ogg',
      ],
    );
    if (!mounted || result == null || result.files.isEmpty) return;
    final picked = result.files.first;
    final path = picked.path;
    if (path == null) return;
    final messaging = ref.read(messagingServiceProvider);
    final channel = messaging.getChannel(widget.threadId);
    if (channel == null) return;
    if (!channel.supportsCapability(kCapEphemeralMedia)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This peer does not support private media yet.'),
          ),
        );
      }
      return;
    }
    final service = ref.read(ephemeralMediaServiceProvider);
    final file = File(path);
    final mimeType = _guessMime(picked.name);
    final raw = await file.readAsBytes();
    if (!mounted) return;
    Uint8List prepared;
    try {
      if (mimeType.startsWith('image/')) {
        prepared = await service.prepareImage(raw);
        if (prepared.length > kEphemeralImageMaxBytes) {
          throw ArgumentError('Image is too large for private media.');
        }
      } else if (mimeType.startsWith('audio/')) {
        prepared = service.prepareVoice(raw);
      } else {
        throw ArgumentError('Private media supports images and voice notes.');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Private media failed: $e')));
      }
      return;
    }
    final mediaId = EphemeralMediaService.generateMediaId();
    final messageId = messaging.addFileMessage(
      threadId: widget.threadId,
      origin: MessageOrigin.local,
      fileId: mediaId,
      fileName: picked.name,
      mimeType: mimeType,
      fileSize: prepared.length,
      isEphemeral: true,
    );
    if (messageId.isEmpty) return;
    _scrollToBottom();
    try {
      await service.sendMedia(
        mediaId: mediaId,
        mimeType: mimeType,
        prepared: prepared,
        channel: channel,
        threadId: widget.threadId,
        messageId: messageId,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Private media send failed: $e')),
        );
      }
    }
  }

  static String _guessMime(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    return switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'aac' || 'm4a' => 'audio/aac',
      'opus' => 'audio/opus',
      'ogg' => 'audio/ogg',
      'pdf' => 'application/pdf',
      _ => 'application/octet-stream',
    };
  }

  // ---------------------------------------------------------------------------
  // Read receipts
  // ---------------------------------------------------------------------------

  void _sendReadReceipts(ChatThread thread) {
    final profile = ref.read(profileServiceProvider).profile;
    if (profile?.readReceiptsEnabled != true) return;
    final ids = thread.messages
        .where(
          (m) =>
              m.origin == MessageOrigin.remote &&
              m.deliveryStatus != MessageDeliveryStatus.read,
        )
        .map((m) => m.messageId)
        .toList();
    if (ids.isEmpty) return;
    ref.read(messagingServiceProvider).sendReadReceipt(widget.threadId, ids);
  }
}
