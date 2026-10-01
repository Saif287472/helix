import 'dart:convert';
import 'dart:typed_data';

import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/src/platform/db/db.dart';

/// SQL for groups, members, bans, invite links and join requests.
final class GroupStore {
  GroupStore(this.s);

  final String s;

  static String baseline(String s) =>
      '''
CREATE TABLE $s.groups (
  id uuid PRIMARY KEY,
  epoch integer NOT NULL DEFAULT 0,
  state_version integer NOT NULL DEFAULT 1,
  encrypted_state bytea NOT NULL,
  add_members text NOT NULL,
  edit_info text NOT NULL,
  send_messages text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE $s.members (
  group_id uuid NOT NULL REFERENCES $s.groups (id) ON DELETE CASCADE,
  account_id uuid NOT NULL,
  role text NOT NULL CHECK (role IN ('owner', 'admin', 'member')),
  joined_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (group_id, account_id)
);
CREATE INDEX members_account ON $s.members (account_id);
CREATE TABLE $s.bans (
  group_id uuid NOT NULL REFERENCES $s.groups (id) ON DELETE CASCADE,
  account_id uuid NOT NULL,
  PRIMARY KEY (group_id, account_id)
);
CREATE TABLE $s.invite_links (
  id uuid PRIMARY KEY,
  group_id uuid NOT NULL REFERENCES $s.groups (id) ON DELETE CASCADE,
  token_hash bytea NOT NULL UNIQUE,
  requires_approval boolean NOT NULL,
  encrypted_preview bytea NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz,
  revoked_at timestamptz
);
CREATE TABLE $s.join_requests (
  id uuid PRIMARY KEY,
  group_id uuid NOT NULL REFERENCES $s.groups (id) ON DELETE CASCADE,
  account_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (group_id, account_id)
);
''';

  /// Group federation (Phase S6c). On the home server, member, ban and join
  /// request accounts may be `uuid@domain`, `roster_version` orders the
  /// snapshots pushed to other servers, and `remote_devices` holds the
  /// devices those servers report for their members. On a member's server,
  /// `remote_groups` caches groups homed elsewhere that local accounts
  /// belong to (`remote_members`).
  static String federation(String s) =>
      '''
ALTER TABLE $s.members ALTER COLUMN account_id TYPE text USING account_id::text;
ALTER TABLE $s.bans ALTER COLUMN account_id TYPE text USING account_id::text;
ALTER TABLE $s.join_requests ALTER COLUMN account_id TYPE text USING account_id::text;
ALTER TABLE $s.groups ADD COLUMN roster_version bigint NOT NULL DEFAULT 0;
CREATE TABLE $s.remote_devices (
  account text NOT NULL,
  device_id uuid NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (account, device_id)
);
CREATE TABLE $s.remote_groups (
  group_id uuid PRIMARY KEY,
  home_domain text NOT NULL,
  roster_version bigint NOT NULL,
  snapshot jsonb NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE $s.remote_members (
  group_id uuid NOT NULL REFERENCES $s.remote_groups (group_id) ON DELETE CASCADE,
  account_id uuid NOT NULL,
  PRIMARY KEY (group_id, account_id)
);
CREATE INDEX remote_members_account ON $s.remote_members (account_id);
''';

  /// S7 hardening. On a member's server, `remote_joins` records that a
  /// local account asked to join a remote group through this server (its
  /// consent to be added without the adder check). On the home server,
  /// reported devices are looked up by id so one id cannot belong to two
  /// accounts.
  static String hardening(String s) =>
      '''
CREATE TABLE $s.remote_joins (
  group_id uuid NOT NULL,
  account_id uuid NOT NULL,
  created_at timestamptz NOT NULL,
  PRIMARY KEY (group_id, account_id)
);
CREATE INDEX remote_joins_account ON $s.remote_joins (account_id);
CREATE INDEX remote_devices_device ON $s.remote_devices (device_id);
''';

  Future<void> insertGroup(
    Tx tx, {
    required String id,
    required Uint8List encryptedState,
    required GroupSettings settings,
  }) async {
    await tx.execute(
      'INSERT INTO $s.groups (id, encrypted_state, add_members, edit_info, send_messages) '
      'VALUES (@id:uuid, @st:bytea, @am:text, @ei:text, @sm:text)',
      {
        'id': id,
        'st': encryptedState,
        'am': settings.addMembers.wire,
        'ei': settings.editInfo.wire,
        'sm': settings.sendMessages.wire,
      },
    );
  }

