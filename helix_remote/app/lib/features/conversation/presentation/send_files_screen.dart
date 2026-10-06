import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/features/conversation/application/composer_notifier.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// What the person is about to send: the picked photos, videos and files, a
/// caption and, for photos and videos, "view once".
///
/// The files are not copied until Send is pressed.
class SendFilesScreen extends ConsumerStatefulWidget {
  const SendFilesScreen({super.key, required this.conversationId});

  final String conversationId;

  @override
  ConsumerState<SendFilesScreen> createState() => _SendFilesScreenState();
}

class _SendFilesScreenState extends ConsumerState<SendFilesScreen> {
  final TextEditingController _caption = TextEditingController();
  bool _viewOnce = false;
  bool _sending = false;
  bool _sent = false;

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
    _caption.dispose();
    // Backing out without sending: the camera's files are not kept.
    if (!_sent) _pending.discard();
    super.dispose();
  }

  Future<void> _send() async {
    final files = ref.read(pendingAttachmentsProvider(widget.conversationId));
    setState(() => _sending = true);
    final sent = await ref
        .read(composerProvider(widget.conversationId).notifier)
        .sendFiles(files, caption: _caption.text, viewOnce: _viewOnce);
    if (!mounted) return;
    if (sent) {
      _sent = true;
      _pending.set(const []);
      Navigator.of(context).pop();
    } else {
      setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final files = ref.watch(pendingAttachmentsProvider(widget.conversationId));
    final visual = files.any(
      (f) => f.kind == DraftKind.image || f.kind == DraftKind.video,
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(
          files.length == 1 ? 'Send file' : 'Send ${files.length} files',
        ),
      ),
      body: files.isEmpty
          ? const HelixEmptyState(
              icon: Icons.attach_file,
              title: 'Nothing to send',
              message: 'Go back and pick a file.',
            )
          : Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(HelixSpace.sm),
                    itemCount: files.length,
                    itemBuilder: (context, index) {
                      final file = files[index];
                      return ListTile(
                        key: ValueKey(file.path),
                        leading: SizedBox.square(
                          dimension: 48,
                          child: file.kind == DraftKind.image
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: Image.file(
                                    File(file.path),
                                    fit: BoxFit.cover,
                                    cacheWidth: 144,
                                    excludeFromSemantics: true,
                                    errorBuilder: (_, _, _) =>
                                        const Icon(Icons.image_outlined),
                                  ),
                                )
                              : Icon(switch (file.kind) {
                                  DraftKind.video => Icons.videocam_outlined,
                                  DraftKind.audio => Icons.headphones,
                                  _ => Icons.insert_drive_file_outlined,
                                }),
                        ),
                        title: Text(
                          file.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(file.sizeLabel),
                        trailing: IconButton(
                          icon: const Icon(Icons.close),
                          tooltip: 'Remove ${file.name}',
                          onPressed: () => _pending.remove(file),
                        ),
                      );
                    },
                  ),
                ),
                if (visual)
                  SwitchListTile(
                    value: _viewOnce,
                    onChanged: (value) => setState(() => _viewOnce = value),
                    secondary: const Icon(Icons.filter_1_outlined),
                    title: const Text('View once'),
                    subtitle: const Text(
                      'Photos and videos disappear after they are opened.',
                    ),
                  ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.all(HelixSpace.sm),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _caption,
                            minLines: 1,
                            maxLines: 4,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: const InputDecoration(
                              hintText: 'Add a caption',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: HelixSpace.xs),
                        IconButton.filled(
                          icon: const Icon(Icons.send),
                          tooltip: 'Send',
                          onPressed: _sending ? null : _send,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
