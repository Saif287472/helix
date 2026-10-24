import 'dart:typed_data';

import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/src/kernel/presence.dart';
import 'package:helix_remote_server/src/modules/identity/api.dart';
import 'package:helix_remote_server/src/modules/messaging/api.dart';
import 'package:helix_remote_server/src/modules/people/api.dart';
import 'package:helix_remote_server/src/platform/db/db.dart';
import 'package:helix_remote_server/src/platform/db/migrations.dart';
import 'package:helix_remote_server/src/platform/http/request.dart';
import 'package:helix_remote_server/src/platform/http/routes.dart';
import 'package:helix_remote_server/src/platform/jobs/jobs.dart';
import 'package:helix_remote_server/src/platform/module.dart';
import 'package:helix_remote_server/src/platform/ratelimit/rate_limiter.dart';
import 'package:shelf/shelf.dart';

/// Profiles (encrypted), privacy, blocks, contacts, discovery, presence,
/// reports. Schema `people`.
final class PeopleModule extends ModuleBase implements ProvidesAccountExport {
  PeopleModule(
    super.context, {
    required this.identity,
    required this.messaging,
  }) {
    api = _PeopleFacade(this);
    messaging.setBlockPolicy(api.blockedBy);
    identity.onAccountDeleted(_purge);
  }

  final IdentityApi identity;
  final MessagingApi messaging;
  late final PeopleApi api;

  static const dailyDiscoveryBudget = 5000;
  static final _byName = RateLimitPolicy.per(
    'people.by_name',
    30,
    const Duration(minutes: 1),
  );
  static final _reports = RateLimitPolicy.per(
    'people.reports',
    20,
    const Duration(hours: 1),
  );

  /// Reading somebody else's presence or profile is cheap here and free for
  /// the caller, so without a limit any signed-in account could walk the id
  /// space and build an activity timeline - which is exactly what the privacy
  /// audiences and the "last seen" rounding are meant to prevent (the
  /// audience check still applies; these limits cap *how often* and *how many
  /// people* one account may ask about).
  static final _reads = RateLimitPolicy.per(
    'people.reads',
    120,
    const Duration(minutes: 1),
  );

  /// Distinct accounts one account may ask about per day. Only the first
  /// read of a target in a day is charged ([_seenFor]).
  static final _readTargets = RateLimitPolicy.per(
    'people.read_targets',
    2000,
    const Duration(days: 1),
  );

  /// Block and unblock per device. The notice is live-only now, so this does
  /// not protect anyone's storage - it bounds how fast one device can push
  /// frames into other people's sockets (AUD-4a-1).
  static const blockPerDevice = RateLimitPolicy(
    'people.block',
    capacity: 60,
    perSecond: 2,
  );

  /// Contact-list uploads per device. The handler only writes the difference,
  /// so a sync of an unchanged phone book costs nothing; when the list really
  /// does change, one call is a rewrite of up to 5,000 rows, and this is what
  /// bounds how often one client can ask the node for that (AUD-4a-3).
  static final contactsPerDevice = RateLimitPolicy.per(
    'people.contacts',
    12,
    const Duration(hours: 1),
  );

  /// Resolved and dismissed reports are deleted this long after they were
  /// closed (review C-02; the operator's choice). Open reports stay until
  /// the operator handles them.
  static const reportRetention = Duration(days: 180);

  /// Days of discovery budget rows kept besides today's. The table is one row
  /// per account per day and, before AUD-4a-4, only account deletion ever
  /// removed one, so a server that is used filled it for ever.
  static const discoveryHistory = Duration(days: 1);

  /// The budget's day, in UTC rather than `current_date`: the row used to be
  /// keyed by whatever day the session time zone thought it was, while the
  /// refusal on it promised an hour. Both now mean the same UTC day.
  static const _budgetDay = "(now() at time zone 'utc')::date";

