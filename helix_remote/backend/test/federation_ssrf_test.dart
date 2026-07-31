// Batch 3 — SSRF defense in FederationClient.
//
// A federation partner's `address` is learned from the (directory-attested,
// but not otherwise verified) federation directory, so it must not be
// trusted enough to let this server be used to probe cloud metadata
// endpoints (169.254.169.254) or other link-local-only services.

import 'package:helix_remote_backend/helix_remote_backend.dart';
import 'package:helix_remote_backend/src/server_identity.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  late BackendDatabase db;
  late ServerIdentity identity;
  late FederationClient client;

  setUp(() async {
    db = BackendDatabase(sqlite3.openInMemory());
    identity = await ServerIdentity.loadOrCreate(db);
    client = FederationClient(
      db: db,
      identity: identity,
      directoryUrl: 'http://127.0.0.1:1',
    );
  });

  Future<void> seedFederatedServer({
    required String domain,
    required String address,
  }) async {
    db.upsertFederationServer(
      serverId: 'evil_server',
      domain: domain,
      publicKey: 'irrelevant_public_key',
      address: address,
      trustSource: 'directory',
    );
  }

  test('proxyCallSignal drops the request without connecting when the peer '
      'address resolves to the cloud metadata (link-local) range', () async {
    await seedFederatedServer(
      domain: 'evil.test',
      address: 'http://169.254.169.254:1234',
    );

    await expectLater(
      client
          .proxyCallSignal(
            domain: 'evil.test',
            senderAccountId: 'alice@a.test',
            senderDeviceId: 'alice_device',
            signal: {'signal_type': 'offer', 'call_id': 'call_1'},
          )
          .timeout(const Duration(seconds: 2)),
      throwsA(
        isA<FederationHttpException>().having(
          (e) => e.statusCode,
          'statusCode',
          equals(403),
        ),
      ),
    );
  });

  test('proxyMessage drops the request when the peer address resolves to a '
      'link-local address', () async {
    await seedFederatedServer(
      domain: 'evil2.test',
      address: 'http://169.254.169.254:1234',
    );

    await expectLater(
      client
          .proxyMessage(remoteAccountId: 'bob@evil2.test', body: {'foo': 'bar'})
          .timeout(const Duration(seconds: 2)),
      throwsA(
        isA<FederationHttpException>().having(
          (e) => e.statusCode,
          'statusCode',
          equals(403),
        ),
      ),
    );
  });
}
