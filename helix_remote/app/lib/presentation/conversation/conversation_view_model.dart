import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:helix_remote/app/remote_messaging_service.dart';
import 'package:helix_remote_domain/models.dart';
import 'package:helix_remote_sync/helix_remote_sync.dart';

/// Presentation state and commands for one conversation.
///
/// This is deliberately a small, constructor-injected ChangeNotifier instead
/// of a screen-owned collection of subscriptions and async state. It keeps
/// Flutter widgets focused on rendering and lets the message delta policy be
/// tested without a widget tree.
class ConversationViewModel extends ChangeNotifier {
  ConversationViewModel({
    required this.conversationId,
    required RemoteMessagingService messaging,
    this.pageSize = 50,
  }) : _messaging = messaging {
    _changes = _messaging.changes.listen(_onRemoteChange);
  }

  final String conversationId;
  final RemoteMessagingService _messaging;
  final int pageSize;

  StreamSubscription<RemoteSyncChange>? _changes;
  List<RemoteDecryptedMessage> _messages = const [];
  bool _loaded = false;
  bool _loadingMore = false;
  bool _hasMore = false;
  String? _errorMessage;
  String _query = '';
  final Set<String> _receiptMarked = {};
  bool _disposed = false;

  List<RemoteDecryptedMessage> get messages => _messages;
  bool get loaded => _loaded;
  bool get loadingMore => _loadingMore;
  bool get hasMore => _hasMore;
  String? get errorMessage => _errorMessage;
  String? get currentAccountId => _messaging.currentAccountId;
  String? get peerDisplayName => _messaging.peerDisplayName(conversationId);

  List<String> get conversationMemberIds =>
      _messaging.conversationMemberIds(conversationId);

  List<String> get recipientDeviceIds =>
      _messaging.recipientDeviceIdsForConversation(conversationId);

  void clearChat() => _messaging.clearChat(conversationId);

  void setDisappearingPolicy(int seconds) =>
      _messaging.db.setConversationDisappearingPolicy(conversationId, seconds);

  void deleteForSelf(String messageId) => _messaging.deleteForSelf(messageId);

  void deleteForEveryone(RemoteDecryptedMessage message) =>
      _messaging.deleteForEveryone(
        messageId: message.messageId,
        conversationId: message.conversationId,
      );

  Future<void> editMessage(RemoteDecryptedMessage message, String plaintext) =>
      _messaging.editMessage(
        messageId: message.messageId,
        conversationId: message.conversationId,
        plaintext: plaintext,
      );

  void addReaction(RemoteDecryptedMessage message, String reaction) =>
      _messaging.addReaction(messageId: message.messageId, reaction: reaction);

  List<RemoteReactionDetail> reactionDetails(String messageId) =>
      _messaging.reactionDetails(messageId);

  void blockPeer() {
    final peer = conversationMemberIds
        .where((accountId) => accountId != currentAccountId)
        .firstOrNull;
    if (peer != null) _messaging.blockContact(peer);
  }

  Future<String> sendRichMedia({
    required String kind,
    required RemoteAttachmentManifest manifest,
    required String filename,
    required String keyDeliverySecret,
    String? caption,
    bool viewOnce = false,
  }) => _messaging.sendRichMedia(
    conversationId: conversationId,
    kind: kind,
    manifest: manifest,
    filename: filename,
    keyDeliverySecret: keyDeliverySecret,
    recipientDeviceIds: recipientDeviceIds,
    caption: caption,
    viewOnce: viewOnce,
  );

  bool canExportAttachment(RemoteAttachmentContent attachment) =>
      _messaging.canExportAttachment(
        conversationId: conversationId,
        attachment: attachment,
      );

  Future<void> load({String query = ''}) async {
    _query = query.trim();
    try {
      final messages = _query.isNotEmpty
          ? await _messaging.searchDecryptedHistory(
              conversationId: conversationId,
              query: _query,
            )
          : await _messaging.messageHistory(conversationId, limit: pageSize);
      _messages = messages;
      _loaded = true;
      _hasMore = _query.isEmpty && messages.length == pageSize;
      _errorMessage = null;
      _markVisibleReceipts(messages);
      _messaging.markConversationRead(conversationId);
      _notify();
    } catch (_) {
      _loaded = true;
      _errorMessage = 'Could not load messages. Tap to retry.';
      _notify();
    }
  }

