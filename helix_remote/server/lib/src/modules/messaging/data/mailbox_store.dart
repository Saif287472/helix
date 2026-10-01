import 'dart:convert';
import 'dart:typed_data';

import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/src/platform/db/db.dart';

final class MailboxStore {
  MailboxStore(this.s);

  final String s;

  static const partitions = 16;
  static const quota = 10000;
  static const retention = Duration(days: 30);

  /// Allocates the next `seq` for each device (row-locked, so concurrent
  /// sends on any node never share a number) and counts it as pending.
  /// Throws `quota_exceeded` if a device has too many undelivered envelopes.
  Future<Map<String, int>> allocate(Tx tx, List<String> deviceIds) async {
    final rows = await tx.query(
      'INSERT INTO $s.device_seq (device_id, last_seq, pending) '
      'SELECT d, 1, 1 FROM unnest(@ids:_uuid) AS d '
      'ON CONFLICT (device_id) DO UPDATE SET last_seq = $s.device_seq.last_seq + 1, '
      'pending = $s.device_seq.pending + 1 '
      'RETURNING device_id, last_seq, pending',
      {'ids': deviceIds},
    );
    final out = <String, int>{};
    for (final r in rows) {
      if (r.integer('pending') > quota) {
        throw const ApiError(
          ErrorCode.quotaExceeded,
          message: 'a recipient device has too many undelivered messages',
        );
      }
      out[r.string('device_id')] = r.integer('last_seq');
    }
    return out;
  }

  Future<void> insert(
    Tx tx, {
    required Map<String, int> seqs,
    required Map<String, Uint8List?> payloads,
    required String id,
    required EnvelopeKind kind,
    EnvelopeSender? from,
    String? groupId,
    String? callId,
    JsonMap? data,
    required bool urgent,
  }) async {
    final devices = seqs.keys.toList();
    final withPayload = devices.where((d) => payloads[d] != null).toList();
    final withoutPayload = devices.where((d) => payloads[d] == null).toList();
    final common = {
      'id': id,
      'kind': kind.wire,
      'sa': from?.account,
      'sd': from?.device,
      'g': groupId,
      'c': callId,
      'data': data == null ? null : jsonEncode(data),
      'urgent': urgent,
      'ret': retention.inSeconds,
    };
    const columns =
        'device_id, seq, id, kind, sender_account, sender_device, group_id, call_id, '
        'payload, data, urgent, expires_at';
    const values = '@id:uuid, @kind:text, @sa:uuid, @sd:uuid, @g:uuid, @c:text';
    if (withPayload.isNotEmpty) {
      await tx.execute(
        'INSERT INTO $s.mailbox ($columns) '
        'SELECT d, q, $values, p, @data:jsonb, @urgent:boolean, '
        'now() + make_interval(secs => @ret:int8) '
        'FROM unnest(@devs:_uuid, @seqs:_int8, @payloads:_bytea) AS t(d, q, p)',
        {
          ...common,
          'devs': withPayload,
          'seqs': [for (final d in withPayload) seqs[d]!],
          'payloads': [for (final d in withPayload) payloads[d]!],
        },
      );
    }
    if (withoutPayload.isNotEmpty) {
      await tx.execute(
        'INSERT INTO $s.mailbox ($columns) '
        'SELECT d, q, $values, NULL, @data:jsonb, @urgent:boolean, '
        'now() + make_interval(secs => @ret:int8) '
        'FROM unnest(@devs:_uuid, @seqs:_int8) AS t(d, q)',
        {
          ...common,
          'devs': withoutPayload,
          'seqs': [for (final d in withoutPayload) seqs[d]!],
        },
      );
    }
  }

  Envelope _envelope(Row r) => Envelope(
    id: r.string('id'),
    kind: EnvelopeKind.values.firstWhere(
      (k) => k.wire == r.string('kind'),
      orElse: () => EnvelopeKind.unknown,
    ),
    sentAt: r.time('created_at'),
    seq: r.integer('seq'),
    from: r.isNull('sender_account')
        ? null
        : EnvelopeSender(
            account: r.string('sender_account'),
            device: r.string('sender_device'),
          ),
    groupId: r.optString('group_id'),
    callId: r.optString('call_id'),
    payload: r.optBytes('payload'),
    data: r.isNull('data') ? null : r.json('data'),
    urgent: r.boolean('urgent'),
  );