  @override
  List<PeriodicJob> get periodic => [
    PeriodicJob(
      'people.purge_reports',
      const Duration(hours: 24),
      () => context.db.execute(
        'DELETE FROM $s.reports WHERE resolved_at < now() - '
        'make_interval(secs => @age:int8)',
        {'age': reportRetention.inSeconds},
      ),
    ),
    PeriodicJob(
      'people.purge_discovery',
      const Duration(hours: 24),
      () => context.db.execute(
        'DELETE FROM $s.discovery_budget WHERE day < $_budgetDay - @days:int4',
        {'days': discoveryHistory.inDays},
      ),
    ),
  ];

  @override
  String get name => 'people';

  @override
  List<Migration> get migrations => const [
    Migration(1, 'people_baseline', _baseline),
    Migration(2, 'federated_blocks', _federatedBlocks),
    Migration(3, 'report_resolved_at', _reportResolvedAt),
    Migration(4, 'display_names', _displayNames),
  ];

  /// The name each account gives itself, as its app reports it in the clear
  /// for the operator console (ADR-030). Contacts read the encrypted profile.
  static String _displayNames(String s) =>
      '''
CREATE TABLE $s.display_names (
  account_id uuid PRIMARY KEY,
  name text NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);
''';

  /// When a report was resolved or dismissed, for [reportRetention].
  /// Reports already closed start their retention at this migration.
  static String _reportResolvedAt(String s) =>
      '''
ALTER TABLE $s.reports ADD COLUMN resolved_at timestamptz;
UPDATE $s.reports SET resolved_at = now() WHERE status <> 'open';
CREATE INDEX reports_resolved ON $s.reports (resolved_at) WHERE resolved_at IS NOT NULL;
''';

  /// Blocked accounts on other servers are stored qualified (`uuid@domain`).
  static String _federatedBlocks(String s) =>
      'ALTER TABLE $s.blocks ALTER COLUMN blocked TYPE text USING blocked::text;';

  static String _baseline(String s) =>
      '''
CREATE TABLE $s.profiles (
  account_id uuid PRIMARY KEY,
  version integer NOT NULL,
  ciphertext bytea NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE $s.privacy (
  account_id uuid PRIMARY KEY,
  discoverable_by_phone boolean NOT NULL DEFAULT true,
  discoverable_by_name boolean NOT NULL DEFAULT true,
  last_seen text NOT NULL DEFAULT 'everyone',
  online text NOT NULL DEFAULT 'everyone',
  group_add text NOT NULL DEFAULT 'everyone'
);
CREATE TABLE $s.blocks (
  account_id uuid NOT NULL,
  blocked uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (account_id, blocked)
);
CREATE INDEX blocks_blocked ON $s.blocks (blocked);
CREATE TABLE $s.contacts (
  account_id uuid NOT NULL,
  contact uuid NOT NULL,
  PRIMARY KEY (account_id, contact)
);
CREATE TABLE $s.discovery_budget (
  account_id uuid NOT NULL,
  day date NOT NULL,
  used integer NOT NULL,
  PRIMARY KEY (account_id, day)
);
CREATE TABLE $s.reports (
  id uuid PRIMARY KEY,
  reporter uuid NOT NULL,
  subject uuid NOT NULL,
  category text NOT NULL,
  note text,
  status text NOT NULL DEFAULT 'open',
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX reports_open ON $s.reports (created_at) WHERE status = 'open';
''';

  @override
  void routes(RouteRegistry r) {
    r
      ..add(name, Routes.discoverySalt, _salt)
      ..add(name, Routes.discover, _discover)
      ..add(name, Routes.findByName, _findByName)
      ..add(name, Routes.profile, _profile)
      ..add(name, Routes.presence, _presence)
      ..add(name, Routes.setOwnProfile, _setProfile, maxBodyBytes: 64 * 1024)
      ..add(name, Routes.setOwnName, _setOwnName)
      ..add(name, Routes.blocks, _blocks, allowSuspended: true)
      ..add(
        name,
        Routes.block,
        _block,
        allowSuspended: true,
        rateLimit: blockPerDevice,
      )
      ..add(
        name,
        Routes.unblock,
        _unblock,
        allowSuspended: true,
        rateLimit: blockPerDevice,
      )
      ..add(name, Routes.privacy, _privacy, allowSuspended: true)
      ..add(name, Routes.setPrivacy, _setPrivacy, allowSuspended: true)
      ..add(
        name,
        Routes.setContacts,
        _setContacts,
        maxBodyBytes: 512 * 1024,
        rateLimit: contactsPerDevice,
      )
      ..add(name, Routes.report, _report);
  }

