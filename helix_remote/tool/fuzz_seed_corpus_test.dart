import 'dart:math';

import 'package:helix_remote_domain/models.dart';
import 'package:test/test.dart';

void main() {
  const statuses = [
    RemoteMessageStatus.pending,
    RemoteMessageStatus.sent,
    RemoteMessageStatus.delivered,
    RemoteMessageStatus.read,
    RemoteMessageStatus.retrying,
    RemoteMessageStatus.failed,
    RemoteMessageStatus.offline,
    RemoteMessageStatus.keyChanged,
    RemoteMessageStatus.revokedDevice,
    'UNKNOWN',
    '',
  ];

  test('P8 property corpus: arbitrary message-status transitions never escape validation', () {
    final random = Random(0xC0DEC0DE);
    for (var seed = 0; seed < 2000; seed++) {
      final from = statuses[random.nextInt(statuses.length)];
      final to = statuses[random.nextInt(statuses.length)];
      expect(
        () => RemoteMessageStatus.validateTransition(from, to),
        anyOf(returnsNormally, throwsA(isA<Exception>())),
        reason: 'seed=$seed from=$from to=$to',
      );
    }
  });
}
