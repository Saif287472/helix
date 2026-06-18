import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:uuid/uuid.dart';
import 'package:helix_local_domain/core/constants.dart';
import 'package:helix_local_domain/domain/models.dart';
import 'package:helix_local_protocol/protocol/protocol_messages.dart';
import 'package:helix_local_transport/services/transport/secure_channel.dart';
import 'package:helix/providers/controllers/trust_service.dart';
import 'package:helix_local_domain/application/contracts/repositories.dart';
import 'package:helix_local_protocol/application/contracts/use_cases.dart';

typedef FileChunkHandler =
    Future<void> Function(
      String threadId,
      String messageId,
      FileTransferFrame frame,
    );

typedef FileProbeHandler =
    Future<void> Function(
      String threadId,
      String messageId,
      FileProbeFrame frame,
      SecureChannel channel,
    );

typedef FileCompleteHandler =
    Future<void> Function(
      String threadId,
      String messageId,
      String fileId,
      String sha256,
    );

typedef FileCancelHandler =
    Future<void> Function(String threadId, String fileId);

typedef EphemeralMediaChunkHandler =
    Future<void> Function(
      String threadId,
      String messageId,
      EphemeralMediaFrame frame,
    );

typedef GroupControlHandler =
    Future<void> Function(
      String threadId,
      GroupControlFrame frame,
      SecureChannel channel,
    );

typedef GroupMessageHandler =
    Future<void> Function(
      String threadId,
      GroupMessageFrame frame,
      SecureChannel channel,
    );

typedef CallSignalHandler =
    Future<void> Function(
      String peerId,
      String peerDisplayName,
      CallSignalFrame frame,
    );

class MessagingService {
  MessagingService({
    this.autoWipeDelay = const Duration(minutes: 5),
    this._conversationRepository,
    this._sendMessageUseCase,
    this._receiveMessageCoordinator,
    this._deliveryReceiptTracker,
    required this._wipeScheduler,
  });

  final Duration autoWipeDelay;
  final ConversationRepository? _conversationRepository;
  final SendMessageUseCase? _sendMessageUseCase;
  final ReceiveMessageCoordinator? _receiveMessageCoordinator;
  final DeliveryReceiptTracker? _deliveryReceiptTracker;
  final DisconnectWipeScheduler _wipeScheduler;

  TrustService? _trustService;
  void setTrustService(TrustService svc) => _trustService = svc;

  FileChunkHandler? _fileChunkHandler;
  void setFileChunkHandler(FileChunkHandler handler) =>
      _fileChunkHandler = handler;

  FileProbeHandler? _fileProbeHandler;
  void setFileProbeHandler(FileProbeHandler handler) =>
      _fileProbeHandler = handler;

  FileCompleteHandler? _fileCompleteHandler;
  void setFileCompleteHandler(FileCompleteHandler handler) =>
      _fileCompleteHandler = handler;

  FileCancelHandler? _fileCancelHandler;
  void setFileCancelHandler(FileCancelHandler handler) =>
      _fileCancelHandler = handler;

  EphemeralMediaChunkHandler? _ephemeralMediaChunkHandler;
  void setEphemeralMediaChunkHandler(EphemeralMediaChunkHandler handler) =>
      _ephemeralMediaChunkHandler = handler;

  GroupControlHandler? _groupControlHandler;
  void setGroupControlHandler(GroupControlHandler handler) =>
      _groupControlHandler = handler;

  GroupMessageHandler? _groupMessageHandler;
  void setGroupMessageHandler(GroupMessageHandler handler) =>
      _groupMessageHandler = handler;

  CallSignalHandler? _callSignalHandler;
  void setCallSignalHandler(CallSignalHandler handler) =>
      _callSignalHandler = handler;

  final Map<String, Map<String, String>> _fileToMessageId = {};
  static const kMaxActiveIncomingAttachments = 16;

  bool _isValidIncomingFileId(String fileId) {
    return RegExp(r'^[a-zA-Z0-9_\-]{1,64}$').hasMatch(fileId);
  }