  String get s => schema;

  /// Reports stay after an account is deleted: they are the moderation
  /// record (ids only; no content).
  @override
  Future<Object?> exportAccount(SqlSession db, String accountId) async {
    final profile = await db.queryOne(
      'SELECT version, updated_at FROM $s.profiles WHERE account_id = @a:uuid',
      {'a': accountId},
    );
    final blocks = await db.query(
      'SELECT blocked, created_at FROM $s.blocks WHERE account_id = @a:uuid ORDER BY created_at',
      {'a': accountId},
    );
    final contacts = await db.queryOne(
      'SELECT count(*)::int8 AS n FROM $s.contacts WHERE account_id = @a:uuid',
      {'a': accountId},
    );
    final reports = await db.query(
      'SELECT id, subject, category, status, created_at FROM $s.reports '
      'WHERE reporter = @a:uuid ORDER BY id DESC LIMIT 500',
      {'a': accountId},
    );
    final displayName = await db.queryOne(
      'SELECT name FROM $s.display_names WHERE account_id = @a:uuid',
      {'a': accountId},
    );
    return {
      // The profile itself is end-to-end encrypted; only its version is
      // meaningful here.
      'profile': profile == null
          ? null
          : {
              'version': profile.integer('version'),
              'updated_at': toWireTime(profile.time('updated_at')),
            },
      // The copy of the name kept for the operator console (ADR-030).
      'display_name': displayName?.string('name'),
      'privacy': (await api.privacy(db, accountId)).toJson(),
      'blocked': [
        for (final r in blocks)
          {
            'account_id': r.string('blocked'),
            'since': toWireTime(r.time('created_at')),
          },
      ],
      'contacts': contacts!.integer('n'),
      'reports_filed': [
        for (final r in reports)
          {
            'report_id': r.string('id'),
            'subject': r.string('subject'),
            'category': r.string('category'),
            'status': r.string('status'),
            'created_at': toWireTime(r.time('created_at')),
          },
      ],
    };
  }

  Future<void> _purge(Tx tx, String accountId) async {
    for (final table in [
      'profiles',
      'privacy',
      'discovery_budget',
      'display_names',
    ]) {
      await tx.execute('DELETE FROM $s.$table WHERE account_id = @a:uuid', {
        'a': accountId,
      });
    }
    await tx.execute(
      'DELETE FROM $s.blocks WHERE account_id = @a:uuid OR blocked = @t:text',
      {'a': accountId, 't': accountId},
    );
    await tx.execute(
      'DELETE FROM $s.contacts WHERE account_id = @a:uuid OR contact = @a:uuid',
      {'a': accountId},
    );
  }

  Future<Response> _salt(HelixRequest q) async => jsonResponse(
    DiscoverySalt(salt: await identity.discoverySalt(), version: 1).toJson(),
  );

