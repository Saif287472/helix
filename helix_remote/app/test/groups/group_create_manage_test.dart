import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/features/groups/application/group_models.dart';
import 'package:helix_remote/features/groups/presentation/add_members_screen.dart';
import 'package:helix_remote/features/groups/presentation/banned_members_screen.dart';
import 'package:helix_remote/features/groups/presentation/create_group_screen.dart';
import 'package:helix_remote/features/groups/presentation/group_invite_screen.dart';
import 'package:helix_remote/features/groups/presentation/group_settings_screen.dart';
import 'package:helix_remote/features/groups/presentation/join_requests_screen.dart';
import 'package:helix_remote_api/v2.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart'
    show ErrorCode;
import 'package:helix_remote_ui/helix_remote_ui.dart';

import '../support/group_support.dart';
import '../support/harness.dart';

/// Creating a group, and the screens an admin manages it from: settings,
/// invite links, join requests, bans and adding people.
void main() {
  void tall(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  final people = [
    const GroupCandidate(
      account: 'ada',
      names: HelixPersonNames(
        phoneBookName: 'Ada Lovelace',
        number: '+8801711000001',
      ),
    ),
    const GroupCandidate(
      account: 'bob',
      names: HelixPersonNames(nickname: 'Bob', number: '+8801711000002'),
    ),
  ];

  group('create group', () {
    Future<FakeGroupsPort> pump(
      WidgetTester tester, {
      FakePicker? picker,
      String? Function(String)? chat,
      FakeGroupsPort? port,
    }) async {
      tall(tester);
      port ??= FakeGroupsPort()..candidates = people;
      await tester.pumpWidget(
        harness(
          home: const CreateGroupScreen(),
          routes: [
            stubRoute('/home/groups/:id', 'info'),
            stubRoute('/home/chat/:id', 'chat'),
          ],
          overrides: groupOverrides(
            port: port,
            picker: picker,
            chatLocation: chat,
          ),
        ),
      );
      await tester.pumpAndSettle();
      return port;
    }

    testWidgets('lists people, and the button waits for a name', (
      tester,
    ) async {
      await pump(tester);

      expect(find.text('Ada Lovelace'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      final button = tester.widget<FloatingActionButton>(
        find.byType(FloatingActionButton),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('chosen people become chips and are created with the group', (
      tester,
    ) async {
      final port = await pump(tester);

      await tester.tap(find.text('Ada Lovelace'));
      await tester.tap(find.text('Bob'));
      await tester.pumpAndSettle();
      expect(find.byType(InputChip), findsNWidgets(2));
      expect(find.text('Create with 2'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, '  Book club ');
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(port.calls, ['create Book club [ada,bob]']);
      // No conversation route registered yet: the group's own page opens.
      expect(find.text('info'), findsOneWidget);
    });

    testWidgets('a chosen person can be un-chosen from the chip', (
      tester,
    ) async {
      final port = await pump(tester);
      await tester.tap(find.text('Ada Lovelace'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Remove from selection'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Solo');
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(port.calls, ['create Solo []']);
    });

    testWidgets('with the conversation route registered the chat opens', (
      tester,
    ) async {
      await pump(tester, chat: (id) => '/home/chat/$id');
      await tester.enterText(find.byType(TextField).first, 'Solo');
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(find.text('chat'), findsOneWidget);
    });

    testWidgets('search filters by name, number and ~name', (tester) async {
      await pump(tester);
      await tester.enterText(find.byType(TextField).last, '0002');
      await tester.pumpAndSettle();

      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Ada Lovelace'), findsNothing);
    });

    testWidgets('a number nobody here knows can be looked up and chosen', (
      tester,
    ) async {
      final port = FakeGroupsPort()
        ..candidates = people
        ..lookupResult = const GroupCandidate(
          account: 'dan',
          names: HelixPersonNames(number: '+8801799999999'),
        );
      await pump(tester, port: port);

      await tester.enterText(find.byType(TextField).last, '+8801799999999');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('lookup')));
      await tester.pumpAndSettle();

      expect(port.calls, ['lookup +8801799999999']);
      expect(find.byType(InputChip), findsOneWidget);
    });

    testWidgets('a number that is nobody says so', (tester) async {
      final port = FakeGroupsPort()..candidates = people;
      await pump(tester, port: port);

      await tester.enterText(find.byType(TextField).last, '+8801700000000');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('lookup')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Nobody on Helix matches'), findsOneWidget);
      expect(find.byType(InputChip), findsNothing);
    });

    testWidgets('a picture chosen from the phone goes with the group', (
      tester,
    ) async {
      final port = await pump(tester, picker: FakePicker(tinyPng));
      await tester.tap(find.bySemanticsLabel('Add a group picture'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'With picture');
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(port.calls.single, contains('+picture'));
    }, skip: false);

    testWidgets('people kept out by their privacy settings are named, and the '
        'group is still made', (tester) async {
      final port = FakeGroupsPort()
        ..candidates = people
        ..created = const CreatedGroupInfo(
          groupId: 'g9',
          conversationId: 'group:g9',
          rejected: ['bob'],
        );
      await pump(tester, port: port);
      await tester.tap(find.text('Bob'));
      await tester.enterText(find.byType(TextField).first, 'Club');
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(find.text('Some people were not added'), findsOneWidget);
      expect(
        find.textContaining('Bob only lets people they know'),
        findsOneWidget,
      );
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('info'), findsOneWidget);
    });

    testWidgets('a failure shows why and keeps the form', (tester) async {
      final port = FakeGroupsPort()..candidates = people;
      await pump(tester, port: port);
      await tester.enterText(find.byType(TextField).first, 'Club');
      await tester.pumpAndSettle();
      port.failWith = const NetworkException();
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(find.textContaining('No connection'), findsOneWidget);
      expect(find.text('Club'), findsOneWidget);
    });

    testWidgets('holds at 2x text', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pump(tester);
      expect(tester.takeException(), isNull);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    });
  });

  group('group settings', () {
    Future<FakeGroupsPort> pump(
      WidgetTester tester,
      GroupSnapshot group,
    ) async {
      tall(tester);
      final port = FakeGroupsPort(group: group);
      await tester.pumpWidget(
        harness(
          home: const GroupSettingsScreen(groupId: 'g1'),
          overrides: groupOverrides(port: port, names: testNames),
        ),
      );
      await tester.pumpAndSettle();
      return port;
    }

    testWidgets('shows who may do what, and an admin changes it', (
      tester,
    ) async {
      final port = await pump(tester, testGroup());
      expect(find.text('Only admins'), findsNWidgets(2));
      expect(find.text('Everyone'), findsOneWidget);

      await tester.tap(find.text('Add members'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Everyone').last);
      await tester.pumpAndSettle();

      expect(port.calls, [
        'permissions add:everyone edit:admins send:everyone',
      ]);
    });

    testWidgets('a member sees the settings and cannot change them', (
      tester,
    ) async {
      final port = await pump(tester, testGroup(role: GroupMemberRole.member));
      expect(
        find.text('Only admins can change these settings.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Send messages'));
      await tester.pumpAndSettle();
      expect(port.calls, isEmpty);
    });

    testWidgets('a refusal is shown', (tester) async {
      final port = await pump(tester, testGroup());
      port.failWith = const ApiException(
        status: 403,
        code: ErrorCode.forbidden,
      );
      await tester.tap(find.text('Edit group info'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Everyone').last);
      await tester.pumpAndSettle();

      expect(find.textContaining('do not have permission'), findsOneWidget);
    });
  });

  group('invite links', () {
    Future<(FakeGroupsPort, FakeSharer)> pump(WidgetTester tester) async {
      tall(tester);
      final port = FakeGroupsPort(group: testGroup());
      final sharer = FakeSharer();
      await tester.pumpWidget(
        harness(
          home: const GroupInviteScreen(groupId: 'g1'),
          overrides: groupOverrides(
            port: port,
            names: testNames,
            sharer: sharer,
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (port, sharer);
    }

    testWidgets('makes a link, shares it through the share sheet', (
      tester,
    ) async {
      final (port, sharer) = await pump(tester);
      expect(find.textContaining('Links you make appear here'), findsOneWidget);

      await tester.tap(find.text('Create link'));
      await tester.pumpAndSettle();
      expect(port.calls, ['link approval:false']);
      expect(find.textContaining('HLX-GRP-secret'), findsOneWidget);
      expect(find.text('Joins straight away'), findsOneWidget);

      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();
      expect(sharer.shared.single, startsWith('Book club|https://'));
    });

    testWidgets('approval mode is chosen before the link is made', (
      tester,
    ) async {
      final (port, _) = await pump(tester);
      await tester.tap(find.text('Admins approve new members'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create link'));
      await tester.pumpAndSettle();

      expect(port.calls, ['link approval:true']);
      expect(find.text('Admins approve new members'), findsNWidgets(2));
    });

    testWidgets('copying puts it on the clipboard and says so', (tester) async {
      final (_, sharer) = await pump(tester);
      await tester.tap(find.text('Create link'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();

      expect(sharer.copied, hasLength(1));
      expect(find.text('Link copied.'), findsOneWidget);
    });

    testWidgets('revoking asks first and removes the link', (tester) async {
      final (port, _) = await pump(tester);
      await tester.tap(find.text('Create link'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Revoke'));
      await tester.pumpAndSettle();
      expect(find.text('Revoke this link?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Revoke'));
      await tester.pumpAndSettle();

      expect(port.calls.last, startsWith('revoke '));
      expect(find.textContaining('HLX-GRP-secret'), findsNothing);
    });

    testWidgets('a refusal when making a link is shown', (tester) async {
      final (port, _) = await pump(tester);
      port.failWith = const GroupException(GroupFailure.notAllowed);
      await tester.tap(find.text('Create link'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Only an admin'), findsOneWidget);
    });
  });

  group('join requests', () {
    Future<FakeGroupsPort> pump(
      WidgetTester tester, {
      List<JoinRequestInfo> requests = const [],
    }) async {
      final port = FakeGroupsPort(group: testGroup())..requests = requests;
      await tester.pumpWidget(
        harness(
          home: const JoinRequestsScreen(groupId: 'g1'),
          overrides: groupOverrides(port: port, names: testNames),
        ),
      );
      await tester.pumpAndSettle();
      return port;
    }

    final request = JoinRequestInfo(
      requestId: 'r1',
      account: 'ada',
      createdAt: DateTime.now(),
    );

    testWidgets('nobody waiting says so', (tester) async {
      await pump(tester);
      expect(find.text('No one is waiting'), findsOneWidget);
    });

    testWidgets('approve lets the person in and clears the row', (
      tester,
    ) async {
      final port = await pump(tester, requests: [request]);
      expect(find.text('Ada Lovelace'), findsOneWidget);

      await tester.tap(find.byTooltip('Approve Ada Lovelace'));
      await tester.pumpAndSettle();

      expect(port.calls, ['approve r1']);
      expect(find.text('Ada Lovelace joined the group.'), findsOneWidget);
      expect(find.text('No one is waiting'), findsOneWidget);
    });

    testWidgets('reject turns the person away', (tester) async {
      final port = await pump(tester, requests: [request]);

      await tester.tap(find.byTooltip('Reject Ada Lovelace'));
      await tester.pumpAndSettle();

      expect(port.calls, ['reject r1']);
    });

    testWidgets('a request another admin already answered shows the reason', (
      tester,
    ) async {
      final port = await pump(tester, requests: [request]);
      port.failWith = const ApiException(status: 404, code: ErrorCode.notFound);

      await tester.tap(find.byTooltip('Approve Ada Lovelace'));
      await tester.pumpAndSettle();

      expect(find.textContaining('could not be found'), findsOneWidget);
    });

    testWidgets('a non-admin sees an error, not the list', (tester) async {
      final port = FakeGroupsPort(
        group: testGroup(role: GroupMemberRole.member),
      )..failRequests = const GroupException(GroupFailure.notAllowed);
      await tester.pumpWidget(
        harness(
          home: const JoinRequestsScreen(groupId: 'g1'),
          overrides: groupOverrides(port: port, names: testNames),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Only admins can see'), findsOneWidget);
    });
  });

  group('banned people', () {
    testWidgets('lists bans made here, and unban lets the person back', (
      tester,
    ) async {
      final port = FakeGroupsPort(group: testGroup())
        ..banned = [BannedInfo(account: 'bob', bannedAt: DateTime.now())];
      await tester.pumpWidget(
        harness(
          home: const BannedMembersScreen(groupId: 'g1'),
          overrides: groupOverrides(port: port, names: testNames),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Bob'), findsOneWidget);
      expect(find.textContaining('not listed here'), findsOneWidget);

      await tester.tap(find.text('Unban'));
      await tester.pumpAndSettle();

      expect(port.calls, ['unban bob']);
      expect(find.text('No one is banned'), findsOneWidget);
    });
  });

  group('add members', () {
    Future<FakeGroupsPort> pump(
      WidgetTester tester, {
      AddMembersOutcome? outcome,
    }) async {
      tall(tester);
      final port = FakeGroupsPort(group: testGroup())
        ..candidates = [
          ...people,
          const GroupCandidate(
            account: 'carol',
            names: HelixPersonNames(helixName: 'carol'),
          ),
          const GroupCandidate(
            account: 'erin',
            names: HelixPersonNames(nickname: 'Erin'),
          ),
        ];
      if (outcome != null) port.addOutcome = outcome;
      await tester.pumpWidget(
        harness(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const AddMembersScreen(groupId: 'g1'),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
          overrides: groupOverrides(port: port, names: testNames),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return port;
    }

    testWidgets('people already in the group are not offered', (tester) async {
      await pump(tester);

      expect(find.text('Erin'), findsOneWidget);
      expect(find.text('Ada Lovelace'), findsNothing);
      expect(find.text('Bob'), findsNothing);
    });

    testWidgets('adds the chosen people and says how many', (tester) async {
      final port = await pump(
        tester,
        outcome: const AddMembersOutcome(added: ['erin'], rejected: {}),
      );
      await tester.tap(find.text('Erin'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add 1'));
      await tester.pumpAndSettle();

      expect(port.calls, ['add erin']);
    });

    testWidgets('a privacy refusal is named and points to an invite link', (
      tester,
    ) async {
      final port = await pump(
        tester,
        outcome: const AddMembersOutcome(
          added: [],
          rejected: {'erin': AddRejection.privacy},
        ),
      );
      await tester.tap(find.text('Erin'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add 1'));
      await tester.pumpAndSettle();

      expect(port.calls, ['add erin']);
      expect(find.text('No one was added'), findsOneWidget);
      expect(
        find.textContaining('Send them an invite link instead'),
        findsOneWidget,
      );
    });

    testWidgets('a group that only admins add to refuses plainly', (
      tester,
    ) async {
      final port = await pump(tester);
      port.failWith = const GroupException(GroupFailure.notAllowed);
      await tester.tap(find.text('Erin'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add 1'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('This group only lets admins do that'),
        findsOneWidget,
      );
    });
  });
}
