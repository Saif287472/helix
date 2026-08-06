import 'package:helix_remote/app/remote_messaging_service.dart';
import 'package:helix_remote_domain/models.dart';
import 'package:helix_remote_storage/helix_remote_storage.dart';

/// Messaging and persistence boundary for a contact-information view.
class ContactInfoViewModel {
  ContactInfoViewModel(this._messaging);

  final RemoteMessagingService _messaging;

  String? peerDisplayName(String conversationId) =>
      _messaging.peerDisplayName(conversationId);
  String? peerAccountIdForConversation(String conversationId) =>
      _messaging.peerAccountIdForConversation(conversationId);
  String? conversationIdForPeer(String accountId) =>
      _messaging.conversationIdForPeer(accountId);
  List<RemoteConversation> conversations() => _messaging.conversationList();
  List<String> memberIds(String conversationId) =>
      _messaging.conversationMemberIds(conversationId);
  Future<List<RemoteDecryptedMessage>> messages(String conversationId) =>
      _messaging.messageHistory(conversationId, limit: 160);
  RemoteConversationPrivacy privacy(String conversationId) =>
      _messaging.db.getConversationPrivacy(conversationId);
  RemoteStorageSummary storage(String conversationId) =>
      _messaging.storageSummary(conversationId);
  String? get currentAccountId => _messaging.currentAccountId;

  void setPrivacy(String conversationId, RemoteConversationPrivacy privacy) =>
      _messaging.db.setConversationPrivacy(conversationId, privacy);
  void setLocked(String conversationId, {required bool locked}) =>
      _messaging.db.setConversationLocked(conversationId, locked: locked);
  void setDisappearingPolicy(String conversationId, int seconds) =>
      _messaging.db.setConversationDisappearingPolicy(conversationId, seconds);
  void setFavorite(String conversationId, {required bool favorite}) =>
      _messaging.favoriteConversation(conversationId, favorite: favorite);
  void addToList({required String listId, required String conversationId, required int sortOrder}) =>
      _messaging.addConversationToCustomList(
        listId: listId,
        conversationId: conversationId,
        sortOrder: sortOrder,
      );
  void clearChat(String conversationId) => _messaging.clearChat(conversationId);
  void blockContact(String accountId) => _messaging.blockContact(accountId);
  void reportContact({required String accountId, required String contextHash}) =>
      _messaging.reportAccount(
        subjectAccountId: accountId,
        category: 'contact',
        reasonCode: 'user_reported',
        contextHash: contextHash,
      );
  void saveNickname({required String accountId, required String nickname}) =>
      _messaging.addContact(peerAccountId: accountId, nickname: nickname);
}
