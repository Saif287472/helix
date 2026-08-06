import 'package:helix_remote/app/remote_messaging_service.dart';
import 'package:helix_remote_domain/models.dart';
import 'package:helix_remote_sync/helix_remote_sync.dart';

/// Screen-facing messaging boundary for the conversation list.
class ConversationListViewModel {
  ConversationListViewModel(this._messaging);

  final RemoteMessagingService _messaging;

  Stream<RemoteSyncChange> get changes => _messaging.changes;
  RemoteOutboxSummary outboxSummary() => _messaging.outboxSummary();
  List<RemoteConversation> conversations() => _messaging.conversationList();
  Future<List<RemoteDecryptedMessage>> preview(String conversationId) =>
      _messaging.messageHistory(conversationId, limit: 1);
  List<RemoteContact> acceptedContacts() => _messaging.acceptedContacts();
  String? conversationIdForPeer(String accountId) =>
      _messaging.conversationIdForPeer(accountId);
  List<String> memberIds(String conversationId) =>
      _messaging.conversationMemberIds(conversationId);
  String createDirectConversation(String accountId) =>
      _messaging.createDirectConversation(peerAccountId: accountId);
  String? get currentAccountId => _messaging.currentAccountId;
  int unreadCount(String conversationId) =>
      _messaging.unreadSummary(conversationId).unreadCount;
  List<RemoteConversation> customList(String listId) =>
      _messaging.conversationListByKind('custom', listId: listId);
  String? peerDisplayName(String conversationId) =>
      _messaging.peerDisplayName(conversationId);
  void markRead(String conversationId) => _messaging.markConversationRead(conversationId);
  void pin(String conversationId) => _messaging.pinConversation(conversationId, pinned: true);
  void mute(String conversationId) => _messaging.muteConversation(conversationId, muted: true);
  void lock(String conversationId) =>
      _messaging.db.setConversationLocked(conversationId, locked: true, hidden: false);
  void favorite(String conversationId) =>
      _messaging.favoriteConversation(conversationId, favorite: true);
  void createQuickList(String listId) => _messaging.createCustomConversationList(
        listId: listId,
        name: 'Quick list',
        sortOrder: 0,
      );
  void addToList({required String listId, required String conversationId, required int sortOrder}) =>
      _messaging.addConversationToCustomList(
        listId: listId,
        conversationId: conversationId,
        sortOrder: sortOrder,
      );
  void clearChat(String conversationId) => _messaging.clearChat(conversationId);
  void deleteConversation(String conversationId) =>
      _messaging.deleteConversation(conversationId);
  Future<void> retryFailedOutbox() => _messaging.retryFailedOutbox();
}
