import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:helix_remote/features/conversation/application/composer_notifier.dart';
import 'package:helix_remote/features/conversation/application/conversation_header.dart';
import 'package:helix_remote/features/conversation/presentation/emoji_panel.dart';
import 'package:helix_remote/shared/navigation/chat_locations.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// The composer of a conversation: the text field with its reply / edit
/// banner, mention suggestions, an emoji panel, the attach sheet and the
/// voice-note gestures. The text lives in a controller owned here; everything
/// else goes through [composerProvider].
class ComposerBar extends ConsumerStatefulWidget {
  const ComposerBar({super.key, required this.conversationId});

  final String conversationId;

  @override
  ConsumerState<ComposerBar> createState() => ComposerBarState();
}

class ComposerBarState extends ConsumerState<ComposerBar>
    with WidgetsBindingObserver {
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode();
  bool _emojiOpen = false;
  bool _draftLoaded = false;

  /// Replace the field's text (an edit starts with the message's text).
  void setText(String value) {
    _text.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    _focus.requestFocus();
  }

  /// Put the cursor in the field (a reply was started).
  void focus() => _focus.requestFocus();

  // Kept in a field: `ref` cannot be used from `dispose`.
  late final ComposerNotifier _notifier;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _notifier = ref.read(composerProvider(widget.conversationId).notifier);
    _focus.addListener(() {
      if (_focus.hasFocus && _emojiOpen) setState(() => _emojiOpen = false);
    });
  }

  /// A recording cannot continue behind the app: a held one is dropped, a
  /// locked one waits until the person is back.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        unawaited(_notifier.appBackgrounded());
      case AppLifecycleState.resumed:
        unawaited(_notifier.appResumed());
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // The draft is saved even if the person leaves in the middle of typing.
    _notifier.flushDraft(_text.text);
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  ComposerNotifier get _composer =>
      ref.read(composerProvider(widget.conversationId).notifier);

  Future<void> _send() async {
    final text = _text.text;
    final sent = await _composer.send(text);
    if (sent && mounted) _text.clear();
  }

  void _changed(String text) =>
      _composer.onChanged(text, _text.selection.baseOffset);

  void _insertEmoji(String emoji) {
    final value = _text.value;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : value.text.length;
    final next = value.text.replaceRange(start, end, emoji);
    _text.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + emoji.length),
    );
    _changed(next);
  }

  /// The attach sheet: the person picks a source, then the files.
  Future<void> _attach() async {
    final id = await showHelixAttachmentSheet(
      context,
      options: _attachmentOptions(),
    );
    if (!mounted) return;
    final source = switch (id) {
      'document' => AttachmentSource.document,
      'camera' => await _chooseCamera(),
      'gallery' => AttachmentSource.gallery,
      'audio' => AttachmentSource.audio,
      _ => null,
    };
    if (source != null) await _pickFrom(source);
  }

  /// The camera shortcut in the field: photo or video, then the camera.
  Future<void> _openCamera() async {
    final source = await _chooseCamera();
    if (source != null) await _pickFrom(source);
  }

  Future<AttachmentSource?> _chooseCamera() {
    return showModalBottomSheet<AttachmentSource>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () =>
                  Navigator.of(sheet).pop(AttachmentSource.cameraPhoto),
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: const Text('Record a video'),
              onTap: () =>
                  Navigator.of(sheet).pop(AttachmentSource.cameraVideo),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickFrom(AttachmentSource source) async {
    final files = await _composer.pick(source);
    if (files.isEmpty || !mounted) return;
    ref
        .read(pendingAttachmentsProvider(widget.conversationId).notifier)
        .set(files);
    await context.push(sendFilesLocation(widget.conversationId));
  }

  List<HelixAttachmentOption> _attachmentOptions() => [
    for (final option in helixDefaultAttachmentOptions)
      if (const {'document', 'camera', 'gallery', 'audio'}.contains(option.id))
        option,
  ];

  @override
  Widget build(BuildContext context) {
    final id = widget.conversationId;
    final state = ref.watch(composerProvider(id));
    final header = ref.watch(conversationHeaderProvider(id));
    if (!_draftLoaded) {
      final draft = ref.watch(composerDraftProvider(id));
      if (draft.hasValue) {
        _draftLoaded = true;
        if (_text.text.isEmpty && draft.requireValue.isNotEmpty) {
          _text.text = draft.requireValue;
        }
      }
    }
    ref.listen(composerProvider(id).select((s) => s.noticeSerial), (_, _) {
      final notice = ref.read(composerProvider(id)).notice;
      if (notice != null && mounted) showHelixSnackBar(context, notice);
    });

    final reply = state.reply;
    final edit = state.edit;
    final target = edit ?? reply;
    final banner = target == null
        ? null
        : HelixComposerBannerModel(
            kind: edit != null
                ? HelixComposerBannerKind.edit
                : HelixComposerBannerKind.reply,
            title: edit != null
                ? 'Edit message'
                : 'Replying to ${target.authorName}',
            text: target.text,
            previewKind: target.kind,
          );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        HelixComposer(
          controller: _text,
          focusNode: _focus,
          onSend: _send,
          hint: 'Message',
          banner: banner,
          onBannerClose: () {
            if (edit != null) _text.clear();
            _composer.cancelTarget();
          },
          editing: edit != null,
          onEmoji: () {
            if (_emojiOpen) {
              setState(() => _emojiOpen = false);
              _focus.requestFocus();
            } else {
              _focus.unfocus();
              SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
              setState(() => _emojiOpen = true);
            }
          },
          onAttach: () => _attach(),
          onCamera: _openCamera,
          onChanged: _changed,
          mentionCandidates: state.mentionCandidates,
          onMentionSelected: (candidate) {
            final inserted = _composer.pickMention(
              candidate,
              _text.text,
              _text.selection.baseOffset,
            );
            _text.value = TextEditingValue(
              text: inserted.text,
              selection: TextSelection.collapsed(offset: inserted.cursor),
            );
          },
          recording: state.recording,
          mic: HelixMicButton(
            onTap: () => showHelixSnackBar(
              context,
              'Hold the microphone to record a voice message.',
            ),
            onStart: _composer.startVoice,
            onSlide: _composer.slideVoice,
            onLock: _composer.lockVoice,
            onCancel: () => _composer.endVoice(send: false),
            onEnd: () => _composer.endVoice(send: true),
          ),
          onRecordingCancel: () => _composer.endVoice(send: false),
          onRecordingSend: () => _composer.endVoice(send: true),
          disabledMessage: header?.composerDisabledReason,
        ),
        if (_emojiOpen)
          ColoredBox(
            color: Theme.of(context).colorScheme.surface,
            child: EmojiPanel(onPick: _insertEmoji),
          ),
      ],
    );
  }
}
