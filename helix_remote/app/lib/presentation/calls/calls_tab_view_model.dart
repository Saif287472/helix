import 'package:helix_remote/app/remote_messaging_service.dart';
import 'package:helix_remote_domain/models.dart';

/// Presentation boundary for data used by the calls tab.
///
/// Keeping contact resolution here means the screen stays concerned with call
/// history and navigation, rather than persistence and messaging APIs.
class CallsTabViewModel {
  CallsTabViewModel(this._messaging);

  final RemoteMessagingService _messaging;

  String? conversationIdForPeer(String peerId) =>
      _messaging.conversationIdForPeer(peerId);

  String? peerDisplayName(String conversationId) =>
      _messaging.peerDisplayName(conversationId);

  List<RemoteContact> acceptedContacts() => _messaging.acceptedContacts();

  String get currentAccountId => _messaging.currentAccountId ?? '';
}