  Future<Response> _discover(HelixRequest q) async {
    final req = q.json(DiscoverRequest.fromJson);
    final hashes = req.phoneHashes.toSet();
    if (hashes.length > DiscoverRequest.maxBatch ||
        hashes.any((h) => !RegExp(r'^[0-9a-f]{64}$').hasMatch(h))) {
      throw const ApiError(
        ErrorCode.invalidField,
        details: {'field': 'phone_hashes'},
      );
    }
    final me = q.device.accountId;
    final remaining = await context.db.tx((tx) async {
      final row = await tx.queryOne(
        'INSERT INTO $s.discovery_budget (account_id, day, used) '
        'VALUES (@a:uuid, $_budgetDay, @n:int4) '
        'ON CONFLICT (account_id, day) DO UPDATE SET used = $s.discovery_budget.used + @n:int4 '
        'RETURNING used',
        {'a': me, 'n': hashes.length},
      );
      final used = row!.integer('used');
      if (used > dailyDiscoveryBudget) {
        throw ApiError(
          ErrorCode.rateLimited,
          message: 'daily contact discovery limit reached',
          retryAfter: _untilUtcMidnight(),
        );
      }
      return dailyDiscoveryBudget - used;
    });
    final found = await identity.accountsByDiscoveryHash(context.db, hashes);
    final candidates = found.values.toSet()..remove(me);
    final hidden = await _hiddenFrom(me, candidates, 'discoverable_by_phone');
    return jsonResponse(
      DiscoverResponse(
        matches: [
          for (final e in found.entries)
            if (candidates.contains(e.value) && !hidden.contains(e.value))
              DiscoverMatch(phoneHash: e.key, account: e.value),
        ],
        remainingToday: remaining,
      ).toJson(),
    );
  }

  /// When the UTC day turns, which is when [dailyDiscoveryBudget] is whole
  /// again. The refusal used to say one hour: a client that obeys
  /// `retry_after` came back hourly all day and was refused each time, each
  /// attempt running the upsert and rolling it back (AUD-4a-4). Rounded up a
  /// second so a retry never lands on the instant the day changes.
  static Duration _untilUtcMidnight() {
    final now = DateTime.now().toUtc();
    final next = DateTime.utc(
      now.year,
      now.month,
      now.day,
    ).add(const Duration(days: 1));
    return Duration(seconds: next.difference(now).inSeconds + 1);
  }

  /// Accounts (of [accounts]) that opted out via [flag] or blocked [me].
  Future<Set<String>> _hiddenFrom(
    String me,
    Set<String> accounts,
    String flag,
  ) async {
    if (accounts.isEmpty) return const {};
    final rows = await context.db.query(
      'SELECT account_id FROM $s.privacy WHERE account_id = ANY(@ids:_uuid) AND NOT $flag '
      'UNION SELECT account_id FROM $s.blocks WHERE account_id = ANY(@ids:_uuid) AND blocked = @me:text',
      {'ids': accounts.toList(), 'me': me},
    );
    return {for (final r in rows) r.string('account_id')};
  }

  Future<Response> _findByName(HelixRequest q) async {
    final decision = await context.rateLimiter.hit(_byName, q.device.accountId);
    if (!decision.allowed) {
      throw ApiError(ErrorCode.rateLimited, retryAfter: decision.retryAfter);
    }
    final name = q.param('name').toLowerCase().replaceFirst('~', '');
    final account = await identity.accountByHelixName(context.db, name);
    if (account == null ||
        account == q.device.accountId ||
        (await _hiddenFrom(q.device.accountId, {
          account,
        }, 'discoverable_by_name')).isNotEmpty) {
      throw const ApiError(ErrorCode.notFound);
    }
    return jsonResponse(
      FindByNameResponse(account: account, name: name).toJson(),
    );
  }

  Future<Response> _profile(HelixRequest q) async {
    final account = q.uuidParam('account');
    await _limitReads(q.device.accountId, account);
    final row = await context.db.queryOne(
      'SELECT version, ciphertext, updated_at FROM $s.profiles WHERE account_id = @a:uuid',
      {'a': account},
    );
    if (row == null) throw const ApiError(ErrorCode.notFound);
    return jsonResponse(
      EncryptedProfile(
        account: account,
        version: row.integer('version'),
        ciphertext: row.bytes('ciphertext'),
        updatedAt: row.time('updated_at'),
      ).toJson(),
    );
  }

  /// How long a read target counts as already seen (`people:seen:`, in the
  /// ephemeral store), so repeat reads of one person are not charged again.
  static const _seenFor = Duration(days: 1);

