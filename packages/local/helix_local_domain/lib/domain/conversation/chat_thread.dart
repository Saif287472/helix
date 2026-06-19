import 'dart:convert';
import 'package:helix_local_domain/domain/conversation/chat_message.dart';

// ---------------------------------------------------------------------------
// Thread
// ---------------------------------------------------------------------------

enum ThreadStatus { connecting, active, disconnected }

/// Connection health derived from keepalive traffic staleness.
enum ConnectionQuality { good, fair, poor }

class ChatThread {
  final String threadId;
  final String peerDisplayName;
  final String peerDeviceSuffix;
  final String peerStaticKeyFingerprint;
  String peerSessionId;
  String peerHost;
  int peerPort;
  ThreadStatus status;
  final List<ChatMessage> messages;
  int unreadCount;
  bool hasNewSessionSeparator;
  bool isArchived;
  String draftText;

  /// Set to true when the user explicitly disconnects; suppresses auto-reconnect.
  bool manuallyDisconnected;

  /// When the channel last dropped due to a non-manual cause (network error).
  DateTime? disconnectedAt;

  ChatThread({
    required this.threadId,
    required this.peerDisplayName,
    required this.peerDeviceSuffix,
    required this.peerStaticKeyFingerprint,
    this.peerSessionId = '',
    this.peerHost = '',
    this.peerPort = 0,
    this.status = ThreadStatus.connecting,
    List<ChatMessage>? messages,
    this.unreadCount = 0,
    this.hasNewSessionSeparator = false,
    this.isArchived = false,
    this.draftText = '',
    this.manuallyDisconnected = false,
    this.disconnectedAt,
  }) : messages = messages ?? [];

  ChatMessage? get lastMessage => messages.isEmpty ? null : messages.last;

  int get totalBytes =>
      messages.fold(0, (sum, m) => sum + utf8.encode(m.text).length);
}
