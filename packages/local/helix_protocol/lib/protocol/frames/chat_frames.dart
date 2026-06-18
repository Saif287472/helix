part of '../protocol_messages.dart';

// ---------------------------------------------------------------------------
// 0x08 ChatMessageFrame
// ---------------------------------------------------------------------------

class ChatMessageFrame extends ProtocolFrame {
  @override
  final int type = kTypeChatMessage;

  final String messageId;
  final String text;
  final int timestamp; // unix ms

  /// Optional reference to the message being replied to.
  final String? replyToMessageId;

  ChatMessageFrame({
    required this.messageId,
    required this.text,
    required this.timestamp,
    this.replyToMessageId,
  });

  factory ChatMessageFrame._fromMap(Map<Object?, Object?> map) =>
      ChatMessageFrame(
        messageId: _requireString(map, 1, 'messageId'),
        text: _requireString(map, 2, 'text'),
        timestamp: _requireInt(map, 3, 'timestamp'),
        replyToMessageId: map[4] as String?,
      );

  @override
  Uint8List encode() => _cborEncodeMap({
    0: kTypeChatMessage,
    1: messageId,
    2: text,
    3: timestamp,
    if (replyToMessageId != null) 4: replyToMessageId,
  });
}

// ---------------------------------------------------------------------------
// 0x09 ChatAckFrame
// ---------------------------------------------------------------------------

class ChatAckFrame extends ProtocolFrame {
  @override
  final int type = kTypeChatAck;

  final String messageId;
  final bool ok;

  ChatAckFrame({required this.messageId, required this.ok});

  factory ChatAckFrame._fromMap(Map<Object?, Object?> map) => ChatAckFrame(
    messageId: _requireString(map, 1, 'messageId'),
    ok: _requireBool(map, 2, 'ok'),
  );

  @override
  Uint8List encode() => _cborEncodeMap({0: kTypeChatAck, 1: messageId, 2: ok});
}

// ---------------------------------------------------------------------------
// 0x0A KeepaliveFrame
// ---------------------------------------------------------------------------

class KeepaliveFrame extends ProtocolFrame {
  @override
  final int type = kTypeKeepalive;

  final int counter;

  KeepaliveFrame({required this.counter});

  factory KeepaliveFrame._fromMap(Map<Object?, Object?> map) =>
      KeepaliveFrame(counter: _requireInt(map, 1, 'counter'));

  @override
  Uint8List encode() => _cborEncodeMap({0: kTypeKeepalive, 1: counter});
}

// ---------------------------------------------------------------------------
// 0x0B CloseFrame
// ---------------------------------------------------------------------------

class CloseFrame extends ProtocolFrame {
  @override
  final int type = kTypeClose;

  /// Generic close reason (not sensitive).
  final String reason;

  CloseFrame({required this.reason});

  factory CloseFrame._fromMap(Map<Object?, Object?> map) =>
      CloseFrame(reason: _requireString(map, 1, 'reason'));

  @override
  Uint8List encode() => _cborEncodeMap({0: kTypeClose, 1: reason});
}

// ---------------------------------------------------------------------------
// 0x0C ProfileUpdateFrame
// ---------------------------------------------------------------------------

class ProfileUpdateFrame extends ProtocolFrame {
  @override
  final int type = kTypeProfileUpdate;

  final String newDisplayName;

  ProfileUpdateFrame({required this.newDisplayName});

  factory ProfileUpdateFrame._fromMap(Map<Object?, Object?> map) =>
      ProfileUpdateFrame(
        newDisplayName: _requireString(map, 1, 'newDisplayName'),
      );

  @override
  Uint8List encode() =>
      _cborEncodeMap({0: kTypeProfileUpdate, 1: newDisplayName});
}

// ---------------------------------------------------------------------------
// 0x0D BusyFrame
// ---------------------------------------------------------------------------

class BusyFrame extends ProtocolFrame {
  @override
  final int type = kTypeBusy;

  BusyFrame();

  // ignore: avoid_unused_constructor_parameters
  factory BusyFrame._fromMap(Map<Object?, Object?> map) => BusyFrame();