  /// The read budget for one account looking at somebody else ([_reads],
  /// [_readTargets]). Asking about yourself is free: it is what a chat list
  /// does while it loads.
  Future<void> _limitReads(String reader, String target) async {
    if (reader == target) return;
    final reads = await context.rateLimiter.hit(_reads, reader);
    if (!reads.allowed) {
      throw ApiError(ErrorCode.rateLimited, retryAfter: reads.retryAfter);
    }
    final seen = 'people:seen:$reader:$target';
    if (!await context.ephemeral.putIfAbsent(seen, '1', _seenFor)) return;
    final targets = await context.rateLimiter.hit(_readTargets, reader);
    if (!targets.allowed) {
      // A refused read did not see the target, so the next try is charged.
      await context.ephemeral.delete(seen);
      throw ApiError(ErrorCode.rateLimited, retryAfter: targets.retryAfter);
    }
  }

  /// Keeps the name this account gives itself, for the operator console
  /// (ADR-030); empty removes it.
  Future<Response> _setOwnName(HelixRequest q) async {
    final name = q.json(SetOwnNameRequest.fromJson).name.trim();
    if (name.length > SetOwnNameRequest.maxLength) {
      throw const ApiError(ErrorCode.invalidField, details: {'field': 'name'});
    }
    if (name.isEmpty) {
      await context.db.execute(
        'DELETE FROM $s.display_names WHERE account_id = @a:uuid',
        {'a': q.device.accountId},
      );
    } else {
      await context.db.execute(
        'INSERT INTO $s.display_names (account_id, name) VALUES (@a:uuid, @n:text) '
        'ON CONFLICT (account_id) DO UPDATE SET name = excluded.name, updated_at = now()',
        {'a': q.device.accountId, 'n': name},
      );
    }
    return noContent();
  }

  Future<Response> _setProfile(HelixRequest q) async {
    final req = q.json(EncryptedProfile.fromJson);
    if (req.ciphertext.length > EncryptedProfile.maxBytes) {
      throw const ApiError(ErrorCode.payloadTooLarge);
    }
    final n = await context.db.execute(
      'INSERT INTO $s.profiles (account_id, version, ciphertext) VALUES (@a:uuid, @v:int4, @c:bytea) '
      'ON CONFLICT (account_id) DO UPDATE SET version = excluded.version, ciphertext = excluded.ciphertext, '
      'updated_at = now() WHERE $s.profiles.version < excluded.version',
      {'a': q.device.accountId, 'v': req.version, 'c': req.ciphertext},
    );
    if (n == 0) {
      throw const ApiError(
        ErrorCode.versionConflict,
        message: 'version must increase',
      );
    }
    return noContent();
  }

  Future<bool> _inAudience(String owner, String viewer, String audience) async {
    switch (audience) {
      case 'everyone':
        return true;
      case 'nobody':
        return false;
      default:
        // Contacts are phone-book matches on this server; an account on
        // another server is never one.
        if (viewer.contains('@')) return false;
        final row = await context.db.queryOne(
          'SELECT 1 FROM $s.contacts WHERE account_id = @o:uuid AND contact = @v:uuid',
          {'o': owner, 'v': viewer},
        );
        return row != null;
    }
  }

  Future<Response> _presence(HelixRequest q) async {
    final target = q.uuidParam('account');
    final me = q.device.accountId;
    await _limitReads(me, target);
    final privacy = await api.privacy(context.db, target);
    final blocked = (await api.blockedBy(context.db, me, [target])).isNotEmpty;
    var online = false;
    DateTime? lastSeen;
    if (!blocked && await _inAudience(target, me, privacy.online.wire)) {
      final devices = await identity.activeDevices(context.db, target);
      online = (await Presence.online(
        context.ephemeral,
        devices.map((d) => d.id),
      )).isNotEmpty;
    }
    if (!blocked &&
        !online &&
        await _inAudience(target, me, privacy.lastSeen.wire)) {
      final raw = await context.ephemeral.get(Presence.lastSeenKey(target));
      if (raw != null) {
        final at = DateTime.fromMillisecondsSinceEpoch(
          int.parse(raw),
          isUtc: true,
        );
        lastSeen = DateTime.utc(at.year, at.month, at.day, at.hour, at.minute);
      }
    }
    return jsonResponse(
      PresenceResponse(
        account: target,
        online: online,
        lastSeenAt: lastSeen,
      ).toJson(),
    );
  }

