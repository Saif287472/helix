import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/chat/chat_gateway.dart';
import 'package:helix_remote/core/people/people_names.dart';
import 'package:helix_remote/core/chat/message_semantics.dart';
import 'package:helix_remote/core/format/labels.dart';
import 'package:helix_remote/core/platform/attachment_picker.dart';
import 'package:helix_remote/core/platform/chat_platform.dart';
import 'package:helix_remote/core/platform/media_sanitizer.dart';
import 'package:helix_remote/core/platform/voice_recorder.dart';
import 'package:helix_remote/features/conversation/application/audio_playback.dart';
import 'package:helix_remote/features/conversation/application/conversation_header.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart' show MediaInput;
import 'package:helix_remote_protocol/helix_remote_protocol.dart'
    show Mention, MediaItemKind, MessageRef;
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// What kind of file a picked attachment is, for the preview.
enum DraftKind { image, video, audio, document }

/// A file picked to be sent, as the preview screen shows it.
@immutable
class AttachmentDraft {
  const AttachmentDraft(this.file);

  final PickedFile file;

  String get path => file.path;
  String get name => file.name;
  String get sizeLabel => formatFileSize(file.size);

  DraftKind get kind => switch (file.kind) {
    PickedKind.image => DraftKind.image,
    PickedKind.video => DraftKind.video,
    PickedKind.audio => DraftKind.audio,
    PickedKind.document => DraftKind.document,
  };

  @override
  bool operator ==(Object other) =>
      other is AttachmentDraft && other.file.path == file.path;

  @override
  int get hashCode => file.path.hashCode;
}

/// The message a reply quotes or an edit changes.
@immutable
class ComposerTarget {
  const ComposerTarget({
    required this.rowid,
    required this.messageId,
    required this.author,
    required this.authorName,
    required this.text,
    required this.kind,
  });

  final int rowid;
  final String messageId;

  /// The author's account id (a reply names the message by id and author).
  final String author;
  final String authorName;
  final String text;
  final HelixPreviewKind kind;

  @override
  bool operator ==(Object other) =>
      other is ComposerTarget &&
      other.rowid == rowid &&
      other.text == text &&
      other.authorName == authorName;

  @override
  int get hashCode => Object.hash(rowid, text, authorName);
}

/// The part of the composer that is not the text: the banner, the mention
/// suggestions, the voice-recording overlay and a one-line notice.
///
/// The text itself lives in the screen's `TextEditingController` (the
/// component takes one), so typing never goes through Riverpod.
@immutable
class ComposerState {
  const ComposerState({
    this.reply,
    this.edit,
    this.mentionCandidates = const [],
    this.recording,
    this.notice,
    this.noticeSerial = 0,
  });

  final ComposerTarget? reply;
  final ComposerTarget? edit;
  final List<HelixMentionCandidate> mentionCandidates;
  final HelixVoiceRecordState? recording;

  /// A sentence for a snackbar ("Voice messages are not available on this
  /// device."); never an exception's text.
  final String? notice;

  /// Changes with every notice, so the same sentence can be shown twice.
  final int noticeSerial;

  ComposerState copyWith({
    ComposerTarget? Function()? reply,
    ComposerTarget? Function()? edit,
    List<HelixMentionCandidate>? mentionCandidates,
    HelixVoiceRecordState? Function()? recording,
    String? notice,
  }) => ComposerState(
    reply: reply == null ? this.reply : reply(),
    edit: edit == null ? this.edit : edit(),
    mentionCandidates: mentionCandidates ?? this.mentionCandidates,
    recording: recording == null ? this.recording : recording(),
    notice: notice ?? this.notice,
    noticeSerial: notice == null ? noticeSerial : noticeSerial + 1,
  );
}

/// What was typed before the cursor that may be a mention: the position of
/// the `@` and what follows it.
@immutable
class MentionToken {
  const MentionToken(this.start, this.query);

  final int start;
  final String query;
}

/// The `@name` being typed at [cursor], or null. An `@` counts only at the
/// start of the text or after a space, so an e-mail address is not a mention.
MentionToken? mentionTokenAt(String text, int cursor) {
  if (cursor <= 0 || cursor > text.length) return null;
  var i = cursor - 1;
  while (i >= 0) {
    final c = text[i];
    if (c == '@') {
      final before = i == 0 ? ' ' : text[i - 1];
      if (before.trim().isNotEmpty) return null;
      return MentionToken(i, text.substring(i + 1, cursor));
    }
    if (c.trim().isEmpty) return null;
    i--;
  }
  return null;
}