  /// The group row, locked when [forUpdate] (membership changes serialise
  /// per group).
  Future<Row?> group(
    SqlSession db,
    String id, {
    bool forUpdate = false,
  }) => db.queryOne(
    'SELECT id, epoch, state_version, encrypted_state, add_members, edit_info, send_messages, created_at, roster_version '
    'FROM $s.groups WHERE id = @id:uuid${forUpdate ? ' FOR UPDATE' : ''}',
    {'id': id},
  );

  GroupSettings settings(Row g) {
    GroupPermission p(String v) =>
        GroupPermission.values.firstWhere((x) => x.wire == v);
    return GroupSettings(
      addMembers: p(g.string('add_members')),
      editInfo: p(g.string('edit_info')),
      sendMessages: p(g.string('send_messages')),
    );
  }

  Future<List<GroupMember>> members(SqlSession db, String groupId) async {
    final rows = await db.query(
      'SELECT account_id, role, joined_at FROM $s.members WHERE group_id = @g:uuid ORDER BY joined_at',
      {'g': groupId},
    );
    return [
      for (final r in rows)
        GroupMember(
          account: r.string('account_id'),
          role: GroupRole.values.firstWhere((x) => x.wire == r.string('role')),
          joinedAt: r.time('joined_at'),
        ),
    ];
  }

  Future<GroupRole?> role(
    SqlSession db,
    String groupId,
    String accountId,
  ) async {
    final r = await db.queryOne(
      'SELECT role FROM $s.members WHERE group_id = @g:uuid AND account_id = @a:text',
      {'g': groupId, 'a': accountId},
    );
    return r == null
        ? null
        : GroupRole.values.firstWhere((x) => x.wire == r.string('role'));
  }

  Future<int> memberCount(SqlSession db, String groupId) async {
    final r = await db.queryOne(
      'SELECT count(*)::int4 AS n FROM $s.members WHERE group_id = @g:uuid',
      {'g': groupId},
    );
    return r!.integer('n');
  }

  Future<void> addMember(
    Tx tx,
    String groupId,
    String accountId,
    GroupRole role,
  ) async {
    await tx.execute(
      'INSERT INTO $s.members (group_id, account_id, role) VALUES (@g:uuid, @a:text, @r:text) '
      'ON CONFLICT DO NOTHING',
      {'g': groupId, 'a': accountId, 'r': role.wire},
    );
    await tx.execute(
      'DELETE FROM $s.join_requests WHERE group_id = @g:uuid AND account_id = @a:text',
      {'g': groupId, 'a': accountId},
    );
  }

  Future<bool> removeMember(Tx tx, String groupId, String accountId) async =>
      await tx.execute(
        'DELETE FROM $s.members WHERE group_id = @g:uuid AND account_id = @a:text',
        {'g': groupId, 'a': accountId},
      ) ==
      1;

  Future<void> setRole(
    Tx tx,
    String groupId,
    String accountId,
    GroupRole role,
  ) async {
    await tx.execute(
      'UPDATE $s.members SET role = @r:text WHERE group_id = @g:uuid AND account_id = @a:text',
      {'g': groupId, 'a': accountId, 'r': role.wire},
    );
  }

  Future<int> bumpEpoch(Tx tx, String groupId) async {
    final r = await tx.queryOne(
      'UPDATE $s.groups SET epoch = epoch + 1 WHERE id = @g:uuid RETURNING epoch',
      {'g': groupId},
    );
    return r!.integer('epoch');
  }

  Future<int?> setState(
    Tx tx,
    String groupId,
    Uint8List state,
    int expectedVersion,
  ) async {
    final r = await tx.queryOne(
      'UPDATE $s.groups SET encrypted_state = @st:bytea, state_version = state_version + 1 '
      'WHERE id = @g:uuid AND state_version = @v:int4 RETURNING state_version',
      {'g': groupId, 'st': state, 'v': expectedVersion},
    );
    return r?.integer('state_version');
  }