  Future<void> loadMore() async {
    if (_loadingMore || _query.isNotEmpty) return;
    _loadingMore = true;
    _notify();
    try {
      final nextPage = await _messaging.messageHistory(
        conversationId,
        limit: pageSize,
        offset: _messages.length,
      );
      _messages = [..._messages, ...nextPage];
      _hasMore = nextPage.length == pageSize;
      _markVisibleReceipts(nextPage);
    } finally {
      _loadingMore = false;
      _notify();
    }
  }

  Future<void> sendText(String text, {RemoteReplyReference? replyTo}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final tempId = 'pending_${DateTime.now().microsecondsSinceEpoch}';
    final optimistic = RemoteDecryptedMessage(
      messageId: tempId,
      conversationId: conversationId,
      senderAccountId: currentAccountId ?? '',
      senderDeviceId: '',
      text: trimmed,
      status: 'PENDING',
      timestamp: DateTime.now().millisecondsSinceEpoch,
      replyTo: replyTo,
    );
    _messages = [optimistic, ..._messages];
    _notify();
    try {
      final messageId = await _messaging.sendText(
        conversationId: conversationId,
        plaintext: trimmed,
        recipientDeviceIds: _messaging.recipientDeviceIdsForConversation(
          conversationId,
        ),
        replyTo: replyTo,
      );
      // Ensure the real message is present before removing the UI placeholder.
      // The stream listener starts this same delta asynchronously, but waiting
      // here avoids a frame with neither the placeholder nor the stored row.
      await _applyMessageDelta(messageId);
      _messages = _messages
          .where((message) => message.messageId != tempId)
          .toList(growable: false);
      _notify();
    } catch (_) {
      _messages = _messages
          .where((message) => message.messageId != tempId)
          .toList(growable: false);
      _notify();
      rethrow;
    }
  }

  Future<void> publishTyping(bool isTyping) => _messaging.publishTyping(
    conversationId: conversationId,
    isTyping: isTyping,
  );

  void _onRemoteChange(RemoteSyncChange change) {
    if (_disposed) return;
    if (!change.affectsConversation(conversationId)) return;
    if (!change.affects(RemoteSyncChangeArea.messages)) return;
    final messageId = change.messageId;
    if (messageId == null) {
      // Older producers do not yet include an ID. Keep the safe fallback for
      // their changes; new sync and local message paths take the delta route.
      unawaited(load(query: _query));
      return;
    }
    unawaited(_applyMessageDelta(messageId));
  }

  Future<void> _applyMessageDelta(String messageId) async {
    final changed = await _messaging.messageById(messageId);
    if (_disposed) return;
    final existingIndex = _messages.indexWhere(
      (message) => message.messageId == messageId,
    );
    if (changed == null) {
      if (existingIndex >= 0) {
        _messages = [..._messages]..removeAt(existingIndex);
        _notify();
      }
      return;
    }
    if (_query.isNotEmpty &&
        !changed.text.toLowerCase().contains(_query.toLowerCase())) {
      if (existingIndex >= 0) {
        _messages = [..._messages]..removeAt(existingIndex);
        _notify();
      }
      return;
    }
    final next = [..._messages];
    if (existingIndex >= 0) {
      next[existingIndex] = changed;
    } else {
      next.add(changed);
    }
    next.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    // A new message while the newest page is full displaces only the oldest
    // rendered row. Older messages remain available through loadMore().
    if (_query.isEmpty && next.length > pageSize && !_hasMore) {
      next.removeLast();
      _hasMore = true;
    }
    _messages = next;
    _markVisibleReceipts([changed]);
    _notify();
  }

  void _markVisibleReceipts(List<RemoteDecryptedMessage> messages) {
    final accountId = currentAccountId;
    if (accountId == null) return;
    for (final message in messages) {
      if (message.senderAccountId == accountId) continue;
      if (!_receiptMarked.add(message.messageId)) continue;
      unawaited(
        _messaging.markDelivered(
          messageId: message.messageId,
          conversationId: message.conversationId,
        ),
      );
      unawaited(
        _messaging.markRead(
          messageId: message.messageId,
          conversationId: message.conversationId,
        ),
      );
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_changes?.cancel());
    super.dispose();
  }
}
