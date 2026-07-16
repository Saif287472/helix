import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'package:helix_local_protocol/application/contracts/gateways.dart';
import 'package:helix_local_domain/application/contracts/repositories.dart';
import 'package:helix_local_protocol/application/contracts/use_cases.dart';
import 'package:helix_local_domain/core/constants.dart';
import 'package:helix_local_domain/domain/models.dart';

class SendMessageUseCaseImpl implements SendMessageUseCase {
  SendMessageUseCaseImpl({
    required this._conversationRepository,
    required this._messageGateway,
    required this._messageCodec,
    required this._onNotify,
    required this._isAtCapacity,
    required this._setAtCapacity,
    required this._onChannelFailed,
  });

  final ConversationRepository _conversationRepository;
  final MessageGateway _messageGateway;
  final MessageCodec _messageCodec;
  final void Function(String threadId) _onNotify;
  final bool Function(String threadId) _isAtCapacity;
  final void Function(String threadId, bool atCapacity) _setAtCapacity;
  final void Function(String threadId) _onChannelFailed;

  static const _uuid = Uuid();

  @override
  Future<void> sendText({
    required String threadId,
    required String text,
    String? replyToMessageId,
  }) async {
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

    final thread = _conversationRepository.getThread(threadId);
    if (thread == null) throw StateError('No thread for threadId=$threadId');

    if (_isAtCapacity(threadId)) {
      throw StateError(
        'Thread $threadId is at memory capacity; clear or close first',
      );
    }

    if (thread.messages.length + 1 > kMaxThreadMessages ||
        thread.totalBytes + textBytes.length > kMaxThreadBytes) {
      _setAtCapacity(threadId, true);
      throw StateError('Thread memory limit reached');
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

    // Save local state
    thread.messages.add(chatMsg);
    await _conversationRepository.saveThread(thread);
    _onNotify(threadId);

    // Build frame
    final frame = _messageCodec.encodeMessage(
      messageId: messageId,
      threadId: threadId,
      text: text,
      timestamp: now.millisecondsSinceEpoch,
      replyToMessageId: replyToMessageId,
    );

    try {
      await _messageGateway.sendMessage(threadId, frame);
      await _updateDeliveryStatus(
        threadId,
        messageId,
        MessageDeliveryStatus.delivered,
      );
    } catch (_) {
      await _updateDeliveryStatus(
        threadId,
        messageId,
        MessageDeliveryStatus.failed,
      );
      _onChannelFailed(threadId);
    }
    _onNotify(threadId);
  }

  Future<void> _updateDeliveryStatus(
    String threadId,
    String messageId,
    MessageDeliveryStatus status,
  ) async {
    final thread = _conversationRepository.getThread(threadId);
    if (thread == null) return;
    for (var i = 0; i < thread.messages.length; i++) {
      if (thread.messages[i].messageId == messageId) {
        thread.messages[i] = thread.messages[i].copyWith(
          deliveryStatus: status,
        );
        await _conversationRepository.saveThread(thread);
        return;
      }
    }
  }
}