  Future<void> setSettings(
    Tx tx,
    String groupId,
    GroupSettings settings,
  ) async {
    await tx.execute(
      'UPDATE $s.groups SET add_members = @am:text, edit_info = @ei:text, send_messages = @sm:text '
      'WHERE id = @g:uuid',
      {
        'g': groupId,
        'am': settings.addMembers.wire,
        'ei': settings.editInfo.wire,
        'sm': settings.sendMessages.wire,
      },
    );
  }

  Future<void> deleteGroup(Tx tx, String groupId) async {
    await tx.execute('DELETE FROM $s.groups WHERE id = @g:uuid', {
      'g': groupId,
    });
  }

  Future<List<GroupSummary>> groupsOf(SqlSession db, String accountId) async {
    final rows = await db.query(
      'SELECT g.id, g.epoch, g.state_version FROM $s.groups g JOIN $s.members m ON m.group_id = g.id '
      'WHERE m.account_id = @a:text ORDER BY g.created_at',
      {'a': accountId},
    );
    return [
      for (final r in rows)
        GroupSummary(
          groupId: r.string('id'),
          epoch: r.integer('epoch'),
          stateVersion: r.integer('state_version'),
        ),
    ];
  }

  Future<List<String>> groupIdsOf(SqlSession db, String accountId) async {
    final rows = await db.query(
      'SELECT group_id FROM $s.members WHERE account_id = @a:text',
      {'a': accountId},
    );
    return [for (final r in rows) r.string('group_id')];
  }

  Future<bool> isBanned(
    SqlSession db,
    String groupId,
    String accountId,
  ) async =>
      await db.queryOne(
        'SELECT 1 FROM $s.bans WHERE group_id = @g:uuid AND account_id = @a:text',
        {'g': groupId, 'a': accountId},
      ) !=
      null;

  Future<void> ban(Tx tx, String groupId, String accountId) async {
    await tx.execute(
      'INSERT INTO $s.bans (group_id, account_id) VALUES (@g:uuid, @a:text) ON CONFLICT DO NOTHING',
      {'g': groupId, 'a': accountId},
    );
  }

  Future<void> unban(SqlSession db, String groupId, String accountId) async {
    await db.execute(
      'DELETE FROM $s.bans WHERE group_id = @g:uuid AND account_id = @a:text',
      {'g': groupId, 'a': accountId},
    );
  }

  // ------------------------------------------------------------ invite links

  Future<void> insertLink(
    SqlSession db, {
    required String id,
    required String groupId,
    required Uint8List tokenHash,
    required CreateInviteLinkRequest req,
  }) async {
    await db.execute(
      'INSERT INTO $s.invite_links (id, group_id, token_hash, requires_approval, encrypted_preview, expires_at) '
      'VALUES (@id:uuid, @g:uuid, @h:bytea, @ra:boolean, @p:bytea, @e:timestamptz)',
      {
        'id': id,
        'g': groupId,
        'h': tokenHash,
        'ra': req.requiresApproval,
        'p': req.encryptedPreview,
        'e': req.expiresAt,
      },
    );
  }

  Future<Row?> linkByHash(SqlSession db, Uint8List tokenHash) => db.queryOne(
    'SELECT id, group_id, requires_approval, encrypted_preview FROM $s.invite_links '
    'WHERE token_hash = @h:bytea AND revoked_at IS NULL AND (expires_at IS NULL OR expires_at > now())',
    {'h': tokenHash},
  );

  Future<bool> revokeLink(SqlSession db, String groupId, String linkId) async =>
      await db.execute(
        'UPDATE $s.invite_links SET revoked_at = now() WHERE id = @id:uuid AND group_id = @g:uuid '
        'AND revoked_at IS NULL',
        {'id': linkId, 'g': groupId},
      ) ==
      1;

  // ------------------------------------------------------------ join requests

  Future<String?> insertJoinRequest(
    Tx tx,
    String groupId,
    String accountId,
  ) async {
    final r = await tx.queryOne(
      'INSERT INTO $s.join_requests (id, group_id, account_id) VALUES (@id:uuid, @g:uuid, @a:text) '
      'ON CONFLICT (group_id, account_id) DO NOTHING RETURNING id',
      {'id': Uuid.v7(), 'g': groupId, 'a': accountId},
    );
    return r?.string('id');
  }

