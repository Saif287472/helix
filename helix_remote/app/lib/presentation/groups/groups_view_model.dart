import 'package:helix_remote/app/remote_messaging_service.dart';
import 'package:helix_remote_domain/models.dart';

/// Read-model boundary for group list presentation.
class GroupsViewModel {
  GroupsViewModel(this._messaging);

  final RemoteMessagingService _messaging;

  List<RemoteConversation> conversations() => _messaging.conversationList();
  List<String> memberIds(String conversationId) =>
      _messaging.conversationMemberIds(conversationId);
  String get currentAccountId => _messaging.currentAccountId ?? '';
}
