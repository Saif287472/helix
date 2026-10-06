import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/src/kernel/presence.dart';
import 'package:helix_remote_server/src/modules/identity/api.dart';
import 'package:helix_remote_server/src/modules/messaging/api.dart';
import 'package:helix_remote_server/src/modules/people/api.dart';
import 'package:helix_remote_server/src/platform/db/db.dart';
import 'package:helix_remote_server/src/platform/db/migrations.dart';
import 'package:helix_remote_server/src/platform/http/request.dart';
import 'package:helix_remote_server/src/platform/http/routes.dart';
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

  @override
  String get name => 'people';

  @override
  List<Migration> get migrations => const [
    Migration(1, 'people_baseline', _baseline),
    Migration(2, 'federated_blocks', _federatedBlocks),
  ];

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
      ..add(name, Routes.blocks, _blocks, allowSuspended: true)
      ..add(name, Routes.block, _block, allowSuspended: true)
      ..add(name, Routes.unblock, _unblock, allowSuspended: true)
      ..add(name, Routes.privacy, _privacy, allowSuspended: true)
      ..add(name, Routes.setPrivacy, _setPrivacy, allowSuspended: true)
      ..add(name, Routes.setContacts, _setContacts, maxBodyBytes: 512 * 1024)
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
    return {
      // The profile itself is end-to-end encrypted; only its version is
      // meaningful here.
      'profile': profile == null
          ? null
          : {
              'version': profile.integer('version'),
              'updated_at': toWireTime(profile.time('updated_at')),
            },
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
    for (final table in ['profiles', 'privacy', 'discovery_budget']) {
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
        'INSERT INTO $s.discovery_budget (account_id, day, used) VALUES (@a:uuid, current_date, @n:int4) '
        'ON CONFLICT (account_id, day) DO UPDATE SET used = $s.discovery_budget.used + @n:int4 '
        'RETURNING used',
        {'a': me, 'n': hashes.length},
      );
      final used = row!.integer('used');
      if (used > dailyDiscoveryBudget) {
        throw const ApiError(
          ErrorCode.rateLimited,
          message: 'daily contact discovery limit reached',
          retryAfter: Duration(hours: 1),
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
    final target = _blockTarget(q);
    if (target == q.device.accountId) {
      throw const ApiError(ErrorCode.invalidField);
    }
    await context.db.execute(
      'INSERT INTO $s.blocks (account_id, blocked) VALUES (@a:uuid, @b:text) ON CONFLICT DO NOTHING',
      {'a': q.device.accountId, 'b': target},
    );
    return noContent();
  }

  Future<Response> _unblock(HelixRequest q) async {
    await context.db.execute(
      'DELETE FROM $s.blocks WHERE account_id = @a:uuid AND blocked = @b:text',
      {'a': q.device.accountId, 'b': _blockTarget(q)},
    );
    return noContent();
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
      await tx.execute('DELETE FROM $s.contacts WHERE account_id = @a:uuid', {
        'a': q.device.accountId,
      });
      if (ids.isNotEmpty) {
        await tx.execute(
          'INSERT INTO $s.contacts (account_id, contact) SELECT @a:uuid, c FROM unnest(@ids:_uuid) AS c',
          {'a': q.device.accountId, 'ids': ids.toList()},
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
          "UPDATE ${_m.s}.reports SET status = @to:text WHERE id = @id:uuid AND status = 'open'",
          {'id': reportId, 'to': to.wire},
        ) ==
        1;
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
