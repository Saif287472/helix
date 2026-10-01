import 'dart:typed_data';

import 'package:helix_remote_server/src/platform/db/db.dart';
import 'package:helix_remote_server/src/platform/db/migrations.dart';

/// Schema `federation`: this server's signing key and known peers.
const federationMigrations = [Migration(1, 'federation_baseline', _baseline)];

String _baseline(String s) =>
    '''
CREATE TABLE $s.settings (
  key text PRIMARY KEY,
  value bytea NOT NULL
);
CREATE TABLE $s.peers (
  domain text PRIMARY KEY,
  public_key bytea NOT NULL,
  api_base text NOT NULL,
  fetched_at timestamptz NOT NULL,
  last_seen_at timestamptz
);
''';

final class Peer {
  const Peer({
    required this.domain,
    required this.publicKey,
    required this.apiBase,
    required this.fetchedAt,
  });

  final String domain;
  final Uint8List publicKey;
  final String apiBase;
  final DateTime fetchedAt;
}

final class FederationStore {
  FederationStore(this.s);

  /// Schema name.
  final String s;

  /// A setting, created by [create] on first use (race-safe).
  Future<Uint8List> setting(
    Db db,
    String key,
    Uint8List Function() create,
  ) async {
    await db.execute(
      'INSERT INTO $s.settings (key, value) VALUES (@k:text, @v:bytea) ON CONFLICT (key) DO NOTHING',
      {'k': key, 'v': create()},
    );
    final row = await db.queryOne(
      'SELECT value FROM $s.settings WHERE key = @k:text',
      {'k': key},
    );
    return row!.bytes('value');
  }

  Future<Peer?> peer(SqlSession db, String domain) async {
    final r = await db.queryOne(
      'SELECT domain, public_key, api_base, fetched_at FROM $s.peers WHERE domain = @d:text',
      {'d': domain},
    );
    return r == null
        ? null
        : Peer(
            domain: r.string('domain'),
            publicKey: r.bytes('public_key'),
            apiBase: r.string('api_base'),
            fetchedAt: r.time('fetched_at'),
          );
  }

  Future<void> savePeer(SqlSession db, Peer peer) async {
    await db.execute(
      'INSERT INTO $s.peers (domain, public_key, api_base, fetched_at) '
      'VALUES (@d:text, @k:bytea, @a:text, @f:timestamptz) '
      'ON CONFLICT (domain) DO UPDATE SET public_key = excluded.public_key, '
      'api_base = excluded.api_base, fetched_at = excluded.fetched_at',
      {
        'd': peer.domain,
        'k': peer.publicKey,
        'a': peer.apiBase,
        'f': peer.fetchedAt,
      },
    );
  }

  Future<void> touch(SqlSession db, String domain) async {
    await db.execute(
      'UPDATE $s.peers SET last_seen_at = now() WHERE domain = @d:text',
      {'d': domain},
    );
  }
}