/// The composer for one conversation: reply and edit state, drafts, mentions,
/// typing indicators, sending text, files and voice notes.
final class ComposerNotifier extends Notifier<ComposerState> {
  ComposerNotifier(this.conversationId);

  final String conversationId;

  /// Mentions the person picked, as `(name shown, account)`; turned into
  /// ranges when the message is sent, by finding `@name` in the final text.
  final List<({String name, String account})> _pendingMentions = [];

  Timer? _draftTimer;
  Timer? _typingStop;
  Timer? _voiceTick;
  DateTime? _lastTypingSent;
  int _voiceElapsedMs = 0;
  String _lastDraft = '';

  // Voice-note state that is not drawn: whether the person still wants the
  // recording (their finger is down, or it is locked), whether the microphone
  // is still opening, what the recorder is doing and whether the app, not the
  // system, paused it.
  bool _voiceWanted = false;
  bool _voiceOpening = false;
  VoicePhase _voicePhase = VoicePhase.idle;
  bool _voicePausedByApp = false;
  StreamSubscription<VoicePhase>? _voicePhaseSub;
  VoiceRecorder? _recorder;

  /// Typing is announced at most this often while the text changes.
  static const typingEvery = Duration(seconds: 4);

  /// Typing stops this long after the last keystroke.
  static const typingIdle = Duration(seconds: 6);

  static const draftDelay = Duration(milliseconds: 500);

  @override
  ComposerState build() {
    ref.onDispose(() {
      _draftTimer?.cancel();
      _typingStop?.cancel();
      unawaited(_voicePhaseSub?.cancel());
      // Leaving the conversation mid-recording throws the recording away; the
      // microphone must never stay open behind a screen that is gone.
      if (_voiceWanted || (_voiceTick?.isActive ?? false)) {
        unawaited(_recorder?.cancel());
      }
      _voiceTick?.cancel();
    });
    return const ComposerState();
  }

  Future<ChatGateway> get _gateway => ref.read(chatGatewayProvider.future);

  void _notice(String text) => state = state.copyWith(notice: text);

  // ------------------------------------------------------- reply and edit

  Future<ComposerTarget?> _targetOf(int rowid) async {
    final gateway = await _gateway;
    final row = await gateway.message(rowid);
    if (row == null || row.deletedAt != null) return null;
    final people =
        ref.read(peopleDirectoryProvider).value ?? PeopleDirectory.empty;
    final self = gateway.selfAccountId;
    return ComposerTarget(
      rowid: row.localRowid,
      messageId: row.messageId,
      author: row.sender,
      authorName: row.sender == self || row.outgoing
          ? 'You'
          : people.displayOf(row.sender),
      text: previewTextOf(row),
      kind: previewKindOf(row),
    );
  }

  /// Quote [rowid] in the next message.
  Future<void> reply(int rowid) async {
    final target = await _targetOf(rowid);
    if (target == null) return;
    state = state.copyWith(reply: () => target, edit: () => null);
  }

  /// Start editing [rowid]; returns the text to put in the field, or null
  /// when it cannot be edited.
  Future<String?> beginEdit(int rowid) async {
    final gateway = await _gateway;
    final row = await gateway.message(rowid);
    if (row == null || !row.outgoing || row.deletedAt != null) return null;
    final target = await _targetOf(rowid);
    if (target == null) return null;
    state = state.copyWith(reply: () => null, edit: () => target);
    return row.body ?? '';
  }

  /// Close the reply or edit banner.
  void cancelTarget() {
    state = state.copyWith(reply: () => null, edit: () => null);
  }

  // ---------------------------------------------------------- text changes

  /// The field's text or cursor changed: save the draft shortly after, tell
  /// the other side somebody is typing, and offer mentions.
  void onChanged(String text, int cursor) {
    if (state.edit == null) {
      _scheduleDraft(text);
      _typing(text);
    }
    _offerMentions(text, cursor);
  }

  void _scheduleDraft(String text) {
    _draftTimer?.cancel();
    _draftTimer = Timer(draftDelay, () => unawaited(_saveDraft(text)));
  }