  @override
  Uint8List encode() => _cborEncodeMap({0: kTypeBusy});
}

// ---------------------------------------------------------------------------
// 0x10 TypingIndicatorFrame
// ---------------------------------------------------------------------------

class TypingIndicatorFrame extends ProtocolFrame {
  @override
  final int type = kTypeTypingIndicator;

  final bool isTyping;

  TypingIndicatorFrame({required this.isTyping});

  factory TypingIndicatorFrame._fromMap(Map<Object?, Object?> map) =>
      TypingIndicatorFrame(isTyping: _requireBool(map, 1, 'isTyping'));

  @override
  Uint8List encode() => _cborEncodeMap({0: kTypeTypingIndicator, 1: isTyping});
}

// ---------------------------------------------------------------------------
// 0x11 ReadReceiptFrame
// ---------------------------------------------------------------------------

class ReadReceiptFrame extends ProtocolFrame {
  @override
  final int type = kTypeReadReceipt;

  final List<String> messageIds;

  ReadReceiptFrame({required this.messageIds});

  factory ReadReceiptFrame._fromMap(Map<Object?, Object?> map) =>
      ReadReceiptFrame(messageIds: _requireStringList(map, 1, 'messageIds'));

  @override
  Uint8List encode() => _cborEncodeMap({0: kTypeReadReceipt, 1: messageIds});
}

// ---------------------------------------------------------------------------
// 0x12 ReactionFrame
// ---------------------------------------------------------------------------

class ReactionFrame extends ProtocolFrame {
  @override
  final int type = kTypeReaction;

  final String messageId;
  final String emoji;

  /// `true` to remove a previously-sent reaction.
  final bool remove;

  ReactionFrame({
    required this.messageId,
    required this.emoji,
    required this.remove,
  });

  factory ReactionFrame._fromMap(Map<Object?, Object?> map) => ReactionFrame(
    messageId: _requireString(map, 1, 'messageId'),
    emoji: _requireString(map, 2, 'emoji'),
    remove: _requireBool(map, 3, 'remove'),
  );

  @override
  Uint8List encode() =>
      _cborEncodeMap({0: kTypeReaction, 1: messageId, 2: emoji, 3: remove});
}

// ---------------------------------------------------------------------------
// 0x14 EditMessageFrame
// ---------------------------------------------------------------------------

class EditMessageFrame extends ProtocolFrame {
  @override
  final int type = kTypeEditMessage;

  final String messageId;
  final String newText;
  final int editedAt; // unix ms

  EditMessageFrame({
    required this.messageId,
    required this.newText,
    required this.editedAt,
  });

  factory EditMessageFrame._fromMap(Map<Object?, Object?> map) =>
      EditMessageFrame(
        messageId: _requireString(map, 1, 'messageId'),
        newText: _requireString(map, 2, 'newText'),
        editedAt: _requireInt(map, 3, 'editedAt'),
      );

  @override
  Uint8List encode() => _cborEncodeMap({
    0: kTypeEditMessage,
    1: messageId,
    2: newText,
    3: editedAt,
  });
}

// ---------------------------------------------------------------------------
// 0x15 DeleteMessageFrame
// ---------------------------------------------------------------------------

class DeleteMessageFrame extends ProtocolFrame {
  @override
  final int type = kTypeDeleteMessage;

  final String messageId;

  DeleteMessageFrame({required this.messageId});

  factory DeleteMessageFrame._fromMap(Map<Object?, Object?> map) =>
      DeleteMessageFrame(messageId: _requireString(map, 1, 'messageId'));

  @override
  Uint8List encode() => _cborEncodeMap({0: kTypeDeleteMessage, 1: messageId});
}

// ---------------------------------------------------------------------------
// 0x16 WipeFrame  — signals the peer to destroy all chat data immediately
// ---------------------------------------------------------------------------

class WipeFrame extends ProtocolFrame {
  @override
  final int type = kTypeWipe;

  WipeFrame();

  factory WipeFrame._fromMap(Map<Object?, Object?> _) => WipeFrame();

  @override
  Uint8List encode() => _cborEncodeMap({0: kTypeWipe});
}
