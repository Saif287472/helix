import 'dart:convert';

import 'package:helix_remote_server/src/platform/observability/log.dart';
import 'package:helix_remote_server/src/platform/observability/metrics.dart';
import 'package:helix_remote_server/src/platform/push/push.dart';
import 'package:test/test.dart';

/// A phone that did not ring has to be explainable from the server's own
/// lines: one `push` event and one count per wake-up, by reason and outcome,
/// with nothing in them the device did not already send.
void main() {
  group('PushTrail', () {
    test('one line per wake-up, with the device it was for', () {
      final sink = MemorySink();
      final trail = PushTrail(Log(sink: sink), Metrics());

      trail.record(PushOutcome.sent, PushReason.message, 'device-1');

      final line = jsonDecode(sink.lines.single) as Map;
      expect(line['event'], 'push');
      expect(line['component'], 'push');
      expect(line['device_id'], 'device-1');
      expect(line['reason'], 'message');
      expect(line['outcome'], 'sent');
      expect(line.keys, isNot(contains('token')));
    });

    test('a refusal carries the provider\'s reason, and nothing else does', () {
      final sink = MemorySink();
      final trail = PushTrail(Log(sink: sink), Metrics());

      trail.record(
        PushOutcome.failed,
        PushReason.call,
        'device-2',
        error: 'unregistered',
      );
      trail.record(PushOutcome.providerOff, PushReason.callEnded, 'device-3');

      final failed = jsonDecode(sink.lines[0]) as Map;
      expect(failed['outcome'], 'failed');
      expect(failed['error'], 'unregistered');
      expect((jsonDecode(sink.lines[1]) as Map).keys, isNot(contains('error')));
    });

    test('the counts share one family, whatever asked for it', () {
      final metrics = Metrics();
      // Messaging and calls each build a trail on the node's own Metrics.
      final mail = PushTrail(Log(sink: MemorySink()), metrics);
      final calls = PushTrail(Log(sink: MemorySink()), metrics);

      mail.record(PushOutcome.sent, PushReason.message, 'device-1');
      mail.record(PushOutcome.online, PushReason.message, 'device-2');
      calls.record(PushOutcome.sent, PushReason.message, 'device-3');
      calls.record(PushOutcome.noToken, PushReason.call, 'device-4');

      final counter = metrics.counter(
        'helix_push_total',
        'Device wake-ups, by reason and outcome',
      );
      expect(counter.value({'reason': 'message', 'outcome': 'sent'}), 2.0);
      expect(counter.value({'reason': 'message', 'outcome': 'online'}), 1.0);
      expect(counter.value({'reason': 'call', 'outcome': 'no_token'}), 1.0);
      expect(counter.value({'reason': 'call', 'outcome': 'sent'}), 0.0);
      expect(
        metrics.render(),
        contains('helix_push_total{reason="message",outcome="sent"} 2.0'),
      );
    });

    test('every outcome has its own word', () {
      expect(
        PushOutcome.values.map((o) => o.wire).toSet(),
        hasLength(PushOutcome.values.length),
      );
      // The words an operator greps for, in the order a wake-up can end.
      expect(PushOutcome.values.map((o) => o.wire).toList(), [
        'sent',
        'online',
        'no_token',
        'provider_off',
        'failed',
        'token_gone',
      ]);
    });
  });
}