  Future<Response> _blocks(HelixRequest q) async {
    final rows = await context.db.query(
      'SELECT blocked FROM $s.blocks WHERE account_id = @a:uuid ORDER BY created_at',
      {'a': q.device.accountId},
    );
    return jsonResponse(
      BlockList(accounts: [for (final r in rows) r.string('blocked')]).toJson(),
    );
  }

  /// The `{account}` of a block route in canonical form: a bare id for
  /// accounts here, `uuid@domain` for accounts on other servers.
  String _blockTarget(HelixRequest q) {
    var address = AccountAddress.tryParse(q.param('account'));
    final local = messaging.localDomain;
    if (address != null && local != null) address = address.relativeTo(local);
    if (address == null || (address.isRemote && local == null)) {
      throw const ApiError(
        ErrorCode.invalidField,
        details: {'field': 'account'},
      );
    }
    return address.toString();
  }

  Future<Response> _block(HelixRequest q) async {
    final me = q.device.accountId;
    final target = _blockTarget(q);
    if (target == me) {
      throw const ApiError(ErrorCode.invalidField);
    }
    final devices = await context.db.tx((tx) async {
      final added = await tx.execute(
        'INSERT INTO $s.blocks (account_id, blocked) VALUES (@a:uuid, @b:text) ON CONFLICT DO NOTHING',
        {'a': me, 'b': target},
      );
      return added > 0 ? await _targetDevices(tx, target) : const <String>[];
    });
    await _tellBlocked(devices, blocker: me, blocked: true);
    return noContent();
  }

  Future<Response> _unblock(HelixRequest q) async {
    final me = q.device.accountId;
    final target = _blockTarget(q);
    final devices = await context.db.tx((tx) async {
      final removed = await tx.execute(
        'DELETE FROM $s.blocks WHERE account_id = @a:uuid AND blocked = @b:text',
        {'a': me, 'b': target},
      );
      return removed > 0 ? await _targetDevices(tx, target) : const <String>[];
    });
    await _tellBlocked(devices, blocker: me, blocked: false);
    return noContent();
  }

  /// [target]'s active devices, or none for an account on another server
  /// (federation has no such signal; it learns from its next send).
  Future<List<String>> _targetDevices(SqlSession db, String target) async =>
      !Uuid.isValid(target)
      ? const <String>[]
      : [for (final d in await identity.activeDevices(db, target)) d.id];

  /// Blocks are not secret: [target]'s devices learn that [blocker] blocked
  /// (or unblocked) them, so their chat says so before they type. It is an
  /// advisory live-only notice (AUD-4a-1): it stores nothing, so no one can
  /// fill another account's mailbox - and so trim its real messages - by
  /// flapping a block. An offline device learns the state from its next
  /// send's `blocked_by`, which is how a remote blocked sender works today.
  Future<void> _tellBlocked(
    List<String> devices, {
    required String blocker,
    required bool blocked,
  }) async {
    if (devices.isEmpty) return;
    await messaging.deliverEphemeral(
      <String, Uint8List?>{for (final d in devices) d: null},
      Delivery(
        kind: EnvelopeKind.blockChange,
        data: BlockChangeEvent(account: blocker, blocked: blocked).toJson(),
      ),
    );
  }

  Future<Response> _privacy(HelixRequest q) async => jsonResponse(
    (await api.privacy(context.db, q.device.accountId)).toJson(),
  );