  Future<List<Envelope>> fetch(
    SqlSession db,
    String deviceId, {
    required int after,
    required int limit,
  }) async {
    final rows = await db.query(
      'SELECT seq, id, kind, sender_account, sender_device, group_id, call_id, payload, data, '
      'urgent, created_at FROM $s.mailbox WHERE device_id = @d:uuid AND seq > @after:int8 '
      'ORDER BY seq LIMIT @n:int4',
      {'d': deviceId, 'after': after, 'n': limit},
    );
    return rows.map(_envelope).toList();
  }

  Future<int> lastSeq(SqlSession db, String deviceId) async {
    final r = await db.queryOne(
      'SELECT coalesce(max(seq), 0) AS m FROM $s.mailbox WHERE device_id = @d:uuid',
      {'d': deviceId},
    );
    return r!.integer('m');
  }

  Future<int> ack(Tx tx, String deviceId, int seq) async {
    final deleted = await tx.execute(
      'DELETE FROM $s.mailbox WHERE device_id = @d:uuid AND seq <= @q:int8',
      {'d': deviceId, 'q': seq},
    );
    if (deleted > 0) {
      await tx.execute(
        'UPDATE $s.device_seq SET pending = greatest(0, pending - @n:int4) WHERE device_id = @d:uuid',
        {'d': deviceId, 'n': deleted},
      );
    }
    return deleted;
  }

  /// Deletes expired envelopes (bounded batches) and fixes pending counts.
  Future<int> purgeExpired(SqlSession db, {int batch = 5000}) async {
    final rows = await db.query(
      'WITH gone AS (DELETE FROM $s.mailbox WHERE ctid IN ('
      '  SELECT ctid FROM $s.mailbox WHERE expires_at < now() LIMIT @n:int4'
      ') RETURNING device_id) '
      'SELECT device_id, count(*) AS n FROM gone GROUP BY device_id',
      {'n': batch},
    );
    var total = 0;
    for (final r in rows) {
      total += r.integer('n');
      await db.execute(
        'UPDATE $s.device_seq SET pending = greatest(0, pending - @n:int4) WHERE device_id = @d:uuid',
        {'d': r.string('device_id'), 'n': r.integer('n')},
      );
    }
    return total;
  }

  Future<void> purgeDevice(SqlSession db, String deviceId) async {
    await db.execute('DELETE FROM $s.mailbox WHERE device_id = @d:uuid', {
      'd': deviceId,
    });
    await db.execute('DELETE FROM $s.device_seq WHERE device_id = @d:uuid', {
      'd': deviceId,
    });
  }

  /// Records a send id; false if it was already accepted (a retry).
  Future<DateTime?> recordSend(Tx tx, String id, String senderDevice) async {
    final r = await tx.queryOne(
      'INSERT INTO $s.sends (id, sender_device) VALUES (@id:uuid, @d:uuid) '
      'ON CONFLICT (id) DO NOTHING RETURNING accepted_at',
      {'id': id, 'd': senderDevice},
    );
    return r?.time('accepted_at');
  }

  Future<DateTime?> acceptedAt(SqlSession db, String id) async {
    final r = await db.queryOne(
      'SELECT accepted_at FROM $s.sends WHERE id = @id:uuid',
      {'id': id},
    );
    return r?.time('accepted_at');
  }

  Future<int> purgeSends(SqlSession db) => db.execute(
    "DELETE FROM $s.sends WHERE accepted_at < now() - interval '7 days'",
  );
}

String mailboxBaseline(String s) {
  final parts = [
    for (var i = 0; i < MailboxStore.partitions; i++)
      'CREATE TABLE $s.mailbox_p$i PARTITION OF $s.mailbox '
          'FOR VALUES WITH (MODULUS ${MailboxStore.partitions}, REMAINDER $i);',
  ].join('\n');
  return '''
CREATE TABLE $s.mailbox (
  device_id uuid NOT NULL,
  seq bigint NOT NULL,
  id uuid NOT NULL,
  kind text NOT NULL,
  sender_account uuid,
  sender_device uuid,
  group_id uuid,
  call_id text,
  payload bytea,
  data jsonb,
  urgent boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  PRIMARY KEY (device_id, seq)
) PARTITION BY HASH (device_id);
$parts
CREATE INDEX mailbox_expires ON $s.mailbox (expires_at);

CREATE TABLE $s.device_seq (
  device_id uuid PRIMARY KEY,
  last_seq bigint NOT NULL DEFAULT 0,
  pending integer NOT NULL DEFAULT 0
);

CREATE TABLE $s.sends (
  id uuid PRIMARY KEY,
  sender_device uuid NOT NULL,
  accepted_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX sends_accepted ON $s.sends (accepted_at);
''';
}