  Future<void> _saveDraft(String text) async {
    if (text == _lastDraft) return;
    _lastDraft = text;
    final gateway = await _gateway;
    await gateway.setDraft(conversationId, text.trim().isEmpty ? null : text);
  }

  /// Writes the draft now (the screen is closing).
  Future<void> flushDraft(String text) async {
    _draftTimer?.cancel();
    if (state.edit != null) return;
    // Both start now, while the provider is still alive: the screen is going
    // away and this runs from its dispose.
    await Future.wait([_saveDraft(text), _stopTyping()]);
  }

  void _typing(String text) {
    if (text.trim().isEmpty) {
      unawaited(_stopTyping());
      return;
    }
    final now = ref.read(clockProvider)();
    final last = _lastTypingSent;
    if (last == null || now.difference(last) >= typingEvery) {
      _lastTypingSent = now;
      unawaited(
        _gateway.then(
          (g) => g.sendTyping(conversationId, typing: true),
          onError: (_) {},
        ),
      );
    }
    _typingStop?.cancel();
    _typingStop = Timer(typingIdle, () => unawaited(_stopTyping()));
  }

  Future<void> _stopTyping() async {
    _typingStop?.cancel();
    if (_lastTypingSent == null) return;
    _lastTypingSent = null;
    try {
      final gateway = await _gateway;
      await gateway.sendTyping(conversationId, typing: false);
    } on Object {
      // Typing is best effort.
    }
  }

  // -------------------------------------------------------------- mentions

  void _offerMentions(String text, int cursor) {
    final group = groupIdOf(conversationId);
    if (group == null) {
      if (state.mentionCandidates.isNotEmpty) {
        state = state.copyWith(mentionCandidates: const []);
      }
      return;
    }
    final token = mentionTokenAt(text, cursor);
    if (token == null) {
      if (state.mentionCandidates.isNotEmpty) {
        state = state.copyWith(mentionCandidates: const []);
      }
      return;
    }
    final people =
        ref.read(peopleDirectoryProvider).value ?? PeopleDirectory.empty;
    final members = ref.read(groupMembersProvider(conversationId)).value ?? [];
    final self = ref.read(chatGatewayProvider).value?.selfAccountId;
    final query = token.query.toLowerCase();
    final candidates = <HelixMentionCandidate>[
      for (final m in members)
        if (!m.isSelf && m.accountId != self)
          if (people.displayOf(m.accountId).toLowerCase().contains(query))
            HelixMentionCandidate(
              id: m.accountId,
              name: people.displayOf(m.accountId),
              detail: people.secondaryOf(m.accountId),
              image: people.imageOf(m.accountId),
            ),
    ];
    state = state.copyWith(mentionCandidates: candidates);
  }

  /// Insert [candidate] where the `@` token is; returns the new text and
  /// cursor for the field.
  ({String text, int cursor}) pickMention(
    HelixMentionCandidate candidate,
    String text,
    int cursor,
  ) {
    final token = mentionTokenAt(text, cursor);
    if (token == null) return (text: text, cursor: cursor);
    final insert = '@${candidate.name} ';
    final next = text.replaceRange(token.start, cursor, insert);
    _pendingMentions.add((name: candidate.name, account: candidate.id));
    state = state.copyWith(mentionCandidates: const []);
    return (text: next, cursor: token.start + insert.length);
  }

  /// The mentions to send with [text]: each picked `@name` that is still in
  /// the text, once each, as a range.
  @visibleForTesting
  List<Mention> mentionsIn(String text) {
    final used = <int>{};
    final out = <Mention>[];
    for (final pending in _pendingMentions) {
      final needle = '@${pending.name}';
      var from = 0;
      while (true) {
        final at = text.indexOf(needle, from);
        if (at < 0) break;
        if (used.add(at)) {
          out.add(
            Mention(account: pending.account, start: at, length: needle.length),
          );
          break;
        }
        from = at + needle.length;
      }
    }
    out.sort((a, b) => a.start.compareTo(b.start));
    return out;
  }

  // --------------------------------------------------------------- sending

