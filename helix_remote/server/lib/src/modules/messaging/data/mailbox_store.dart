import 'dart:convert';
import 'dart:typed_data';

import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/src/platform/db/db.dart';

final class MailboxStore {
  MailboxStore(this.s);

  final String s;

  static const partitions = 16;

  /// Undelivered envelopes kept per device; [trim] drops the oldest beyond.
  static const quota = 10000;
  static const retention = Duration(days: 30);

  /// Allocates the next `seq` for each device (row-locked, so concurrent
  /// sends on any node never share a number) and counts it as pending.
  /// Devices are locked in id order, so two sends to overlapping devices
  /// cannot deadlock. `over` holds the devices now above [quota], and by
  /// how much: pass it to [trim] once the new rows are in.
  Future<({Map<String, int> seqs, Map<String, int> over})> allocate(
    Tx tx,
    List<String> deviceIds,
  ) async {
    final rows = await tx.query(
      'INSERT INTO $s.device_seq (device_id, last_seq, pending) '
      'SELECT d, 1, 1 FROM unnest(@ids:_uuid) AS d ORDER BY d '
      'ON CONFLICT (device_id) DO UPDATE SET last_seq = $s.device_seq.last_seq + 1, '
      'pending = $s.device_seq.pending + 1 '
      'RETURNING device_id, last_seq, pending',
      {'ids': deviceIds},
    );
    final seqs = <String, int>{};
    final over = <String, int>{};
    for (final r in rows) {
      final device = r.string('device_id');
      seqs[device] = r.integer('last_seq');
      final excess = r.integer('pending') - quota;
      if (excess > 0) over[device] = excess;
    }
    return (seqs: seqs, over: over);
  }

  /// Deletes the oldest envelopes of each device in [over] (device id →
  /// how many), so it keeps its newest [quota]. A device that never
  /// collects its mail (an unused PC that was never signed out) loses its
  /// oldest envelopes, as expiry would, instead of failing every send to its
  /// account and its groups. Returns how many rows went.
  Future<int> trim(Tx tx, Map<String, int> over) async {
    var total = 0;
    for (final e in over.entries) {
      final deleted = await tx.execute(
        'DELETE FROM $s.mailbox WHERE device_id = @d:uuid AND seq IN ('
        'SELECT seq FROM $s.mailbox WHERE device_id = @d:uuid ORDER BY seq LIMIT @n:int4)',
        {'d': e.key, 'n': e.value},
      );
      if (deleted > 0) {
        await tx.execute(
          'UPDATE $s.device_seq SET pending = greatest(0, pending - @n:int4) WHERE device_id = @d:uuid',
          {'d': e.key, 'n': deleted},
        );
      }
      total += deleted;
    }
    return total;
  }

