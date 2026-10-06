import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/core/engine/helix_runtime.dart';
import 'package:helix_remote/core/platform/network_probe.dart';
import 'package:helix_remote_api/v2.dart';
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart'
    show BackupOptions, DbSessionTokenStore;

/// History transfers are opt-in in the engine now (a newly linked device, or a
/// stolen session, must not receive the whole history unasked). The app must
/// not silently turn either direction back on: the old device offers "Send
/// history to this device" after approving (devices tests), the new one shows
/// Accept / Decline (backup tests); here, the options the runtime builds.
void main() {
  test('the runtime passes the engine options with both transfers off', () {
    final db = HelixDb.inMemory(key: DatabaseKey.generate());
    addTearDown(db.close);
    final api = HelixApi(
      baseUrl: Uri.parse('http://127.0.0.1:9'),
      sessions: DbSessionTokenStore(db),
      clientName: 'test',
    );
    addTearDown(api.close);

    final options = HelixRuntime.backupOptionsFor(
      db: db,
      api: api,
      network: const DeviceNetworkProbe(),
    );

    expect(options.autoTransferToNewDevices, isFalse);
    expect(options.autoAcceptTransfers, isFalse);
    // And these are the engine's own defaults too, so a change there that
    // turned them on would be noticed in this build.
    const engineDefaults = BackupOptions();
    expect(engineDefaults.autoTransferToNewDevices, isFalse);
    expect(engineDefaults.autoAcceptTransfers, isFalse);
  });
}