  /// Sends [text] (or saves the edit). True when it went; the screen then
  /// clears the field.
  Future<bool> send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    final gateway = await _gateway;
    try {
      final editing = state.edit;
      if (editing != null) {
        await gateway.edit(editing.rowid, trimmed);
        state = state.copyWith(edit: () => null);
      } else {
        final reply = state.reply;
        await gateway.sendText(
          conversationId,
          text,
          replyTo: reply == null
              ? null
              : MessageRef(id: reply.messageId, author: reply.author),
          mentions: mentionsIn(text),
        );
        state = state.copyWith(reply: () => null);
      }
    } on Object {
      _notice('The message could not be sent.');
      return false;
    }
    _pendingMentions.clear();
    _lastDraft = '';
    _draftTimer?.cancel();
    await _stopTyping();
    return true;
  }

  // ----------------------------------------------------------- attachments

  /// Opens the chosen source and returns what was picked (empty when the
  /// person cancelled or nothing is available).
  Future<List<AttachmentDraft>> pick(AttachmentSource source) async {
    final picker = ref.read(attachmentPickerProvider);
    final List<PickedFile> files;
    switch (source) {
      case AttachmentSource.gallery:
        files = await picker.pickGallery();
      case AttachmentSource.document:
        files = await picker.pickDocuments();
      case AttachmentSource.audio:
        files = await picker.pickAudio();
      case AttachmentSource.cameraPhoto:
      case AttachmentSource.cameraVideo:
        if (!picker.cameraAvailable) {
          _notice('The camera is not available on this device.');
          return const [];
        }
        try {
          final shot = source == AttachmentSource.cameraPhoto
              ? await picker.takePhoto()
              : await picker.recordVideo();
          files = shot == null ? const [] : [shot];
        } on AttachmentPermissionDenied {
          _notice(
            'Allow camera access in your phone settings to take photos '
            'and videos.',
          );
          return const [];
        }
    }
    return [for (final f in files) AttachmentDraft(f)];
  }

  /// Sends picked files: photos and videos as one album with [caption],
  /// every document or audio file as a message of its own.
  ///
  /// Photos and videos first lose their location, time and camera details
  /// (`MediaSanitizer`); a photo whose details cannot be removed is not sent.
  /// The copies made for that, and the camera's own file, are deleted as soon
  /// as the engine has taken its copy.
  Future<bool> sendFiles(
    List<AttachmentDraft> drafts, {
    String caption = '',
    bool viewOnce = false,
  }) async {
    if (drafts.isEmpty) return false;
    final gateway = await _gateway;
    if (!gateway.canSendMedia) {
      _notice('Sending files is not available on this device.');
      return false;
    }
    final sanitizer = ref.read(mediaSanitizerProvider);
    final temp = ref.read(mediaTempProvider);
    // Deleted whatever happens: the cleaned copies (made again on a retry).
    final copies = <String>[];
    // Deleted once the send worked: the camera's own files.
    final originals = <String>[];
    final files = <PickedFile>[];
    var refused = 0;
    try {
      for (final draft in drafts) {
        final original = draft.file;
        final result = await sanitizer.sanitize(original);
        if (result.outcome == SanitizeOutcome.failed) {
          refused++;
          continue;
        }
        if (result.file.path != original.path) copies.add(result.file.path);
        if (original.temporary) originals.add(original.path);
        files.add(result.file);
      }
      if (files.isEmpty) {
        _notice(
          'These files could not be prepared, so nothing was sent. Photos '
          'are only sent once their location details have been removed.',
        );
        return false;
      }
      final sent = await _sendPrepared(
        gateway,
        files,
        caption: caption,
        viewOnce: viewOnce,
      );
      if (sent) {
        await temp.deleteAll(originals);
        if (refused > 0) {
          _notice(
            refused == 1
                ? 'One file was not sent: its location details could not be '
                      'removed.'
                : '$refused files were not sent: their location details '
                      'could not be removed.',
          );
        }
      }
      return sent;
    } finally {
      await temp.deleteAll(copies);
    }
  }

  Future<bool> _sendPrepared(
    ChatGateway gateway,
    List<PickedFile> files, {
    required String caption,
    required bool viewOnce,
  }) async {
    final reply = state.reply;
    final replyRef = reply == null
        ? null
        : MessageRef(id: reply.messageId, author: reply.author);
    final visual = [
      for (final f in files)
        if (f.kind == PickedKind.image || f.kind == PickedKind.video) f,
    ];
    final others = [
      for (final f in files)
        if (f.kind != PickedKind.image && f.kind != PickedKind.video) f,
    ];
    try {
      var first = true;
      if (visual.isNotEmpty) {
        await gateway.sendMedia(
          conversationId,
          [for (final f in visual) _inputOf(f)],
          caption: caption.trim().isEmpty ? null : caption.trim(),
          replyTo: replyRef,
          viewOnce: viewOnce,
        );
        first = false;
      }
      for (final f in others) {
        await gateway.sendMedia(
          conversationId,
          [_inputOf(f)],
          caption:
              visual.isEmpty && others.length == 1 && caption.trim().isNotEmpty
              ? caption.trim()
              : null,
          replyTo: first ? replyRef : null,
        );
        first = false;
      }
    } on Object {
      _notice('The files could not be sent.');
      return false;
    }
    state = state.copyWith(reply: () => null);
    return true;
  }

  MediaInput _inputOf(PickedFile file) => MediaInput.file(
    path: file.path,
    kind: switch (file.kind) {
      PickedKind.image =>
        file.mime == 'image/gif' ? MediaItemKind.gif : MediaItemKind.image,
      PickedKind.video => MediaItemKind.video,
      PickedKind.audio || PickedKind.document => MediaItemKind.document,
    },
    mime: file.mime,
    name: file.name,
  );

  // ------------------------------------------------------------ voice notes

  /// The finger went down on the microphone.
  ///
  /// The first time, the system asks for the microphone while the finger is
  /// still down, which usually ends the gesture; `_voiceWanted` tells us when
  /// the recording that then opens is no longer wanted, and it is dropped.
  Future<void> startVoice() async {
    final recorder = ref.read(voiceRecorderProvider);
    _recorder = recorder;
    if (!recorder.isAvailable) {
      _notice('Voice messages are not available on this device.');
      return;
    }
    if (_voiceOpening || state.recording != null) return;
    _voiceOpening = true;
    _voiceWanted = true;
    // A voice note and a playing one would record each other.
    unawaited(ref.read(playbackProvider.notifier).stop());
    try {
      await recorder.start();
    } on VoiceRecorderPermissionDenied {
      _voiceOpening = false;
      _voiceWanted = false;
      _notice(
        'Allow microphone access in your phone settings to record voice '
        'messages.',
      );
      return;
    } on VoiceRecorderUnavailable {
      _voiceOpening = false;
      _voiceWanted = false;
      _notice('Voice messages are not available on this device.');
      return;
    }
    _voiceOpening = false;
    if (!_voiceWanted) {
      await recorder.cancel();
      _notice('Hold the microphone to record, then let go to send.');
      return;
    }
    _voiceElapsedMs = 0;
    _voicePhase = VoicePhase.recording;
    _voicePausedByApp = false;
    state = state.copyWith(
      recording: () => const HelixVoiceRecordState(elapsedLabel: '0:00'),
    );
    await _voicePhaseSub?.cancel();
    _voicePhaseSub = recorder.phases.listen((phase) {
      // A call or another app took the microphone, or gave it back: the clock
      // stops and starts with it.
      _voicePhase = phase;
    });
    _voiceTick?.cancel();
    _voiceTick = Timer.periodic(_voiceStep, (_) => _voiceTicked());
  }

  static const _voiceStep = Duration(milliseconds: 100);

  void _voiceTicked() {
    if (_voicePhase != VoicePhase.recording) return;
    final before = formatDurationMs(_voiceElapsedMs);
    _voiceElapsedMs += _voiceStep.inMilliseconds;
    final current = state.recording;
    if (current == null) return;
    final label = formatDurationMs(_voiceElapsedMs);
    if (label != before) {
      state = state.copyWith(
        recording: () => HelixVoiceRecordState(
          elapsedLabel: label,
          cancelProgress: current.cancelProgress,
          lockProgress: current.lockProgress,
          locked: current.locked,
        ),
      );
    }
    if (_voiceElapsedMs >= VoiceRecorder.maxDuration.inMilliseconds) {
      _notice('That is the longest a voice message can be, so it was sent.');
      unawaited(endVoice(send: true));
    }
  }

  /// The finger moved: how far towards cancel and towards lock.
  void slideVoice(double cancel, double lock) {
    final current = state.recording;
    if (current == null || current.locked) return;
    state = state.copyWith(
      recording: () => HelixVoiceRecordState(
        elapsedLabel: current.elapsedLabel,
        cancelProgress: cancel,
        lockProgress: lock,
      ),
    );
  }

  /// Slid up far enough: keep recording without holding.
  void lockVoice() {
    final current = state.recording;
    if (current == null) return;
    state = state.copyWith(
      recording: () => HelixVoiceRecordState(
        elapsedLabel: current.elapsedLabel,
        lockProgress: 1,
        locked: true,
      ),
    );
  }

  /// The app left the foreground. Android takes the microphone from a
  /// background app, so a recording the person is holding is dropped (their
  /// finger is gone too) and a locked one is paused until they are back.
  Future<void> appBackgrounded() async {
    final current = state.recording;
    final recorder = _recorder;
    if (current == null || recorder == null) return;
    if (current.locked) {
      _voicePausedByApp = true;
      await recorder.pause();
    } else {
      await endVoice(send: false);
      _notice('The recording was stopped because you left the app.');
    }
  }

  /// The app is back: a recording paused by [appBackgrounded] carries on.
  Future<void> appResumed() async {
    if (!_voicePausedByApp) return;
    _voicePausedByApp = false;
    if (state.recording == null) return;
    await _recorder?.resume();
  }

  /// Stop recording and send it ([send]) or throw it away.
  Future<void> endVoice({required bool send}) async {
    _voiceWanted = false;
    if (state.recording == null) return;
    _voiceTick?.cancel();
    unawaited(_voicePhaseSub?.cancel());
    _voicePhaseSub = null;
    _voicePausedByApp = false;
    final recorder = ref.read(voiceRecorderProvider);
    state = state.copyWith(recording: () => null);
    if (!send) {
      await recorder.cancel();
      return;
    }
    final result = await recorder.stop();
    if (result == null) {
      _notice('Nothing was recorded. Hold the microphone and speak.');
      return;
    }
    final temp = ref.read(mediaTempProvider);
    try {
      if (result.durationMs < 700) {
        _notice('Hold the microphone to record, then let go to send.');
        return;
      }
      final gateway = await _gateway;
      final reply = state.reply;
      try {
        await gateway.sendMedia(
          conversationId,
          [
            MediaInput.file(
              path: result.path,
              kind: MediaItemKind.voiceNote,
              mime: result.mime,
              durationMs: result.durationMs,
              waveform: result.waveform.isEmpty ? null : result.waveform,
            ),
          ],
          replyTo: reply == null
              ? null
              : MessageRef(id: reply.messageId, author: reply.author),
        );
        state = state.copyWith(reply: () => null);
      } on Object {
        _notice('The voice message could not be sent.');
      }
    } finally {
      // The engine has its own copy; the recording must not outlive the send.
      await temp.delete(result.path);
    }
  }
}

