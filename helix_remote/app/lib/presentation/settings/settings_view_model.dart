import 'package:helix_remote/app/remote_messaging_service.dart';
import 'package:helix_remote_sync/helix_remote_sync.dart';

/// Read-model boundary for account and privacy summaries in Settings.
class SettingsViewModel {
  SettingsViewModel(this._messaging);

  final RemoteMessagingService _messaging;

  Stream<RemoteSyncChange> get changes => _messaging.changes;
  String get displayName => _messaging.currentDisplayName ?? '';
  String get accountId => _messaging.currentAccountId ?? '';
  int get blockedContactsCount => _messaging.db
      .getContacts()
      .where((contact) => contact.status == 'Blocked')
      .length;
  int get groupCount {
    try {
      return _messaging.conversationListByKind('groups').length;
    } catch (_) {
      return _messaging
          .conversationList()
          .where((conversation) => conversation.type == 'Group')
          .length;
    }
  }
  int get lockedConversationCount => _messaging.db.getLockedConversations().length;
  bool get appLockEnabled => _messaging.db.getAppLockSettings().enabled;
  int get defaultDisappearingSeconds =>
      _messaging.db.getAccountDefaultDisappearingSeconds();
  bool get notificationPreviewsEnabled =>
      _messaging.db.getNotificationPreviewsEnabled();
  bool get silenceUnknownCallers => _messaging.db.getSilenceUnknownCallers();
}