  DateTime? _safeProtocolTime(int value) {
    const min = -8640000000000000;
    const max = 8640000000000000;
    if (value < min || value > max) return null;
    try {
      return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true).toLocal();
    } on RangeError {
      return null;
    } catch (_) {
      return null;
    }
  }

  final Map<String, ChatThread> _threadsLegacy = {};

  ChatThread? _getThread(String threadId) {
    if (_conversationRepository != null) {
      return _conversationRepository.getThread(threadId);
    }
    return _threadsLegacy[threadId];
  }

  void _saveThread(ChatThread thread) {
    if (_conversationRepository != null) {
      _conversationRepository.saveThread(thread);
    } else {
      _threadsLegacy[thread.threadId] = thread;
    }
  }

  void _removeThread(String threadId) {
    if (_conversationRepository != null) {
      _conversationRepository.removeThread(threadId);
    } else {
      _threadsLegacy.remove(threadId);
    }
  }

  bool _hasThread(String threadId) {
    if (_conversationRepository != null) {
      return _conversationRepository.getThread(threadId) != null;
    }
    return _threadsLegacy.containsKey(threadId);
  }

  void _clearThreads() {
    if (_conversationRepository != null) {
      for (final t in _conversationRepository.listThreads()) {
        _conversationRepository.removeThread(t.threadId);
      }
    } else {
      _threadsLegacy.clear();
    }
  }

  List<ChatThread> _listThreads() {
    if (_conversationRepository != null) {
      return _conversationRepository.listThreads();
    }
    return _threadsLegacy.values.toList();
  }

  final Map<String, SecureChannel> _channels = {};
  final Map<String, LinkedHashSet<String>> _seenIds = {};
  static const _kMaxSeenIds = 1000;
  final Map<String, bool> _atCapacity = {};
  final Map<String, StreamSubscription<ChatMessageFrame>> _subs = {};
  final Map<String, List<StreamSubscription<dynamic>>> _phase3Subs = {};
  final Map<String, bool> _peerTyping = {};
  final Map<String, Timer> _typingTimers = {};
  final List<OneWayMessage> _oneWayInbox = [];
  final Set<String> _oneWayOnlyThreads = {};
  Timer? _oneWayCleanupTimer;

  final _threadUpdatesCtrl =
      StreamController<Map<String, ChatThread>>.broadcast();
  final _threadChangesCtrl = StreamController<ChatThread>.broadcast();
  final _typingChangesCtrl =
      StreamController<MapEntry<String, bool>>.broadcast();
  final _oneWayInboxCtrl = StreamController<List<OneWayMessage>>.broadcast();
  bool _disposed = false;

  Map<String, ChatThread> get threads {
    final list = _listThreads();
    return Map.unmodifiable({for (var t in list) t.threadId: t});
  }

  Stream<Map<String, ChatThread>> get threadUpdates =>
      _threadUpdatesCtrl.stream;
  Stream<ChatThread> get threadChanges => _threadChangesCtrl.stream;

  Stream<MapEntry<String, bool>> get typingChanges => _typingChangesCtrl.stream;
  Stream<List<OneWayMessage>> get oneWayInboxUpdates => _oneWayInboxCtrl.stream;
  List<OneWayMessage> get oneWayInbox => List.unmodifiable(_oneWayInbox);

  bool isPeerTyping(String threadId) => _peerTyping[threadId] ?? false;
  bool isOneWayOnlyThread(String threadId) =>
      _oneWayOnlyThreads.contains(threadId);

  bool shouldAutoResume(String peerFingerprint) {
    final thread = _getThread(peerFingerprint);
    if (thread == null) return false;
    if (thread.manuallyDisconnected) return false;
    if (thread.status != ThreadStatus.disconnected) return false;
    final at = thread.disconnectedAt;
    if (at == null) return false;
    return DateTime.now().difference(at) < kAutoResumeWindow;
  }

  ChatThread? findActiveThreadForPeer(Peer peer) {
    for (final thread in _listThreads()) {
      if (thread.status != ThreadStatus.active) continue;
      if (peer.sessionId.isNotEmpty && thread.peerSessionId == peer.sessionId) {
        return thread;
      }
      if (thread.peerHost == peer.host && thread.peerPort == peer.port) {
        return thread;
      }
      if (thread.peerDeviceSuffix == peer.deviceSuffix &&
          thread.peerDisplayName == peer.displayName) {
        return thread;
      }
    }
    return null;
  }

  void notify(String threadId) => _notify(threadId);

  bool isDuplicate(String threadId, String messageId) =>
      _seenIds[threadId]?.contains(messageId) ?? false;

  void markSeen(String threadId, String messageId) {
    final set = _seenIds[threadId] ??= LinkedHashSet<String>();
    set.add(messageId);
    if (set.length > _kMaxSeenIds) set.remove(set.first);
  }

  void setAtCapacity(String threadId, bool atCapacity) =>
      _atCapacity[threadId] = atCapacity;

  void attachChannel(
    String peerStaticKeyFingerprint,
    String peerDisplayName,
    String peerDeviceSuffix,
    SecureChannel channel,
    String peerSessionId,
    String peerHost,
    int peerPort,
  ) {
    final threadId = peerStaticKeyFingerprint;

    final oldSub = _subs.remove(threadId);
    final oldPhase3 = _phase3Subs.remove(threadId);
    final oldChannel = _channels[threadId];

    if (oldSub != null || oldPhase3 != null || oldChannel != null) {
      unawaited(() async {
        if (oldSub != null) {
          await oldSub.cancel().catchError((_) {});
        }
        if (oldPhase3 != null) {
          for (final s in oldPhase3) {
            await s.cancel().catchError((_) {});
          }
        }
        if (oldChannel != null) {
          try {
            await oldChannel.sendClose(reason: 'replaced');
          } catch (_) {}
          await oldChannel.close().catchError((_) {});
        }
      }());
    }

    _wipeScheduler.cancelWipe(threadId);

    _channels[threadId] = channel;
    _oneWayOnlyThreads.remove(threadId);
    _trustService?.markKnown(
      threadId,
      peerDisplayName,
      peerDeviceSuffix,
      peerHost,
      peerPort,
    );

    final thread = _getThread(threadId);
    if (thread != null) {
      thread.status = ThreadStatus.active;
      thread.hasNewSessionSeparator = true;
      thread.manuallyDisconnected = false;
      thread.disconnectedAt = null;
      thread.peerSessionId = peerSessionId;
      thread.peerHost = peerHost;
      thread.peerPort = peerPort;
      _saveThread(thread);
    } else {
      final newThread = ChatThread(
        threadId: threadId,
        peerDisplayName: peerDisplayName,
        peerDeviceSuffix: peerDeviceSuffix,
        peerStaticKeyFingerprint: peerStaticKeyFingerprint,
        peerSessionId: peerSessionId,
        peerHost: peerHost,
        peerPort: peerPort,
        status: ThreadStatus.active,
      );
      _saveThread(newThread);
      _seenIds[threadId] = LinkedHashSet<String>();
      _atCapacity[threadId] = false;
    }

    final sub = channel.messages.listen(
      (frame) => _onIncomingMessage(threadId, frame),
      onError: (_) => detachChannel(threadId, expectedChannel: channel),
      onDone: () => detachChannel(threadId, expectedChannel: channel),
      cancelOnError: true,
    );
    _subs[threadId] = sub;

    _phase3Subs[threadId] = [
      channel.stateChanges.listen((state) {
        if ((state == ChannelState.closed || state == ChannelState.closing) &&
            identical(_channels[threadId], channel)) {
          detachChannel(threadId, expectedChannel: channel);
        }
      }),
      channel.typingEvents.listen(
        (isTyping) => _onPeerTyping(threadId, isTyping),
      ),
      channel.receiptEvents.listen((ids) => _onReadReceipt(threadId, ids)),
      channel.reactionEvents.listen((frame) => _onReaction(threadId, frame)),
      channel.editEvents.listen((frame) => _onEdit(threadId, frame)),
      channel.deleteEvents.listen((frame) => _onDelete(threadId, frame)),
      channel.wipeEvents.listen((_) => wipeAll()),
      channel.fileChunkEvents.listen((frame) => _onFileChunk(threadId, frame)),
      channel.fileProbeEvents.listen(
        (frame) => _onFileProbe(threadId, frame, channel),
      ),
      channel.fileCompleteEvents.listen(
        (frame) => _onFileComplete(threadId, frame),
      ),
      channel.fileCancelEvents.listen(
        (frame) => _onFileCancel(threadId, frame),
      ),
      channel.ephemeralMediaEvents.listen(
        (frame) => _onEphemeralMediaChunk(threadId, frame),
      ),
      channel.groupControlEvents.listen(
        (frame) => _onGroupControl(threadId, frame, channel),
      ),
      channel.groupMessageEvents.listen(
        (frame) => _onGroupMessage(threadId, frame, channel),
      ),
      channel.callSignalEvents.listen(
        (frame) => _onCallSignal(threadId, frame),
      ),
    ];

    _notify(threadId);
  }

  void _cancelPhase3Subs(String threadId) {
    final subs = _phase3Subs.remove(threadId);
    if (subs != null) {
      for (final s in subs) {
        s.cancel();
      }
    }
  }

  void receiveOneWayMessage(OneWayMessage message) {
    final threadId = message.peerStaticKeyFingerprint;
    if (threadId.isEmpty) return;

    if (!message.isExpired) {
      _oneWayInbox.insert(0, message);
      if (_oneWayInbox.length > 100) _oneWayInbox.removeLast();
      _oneWayInboxCtrl.add(List.unmodifiable(_oneWayInbox));
      _oneWayCleanupTimer ??= Timer.periodic(
        const Duration(seconds: 30),
        (_) => _purgeExpiredOneWayMessages(),
      );
    }

    final seen = _seenIds[threadId] ??= LinkedHashSet<String>();
    if (seen.contains(message.messageId)) return;
    seen.add(message.messageId);
  }

  void _purgeExpiredOneWayMessages() {
    final before = _oneWayInbox.length;
    _oneWayInbox.removeWhere((m) => m.isExpired);
    if (_oneWayInbox.length != before) {
      _oneWayInboxCtrl.add(List.unmodifiable(_oneWayInbox));
    }
    if (_oneWayInbox.isEmpty) {
      _oneWayCleanupTimer?.cancel();
      _oneWayCleanupTimer = null;
    }
  }

  void dismissOneWayMessage(String messageId) {
    _oneWayInbox.removeWhere((m) => m.messageId == messageId);
    _oneWayInboxCtrl.add(List.unmodifiable(_oneWayInbox));
  }

  Future<void> sendMessage(
    String threadId,
    String text, {
    String? replyToMessageId,
  }) async {
    if (_sendMessageUseCase != null) {
      await _sendMessageUseCase.sendText(
        threadId: threadId,
        text: text,
        replyToMessageId: replyToMessageId,
      );
      return;
    }

    if (text.isEmpty) throw ArgumentError('Message text must not be empty');

    try {
      utf8.decode(utf8.encode(text), allowMalformed: false);
    } on FormatException {
      throw ArgumentError('Message text contains invalid Unicode');
    }

    final textBytes = utf8.encode(text);
    if (textBytes.length > kMaxMessageBytes) {
      throw ArgumentError(
        'Message text exceeds maximum size of $kMaxMessageBytes UTF-8 bytes',
      );
    }

    final thread = _getThread(threadId);
    if (thread == null) throw StateError('No thread for threadId=$threadId');

    final channel = _channels[threadId];
    if (channel == null || channel.state != ChannelState.active) {
      throw StateError('No active channel for threadId=$threadId');
    }

    if (_atCapacity[threadId] == true) {
      throw StateError(
        'Thread $threadId is at memory capacity; clear or close first',
      );
    }

    final messageId = _uuid.v4();
    final now = DateTime.now();
    final chatMsg = ChatMessage(
      messageId: messageId,
      threadId: threadId,
      origin: MessageOrigin.local,
      text: text,
      timestamp: now,
      deliveryStatus: MessageDeliveryStatus.sending,
      replyToMessageId: replyToMessageId,
    );
    _addMessage(thread, chatMsg);
    _notify(threadId);

    final frame = ChatMessageFrame(
      messageId: messageId,
      text: text,
      timestamp: now.millisecondsSinceEpoch,
      replyToMessageId: replyToMessageId,
    );

    try {
      await channel.sendMessage(frame);
      _updateDeliveryStatus(thread, messageId, MessageDeliveryStatus.delivered);
    } catch (_) {
      _updateDeliveryStatus(thread, messageId, MessageDeliveryStatus.failed);
      detachChannel(threadId, expectedChannel: channel);
    }
    _notify(threadId);
  }

  String addFileMessage({
    required String threadId,
    required MessageOrigin origin,
    required String fileId,
    required String fileName,
    required String mimeType,
    required int fileSize,
    String? localFilePath,
    bool isEphemeral = false,
  }) {
    final thread = _getThread(threadId);
    if (thread == null) return '';

    final messageId = _uuid.v4();
    final msg = ChatMessage(
      messageId: messageId,
      threadId: threadId,
      origin: origin,
      text: fileName,
      timestamp: DateTime.now(),
      deliveryStatus: origin == MessageOrigin.local
          ? MessageDeliveryStatus.sending
          : MessageDeliveryStatus.delivered,
      fileId: fileId,
      fileName: fileName,
      mimeType: mimeType,
      fileSize: fileSize,
      localFilePath: localFilePath,
      isEphemeral: isEphemeral,
      transferProgress: 0.0,
    );
    _addMessage(thread, msg);
    if (origin == MessageOrigin.remote) thread.unreadCount++;
    _saveThread(thread);
    _notify(threadId);
    return messageId;
  }

  void removeFileMessage(String threadId, String fileId) {
    final mapping = _fileToMessageId[threadId];
    if (mapping == null) return;
    final messageId = mapping.remove(fileId);
    if (messageId == null) return;

    final thread = _getThread(threadId);
    if (thread == null) return;

    thread.messages.removeWhere((m) => m.messageId == messageId);
    _saveThread(thread);
    _notify(threadId);
  }

  void updateTransferProgress(
    String threadId,
    String messageId,
    double? progress, {
    String? localFilePath,
  }) {
    final thread = _getThread(threadId);
    if (thread == null) return;
    for (var i = 0; i < thread.messages.length; i++) {
      if (thread.messages[i].messageId == messageId) {
        thread.messages[i] = thread.messages[i].copyWith(
          transferProgress: progress,
          clearTransferProgress: progress == null,
          localFilePath: localFilePath,
          deliveryStatus: progress == null && localFilePath != null
              ? MessageDeliveryStatus.delivered
              : null,
        );
        _saveThread(thread);
        _notify(threadId);
        return;
      }
    }
  }

  Future<void> sendTyping(String threadId, {required bool isTyping}) async {
    await _channels[threadId]?.sendTyping(isTyping);
  }

  void markThreadRead(String threadId) {
    final thread = _getThread(threadId);
    if (thread == null || thread.unreadCount == 0) return;
    thread.unreadCount = 0;
    _saveThread(thread);
    _notify(threadId);
  }

  void _onPeerTyping(String threadId, bool isTyping) {
    _typingTimers.remove(threadId)?.cancel();
    _peerTyping[threadId] = isTyping;
    if (!_typingChangesCtrl.isClosed) {
      _typingChangesCtrl.add(MapEntry(threadId, isTyping));
    }
    if (isTyping) {
      _typingTimers[threadId] = Timer(const Duration(seconds: 5), () {
        _peerTyping[threadId] = false;
        if (!_typingChangesCtrl.isClosed) {
          _typingChangesCtrl.add(MapEntry(threadId, false));
        }
      });
    }
  }

  Future<void> sendReadReceipt(String threadId, List<String> messageIds) async {
    await _channels[threadId]?.sendReadReceipt(messageIds);
  }

  void _onReadReceipt(String threadId, List<String> messageIds) {
    if (_deliveryReceiptTracker != null) {
      for (final id in messageIds) {
        _deliveryReceiptTracker.markRead(id);
      }
      return;
    }
    final thread = _getThread(threadId);
    if (thread == null) return;
    final idSet = messageIds.toSet();
    var changed = false;
    for (var i = 0; i < thread.messages.length; i++) {
      final m = thread.messages[i];
      if (m.origin == MessageOrigin.local &&
          idSet.contains(m.messageId) &&
          m.deliveryStatus != MessageDeliveryStatus.read) {
        thread.messages[i] = m.copyWith(
          deliveryStatus: MessageDeliveryStatus.read,
        );
        changed = true;
      }
    }
    if (changed) {
      _saveThread(thread);
      _notify(threadId);
    }
  }

  Future<void> sendReaction(
    String threadId,
    String messageId,
    String emoji, {
    required bool remove,
  }) async {
    final thread = _getThread(threadId);
    if (thread == null) return;
    _applyReaction(
      thread,
      messageId,
      emoji,
      MessageOrigin.local,
      remove: remove,
    );
    _saveThread(thread);
    _notify(threadId);
    await _channels[threadId]?.sendReaction(messageId, emoji, remove: remove);
  }

  void _onReaction(String threadId, ReactionFrame frame) {
    final thread = _getThread(threadId);
    if (thread == null) return;
    _applyReaction(
      thread,
      frame.messageId,
      frame.emoji,
      MessageOrigin.remote,
      remove: frame.remove,
    );
    _saveThread(thread);
    _notify(threadId);
  }

  void _applyReaction(
    ChatThread thread,
    String messageId,
    String emoji,
    MessageOrigin origin, {
    required bool remove,
  }) {
    for (var i = 0; i < thread.messages.length; i++) {
      if (thread.messages[i].messageId == messageId) {
        thread.messages[i] = thread.messages[i].withReaction(
          emoji,
          origin,
          remove: remove,
        );
        return;
      }
    }
  }

  Future<void> editMessage(
    String threadId,
    String messageId,
    String newText,
  ) async {
    final thread = _getThread(threadId);
    if (thread == null) return;
    for (var i = 0; i < thread.messages.length; i++) {
      if (thread.messages[i].messageId == messageId &&
          thread.messages[i].origin == MessageOrigin.local) {
        thread.messages[i] = thread.messages[i].withEdit(newText);
        _saveThread(thread);
        _notify(threadId);
        await _channels[threadId]?.sendEdit(messageId, newText);
        return;
      }
    }
  }

  Future<void> deleteMessage(String threadId, String messageId) async {
    final thread = _getThread(threadId);
    if (thread == null) return;
    for (var i = 0; i < thread.messages.length; i++) {
      if (thread.messages[i].messageId == messageId &&
          thread.messages[i].origin == MessageOrigin.local) {
        thread.messages[i] = thread.messages[i].copyWith(isDeleted: true);
        _saveThread(thread);
        _notify(threadId);
        await _channels[threadId]?.sendDelete(messageId);
        return;
      }
    }
  }

  void _onEdit(String threadId, EditMessageFrame frame) {
    final thread = _getThread(threadId);
    if (thread == null) return;
    for (var i = 0; i < thread.messages.length; i++) {
      if (thread.messages[i].messageId == frame.messageId &&
          thread.messages[i].origin == MessageOrigin.remote) {
        thread.messages[i] = thread.messages[i].withEdit(frame.newText);
        _saveThread(thread);
        _notify(threadId);
        return;
      }
    }
  }

  void _onDelete(String threadId, DeleteMessageFrame frame) {
    final thread = _getThread(threadId);
    if (thread == null) return;
    for (var i = 0; i < thread.messages.length; i++) {
      if (thread.messages[i].messageId == frame.messageId &&
          thread.messages[i].origin == MessageOrigin.remote) {
        thread.messages[i] = thread.messages[i].copyWith(isDeleted: true);
        _saveThread(thread);
        _notify(threadId);
        return;
      }
    }
  }

  void _onFileChunk(String threadId, FileTransferFrame frame) {
    if (!_isValidIncomingFileId(frame.fileId) ||
        frame.totalSize <= 0 ||
        frame.totalSize > kMaxFileBytes) {
      return;
    }
    final thread = _getThread(threadId);
    if (thread == null || _atCapacity[threadId] == true) return;

    final mapping = _fileToMessageId[threadId] ??= {};
    var messageId = mapping[frame.fileId];
    if (messageId == null) {
      if (mapping.length >= kMaxActiveIncomingAttachments) return;
      messageId = addFileMessage(
        threadId: threadId,
        origin: MessageOrigin.remote,
        fileId: frame.fileId,
        fileName: frame.fileName,
        mimeType: frame.mimeType,
        fileSize: frame.totalSize,
      );
      if (messageId.isEmpty) return;
      mapping[frame.fileId] = messageId;
    }

    final handler = _fileChunkHandler;
    if (handler != null) {
      handler(threadId, messageId, frame).catchError((_) {});
    }
  }

  void _onFileProbe(
    String threadId,
    FileProbeFrame frame,
    SecureChannel channel,
  ) {
    if (!_isValidIncomingFileId(frame.fileId) ||
        frame.totalSize <= 0 ||
        frame.totalSize > kMaxFileBytes) {
      return;
    }
    final thread = _getThread(threadId);
    if (thread == null || _atCapacity[threadId] == true) return;

    final mapping = _fileToMessageId[threadId] ??= {};
    var messageId = mapping[frame.fileId];
    if (messageId == null) {
      if (mapping.length >= kMaxActiveIncomingAttachments) return;
      messageId = addFileMessage(
        threadId: threadId,
        origin: MessageOrigin.remote,
        fileId: frame.fileId,
        fileName: frame.fileName,
        mimeType: frame.mimeType,
        fileSize: frame.totalSize,
      );
      if (messageId.isEmpty) return;
      mapping[frame.fileId] = messageId;
    }

    final handler = _fileProbeHandler;
    if (handler != null) {
      handler(threadId, messageId, frame, channel).catchError((_) {});
    }
  }

  void _onFileComplete(String threadId, FileCompleteFrame frame) {
    final messageId = _fileToMessageId[threadId]?[frame.fileId];
    if (messageId == null) return;

    final handler = _fileCompleteHandler;
    if (handler != null) {
      handler(
        threadId,
        messageId,
        frame.fileId,
        frame.sha256,
      ).catchError((_) {});
    }
  }

  void _onEphemeralMediaChunk(String threadId, EphemeralMediaFrame frame) {
    if (!_isValidIncomingFileId(frame.mediaId) ||
        frame.totalSize <= 0 ||
        frame.totalSize > kEphemeralCacheMaxBytes) {
      return;
    }
    final thread = _getThread(threadId);
    if (thread == null || _atCapacity[threadId] == true) return;

    final mapping = _fileToMessageId[threadId] ??= {};
    var messageId = mapping[frame.mediaId];
    if (messageId == null) {
      if (mapping.length >= kMaxActiveIncomingAttachments) return;
      messageId = addFileMessage(
        threadId: threadId,
        origin: MessageOrigin.remote,
        fileId: frame.mediaId,
        fileName: 'Private media',
        mimeType: frame.mimeType,
        fileSize: frame.totalSize,
        isEphemeral: true,
      );
      if (messageId.isEmpty) return;
      mapping[frame.mediaId] = messageId;
    }

    final handler = _ephemeralMediaChunkHandler;
    if (handler != null) {
      handler(threadId, messageId, frame).catchError((_) {});
    }
  }

  void _onFileCancel(String threadId, FileCancelFrame frame) {
    _fileToMessageId[threadId]?.remove(frame.fileId);

    final handler = _fileCancelHandler;
    if (handler != null) {
      handler(threadId, frame.fileId).catchError((_) {});
    }
  }

  void _onGroupControl(
    String threadId,
    GroupControlFrame frame,
    SecureChannel channel,
  ) {
    final handler = _groupControlHandler;
    if (handler != null) {
      handler(threadId, frame, channel).catchError((_) {});
    }
  }

  void _onGroupMessage(
    String threadId,
    GroupMessageFrame frame,
    SecureChannel channel,
  ) {
    final handler = _groupMessageHandler;
    if (handler != null) {
      handler(threadId, frame, channel).catchError((_) {});
    }
  }

  void _onCallSignal(String threadId, CallSignalFrame frame) {
    final handler = _callSignalHandler;
    if (handler == null) return;
    final thread = _getThread(threadId);
    final displayName = thread?.peerDisplayName ?? threadId.substring(0, 8);
    handler(threadId, displayName, frame).catchError((_) {});
  }

  void detachChannel(String threadId, {SecureChannel? expectedChannel}) {
    final current = _channels[threadId];
    if (expectedChannel != null && !identical(current, expectedChannel)) {
      return;
    }

    _subs.remove(threadId)?.cancel();
    _cancelPhase3Subs(threadId);
    final removed = _channels.remove(threadId);
    if (removed != null) {
      unawaited(removed.close().catchError((_) {}));
    }
    _fileToMessageId.remove(threadId);
    _typingTimers.remove(threadId)?.cancel();
    if (_peerTyping.remove(threadId) == true) {
      if (!_typingChangesCtrl.isClosed) {
        _typingChangesCtrl.add(MapEntry(threadId, false));
      }
    }
    if (_disposed) return;

    final thread = _getThread(threadId);
    if (thread == null) return;

    if (!thread.manuallyDisconnected) {
      thread.disconnectedAt = DateTime.now();
    }
    thread.status = ThreadStatus.disconnected;
    for (var i = 0; i < thread.messages.length; i++) {
      final m = thread.messages[i];
      if (m.deliveryStatus == MessageDeliveryStatus.sending) {
        thread.messages[i] = m.copyWith(
          deliveryStatus: MessageDeliveryStatus.disconnected,
        );
      }
    }
    _saveThread(thread);
    _notify(threadId);

    if (!thread.manuallyDisconnected) {
      _wipeScheduler.scheduleWipe(
        threadId,
        autoWipeDelay,
        () => wipeThread(threadId),
      );
    }
  }

  Future<void> endConnection(String threadId) async {
    final thread = _getThread(threadId);
    if (thread != null) {
      thread.manuallyDisconnected = true;
      _saveThread(thread);
    }

    final channel = _channels[threadId];
    if (channel != null) {
      try {
        await channel.sendClose(reason: 'user-ended');
      } catch (_) {
        await channel.close();
      }
    }
    detachChannel(threadId, expectedChannel: channel);
  }

  Future<void> wipeAll() async {
    _wipeScheduler.cancelAll();
    for (final channel in List.of(_channels.values)) {
      try {
        await channel.sendWipe();
      } catch (_) {}
      try {
        await channel.close();
      } catch (_) {}
    }
    _channels.clear();
    _subs.forEach((_, sub) => sub.cancel());
    _subs.clear();
    _phase3Subs.forEach((_, subs) {
      for (final s in subs) {
        s.cancel();
      }
    });
    _phase3Subs.clear();
    _clearThreads();
    _atCapacity.clear();
    _peerTyping.clear();
    _oneWayInbox.clear();
    _oneWayOnlyThreads.clear();
    _seenIds.clear();
    _fileToMessageId.clear();
    _typingTimers.forEach((_, t) => t.cancel());
    _typingTimers.clear();
    _threadUpdatesCtrl.add(threads);
    _oneWayInboxCtrl.add(List.unmodifiable(_oneWayInbox));
  }

  Future<void> clearThread(String threadId) async {
    _wipeScheduler.cancelWipe(threadId);
    final thread = _getThread(threadId);
    if (thread == null) return;
    thread.messages.clear();
    _saveThread(thread);
    _seenIds[threadId]?.clear();
    _atCapacity[threadId] = false;
    _notify(threadId);
  }

  void wipeThread(String threadId) {
    _wipeScheduler.cancelWipe(threadId);
    _subs.remove(threadId)?.cancel();
    _cancelPhase3Subs(threadId);
    _channels.remove(threadId);
    _fileToMessageId.remove(threadId);
    _typingTimers.remove(threadId)?.cancel();
    _peerTyping.remove(threadId);
    _seenIds.remove(threadId);
    _atCapacity.remove(threadId);
    _oneWayOnlyThreads.remove(threadId);
    _removeThread(threadId);
    _notifyAll();
  }

  void createThread(
    String peerStaticKeyFingerprint,
    String peerDisplayName,
    String peerDeviceSuffix,
    String peerSessionId,
    String peerHost,
    int peerPort,
  ) {
    final threadId = peerStaticKeyFingerprint;
    if (_hasThread(threadId)) return;
    final thread = ChatThread(
      threadId: threadId,
      peerDisplayName: peerDisplayName,
      peerDeviceSuffix: peerDeviceSuffix,
      peerStaticKeyFingerprint: peerStaticKeyFingerprint,
      peerSessionId: peerSessionId,
      peerHost: peerHost,
      peerPort: peerPort,
      status: ThreadStatus.disconnected,
    );
    _saveThread(thread);
    _seenIds[threadId] = LinkedHashSet<String>();
    _atCapacity[threadId] = false;
    _notifyAll();
  }

  Future<void> closeThread(String threadId) async {
    await endConnection(threadId);
    final thread = _getThread(threadId);
    if (thread != null) {
      thread.messages.clear();
      _saveThread(thread);
      _notify(threadId);
    }
    _removeThread(threadId);
    _seenIds.remove(threadId);
    _atCapacity.remove(threadId);
    _oneWayOnlyThreads.remove(threadId);
    _notifyAll();
  }

  void injectSystemMessage(String threadId, String text) {
    final thread = _getThread(threadId);
    if (thread == null) return;
    final msg = ChatMessage(
      messageId: _uuid.v4(),
      threadId: threadId,
      origin: MessageOrigin.local,
      text: text,
      timestamp: DateTime.now(),
      deliveryStatus: MessageDeliveryStatus.delivered,
      isSystem: true,
    );
    thread.messages.add(msg);
    _saveThread(thread);
    _notify(threadId);
  }

  bool isAtCapacity(String threadId) => _atCapacity[threadId] ?? false;

  ConnectionQuality? getChannelQuality(String threadId) =>
      _channels[threadId]?.connectionQuality;

  SecureChannel? getChannel(String threadId) => _channels[threadId];

  List<String> get activeChannelFingerprints => _channels.keys.toList();

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    try {
      _wipeScheduler.cancelAll();
    } catch (_) {}

    try {
      _oneWayCleanupTimer?.cancel();
      _oneWayCleanupTimer = null;
    } catch (_) {}

    for (final t in _typingTimers.values) {
      try {
        t.cancel();
      } catch (_) {}
    }
    _typingTimers.clear();

    final subs = _subs.values.toList();
    _subs.clear();
    for (final sub in subs) {
      await sub.cancel().catchError((_) {});
    }

    for (final list in _phase3Subs.values) {
      for (final s in list) {
        await s.cancel().catchError((_) {});
      }
    }
    _phase3Subs.clear();

    final channels = _channels.values.toList();
    _channels.clear();
    for (final ch in channels) {
      await ch.close().catchError((_) {});
    }

    try {
      await _threadUpdatesCtrl.close().catchError((_) {});
    } catch (_) {}
    try {
      await _threadChangesCtrl.close().catchError((_) {});
    } catch (_) {}
    try {
      await _typingChangesCtrl.close().catchError((_) {});
    } catch (_) {}
    try {
      await _oneWayInboxCtrl.close().catchError((_) {});
    } catch (_) {}
  }

  void _onIncomingMessage(String threadId, ChatMessageFrame frame) {
    final parsedTime = _safeProtocolTime(frame.timestamp);
    if (parsedTime == null) return;

    if (_receiveMessageCoordinator != null) {
      final msg = ChatMessage(
        messageId: frame.messageId,
        threadId: threadId,
        origin: MessageOrigin.remote,
        text: frame.text,
        timestamp: parsedTime,
        deliveryStatus: MessageDeliveryStatus.delivered,
        replyToMessageId: frame.replyToMessageId,
      );
      _receiveMessageCoordinator.receive(msg);
      return;
    }

    final thread = _getThread(threadId);
    if (thread == null) return;

    final seen = _seenIds[threadId] ??= LinkedHashSet<String>();
    if (seen.contains(frame.messageId)) return;
    seen.add(frame.messageId);

    if (_atCapacity[threadId] == true) return;

    final msg = ChatMessage(
      messageId: frame.messageId,
      threadId: threadId,
      origin: MessageOrigin.remote,
      text: frame.text,
      timestamp: parsedTime,
      deliveryStatus: MessageDeliveryStatus.delivered,
      replyToMessageId: frame.replyToMessageId,
    );
    _addMessage(thread, msg);
    thread.unreadCount++;
    _saveThread(thread);
    _notify(threadId);
  }

  void _addMessage(ChatThread thread, ChatMessage msg) {
    thread.messages.add(msg);
    _enforceCapacity(thread);
    _saveThread(thread);
  }

  void _enforceCapacity(ChatThread thread) {
    if (thread.messages.length > kMaxThreadMessages ||
        thread.totalBytes > kMaxThreadBytes) {
      _atCapacity[thread.threadId] = true;
    }
  }

  void _updateDeliveryStatus(
    ChatThread thread,
    String messageId,
    MessageDeliveryStatus status,
  ) {
    for (var i = 0; i < thread.messages.length; i++) {
      if (thread.messages[i].messageId == messageId) {
        thread.messages[i] = thread.messages[i].copyWith(
          deliveryStatus: status,
        );
        _saveThread(thread);
        return;
      }
    }
  }

  void _notify(String threadId) {
    final thread = _getThread(threadId);
    if (thread == null) return;
    if (!_threadChangesCtrl.isClosed) _threadChangesCtrl.add(thread);
    if (!_threadUpdatesCtrl.isClosed) {
      _threadUpdatesCtrl.add(threads);
    }
  }

  void _notifyAll() {
    if (!_threadUpdatesCtrl.isClosed) {
      _threadUpdatesCtrl.add(threads);
    }
  }

  static const _uuid = Uuid();
}
