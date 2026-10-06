import 'package:test/test.dart';

import '../../tool/load/coordinator.dart';
import '../../tool/load/options.dart';
import '../support/test_database.dart';

/// Keeps the load harness (tool/load.dart) from rotting: a tiny run must
/// register, connect, send 1:1 and group messages, and deliver all of them.
void main() {
  test(
    'the load harness runs end to end at 20 devices',
    skip: databaseTestSkipReason,
    timeout: const Timeout(Duration(minutes: 4)),
    () async {
      final report = await runLoad(
        const LoadOptions(
          devices: 20,
          workers: 2,
          warmupSeconds: 1,
          durationSeconds: 5,
          drainSeconds: 15,
          rate: 1,
          groupSize: 4,
          groupShare: 0.3,
          ackSample: 0.2,
          oneTimePrekeys: 2,
        ),
      );
      expect(report.errors.values, isEmpty, reason: report.render());
      expect(report.accepted, greaterThan(20), reason: report.render());
      expect(report.lost, 0, reason: report.render());
      expect(report.run['e2e_group']!.count, greaterThan(0));
      expect(report.setup['connect']!.count, 20);
    },
  );
}