/// Where an attachment comes from.
enum AttachmentSource { gallery, document, audio, cameraPhoto, cameraVideo }

final composerProvider = NotifierProvider.autoDispose
    .family<ComposerNotifier, ComposerState, String>(ComposerNotifier.new);

/// The unsent text the conversation had when it was last closed.
final composerDraftProvider = FutureProvider.autoDispose.family<String, String>(
  (ref, conversationId) async {
    final gateway = await ref.watch(chatGatewayProvider.future);
    return (await gateway.chat(conversationId))?.draft ?? '';
  },
);

/// Files picked and waiting on the "send" preview screen.
final class PendingAttachments extends Notifier<List<AttachmentDraft>> {
  PendingAttachments(this.conversationId);

  final String conversationId;

  @override
  List<AttachmentDraft> build() => const [];

  void set(List<AttachmentDraft> files) => state = files;

  void remove(AttachmentDraft file) {
    state = [
      for (final f in state)
        if (f != file) f,
    ];
    unawaited(ref.read(mediaTempProvider).delete(file.path));
  }

  /// The person left the preview without sending: the camera's files and the
  /// copies the app made go with it. Their own files are never touched.
  Future<void> discard() async {
    final files = state;
    // Not in this call: it may run while the preview screen is being taken
    // down, when a provider must not notify the widgets.
    scheduleMicrotask(() => state = const []);
    await ref.read(mediaTempProvider).deleteAll([
      for (final f in files)
        if (f.file.temporary) f.path,
    ]);
  }
}

/// Not auto-disposed: the files are set on one screen and read on the next,
/// with nothing listening in between.
final pendingAttachmentsProvider =
    NotifierProvider.family<PendingAttachments, List<AttachmentDraft>, String>(
      PendingAttachments.new,
    );
