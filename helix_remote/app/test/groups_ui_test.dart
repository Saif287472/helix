// Phase 13 group end-to-end reachability tests.

import 'dart:ffi';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/app/remote_messaging_service.dart';
import 'package:helix_remote/screens/groups_screen.dart';
import 'package:helix_remote_api/api/realtime_envelope.dart';
import 'package:helix_remote_api/api/rest_client.dart';
import 'package:helix_remote_domain/models.dart';
import 'package:helix_remote_groups/helix_remote_groups.dart';
import 'package:helix_remote_storage/helix_remote_storage.dart';
import 'package:helix_remote_sync/helix_remote_sync.dart';
import 'package:path/path.dart' as p;
import 'package:helix_remote/l10n/helix_localizations.dart';

// ---------------------------------------------------------------------------
// Minimal fakes (same pattern as phase12_remote_messaging_screen_test.dart)
// ---------------------------------------------------------------------------

class _FakeProtector implements RemoteMessageProtector {
  @override
  Future<String> encryptText({
    required String conversationId,
    required String messageId,
    required String plaintext,
    required String recipientDeviceId,
  }) async => 'enc:$plaintext';

  @override
  Future<String> decryptText({
    required String conversationId,
    required String messageId,
    required String ciphertext,
  }) async => ciphertext.substring(4);
}

class _FakeGateway implements SyncGateway {
  @override
  Future<List<RemoteRealtimeEnvelope>> fetchInboundEvents({
    required int sinceSequence,
  }) async => [];

  @override
  Future<void> sendOutboundOperation({
    required String opId,
    required String type,
    required Map<String, dynamic> payload,
  }) async {}
}

class _FakeRestClient implements HelixRemoteRestClient {
  @override
  set accessToken(String? token) {}
  @override
  Future<void> close() async {}
  @override
  dynamic noSuchMethod(Invocation i) async => {};
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

HelixRemoteDatabase _openDb() {
  final db = HelixRemoteDatabase(File(':memory:'));
  db.initialize();
  return db;
}

RemoteGroupService _groupService(HelixRemoteDatabase db) {
  var counter = 0;
  return RemoteGroupService(
    db: db,
    generateId: () => 'gen-${++counter}',
    encryptionKeyProvider: (groupId, epoch) => 'key-$groupId-$epoch',
  );
}

Future<RemoteMessagingService> _messagingService(HelixRemoteDatabase db) async {
  var tick = 0;
  final svc = RemoteMessagingService(
    db: db,
    syncEngine: RemoteSyncEngine(db),
    gateway: _FakeGateway(),
    protector: _FakeProtector(),
    restClient: _FakeRestClient(),
    clock: () => DateTime.fromMillisecondsSinceEpoch(++tick * 1000),
  );
  await svc.setupAccount(
    account: RemoteAccount(
      accountId: 'alice',
      identityPublicKey: 'alice_key',
      createdAt: DateTime.now(),
    ),
    device: RemoteDevice(
      deviceId: 'alice_dev',
      deviceName: 'Alice phone',
      deviceSigningPublicKey: 'alice_sign',
      deviceAgreementPublicKey: 'alice_agree',
      createdAt: DateTime.now(),
    ),
  );
  return svc;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() {
    if (Platform.isWindows) {
      var dir = Directory.current;
      for (var i = 0; i < 5; i++) {
        final path = p.join(dir.path, '.dart_tool', 'lib', 'sqlite3.dll');
        if (File(path).existsSync()) {
          DynamicLibrary.open(path);
          break;
        }
        final parent = dir.parent;
        if (parent.path == dir.path) break;
        dir = parent;
      }
    }
  });

  late HelixRemoteDatabase db;
  late RemoteGroupService groupService;
  late RemoteMessagingService messagingService;

  setUp(() async {
    db = _openDb();
    groupService = _groupService(db);
    messagingService = await _messagingService(db);
  });

  tearDown(() {
    db.close();
  });

