import 'dart:convert';

import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  final id = Uuid.v7();

  group('AccountAddress', () {
    test('parses bare and qualified ids', () {
      final bare = AccountAddress.tryParse(id)!;
      expect(bare.isRemote, isFalse);
      expect(bare.toString(), id);

      final remote = AccountAddress.tryParse('$id@Helix.Example.org:8443')!;
      expect(remote.domain, 'helix.example.org:8443');
      expect(remote.toString(), '$id@helix.example.org:8443');
      expect(remote.relativeTo('helix.example.org:8443'), bare);
      expect(remote.relativeTo('other.example'), remote);
      expect(bare.qualified('home.example'), '$id@home.example');
    });

    test('refuses malformed addresses', () {
      for (final bad in [
        '',
        'not-a-uuid',
        '$id@',
        '@example.org',
        'x@example.org',
        '$id@exa mple.org',
        '$id@-example.org',
        '$id@example.org:99999x',
        '$id@[::1]',
        '$id@user@example.org',
      ]) {
        expect(AccountAddress.tryParse(bad), isNull, reason: bad);
      }
    });
  });

  test('the signing input binds every part of a request', () {
    String input({
      String server = 'a.example',
      int ts = 1,
      String method = 'post',
      String path = '/v1/s2s/messages',
      String body = '{}',
    }) => utf8.decode(
      s2sSigningInput(
        server: server,
        timestampMs: ts,
        method: method,
        pathAndQuery: path,
        body: utf8.encode(body),
      ),
    );
    final base = input();
    expect(base, startsWith('helix-s2s-v1|a.example|1|POST|/v1/s2s/messages|'));
    expect(input(server: 'b.example'), isNot(base));
    expect(input(ts: 2), isNot(base));
    expect(input(method: 'GET'), isNot(base));
    expect(input(path: '/v1/s2s/keys/x'), isNot(base));
    expect(input(body: '{"a":1}'), isNot(base));
  });

  test('S2S DTOs round-trip', () {
    final recipients = [
      Recipient(
        account: id,
        devices: [DevicePayload(device: Uuid.v7(), payload: bytes(8))],
      ),
    ];
    expectRoundTrip(
      S2SMessageBatch(
        id: Uuid.v7(),
        sender: '$id@a.example',
        senderDevice: Uuid.v7(),
        recipients: recipients,
        urgent: false,
      ),
      (v) => v.toJson(),
      S2SMessageBatch.fromJson,
    );
    expectRoundTrip(
      S2SCallSignal(
        sender: '$id@a.example',
        senderDevice: Uuid.v7(),
        signal: CallSignalRequest(
          kind: CallSignalKind.offer,
          recipients: recipients,
        ),
      ),
      (v) => v.toJson(),
      S2SCallSignal.fromJson,
    );
  });

  test('group invite tokens name their group and home server', () {
    final group = Uuid.v7();
    expect(groupInviteTokenParts('grp_abc-_x.$group@Helix.Example:8443'), (
      groupId: group,
      domain: 'helix.example:8443',
    ));
    expect(groupInviteTokenParts('grp_abc'), (groupId: null, domain: null));
    expect(groupInviteTokenParts('grp_abc.nope@helix.example'), (
      groupId: null,
      domain: null,
    ));
  });

  test('group S2S DTOs round-trip', () {
    final group = Uuid.v7();
    expectRoundTrip(
      S2SGroupAction(
        actor: '$id@b.example',
        actorDevice: Uuid.v7(),
        action: 'add_members',
        params: {'account': id},
        body: const {'accounts': <String>[]},
      ),
      (v) => v.toJson(),
      S2SGroupAction.fromJson,
    );
    expectRoundTrip(
      const S2SGroupActionResult(status: 204),
      (v) => v.toJson(),
      S2SGroupActionResult.fromJson,
    );
    expectRoundTrip(
      S2SGroupSync(
        rosterVersion: 3,
        group: Group(
          groupId: group,
          epoch: 1,
          stateVersion: 2,
          encryptedState: bytes(8),
          settings: const GroupSettings(),
          members: [
            GroupMember(
              account: id,
              role: GroupRole.owner,
              joinedAt: DateTime.utc(2026),
            ),
          ],
          createdAt: DateTime.utc(2026),
          homeServer: 'a.example',
        ),
        event: RosterChangeEvent(
          groupId: group,
          change: RosterChangeKind.added,
          epoch: 1,
          actor: '$id@a.example',
          members: [id],
        ),
        notify: [id],
      ),
      (v) => v.toJson(),
      S2SGroupSync.fromJson,
    );
    expectRoundTrip(
      S2SGroupSyncResponse(
        devices: {
          id: [Uuid.v7()],
        },
        rejected: [Uuid.v7()],
      ),
      (v) => v.toJson(),
      S2SGroupSyncResponse.fromJson,
    );
    expectRoundTrip(
      S2SGroupMessage(
        id: Uuid.v7(),
        sender: '$id@a.example',
        senderDevice: Uuid.v7(),
        payload: bytes(16),
        devices: [Uuid.v7()],
        distributions: [DevicePayload(device: Uuid.v7(), payload: bytes(4))],
      ),
      (v) => v.toJson(),
      S2SGroupMessage.fromJson,
    );
  });
}