  Future<List<JoinRequest>> joinRequests(SqlSession db, String groupId) async {
    final rows = await db.query(
      'SELECT id, account_id, created_at FROM $s.join_requests WHERE group_id = @g:uuid ORDER BY created_at',
      {'g': groupId},
    );
    return [
      for (final r in rows)
        JoinRequest(
          requestId: r.string('id'),
          account: r.string('account_id'),
          createdAt: r.time('created_at'),
        ),
    ];
  }

  Future<String?> takeJoinRequest(
    Tx tx,
    String groupId,
    String requestId,
  ) async {
    final r = await tx.queryOne(
      'DELETE FROM $s.join_requests WHERE id = @id:uuid AND group_id = @g:uuid RETURNING account_id',
      {'id': requestId, 'g': groupId},
    );
    return r?.string('account_id');
  }

  // ------------------------------------------------- federation: home side

  Future<int> bumpRosterVersion(Tx tx, String groupId) async {
    final r = await tx.queryOne(
      'UPDATE $s.groups SET roster_version = roster_version + 1 WHERE id = @g:uuid RETURNING roster_version',
      {'g': groupId},
    );
    return r?.integer('roster_version') ?? 0;
  }

  Future<int> rosterVersion(SqlSession db, String groupId) async {
    final r = await db.queryOne(
      'SELECT roster_version FROM $s.groups WHERE id = @g:uuid',
      {'g': groupId},
    );
    return r?.integer('roster_version') ?? 0;
  }

  /// Devices other servers reported for their accounts (stored form).
  Future<Map<String, List<String>>> remoteDevicesOf(
    SqlSession db,
    Iterable<String> accounts,
  ) async {
    final list = accounts.toList();
    if (list.isEmpty) return const {};
    final rows = await db.query(
      'SELECT account, device_id FROM $s.remote_devices WHERE account = ANY(@a:_text) ORDER BY device_id',
      {'a': list},
    );
    final out = <String, List<String>>{};
    for (final r in rows) {
      out.putIfAbsent(r.string('account'), () => []).add(r.string('device_id'));
    }
    return out;
  }

  Future<void> setRemoteDevices(
    Tx tx,
    String account,
    List<String> devices,
  ) async {
    await tx.execute('DELETE FROM $s.remote_devices WHERE account = @a:text', {
      'a': account,
    });
    if (devices.isEmpty) return;
    await tx.execute(
      'INSERT INTO $s.remote_devices (account, device_id) SELECT @a:text, d FROM unnest(@d:_uuid) AS d',
      {'a': account, 'd': devices},
    );
  }

  /// Whether [deviceId] is already reported for an account other than
  /// [account].
  Future<bool> remoteDeviceTaken(
    SqlSession db,
    String deviceId, {
    required String account,
  }) async =>
      await db.queryOne(
        'SELECT 1 AS x FROM $s.remote_devices WHERE device_id = @d:uuid AND account <> @a:text LIMIT 1',
        {'d': deviceId, 'a': account},
      ) !=
      null;

  /// Forgets a remote account's devices once it is in none of this
  /// server's groups.
  Future<void> forgetRemoteDevicesIfUnused(Tx tx, String account) async {
    await tx.execute(
      'DELETE FROM $s.remote_devices WHERE account = @a:text '
      'AND NOT EXISTS (SELECT 1 FROM $s.members WHERE account_id = @a:text)',
      {'a': account},
    );
  }

  // ------------------------------------------ federation: member's server

  Future<({String home, int version, Map<String, Object?> snapshot})?>
  remoteGroup(SqlSession db, String groupId) async {
    final r = await db.queryOne(
      'SELECT home_domain, roster_version, snapshot FROM $s.remote_groups WHERE group_id = @g:uuid',
      {'g': groupId},
    );
    return r == null
        ? null
        : (
            home: r.string('home_domain'),
            version: r.integer('roster_version'),
            snapshot: r.json('snapshot'),
          );
  }

  Future<String?> remoteHome(SqlSession db, String groupId) async {
    final r = await db.queryOne(
      'SELECT home_domain FROM $s.remote_groups WHERE group_id = @g:uuid',
      {'g': groupId},
    );
    return r?.string('home_domain');
  }