  group('P13-W01 GroupsScreen reachability', () {
    Widget makeWidget() => MaterialApp(
      localizationsDelegates: HelixLocalizations.localizationsDelegates,
      supportedLocales: HelixLocalizations.supportedLocales,
      home: GroupsScreen(
        groupService: groupService,
        messagingService: messagingService,
      ),
    );

    testWidgets('shows No groups yet when no groups', (tester) async {
      await tester.pumpWidget(makeWidget());
      expect(find.text('No groups yet'), findsOneWidget);
    });

    testWidgets('shows Create group button', (tester) async {
      await tester.pumpWidget(makeWidget());
      expect(find.byIcon(Icons.add), findsOneWidget);
    });

    testWidgets('Create Group dialog appears on add button tap', (
      tester,
    ) async {
      await tester.pumpWidget(makeWidget());
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      expect(find.text('Create Group'), findsOneWidget);
    });

    testWidgets('creating a group shows it in the list', (tester) async {
      groupService.createGroup(
        groupId: 'grp-001',
        name: 'Dev Team',
        creatorId: 'alice',
      );

      await tester.pumpWidget(makeWidget());
      expect(find.text('Dev Team'), findsOneWidget);
    });

    testWidgets(
      'group list tile has onTap that navigates to ConversationScreen',
      (tester) async {
        groupService.createGroup(
          groupId: 'grp-002',
          name: 'Design Crew',
          creatorId: 'alice',
        );

        await tester.pumpWidget(makeWidget());
        await tester.pumpAndSettle();

        expect(find.text('Design Crew'), findsOneWidget);
        await tester.tap(find.text('Design Crew'));
        await tester.pumpAndSettle();

        // GroupsScreen is no longer on top — ConversationScreen was pushed
        expect(find.byType(GroupsScreen), findsNothing);
      },
    );

    testWidgets('popup menu shows Open and Leave for admin', (tester) async {
      groupService.createGroup(
        groupId: 'grp-003',
        name: 'Admin Group',
        creatorId: 'alice',
      );

      await tester.pumpWidget(makeWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();

      expect(find.text('Open'), findsOneWidget);
      expect(find.text('Leave group'), findsOneWidget);
    });

    testWidgets('popup menu shows Invite member for admin', (tester) async {
      groupService.createGroup(
        groupId: 'grp-004',
        name: 'Admin Only',
        creatorId: 'alice',
      );

      await tester.pumpWidget(makeWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();

      expect(find.text('Invite member'), findsOneWidget);
      expect(find.text('Delete group'), findsOneWidget);
    });

    testWidgets('popup Invite member opens invite dialog', (tester) async {
      groupService.createGroup(
        groupId: 'grp-005',
        name: 'Invite Test',
        creatorId: 'alice',
      );

      await tester.pumpWidget(makeWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Invite member'));
      await tester.pumpAndSettle();

      expect(find.text('Invite Member'), findsOneWidget);
    });

    testWidgets('pending invite section appears when invites exist', (
      tester,
    ) async {
      db.upsertGroupInvite(
        inviteId: 'inv-1',
        groupId: 'grp-external',
        inviterId: 'bob',
        status: kInviteStatusPending,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );

      await tester.pumpWidget(makeWidget());
      expect(find.text('Pending Invites (1)'), findsOneWidget);
    });
  });

  group('P13-A01 group service reachability', () {
    test('createGroup persists conversation with GROUP type', () {
      groupService.createGroup(groupId: 'g1', name: 'Test', creatorId: 'alice');

      final convs = messagingService.conversationList();
      expect(convs.any((c) => c.conversationId == 'g1'), isTrue);
    });

    test('creator is automatically ADMIN', () {
      groupService.createGroup(
        groupId: 'g2',
        name: 'Admin test',
        creatorId: 'alice',
      );

      final members = groupService.getGroupMembersWithRoles('g2');
      final alice = members.firstWhere((m) => m['account_id'] == 'alice');
      expect(alice['role'], equals(kRoleAdmin));
    });

    test('inviteMember queues invite operation', () {
      groupService.createGroup(
        groupId: 'g3',
        name: 'Invite test',
        creatorId: 'alice',
      );
      groupService.inviteMember(
        groupId: 'g3',
        inviteId: 'inv-x',
        inviterId: 'alice',
        inviteeId: 'charlie',
      );

      final invites = db.getGroupInvites();
      expect(invites.any((i) => i['invite_id'] == 'inv-x'), isTrue);
    });

    test('leaveGroup removes member and rotates epoch', () {
      groupService.createGroup(
        groupId: 'g4',
        name: 'Leave test',
        creatorId: 'alice',
      );
      db.upsertConversationMember('g4', 'bob', role: kRoleMember);
      final epochBefore = groupService.getGroupEpoch('g4');

      groupService.leaveGroup(groupId: 'g4', selfAccountId: 'bob');

      final epochAfter = groupService.getGroupEpoch('g4');
      expect(epochAfter, greaterThan(epochBefore));
      expect(groupService.getGroupMembers('g4'), isNot(contains('bob')));
    });
  });
}