  Future<Response> _setPrivacy(HelixRequest q) async {
    final p = q.json(PrivacySettings.fromJson);
    final me = q.device.accountId;
    await context.db.tx((tx) async {
      await tx.execute(
        'INSERT INTO $s.privacy (account_id, discoverable_by_phone, discoverable_by_name, last_seen, online, group_add) '
        'VALUES (@a:uuid, @p:boolean, @n:boolean, @ls:text, @o:text, @g:text) '
        'ON CONFLICT (account_id) DO UPDATE SET discoverable_by_phone = excluded.discoverable_by_phone, '
        'discoverable_by_name = excluded.discoverable_by_name, last_seen = excluded.last_seen, '
        'online = excluded.online, group_add = excluded.group_add',
        {
          'a': me,
          'p': p.discoverableByPhone,
          'n': p.discoverableByName,
          'ls': p.lastSeen.wire,
          'o': p.online.wire,
          'g': p.groupAdd.wire,
        },
      );
      // Identity keeps the discovery index only while discovery is on.
      await identity.setPhoneDiscoverable(
        tx,
        me,
        on: p.discoverableByPhone,
        phoneNumber: p.phoneNumber,
      );
    });
    return noContent();
  }

  Future<Response> _setContacts(HelixRequest q) async {
    final req = q.json(SetContactsRequest.fromJson);
    final ids = req.accounts.toSet();
    if (ids.length > SetContactsRequest.maxContacts ||
        ids.any((a) => !Uuid.isValid(a))) {
      throw const ApiError(
        ErrorCode.invalidField,
        details: {'field': 'accounts'},
      );
    }
    await context.db.tx((tx) async {
      // Diff, never replace: an unchanged list writes nothing. The read is
      // inside the transaction so two uploads racing still converge on the
      // last one, which is what the delete-all/insert-all did (AUD-4a-3).
      final stored = await tx.query(
        'SELECT contact FROM $s.contacts WHERE account_id = @a:uuid',
        {'a': q.device.accountId},
      );
      final known = {for (final row in stored) row.string('contact')};
      final gone = known.difference(ids).toList();
      final fresh = ids.difference(known).toList();
      if (gone.isNotEmpty) {
        await tx.execute(
          'DELETE FROM $s.contacts WHERE account_id = @a:uuid AND contact = ANY(@gone:_uuid)',
          {'a': q.device.accountId, 'gone': gone},
        );
      }
      if (fresh.isNotEmpty) {
        await tx.execute(
          'INSERT INTO $s.contacts (account_id, contact) SELECT @a:uuid, c FROM unnest(@ids:_uuid) AS c '
          'ON CONFLICT (account_id, contact) DO NOTHING',
          {'a': q.device.accountId, 'ids': fresh},
        );
      }
    });
    return noContent();
  }

  Future<Response> _report(HelixRequest q) async {
    final decision = await context.rateLimiter.hit(
      _reports,
      q.device.accountId,
    );
    if (!decision.allowed) {
      throw ApiError(ErrorCode.rateLimited, retryAfter: decision.retryAfter);
    }
    final req = q.json(ReportRequest.fromJson);
    if (!Uuid.isValid(req.account) ||
        (req.note?.length ?? 0) > ReportRequest.maxNoteLength) {
      throw const ApiError(ErrorCode.invalidField);
    }
    final id = Uuid.v7();
    await context.db.execute(
      'INSERT INTO $s.reports (id, reporter, subject, category, note) VALUES (@id:uuid, @r:uuid, @s:uuid, @c:text, @n:text)',
      {
        'id': id,
        'r': q.device.accountId,
        's': req.account,
        'c': req.category.wire,
        'n': req.note,
      },
    );
    return jsonResponse(ReportResponse(reportId: id).toJson(), status: 201);
  }
}

final class _PeopleFacade implements PeopleApi {
  _PeopleFacade(this._m);

  final PeopleModule _m;

  @override
  Future<Set<String>> blockedBy(
    SqlSession db,
    String sender,
    Iterable<String> recipients,
  ) async {
    final ids = recipients.toSet().toList();
    if (ids.isEmpty) return const {};
    final rows = await db.query(
      'SELECT account_id FROM ${_m.s}.blocks WHERE blocked = @s:text AND account_id = ANY(@ids:_uuid)',
      {'s': sender, 'ids': ids},
    );
    return {for (final r in rows) r.string('account_id')};
  }

