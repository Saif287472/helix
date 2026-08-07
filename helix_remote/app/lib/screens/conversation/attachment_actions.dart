part of '../conversation_screen.dart';

extension _ConversationAttachmentActions on _ConversationScreenState {
  // ---------------------------------------------------------------------------
  // Attachment helpers
  // ---------------------------------------------------------------------------

  Future<void> _attachFile({String? initialKind}) async {
    final attachmentService = widget.attachmentService;
    if (attachmentService == null || _attachmentBusy) return;
    String? attachmentId;
    try {
      final selected =
          await (widget.pickAttachmentFile ?? _pickAttachmentFile)();
      if (selected == null) return;
      final options = await _mediaOptionsFor(
        selected,
        initialKind: initialKind,
      );
      if (options == null) return;
      if (!mounted) return;
      _update(() {
        _attachmentBusy = true;
        _attachmentStatus = 'Preparing attachment';
      });

      final prepared = await attachmentService.prepareAttachment(selected);
      attachmentId = prepared['attachment_id'] as String;
      final ciphertextPath = prepared['ciphertext_path'] as String;
      if (!mounted) return;
      _update(() => _attachmentStatus = 'Uploading attachment');

      await attachmentService.uploadAttachment(
        attachmentId: attachmentId,
        ciphertextPath: ciphertextPath,
      );

      final manifest = RemoteAttachmentManifest(
        fileId: attachmentId,
        fileSize: prepared['size_bytes'] as int,
        fileHash: prepared['file_hash'] as String,
        mimeType: _inferMimeType(selected.path),
      );
      if (!mounted) return;
      _update(() => _attachmentStatus = 'Queueing attachment message');
      final messageId = await _model.sendRichMedia(
        kind: options.kind,
        manifest: manifest,
        filename: prepared['filename'] as String,
        keyDeliverySecret: prepared['key_delivery_secret'] as String,
        caption: options.caption,
        viewOnce: options.viewOnce,
      );
      await attachmentService.registerReference(
        fileId: attachmentId,
        messageId: messageId,
      );
      if (!mounted) return;
      _update(() => _attachmentStatus = 'Attachment queued');
      await _loadMessages();
    } catch (e) {
      if (attachmentId != null) {
        widget.attachmentService?.updateAttachmentStatus(
          attachmentId,
          'FAILED',
        );
      }
      if (mounted) {
        _update(() => _attachmentStatus = 'Attachment failed');
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Attachment failed: $e')));
      }
    } finally {
      if (mounted) _update(() => _attachmentBusy = false);
    }
  }

  Future<File?> _pickAttachmentFile() async {
    final file = await FilePicker.pickFile(
      dialogTitle: 'Select attachment',
      lockParentWindow: true,
    );
    final path = file?.path;
    if (path == null || path.isEmpty) return null;
    return File(path);
  }

