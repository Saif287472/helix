import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/features/conversation/application/composer_notifier.dart';
import 'package:helix_remote/features/conversation/application/send_preview.dart';
import 'package:orbit_ui/orbit_ui.dart' as orbit;

/// Connector: what the person is about to send, the picked photos, videos
/// and files, a caption and, for photos and videos, "view once", drawn by
/// `orbit_ui`'s send-files page.
///
/// The files are not copied until Send is pressed. Leaving without sending
/// deletes the camera's files; their own files are never touched.
class SendFilesScreen extends ConsumerStatefulWidget {
  const SendFilesScreen({super.key, required this.conversationId});

  final String conversationId;

  @override
  ConsumerState<SendFilesScreen> createState() => _SendFilesScreenState();
}

class _SendFilesScreenState extends ConsumerState<SendFilesScreen> {
  bool _sent = false;

  /// The files as last drawn: once sent, the page keeps them while it
  /// closes.
  List<AttachmentDraft> _files = const [];

  // Kept in a field: `ref` cannot be used from `dispose`.
  late final PendingAttachments _pending;

  @override
  void initState() {
    super.initState();
    _pending = ref.read(
      pendingAttachmentsProvider(widget.conversationId).notifier,
    );
  }

  @override
  void dispose() {
    // Backing out without sending: the camera's files are not kept.
    if (!_sent) unawaited(_pending.discard());
    super.dispose();
  }

  Future<bool> _send({required String caption, required bool viewOnce}) async {
    final files = ref.read(pendingAttachmentsProvider(widget.conversationId));
    final sent = await ref
        .read(composerProvider(widget.conversationId).notifier)
        .sendFiles(files, caption: caption, viewOnce: viewOnce);
    if (sent) {
      _sent = true;
      _pending.set(const []);
    }
    return sent;
  }

  static orbit.SendFileKind _kindOf(DraftKind kind) => switch (kind) {
    DraftKind.image => orbit.SendFileKind.image,
    DraftKind.video => orbit.SendFileKind.video,
    DraftKind.audio => orbit.SendFileKind.audio,
    DraftKind.document => orbit.SendFileKind.document,
  };

  @override
  Widget build(BuildContext context) {
    final files = ref.watch(pendingAttachmentsProvider(widget.conversationId));
    if (!_sent) _files = files;
    return orbit.SendFilesScreen(
      model: orbit.SendFilesModel(
        files: [
          for (final f in _files)
            orbit.SendFileItem(
              id: f.path,
              name: f.name,
              sizeLabel: f.sizeLabel,
              kind: _kindOf(f.kind),
              preview: switch (f.kind) {
                DraftKind.image => photoPreviewOf(f),
                DraftKind.video => ref.watch(videoStillProvider(f.path)).value,
                _ => null,
              },
            ),
        ],
      ),
      actions: orbit.SendFilesActions(
        onRemove: (id) {
          final file = _files.where((f) => f.path == id).firstOrNull;
          if (file != null) _pending.remove(file);
        },
        onSend: _send,
      ),
    );
  }
}
