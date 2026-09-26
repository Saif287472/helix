import 'package:helix_remote_backend/src/account_restrictions.dart';
import 'package:test/test.dart';

void main() {
  group('isSuspendedActivity', () {
    test('refuses activity that reaches other people', () {
      for (final path in [
        'api/v1/messages/send',
        'api/v1/messages/edit',
        'api/v1/messages/reactions',
        'api/v1/messages/typing',
        'api/v1/messages/conversations/create',
        'api/v1/contacts/requests',
        'api/v1/contacts/requests/accept',
        'api/v1/contacts/add',
        'api/v1/accounts/profile',
        'api/v1/calls/signal',
        'api/v1/calls/pending/call_1/accept',
        'api/v1/attachments/upload',
        'api/v1/attachments/upload/file/f1',
        'api/v1/groups/create',
        'api/v1/groups/invite/respond',
        'api/v1/group-calls',
        'api/v1/group-calls/room_1/join',
      ]) {
        expect(isSuspendedActivity('POST', path), isTrue, reason: path);
      }
      expect(
        isSuspendedActivity('PUT', 'api/v1/attachments/upload/file/f1'),
        isTrue,
      );
    });

    test('keeps reading, receiving and self-management working', () {
      for (final path in [
        'api/v1/messages/cursor',
        'api/v1/messages/receipts',
        'api/v1/contacts/presence',
        'api/v1/contacts/requests/reject',
        'api/v1/contacts/requests/cancel',
        'api/v1/contacts/block',
        'api/v1/contacts/report',
        'api/v1/calls/pending/call_1/decline',
        'api/v1/groups/leave',
        'api/v1/accounts/devices/revoke',
        'api/v1/accounts/devices/rename',
        'api/v1/prekeys/publish',
        'api/v1/account/delete',
      ]) {
        expect(isSuspendedActivity('POST', path), isFalse, reason: path);
      }
      expect(isSuspendedActivity('GET', 'api/v1/messages/send'), isFalse);
      expect(isSuspendedActivity('DELETE', 'api/v1/account/delete'), isFalse);
    });

    test('tolerates a leading slash', () {
      expect(isSuspendedActivity('POST', '/api/v1/messages/send'), isTrue);
    });
  });
}
