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
          onCreate: () => created++,
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
          picker: MemberPickerActions(onLookup: (q) => looked = q),
        ),
      ),
    );
    await tester.enterText(find.byType(EditableText).last, '+8801999');
    await tester.pump();
    await tester.tap(find.text('Find “+8801999” on Orbit'));
    expect(looked, '+8801999');
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
        actions: GroupInfoActions(onMemberAction: (a, x) => acted = (a, x)),
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
          onApprove: (a) => done.add('+$a'),
          onReject: (a) => done.add('-$a'),
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
}