  /// Replaces the cached group and its local members.
  Future<void> saveRemoteGroup(
    Tx tx, {
    required String groupId,
    required String home,
    required int version,
    required Map<String, Object?> snapshot,
    required Iterable<String> members,
  }) async {
    await tx.execute(
      'INSERT INTO $s.remote_groups (group_id, home_domain, roster_version, snapshot) '
      'VALUES (@g:uuid, @h:text, @v:int8, @s:jsonb) ON CONFLICT (group_id) DO UPDATE SET '
      'roster_version = excluded.roster_version, snapshot = excluded.snapshot, updated_at = now()',
      {'g': groupId, 'h': home, 'v': version, 's': jsonEncode(snapshot)},
    );
    await tx.execute('DELETE FROM $s.remote_members WHERE group_id = @g:uuid', {
      'g': groupId,
    });
    final list = members.toList();
    if (list.isEmpty) return;
    await tx.execute(
      'INSERT INTO $s.remote_members (group_id, account_id) SELECT @g:uuid, a FROM unnest(@a:_uuid) AS a',
      {'g': groupId, 'a': list},
    );
  }

  Future<void> deleteRemoteGroup(Tx tx, String groupId) async {
    await tx.execute('DELETE FROM $s.remote_groups WHERE group_id = @g:uuid', {
      'g': groupId,
    });
  }

  Future<Set<String>> remoteMembers(SqlSession db, String groupId) async {
    final rows = await db.query(
      'SELECT account_id FROM $s.remote_members WHERE group_id = @g:uuid',
      {'g': groupId},
    );
    return {for (final r in rows) r.string('account_id')};
  }

  /// Remote groups [accountId] belongs to: id, home and cached versions.
  Future<List<({String groupId, String home, int epoch, int stateVersion})>>
  remoteGroupsOf(SqlSession db, String accountId) async {
    final rows = await db.query(
      'SELECT g.group_id, g.home_domain, g.snapshot FROM $s.remote_groups g '
      'JOIN $s.remote_members m ON m.group_id = g.group_id WHERE m.account_id = @a:uuid '
      'ORDER BY g.group_id',
      {'a': accountId},
    );
    return [
      for (final r in rows)
        (
          groupId: r.string('group_id'),
          home: r.string('home_domain'),
          epoch: (r.json('snapshot')['epoch'] as int?) ?? 0,
          stateVersion: (r.json('snapshot')['state_version'] as int?) ?? 0,
        ),
    ];
  }

  /// Records that [accountId] asked to join [groupId] (homed elsewhere)
  /// at [at], and drops its markers older than [expired].
  Future<void> recordRemoteJoin(
    SqlSession db,
    String groupId,
    String accountId, {
    required DateTime at,
    required DateTime expired,
  }) async {
    await db.execute(
      'DELETE FROM $s.remote_joins WHERE account_id = @a:uuid AND created_at < @e:timestamptz',
      {'a': accountId, 'e': expired},
    );
    await db.execute(
      'INSERT INTO $s.remote_joins (group_id, account_id, created_at) '
      'VALUES (@g:uuid, @a:uuid, @t:timestamptz) '
      'ON CONFLICT (group_id, account_id) DO UPDATE SET created_at = excluded.created_at',
      {'g': groupId, 'a': accountId, 't': at},
    );
  }

  /// Consumes a join marker newer than [expired]; whether there was one.
  Future<bool> takeRemoteJoin(
    Tx tx,
    String groupId,
    String accountId, {
    required DateTime expired,
  }) async => (await tx.query(
    'DELETE FROM $s.remote_joins WHERE group_id = @g:uuid AND account_id = @a:uuid '
    'RETURNING created_at >= @e:timestamptz AS live',
    {'g': groupId, 'a': accountId, 'e': expired},
  )).any((r) => r.boolean('live'));

  Future<void> dropRemoteJoin(
    SqlSession db,
    String groupId,
    String accountId,
  ) async {
    await db.execute(
      'DELETE FROM $s.remote_joins WHERE group_id = @g:uuid AND account_id = @a:uuid',
      {'g': groupId, 'a': accountId},
    );
  }

  Future<void> removeRemoteMember(Tx tx, String accountId) async {
    await tx.execute('DELETE FROM $s.remote_joins WHERE account_id = @a:uuid', {
      'a': accountId,
    });
    await tx.execute(
      'DELETE FROM $s.remote_members WHERE account_id = @a:uuid',
      {'a': accountId},
    );
    await tx.execute(
      'DELETE FROM $s.remote_groups g WHERE NOT EXISTS '
      '(SELECT 1 FROM $s.remote_members m WHERE m.group_id = g.group_id)',
    );
  }
}
