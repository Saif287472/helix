import 'dart:async';
import 'package:helix_remote_backend/helix_remote_backend.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  test('Concurrent getPrekeyBundleForDevice and upsertPrekeys transactions do not collide', () async {
    final db = BackendDatabase(sqlite3.openInMemory());
    try {
      db.createAccount('user1', 'alice', 'alice_identity_key');
      db.registerDevice('device1', 'user1', 'alice_device_agreement_key', 'Alice Phone');

      db.publishPrekeys(
        accountId: 'user1',
        deviceId: 'device1',
        signedPrekeyId: 1,
        signedPrekey: 'spk1',
        signature: 'sig1',
        oneTimePrekeys: List.generate(50, (i) => {
          'key_id': i,
          'public_key': 'otk_$i',
        }),
      );

      final futures = <Future<void>>[];
      for (var i = 0; i < 20; i++) {
        final index = i;
        futures.add(Future(() {
          if (index % 2 == 0) {
            db.getPrekeyBundleForDevice('user1', 'device1');
          } else {
            db.publishPrekeys(
              accountId: 'user1',
              deviceId: 'device1',
              signedPrekeyId: 1,
              signedPrekey: 'spk1',
              signature: 'sig1',
              oneTimePrekeys: [
                {'key_id': 100 + index, 'public_key': 'otk_concurrent_$index'},
              ],
            );
          }
        }));
      }

      await expectLater(Future.wait(futures), completes);
    } finally {
      db.close();
    }
  });

  test('Nested transaction execution with savepoints succeeds and commits', () {
    final db = BackendDatabase(sqlite3.openInMemory());
    try {
      db.createAccount('u1', 'user1', 'key1');
      db.transaction(() {
        db.registerDevice('d1', 'u1', 'devkey1', 'Phone');
        db.transaction(() {
          db.publishPrekeys(
            accountId: 'u1',
            deviceId: 'd1',
            signedPrekeyId: 1,
            signedPrekey: 'spk1',
            signature: 'sig1',
            oneTimePrekeys: [{'key_id': 1, 'public_key': 'otk1'}],
          );
        });
      });
      final bundle = db.getPrekeyBundleForDevice('u1', 'd1');
      expect(bundle, isNotNull);
      expect(bundle!['device_id'], equals('d1'));
    } finally {
      db.close();
    }
  });
}
