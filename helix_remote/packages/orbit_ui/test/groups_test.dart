import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_ui/orbit_ui.dart';

/// Phase 4 batch 7: the group pages. How they look is checked against the
/// prototype by the compare tool (`group-*`).
void main() {
  late OrbitTokens orbit;
  setUpAll(() {
    orbit = OrbitTokens.fromThemeJson(
      jsonDecode(File('assets/themes/orbit.json').readAsStringSync())
          as Map<String, Object?>,
    );
  });

  Future<void> show(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(412, 866);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(412, 866),
          disableAnimations: true,
        ),
        child: MaterialApp(
          theme: OrbitTheme.of(orbit),
          home: Scaffold(body: screen),
        ),
      ),
    );
    await tester.pump();
  }

  final people = [OrbitFakes.people['nadia']!, OrbitFakes.people['arif']!];

  testWidgets('new group: picking shows chips and Create with N', (
    tester,
  ) async {
    String? toggled;
    var created = 0;
    await show(
      tester,
      NewGroupScreen(
        model: NewGroupModel(
          picker: MemberPickerModel(
            candidates: people,
            selected: const ['arif'],
          ),
        ),
        actions: NewGroupActions(
          picker: MemberPickerActions(onToggle: (id) => toggled = id),
          onCreate: () async {
            created++;
            return null;
          },
        ),
      ),
    );
    expect(find.text('Create with 1'), findsOneWidget);
    expect(find.text('Arif'), findsOneWidget);
    await tester.tap(find.text('Nadia Rahman'));
    expect(toggled, 'nadia');
    await tester.tap(find.text('Create with 1'));
    expect(created, 1);
  });

  testWidgets('the picker offers a lookup for a number', (tester) async {
    String? looked;
    await show(
      tester,
      NewGroupScreen(
        model: NewGroupModel(picker: MemberPickerModel(candidates: people)),
        actions: NewGroupActions(
          picker: MemberPickerActions(
            onLookup: (q) async {
              looked = q;
              return (found: null, error: 'Nobody has that number.');
            },
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(EditableText).last, '+8801999');
    await tester.pump();
    await tester.tap(find.text('Find “+8801999” on Orbit'));
    await tester.pump();
    expect(looked, '+8801999');
    // A look-up that finds nobody says why.
    expect(find.text('Nobody has that number.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  GroupInfoModel info({bool admin = true, bool owner = false}) =>
      GroupInfoModel(
        groupId: 'family',
        title: 'Family',
        avatar: const HelixAvatarModel(name: 'Family', isGroup: true),
        memberCountLabel: '3 members',
        isOwner: owner,
        canAdminister: admin,
        canEditInfo: admin,
        canAddMembers: admin,
        members: const [
          GroupMemberView(
            account: 'me',
            title: 'You',
            avatar: HelixAvatarModel(name: 'Hasan'),
            roleLabel: 'Admin',
          ),
          GroupMemberView(
            account: 'rumana',
            title: 'Rumana Apu',
            avatar: HelixAvatarModel(name: 'Rumana Apu'),
            canAct: true,
          ),
        ],
      );

  testWidgets('group info: admins see the admin pages and member actions', (
    tester,
  ) async {
    (String, MemberAction)? acted;
    await show(
      tester,
      GroupInfoScreen(
        model: info(),
        actions: GroupInfoActions(
          onMemberAction: (a, x) async {
            acted = (a, x);
            return 'Rumana Apu is an admin now.';
          },
        ),
      ),
    );
    expect(find.text('Group settings'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byTooltip('Actions for Rumana Apu'),
      200,
    );
    await tester.tap(find.byTooltip('Actions for Rumana Apu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Make admin'));
    await tester.pumpAndSettle();
    expect(acted, ('rumana', MemberAction.makeAdmin));
    // The answer is said.
    expect(find.text('Rumana Apu is an admin now.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('group info: a member sees no admin pages; owner can delete', (
    tester,
  ) async {
    await show(tester, GroupInfoScreen(model: info(admin: false)));
    expect(find.text('Group settings'), findsNothing);
    expect(find.text('Edit group info'), findsNothing);
    await show(tester, GroupInfoScreen(model: info(owner: true)));
    await tester.scrollUntilVisible(find.text('Delete group'), 200);
    expect(find.text('Delete group'), findsOneWidget);
  });

  testWidgets('invite links: revoke asks first', (tester) async {
    String? revoked;
    await show(
      tester,
      InviteLinksScreen(
        model: const InviteLinksModel(
          links: [InviteLinkItem(id: '1', url: 'https://x/open#HLX-GRP-1')],
        ),
        actions: InviteLinksActions(onRevoke: (id) => revoked = id),
      ),
    );
    await tester.tap(find.text('Revoke'));
    await tester.pumpAndSettle();
    expect(revoked, isNull);
    await tester.tap(find.text('Revoke').last);
    await tester.pumpAndSettle();
    expect(revoked, '1');
  });

  testWidgets('a link without its URL says when it was made, revoke only', (
    tester,
  ) async {
    String? revoked;
    await show(
      tester,
      InviteLinksScreen(
        model: const InviteLinksModel(
          links: [
            InviteLinkItem(id: 'old', approve: true, made: '3 Oct, 14:05'),
          ],
        ),
        actions: InviteLinksActions(onRevoke: (id) => revoked = id),
      ),
    );
    expect(
      find.text(
        'Made 3 Oct, 14:05. It cannot be shown again, but it can be revoked.',
      ),
      findsOneWidget,
    );
    expect(find.text('Share'), findsNothing);
    expect(find.text('Copy'), findsNothing);
    await tester.tap(find.text('Revoke'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Revoke').last);
    await tester.pumpAndSettle();
    expect(revoked, 'old');
  });

  testWidgets('no "links appear here" while the list loads', (tester) async {
    await show(
      tester,
      const InviteLinksScreen(model: InviteLinksModel(loading: true)),
    );
    expect(find.textContaining('Links you make appear here'), findsNothing);
  });

  testWidgets('join requests approve and reject', (tester) async {
    final done = <String>[];
    await show(
      tester,
      JoinRequestsScreen(
        model: const JoinRequestsModel(
          requests: [
            PersonEntryView(
              account: 'sadia',
              title: 'Sadia Islam',
              whenLabel: 'Asked today at 09:02',
              avatar: HelixAvatarModel(name: 'Sadia Islam'),
            ),
          ],
        ),
        actions: JoinRequestsActions(
          onApprove: (a) async {
            done.add('+$a');
            return null;
          },
          onReject: (a) async {
            done.add('-$a');
            return null;
          },
        ),
      ),
    );
    await tester.tap(find.byTooltip('Approve Sadia Islam'));
    await tester.tap(find.byTooltip('Reject Sadia Islam'));
    expect(done, ['+sadia', '-sadia']);
  });

  testWidgets('join a group: preview, approval and already a member', (
    tester,
  ) async {
    await show(
      tester,
      const JoinGroupScreen(
        model: JoinGroupModel(
          stage: JoinStage.preview,
          previewName: 'Book Club',
          previewMemberCount: 14,
          requiresApproval: true,
        ),
      ),
    );
    expect(find.text('Ask to join'), findsOneWidget);
    await show(
      tester,
      const JoinGroupScreen(
        model: JoinGroupModel(
          stage: JoinStage.preview,
          previewName: 'Book Club',
          alreadyMember: true,
        ),
      ),
    );
    expect(find.text('Open group'), findsOneWidget);
    expect(find.text('You are already in this group.'), findsOneWidget);
  });

  group("the app's hooks", () {
    testWidgets('a member menu offers only what the app allows', (
      tester,
    ) async {
      await show(
        tester,
        const GroupInfoScreen(
          model: GroupInfoModel(
            groupId: 'family',
            title: 'Family',
            avatar: HelixAvatarModel(name: 'Family', isGroup: true),
            memberCountLabel: '2 members',
            isOwner: true,
            canAdminister: true,
            members: [
              GroupMemberView(
                account: 'rumana',
                title: 'Rumana Apu',
                avatar: HelixAvatarModel(name: 'Rumana Apu'),
                canAct: true,
                actions: {MemberAction.makeAdmin, MemberAction.remove},
              ),
            ],
          ),
        ),
      );
      await tester.scrollUntilVisible(
        find.byTooltip('Actions for Rumana Apu'),
        200,
      );
      await tester.tap(find.byTooltip('Actions for Rumana Apu'));
      await tester.pumpAndSettle();
      expect(find.text('Make admin'), findsOneWidget);
      expect(find.text('Remove from group'), findsOneWidget);
      expect(find.text('Make owner'), findsNothing);
      expect(find.text('Remove and ban'), findsNothing);
    });

    testWidgets('adding nobody explains why and stays', (tester) async {
      await show(
        tester,
        AddMembersScreen(
          model: AddMembersModel(
            picker: MemberPickerModel(
              candidates: people,
              selected: const ['arif'],
            ),
          ),
          actions: AddMembersActions(
            onAdd: () async =>
                (ok: false, message: 'Arif Hossain could not be added.'),
          ),
        ),
      );
      await tester.tap(find.text('Add 1'));
      await tester.pumpAndSettle();
      expect(find.text('No one was added'), findsOneWidget);
      expect(find.text('Arif Hossain could not be added.'), findsOneWidget);
    });

    testWidgets('a new group explains who was not added, then opens', (
      tester,
    ) async {
      String? opened;
      await show(
        tester,
        NewGroupScreen(
          model: NewGroupModel(
            name: 'Trip',
            picker: MemberPickerModel(
              candidates: people,
              selected: const ['arif'],
            ),
          ),
          actions: NewGroupActions(
            onCreate: () async => (
              groupId: 'g1',
              conversationId: 'group:g1',
              notAddedNames: const ['Arif Hossain'],
            ),
            onOpenGroupChat: (g, c) => opened = c,
          ),
        ),
      );
      await tester.tap(find.text('Create with 1'));
      await tester.pumpAndSettle();
      expect(find.text('Some people were not added'), findsOneWidget);
      expect(opened, isNull);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(opened, 'group:g1');
    });

    testWidgets('a wrong link stays on the field and says so', (tester) async {
      String? continued;
      await show(
        tester,
        JoinGroupScreen(
          model: const JoinGroupModel(),
          actions: JoinGroupActions(
            linkLooksRight: (l) => l.contains('HLX-GRP-'),
            onContinue: (l) => continued = l,
          ),
        ),
      );
      await tester.enterText(find.byType(EditableText), 'hello');
      await tester.tap(find.text('Continue'));
      await tester.pump();
      expect(continued, isNull);
      expect(find.textContaining('not an Orbit group link'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.enterText(
        find.byType(EditableText),
        'https://x/open#HLX-GRP-1',
      );
      await tester.tap(find.text('Continue'));
      expect(continued, 'https://x/open#HLX-GRP-1');
    });
  });
}