  Future<_MediaSendOptions?> _mediaOptionsFor(
    File file, {
    String? initialKind,
  }) {
    final inferredKind = _inferMediaKind(file.path);
    var selectedKind = initialKind ?? inferredKind;
    var caption = '';
    var viewOnce = false;
    return showDialog<_MediaSendOptions>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(HelixLocalizations.of(context).sendMedia),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selectedKind,
                  decoration: const InputDecoration(
                    labelText: 'Media type',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'image',
                      child: Text(HelixLocalizations.of(context).image),
                    ),
                    DropdownMenuItem(
                      value: 'video',
                      child: Text(HelixLocalizations.of(context).video),
                    ),
                    DropdownMenuItem(
                      value: 'document',
                      child: Text(HelixLocalizations.of(context).document),
                    ),
                    DropdownMenuItem(
                      value: 'scanner_document',
                      child: Text(
                        HelixLocalizations.of(context).scannedDocument,
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'camera_capture',
                      child: Text(HelixLocalizations.of(context).cameraCapture),
                    ),
                    DropdownMenuItem(
                      value: 'live_photo',
                      child: Text(HelixLocalizations.of(context).livePhoto),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => selectedKind = value);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'Caption',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                  onChanged: (value) => caption = value,
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: viewOnce,
                  onChanged: (value) =>
                      setDialogState(() => viewOnce = value ?? false),
                  title: Text(HelixLocalizations.of(context).viewOnce),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(HelixLocalizations.of(context).cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(
                  ctx,
                  _MediaSendOptions(
                    kind: selectedKind,
                    caption: caption.trim(),
                    viewOnce: viewOnce,
                  ),
                ),
                child: Text(HelixLocalizations.of(context).send),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _downloadAttachment(RemoteAttachmentContent attachment) async {
    final attachmentService = widget.attachmentService;
    if (attachmentService == null || _attachmentBusy) return;
    final proceed = await _confirm(
      title: 'Open attachment?',
      message: RemoteAttachmentSafety.malwareWarningMessage,
      confirmLabel: 'Download',
    );
    if (!proceed) return;
    try {
      _update(() {
        _attachmentBusy = true;
        _attachmentStatus = 'Downloading attachment';
      });
      await attachmentService.importAttachmentKeyFromMessage(
        manifest: attachment.manifest,
        filename: attachment.filename,
        keyDeliverySecret: attachment.keyDeliverySecret,
      );
      await attachmentService.downloadAttachment(
        attachmentId: attachment.fileId,
        savePath: p.join(
          attachmentService.tempDir.path,
          '${attachment.fileId}.download.enc',
        ),
      );
      if (!mounted) return;
      _update(() => _attachmentStatus = 'Attachment downloaded');
      await _refreshVisibleMessages();
    } catch (e) {
      if (mounted) {
        _update(() => _attachmentStatus = 'Attachment download failed');
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Download failed: $e')));
      }
    } finally {
      if (mounted) _update(() => _attachmentBusy = false);
    }
  }

  Future<void> _exportAttachment(RemoteAttachmentContent attachment) async {
    final attachmentService = widget.attachmentService;
    final path = attachment.localPath;
    if (attachmentService == null || path == null || _attachmentBusy) return;
    if (!_model.canExportAttachment(attachment)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            HelixLocalizations.of(context).chatBlocksExternalExport,
          ),
        ),
      );
      return;
    }
    final source = File(path);
    if (!source.existsSync()) return;
    final proceed = await _confirm(
      title: 'Export decrypted file?',
      message: RemoteAttachmentExport.exportWarningMessage,
      confirmLabel: 'Export',
    );
    if (!proceed) return;
    try {
      final exportedPath =
          await (widget.exportAttachmentFile ?? _exportAttachmentFile)(
            attachment,
            source,
          );
      if (exportedPath == null) return;
      attachmentService.markAttachmentExported(
        attachmentId: attachment.fileId,
        exportedPlaintextPath: exportedPath,
      );
      if (!mounted) return;
      _update(() => _attachmentStatus = 'Attachment exported');
      await _refreshVisibleMessages();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }
  }

  Future<String?> _exportAttachmentFile(
    RemoteAttachmentContent attachment,
    File file,
  ) {
    return FilePicker.saveFile(
      dialogTitle: 'Export decrypted attachment',
      fileName: attachment.filename,
      bytes: Uint8List.fromList(file.readAsBytesSync()),
      lockParentWindow: true,
    );
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(HelixLocalizations.of(context).cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  String _inferMimeType(String path) {
    switch (p.extension(path).toLowerCase()) {
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.png':
        return 'image/png';
      case '.gif':
        return 'image/gif';
      case '.pdf':
        return 'application/pdf';
      case '.txt':
        return 'text/plain';
      default:
        return 'application/octet-stream';
    }
  }

  String _inferMediaKind(String path) {
    switch (p.extension(path).toLowerCase()) {
      case '.jpg':
      case '.jpeg':
      case '.png':
      case '.gif':
        return RemoteMediaContent.imageKind;
      case '.mp4':
      case '.mov':
      case '.webm':
        return RemoteMediaContent.videoKind;
      default:
        return RemoteMediaContent.documentKind;
    }
  }
}

class _MediaSendOptions {
  const _MediaSendOptions({
    required this.kind,
    required this.caption,
    required this.viewOnce,
  });

  final String kind;
  final String caption;
  final bool viewOnce;
}