  /// Deletes the envelope just stored for each device in [newest] (device id →
  /// its new `seq`), and un-counts it. A server-generated signal uses this
  /// instead of [trim]: when a device is at its quota the signal is the row
  /// that goes, never the mail the device had not read yet (AUD-4a-1). Every
  /// signal it can miss is re-discoverable (a stale device list answers
  /// `device_list_stale`, blocks answer `blocked_by`) or moot (a revoked
  /// device cannot authenticate). Returns how many rows went.
  Future<int> dropNewest(Tx tx, Map<String, int> newest) async {
    if (newest.isEmpty) return 0;
    final devices = newest.keys.toList();
    final deleted = await tx.execute(
      'DELETE FROM $s.mailbox WHERE (device_id, seq) IN ('
      'SELECT d, q FROM unnest(@devs:_uuid, @seqs:_int8) AS t(d, q))',
      {
        'devs': devices,
        'seqs': [for (final d in devices) newest[d]!],
      },
    );
    if (deleted > 0) {
      await tx.execute(
        'UPDATE $s.device_seq SET pending = greatest(0, pending - 1) '
        'WHERE device_id = ANY(@devs:_uuid)',
        {'devs': devices},
      );
    }
    return deleted;
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
    const values = '@id:uuid, @kind:text, @sa:text, @sd:uuid, @g:uuid, @c:text';
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

  /// Undelivered envelopes across every device.
  ///
  /// Read from the counter the quota already maintains: one narrow row per
  /// device that ever got mail, instead of counting up to ten thousand rows
  /// for each of them across sixteen partitions on every scrape (AUD-3-11).
  /// No index: the table is bounded by the device count, while an index on
  /// `pending` would make every send's `pending ± 1` a non-HOT update.
  Future<int> backlog(SqlSession db) async {
    final r = await db.queryOne(
      'SELECT coalesce(sum(pending), 0)::int8 AS n FROM $s.device_seq '
      'WHERE pending > 0',
    );
    return r!.integer('n');
  }

  /// The highest `seq` ever given to [deviceId] (0 if none): unlike
  /// [lastSeq] it survives acks, so a client cursor above it means the
  /// database was restored from a backup.
  Future<int> head(SqlSession db, String deviceId) async {
    final r = await db.queryOne(
      'SELECT last_seq FROM $s.device_seq WHERE device_id = @d:uuid',
      {'d': deviceId},
    );
    return r?.integer('last_seq') ?? 0;
  }

  /// Deletes envelopes up to [seq]. An ack above [head] deletes nothing: the
  /// server never gave that `seq`, so the cursor behind it is from before a
  /// restore, and honouring it would delete messages never delivered.
  Future<int> ack(Tx tx, String deviceId, int seq) async {
    final deleted = await tx.execute(
      'DELETE FROM $s.mailbox WHERE device_id = @d:uuid AND seq <= @q:int8 '
      'AND @q:int8 <= (SELECT coalesce(max(last_seq), 0) FROM $s.device_seq '
      'WHERE device_id = @d:uuid)',
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

  /// Deletes up to [batch] expired envelopes and takes exactly that many off
  /// each device's `pending`, in one statement, and returns how many went.
  ///
  /// Two things used to be wrong here. The delete and the per-device updates
  /// were separate autocommit statements, so a node killed in between left
  /// `pending` above the rows actually stored - and the next send to that
  /// device computed `excess = pending - quota` and had [trim] delete that many
  /// of its oldest *undelivered* envelopes: mail lost because a sweep was
  /// interrupted (AUD-3-2). And the rows were chosen by `ctid`, which is unique
  /// only inside a partition, so a batch could also delete live rows of the
  /// same `(block, offset)` in the other fifteen.
  ///
  /// One statement cannot be half-applied, and the batch is now picked by the
  /// primary key, so what goes is exactly what was chosen.
  Future<int> purgeExpired(SqlSession db, {int batch = 5000}) async {
    final r = await db.queryOne(
      '''WITH picked AS (
         SELECT device_id, seq FROM $s.mailbox
         WHERE expires_at < now() LIMIT @n:int4
       ), gone AS (
         DELETE FROM $s.mailbox m USING picked p
         WHERE m.device_id = p.device_id AND m.seq = p.seq
         RETURNING m.device_id
       ), by_device AS (
         SELECT device_id, count(*)::int AS n FROM gone GROUP BY device_id
       ), uncounted AS (
         UPDATE $s.device_seq d SET pending = greatest(0, d.pending - g.n)
         FROM by_device g WHERE d.device_id = g.device_id
         RETURNING 1
       )
       -- Both counts are read: the second is what makes the update part of
       -- this statement rather than a CTE whose result nothing asks for.
       SELECT (SELECT count(*)::int FROM gone) AS deleted,
              (SELECT count(*)::int FROM uncounted) AS uncounted''',
      {'n': batch},
    );
    return r?.integer('deleted') ?? 0;
  }

  Future<void> purgeDevice(SqlSession db, String deviceId) async {
    await db.execute('DELETE FROM $s.mailbox WHERE device_id = @d:uuid', {
      'd': deviceId,
    });
    await db.execute('DELETE FROM $s.device_seq WHERE device_id = @d:uuid', {
      'd': deviceId,
    });
  }

  /// Records a send by (sender account, sender device, id); null if it was
  /// already accepted (a retry). Keyed on the sender too, so another
  /// server reusing an id cannot suppress someone else's message.
  Future<DateTime?> recordSend(
    Tx tx,
    String id, {
    required String senderAccount,
    required String senderDevice,
  }) async {
    final r = await tx.queryOne(
      'INSERT INTO $s.sends (sender_account, sender_device, id) '
      'VALUES (@a:text, @d:uuid, @id:uuid) '
      'ON CONFLICT (sender_account, sender_device, id) DO NOTHING RETURNING accepted_at',
      {'a': senderAccount, 'd': senderDevice, 'id': id},
    );
    return r?.time('accepted_at');
  }

  Future<DateTime?> acceptedAt(
    SqlSession db,
    String id, {
    required String senderAccount,
    required String senderDevice,
  }) async {
    final r = await db.queryOne(
      'SELECT accepted_at FROM $s.sends WHERE sender_account = @a:text '
      'AND sender_device = @d:uuid AND id = @id:uuid',
      {'a': senderAccount, 'd': senderDevice, 'id': id},
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

/// Migration 3: send ids are unique per sender, not globally (rows from
/// before it keep an empty account and simply age out).
String sendsBySender(String s) =>
    '''
ALTER TABLE $s.sends ADD COLUMN sender_account text NOT NULL DEFAULT '';
ALTER TABLE $s.sends ALTER COLUMN sender_account DROP DEFAULT;
ALTER TABLE $s.sends DROP CONSTRAINT sends_pkey;
ALTER TABLE $s.sends ADD PRIMARY KEY (sender_account, sender_device, id);
''';
