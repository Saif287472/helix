import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/features/conversation/application/conversation_header.dart';
import 'package:helix_remote/features/conversation/presentation/conversation_screen.dart';
import 'package:helix_remote_db/helix_remote_db.dart';

import 'support/chat_harness.dart';
import 'support/group_support.dart';
import 'package:helix_remote/features/groups/application/group_models.dart';

/// A group that lets only admins send: a member sees why they cannot write,
/// instead of a composer that fails when they press send.
void main() {
  Future<void> openGroup(
    WidgetTester tester,
    TestChatGateway gateway, {
    required bool adminsOnly,
    required String role,
  }) async {
    tester.view.physicalSize = const Size(412, 866);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(
      () => gateway.db.conversationsDao.ensureGroup(
        'group:g1',
        title: 'Announcements',
        now: testNow,
      ),
    );
    if (adminsOnly) gateway.adminsOnlyGroups.add('g1');
    await tester.pumpWidget(
      chatApp(
        gateway,
        const ConversationScreen(conversationId: 'group:g1'),
        overrides: [
          ...groupOverrides(
            port: FakeGroupsPort(
              group: testGroup(role: GroupMemberRole.member),
            ),
            names: testNames,
          ),
          groupMembersProvider.overrideWith(
            (ref, id) => Stream.value([
              GroupMemberRow(
                groupId: 'g1',
                accountId: 'me',
                qualifiedId: 'me',
                role: role,
                isSelf: true,
                devicesJson: '[]',
              ),
            ]),
          ),
        ],
      ),
    );
    await settle(tester, rounds: 10);
  }

  chatTest('a member of an admins-only group is told why they cannot write', (
    tester,
    gateway,
  ) async {
    await openGroup(tester, gateway, adminsOnly: true, role: 'member');
    expect(
      find.text('Only admins can send messages to this group.'),
      findsOneWidget,
    );
    expect(find.byType(TextField), findsNothing);
  });

  chatTest('a group that lets everyone send has its composer', (
    tester,
    gateway,
  ) async {
    await openGroup(tester, gateway, adminsOnly: false, role: 'member');
    expect(find.textContaining('Only admins can send'), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
  });
}