  @override
  Future<PrivacySettings> privacy(SqlSession db, String accountId) async {
    final r = await db.queryOne(
      'SELECT discoverable_by_phone, discoverable_by_name, last_seen, online, group_add '
      'FROM ${_m.s}.privacy WHERE account_id = @a:uuid',
      {'a': accountId},
    );
    if (r == null) return const PrivacySettings();
    Audience audience(String v) =>
        Audience.values.firstWhere((a) => a.wire == v);
    return PrivacySettings(
      discoverableByPhone: r.boolean('discoverable_by_phone'),
      discoverableByName: r.boolean('discoverable_by_name'),
      lastSeen: audience(r.string('last_seen')),
      online: audience(r.string('online')),
      groupAdd: audience(r.string('group_add')),
    );
  }

  @override
  Future<Page<AdminReport>> reports(
    SqlSession db, {
    required PageRequest page,
    ReportStatus? status,
  }) async {
    final cursor = page.cursor;
    if (cursor != null && !Uuid.isValid(cursor)) {
      throw const ApiError(
        ErrorCode.invalidField,
        details: {'field': 'cursor'},
      );
    }
    final rows = await db.query(
      'SELECT id, reporter, subject, category, note, status, created_at FROM ${_m.s}.reports '
      'WHERE (@cursor:uuid IS NULL OR id < @cursor:uuid) '
      'AND (@status:text IS NULL OR status = @status:text) '
      'ORDER BY id DESC LIMIT @limit:int4',
      {'cursor': cursor, 'status': status?.wire, 'limit': page.limit + 1},
    );
    final items = [
      for (final r in rows.take(page.limit))
        AdminReport(
          reportId: r.string('id'),
          reporter: r.string('reporter'),
          subject: r.string('subject'),
          category: ReportCategory.values.firstWhere(
            (c) => c.wire == r.string('category'),
            orElse: () => ReportCategory.other,
          ),
          status: ReportStatus.values.firstWhere(
            (v) => v.wire == r.string('status'),
            orElse: () => ReportStatus.unknown,
          ),
          createdAt: r.time('created_at'),
          note: r.optString('note'),
        ),
    ];
    return Page(
      items: items,
      nextCursor: rows.length > page.limit ? items.last.reportId : null,
    );
  }

  @override
  Future<bool> resolveReport(
    SqlSession db,
    String reportId,
    ReportStatus to,
  ) async {
    if (to != ReportStatus.resolved && to != ReportStatus.dismissed) {
      throw const ApiError(
        ErrorCode.invalidField,
        details: {'field': 'status'},
      );
    }
    return await db.execute(
          'UPDATE ${_m.s}.reports SET status = @to:text, resolved_at = now() '
          "WHERE id = @id:uuid AND status = 'open'",
          {'id': reportId, 'to': to.wire},
        ) ==
        1;
  }

  @override
  Future<Map<String, String>> displayNames(
    SqlSession db,
    Iterable<String> accounts,
  ) async {
    final ids = accounts.toSet().toList();
    if (ids.isEmpty) return const {};
    final rows = await db.query(
      'SELECT account_id, name FROM ${_m.s}.display_names WHERE account_id = ANY(@ids:_uuid)',
      {'ids': ids},
    );
    return {for (final r in rows) r.string('account_id'): r.string('name')};
  }

  @override
  Future<int> openReportsAbout(SqlSession db, String accountId) async {
    final r = await db.queryOne(
      "SELECT count(*)::int8 AS n FROM ${_m.s}.reports WHERE subject = @a:uuid AND status = 'open'",
      {'a': accountId},
    );
    return r!.integer('n');
  }

  @override
  Future<bool> mayAddToGroup(
    SqlSession db, {
    required String adder,
    required String target,
  }) async {
    if ((await blockedBy(db, adder, [target])).isNotEmpty) return false;
    final audience = (await privacy(db, target)).groupAdd.wire;
    return _m._inAudience(target, adder, audience);
  }
}
