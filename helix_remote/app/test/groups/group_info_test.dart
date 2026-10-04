import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/features/groups/application/group_info.dart';
import 'package:helix_remote/features/groups/application/group_models.dart';
import 'package:helix_remote/features/groups/presentation/group_info_screen.dart';
import 'package:helix_remote_api/v2.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart'
    show ErrorCode;

import '../support/group_support.dart';
import '../support/harness.dart';

/// A group's page: who is in it, what each role may do, and what a refusal
/// says.
void main() {
  void tall(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<FakeGroupsPort> pump(
    WidgetTester tester,
    GroupSnapshot? group, {
    FakePicker? picker,
    String? Function(String)? chat,
  }) async {
    tall(tester);
    final port = FakeGroupsPort(group: group);
    await tester.pumpWidget(
      harness(
        home: const GroupInfoScreen(groupId: 'g1'),
        routes: [
          stubRoute('/home/groups/:id/settings', 'settings'),
          stubRoute('/home/groups/:id/invite', 'invite'),
          stubRoute('/home/groups/:id/requests', 'requests'),
          stubRoute('/home/groups/:id/banned', 'banned'),
          stubRoute('/home/groups/:id/add', 'add'),
        ],
        overrides: groupOverrides(
          port: port,
          names: testNames,
          picker: picker,
          chatLocation: chat,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return port;
  }

  Future<void> tapMember(WidgetTester tester, String name) async {
    await tester.tap(find.text(name));
    await tester.pumpAndSettle();
  }

  group('the header and the roster', () {
    testWidgets('shows the name, count, description and every member', (
      tester,
    ) async {
      await pump(tester, testGroup());

      expect(find.text('Book club'), findsWidgets);
      expect(find.text('4 members'), findsWidgets);
      expect(find.text('We read on Sundays'), findsOneWidget);
      expect(find.text('You'), findsOneWidget);
      expect(find.text('Ada Lovelace'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('~carol'), findsOneWidget);
    });

    testWidgets('roles are shown and members are ordered owner, admins, '
        'the rest', (tester) async {
      await pump(tester, testGroup());

      expect(find.textContaining('Owner'), findsOneWidget);
      expect(find.textContaining('Admin'), findsOneWidget);
      final owner = tester.getTopLeft(find.text('You')).dy;
      final admin = tester.getTopLeft(find.text('Ada Lovelace')).dy;
      final bob = tester.getTopLeft(find.text('Bob')).dy;
      expect(owner, lessThan(admin));
      expect(admin, lessThan(bob));
    });

    testWidgets('the naming order is used: number under a name, ~Helix name '
        'alone', (tester) async {
      await pump(tester, testGroup());

      expect(find.textContaining('+8801711000001'), findsOneWidget);
      expect(find.textContaining('+8801711000002'), findsOneWidget);
    });

    testWidgets('a member from another server shows that server', (
      tester,
    ) async {
      await pump(
        tester,
        testGroup(
          homeServer: 'chat.example.org',
          members: const [
            GroupMemberInfo(
              account: 'self',
              role: GroupMemberRole.member,
              isSelf: true,
            ),
            GroupMemberInfo(
              account: 'zed@far.example.net',
              role: GroupMemberRole.member,
              nameHint: 'zed',
            ),
          ],
          role: GroupMemberRole.member,
        ),
      );

      expect(find.textContaining('far.example.net'), findsOneWidget);
      expect(find.textContaining('on chat.example.org'), findsOneWidget);
    });

    testWidgets('a group whose name has not arrived says so', (tester) async {
      await pump(tester, testGroup(title: ''));

      expect(find.text('New group'), findsOneWidget);
      expect(find.textContaining('still arriving'), findsOneWidget);
    });
  });

  group('what each role sees', () {
    testWidgets('the owner sees every admin tool and can delete', (
      tester,
    ) async {
      await pump(tester, testGroup());

      expect(find.text('Edit group info'), findsOneWidget);
      expect(find.text('Group settings'), findsOneWidget);
      expect(find.text('Invite with a link'), findsOneWidget);
      expect(find.text('Join requests'), findsOneWidget);
      expect(find.text('Banned people'), findsOneWidget);
      expect(find.text('Add members'), findsOneWidget);
      expect(find.text('Leave group'), findsOneWidget);
      expect(find.text('Delete group'), findsOneWidget);
    });

    testWidgets('an admin cannot delete the group', (tester) async {
      await pump(tester, testGroup(role: GroupMemberRole.admin));

      expect(find.text('Group settings'), findsOneWidget);
      expect(find.text('Delete group'), findsNothing);
    });

    testWidgets('a member sees no admin tool unless the group allows it', (
      tester,
    ) async {
      await pump(tester, testGroup(role: GroupMemberRole.member));

      expect(find.text('Group settings'), findsNothing);
      expect(find.text('Invite with a link'), findsNothing);
      expect(find.text('Edit group info'), findsNothing);
      expect(find.text('Add members'), findsNothing);
      expect(find.text('Leave group'), findsOneWidget);
      // Nothing to do to anybody.
      expect(find.byIcon(Icons.more_vert), findsNothing);
    });

    testWidgets('a member may add and edit when the group says everyone', (
      tester,
    ) async {
      await pump(
        tester,
        testGroup(
          role: GroupMemberRole.member,
          permissions: const GroupPermissions(
            addMembers: GroupWho.everyone,
            editInfo: GroupWho.everyone,
          ),
        ),
      );

      expect(find.text('Add members'), findsOneWidget);
      expect(find.text('Edit group info'), findsOneWidget);
      expect(find.text('Group settings'), findsNothing);
    });

    test('what the viewer may do to each kind of member', () {
      List<MemberAction> actions(
        GroupMemberRole viewer,
        GroupMemberRole target,
      ) => buildGroupInfo(
        testGroup(
          role: viewer,
          members: [
            GroupMemberInfo(account: 'self', role: viewer, isSelf: true),
            GroupMemberInfo(account: 'x', role: target),
          ],
        ),
        testNames,
      ).members.firstWhere((m) => m.account == 'x').actions;

      expect(actions(GroupMemberRole.owner, GroupMemberRole.member), [
        MemberAction.makeAdmin,
        MemberAction.makeOwner,
        MemberAction.remove,
        MemberAction.ban,
      ]);
      expect(actions(GroupMemberRole.owner, GroupMemberRole.admin), [
        MemberAction.removeAdmin,
        MemberAction.makeOwner,
        MemberAction.remove,
        MemberAction.ban,
      ]);
      expect(actions(GroupMemberRole.admin, GroupMemberRole.member), [
        MemberAction.makeAdmin,
        MemberAction.remove,
        MemberAction.ban,
      ]);
      // Admins manage members, not each other; nobody touches the owner.
      expect(actions(GroupMemberRole.admin, GroupMemberRole.admin), isEmpty);
      expect(actions(GroupMemberRole.admin, GroupMemberRole.owner), isEmpty);
      expect(actions(GroupMemberRole.member, GroupMemberRole.member), isEmpty);
    });
  });

  group('admin actions on a member', () {
    testWidgets('make admin', (tester) async {
      final port = await pump(tester, testGroup());
      await tapMember(tester, 'Bob');
      await tester.tap(find.text('Make admin'));
      await tester.pumpAndSettle();

      expect(port.calls, ['role bob admin']);
      expect(find.text('Bob is now an admin.'), findsOneWidget);
    });

    testWidgets('remove admin', (tester) async {
      final port = await pump(tester, testGroup());
      await tapMember(tester, 'Ada Lovelace');
      await tester.tap(find.text('Remove admin'));
      await tester.pumpAndSettle();

      expect(port.calls, ['role ada member']);
    });

    testWidgets('remove asks first, then removes', (tester) async {
      final port = await pump(tester, testGroup());
      await tapMember(tester, 'Bob');
      await tester.tap(find.text('Remove from group'));
      await tester.pumpAndSettle();
      expect(find.text('Remove Bob?'), findsOneWidget);
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      expect(port.calls, ['remove bob']);
      expect(find.text('Bob was removed.'), findsOneWidget);
    });

    testWidgets('cancelling a removal does nothing', (tester) async {
      final port = await pump(tester, testGroup());
      await tapMember(tester, 'Bob');
      await tester.tap(find.text('Remove from group'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(port.calls, isEmpty);
    });

    testWidgets('ban asks first, then removes and bans', (tester) async {
      final port = await pump(tester, testGroup());
      await tapMember(tester, 'Bob');
      await tester.tap(find.text('Remove and ban'));
      await tester.pumpAndSettle();
      expect(find.text('Remove and ban Bob?'), findsOneWidget);
      await tester.tap(find.text('Ban'));
      await tester.pumpAndSettle();

      expect(port.calls, ['ban bob']);
    });

    testWidgets('making somebody the owner needs a clear yes', (tester) async {
      final port = await pump(tester, testGroup());
      await tapMember(tester, 'Bob');
      await tester.tap(find.text('Make owner'));
      await tester.pumpAndSettle();
      expect(find.text('Make Bob the owner?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Make owner'));
      await tester.pumpAndSettle();

      expect(port.calls, ['role bob owner']);
    });

    testWidgets('a refusal from the server is said in plain words', (
      tester,
    ) async {
      final port = await pump(tester, testGroup());
      port.failWith = const ApiException(
        status: 403,
        code: ErrorCode.forbidden,
        message: 'internal detail',
      );
      await tapMember(tester, 'Bob');
      await tester.tap(find.text('Make admin'));
      await tester.pumpAndSettle();

      expect(
        find.text('You do not have permission to do that in this group.'),
        findsOneWidget,
      );
      expect(find.textContaining('internal detail'), findsNothing);
    });

    testWidgets('a stale roster is said, with what to do', (tester) async {
      final port = await pump(tester, testGroup());
      port.failWith = const ApiException(
        status: 409,
        code: ErrorCode.deviceListStale,
      );
      await tapMember(tester, 'Bob');
      await tester.tap(find.text('Remove from group'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      expect(find.textContaining('member list changed'), findsOneWidget);
    });
  });

  group('the group itself', () {
    testWidgets('leaving asks, leaves, and says so', (tester) async {
      final port = await pump(tester, testGroup(role: GroupMemberRole.member));
      await tester.tap(find.text('Leave group'));
      await tester.pumpAndSettle();
      expect(find.text('Leave "Book club"?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Leave'));
      await tester.pumpAndSettle();

      expect(port.calls, ['leave']);
    });

    testWidgets('deleting asks, then deletes for everyone', (tester) async {
      final port = await pump(tester, testGroup());
      await tester.tap(find.text('Delete group'));
      await tester.pumpAndSettle();
      expect(find.text('Delete "Book club"?'), findsOneWidget);
      await tester.tap(find.text('Delete group').last);
      await tester.pumpAndSettle();

      expect(port.calls, ['delete']);
    });

    testWidgets('a failed leave shows why and stays', (tester) async {
      final port = await pump(tester, testGroup(role: GroupMemberRole.member));
      port.failWith = const NetworkException();
      await tester.tap(find.text('Leave group'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Leave'));
      await tester.pumpAndSettle();

      expect(find.textContaining('No connection'), findsOneWidget);
      expect(find.text('Leave group'), findsOneWidget);
    });

    testWidgets('the disappearing-messages default shows and can be set by an '
        'admin', (tester) async {
      final port = await pump(tester, testGroup(disappearing: 604800));
      expect(find.text('7 days'), findsOneWidget);

      await tester.tap(find.text('Disappearing messages'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('24 hours'));
      await tester.pumpAndSettle();

      expect(port.calls, ['disappearing 86400']);
    });

    testWidgets('turning disappearing messages off sends null', (tester) async {
      final port = await pump(tester, testGroup(disappearing: 604800));
      await tester.tap(find.text('Disappearing messages'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Off'));
      await tester.pumpAndSettle();

      expect(port.calls, ['disappearing null']);
    });

    testWidgets('a member sees the timer but cannot change it', (tester) async {
      final port = await pump(
        tester,
        testGroup(role: GroupMemberRole.member, disappearing: 86400),
      );
      expect(find.text('24 hours'), findsOneWidget);
      await tester.tap(find.text('Disappearing messages'));
      await tester.pumpAndSettle();
      expect(port.calls, isEmpty);
      expect(find.text('Off'), findsNothing);
    });

    testWidgets('the admin tools open their pages', (tester) async {
      await pump(tester, testGroup());
      await tester.tap(find.text('Group settings'));
      await tester.pumpAndSettle();
      expect(find.text('settings'), findsOneWidget);
    });
  });

  group('editing', () {
    testWidgets('name and description are saved, only what changed', (
      tester,
    ) async {
      final port = await pump(tester, testGroup());
      await tester.tap(find.text('Edit group info'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Group name'),
        'Reading club',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(port.calls, ['rename Reading club']);
    });

    testWidgets('a new description is saved on its own', (tester) async {
      final port = await pump(tester, testGroup());
      await tester.tap(find.text('Edit group info'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Description'),
        'Now on Saturdays',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(port.calls, ['description Now on Saturdays']);
    });

    testWidgets('a conflict while saving is explained', (tester) async {
      final port = await pump(tester, testGroup());
      port.failWith = const GroupException(GroupFailure.versionConflict);
      await tester.tap(find.text('Edit group info'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Group name'),
        'Other',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.textContaining('changed at the same time'), findsOneWidget);
    });

    testWidgets('the picture is chosen from the phone and encrypted up', (
      tester,
    ) async {
      final port = await pump(
        tester,
        testGroup(),
        picker: FakePicker(Uint8List.fromList([1, 2, 3])),
      );
      await tester.tap(find.byType(InkResponse).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose a picture'));
      await tester.pumpAndSettle();

      expect(port.calls, ['picture set']);
    });

    testWidgets('choosing nothing changes nothing', (tester) async {
      final port = await pump(tester, testGroup(), picker: FakePicker());
      await tester.tap(find.byType(InkResponse).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose a picture'));
      await tester.pumpAndSettle();

      expect(port.calls, isEmpty);
    });
  });

  group('roster changes and the end of membership', () {
    testWidgets('being removed is said, and the page says you are out', (
      tester,
    ) async {
      final port = await pump(tester, testGroup());

      port.signal(const GroupMembershipEnded('g1', 'removed'));
      await tester.pump();
      port.set(null);
      await tester.pumpAndSettle();

      expect(find.text('You were removed from this group.'), findsOneWidget);
      expect(find.text('You are not in this group'), findsOneWidget);
    });

    testWidgets('a group that was deleted says so', (tester) async {
      final port = await pump(tester, testGroup());
      port.signal(const GroupMembershipEnded('g1', 'deleted'));
      await tester.pumpAndSettle();

      expect(find.text('This group was deleted.'), findsOneWidget);
    });

    testWidgets('a member added elsewhere appears without a refresh', (
      tester,
    ) async {
      final port = await pump(tester, testGroup());
      expect(find.text('5 members'), findsNothing);

      port.set(
        testGroup(
          members: [
            ...testGroup().members,
            const GroupMemberInfo(
              account: 'dan',
              role: GroupMemberRole.member,
              nameHint: 'dan',
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('5 members'), findsWidgets);
      expect(find.text('~dan'), findsOneWidget);
    });

    testWidgets('a group that is not there shows the not-a-member page', (
      tester,
    ) async {
      await pump(tester, null);
      expect(find.text('You are not in this group'), findsOneWidget);
      expect(find.text('Go back'), findsOneWidget);
    });
  });

  group('states and accessibility', () {
    testWidgets('holds at 2x text with nothing overflowing', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pump(tester, testGroup());

      expect(tester.takeException(), isNull);
    });

    testWidgets('meets the tap-target and label guidelines', (tester) async {
      await pump(tester, testGroup());

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    });
  });
}
