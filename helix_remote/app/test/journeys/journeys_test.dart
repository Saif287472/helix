import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/core/links/deep_link.dart';
import 'package:helix_remote/core/router/app_router.dart';
import 'package:helix_remote/features/groups/application/group_models.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';
import 'package:orbit_ui/orbit_ui.dart'
    show OrbitCallLogTile, OrbitExtendedFab, PeoplePanel;

import '../support/chat_harness.dart' show settle, testNow;
import '../support/orbit_theme.dart' show findMessageText;
import '../support/people_fakes.dart' show personRow;
import 'journey_harness.dart';

/// Whole-app walks across features, over the real router: the seams the
/// features were built around are the thing under test, so each journey ends
/// in a screen that only exists if two features were wired together.
void main() {
  journeyTest('sign-in, empty chats, find a person, chat, contact info, call, '
      'and the call is in the Calls tab', (tester) async {
    final app = await Journey.start(
      tester,
      known: [knownPerson('mum', 'Mum', number: '+8801711000001')],
    );

    // Signed out: sign-in. The engine reports a session: the empty chats.
    expect(find.text('Sign in'), findsWidgets);
    await app.signIn(tester);
    expect(find.text('No chats yet'), findsOneWidget);

    // Search: the people panel is mounted under the Chats search field.
    await tester.tap(find.byTooltip('Search'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Mum');
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester, rounds: 10);
    final person = find.descendant(
      of: find.byType(PeoplePanel),
      matching: find.text('Mum'),
    );
    expect(person, findsOneWidget);

    // Tapping the result starts the conversation and opens it.
    await tapAndSettle(tester, person);
    expect(app.people.calls, contains('openChat:mum'));
    expect(find.byTooltip('Voice call'), findsOneWidget);

    // Send a message.
    await tester.enterText(find.byType(TextField), 'are you free?');
    await tester.pump();
    await tapAndSettle(tester, find.byTooltip('Send'));
    expect(app.chat.log, contains('sendText:direct:mum:are you free?'));
    expect(findMessageText('are you free?'), findsOneWidget);

    // The header opens the contact info; its Voice call button places the
    // call through the one calls seam.
    await tapAndSettle(tester, find.text('Mum').first);
    expect(find.text('Voice call'), findsOneWidget);
    await tapAndSettle(tester, find.text('Voice call'));
    expect(app.calls.calls, ['start mum video:false']);

    // Back to the home tabs, the Calls tab: the call is in the log.
    app.router.go('/home');
    await settle(tester, rounds: 10);
    // Home keeps the search open while you were away; close it first.
    await tapAndSettle(tester, find.byTooltip('Close search'));
    await tapAndSettle(tester, find.byTooltip('Calls'));
    expect(find.text('Mum'), findsWidgets);
    expect(find.byType(OrbitCallLogTile), findsOneWidget);
  });

  journeyTest('the conversation header places a call and shows why it could '
      'not', (tester) async {
    final app = await Journey.start(
      tester,
      known: [knownPerson('mum', 'Mum')],
      seed: (chat) => chat.chatWith('mum', name: 'Mum'),
    );
    await app.signIn(tester);
    app.router.go('/chat/direct:mum');
    await settle(tester, rounds: 10);

    await tapAndSettle(tester, find.byTooltip('Video call'));
    expect(app.calls.calls, ['start mum video:true']);

    app.calls.failWith = const CallFailedException(CallFailure.busy);
    await tapAndSettle(tester, find.byTooltip('Voice call'));
    // A failure is one plain sentence, never the exception.
    expect(find.text('You are already in a call.'), findsOneWidget);
  });

  journeyTest('the shared media page opens from the conversation menu', (
    tester,
  ) async {
    final app = await Journey.start(
      tester,
      known: [knownPerson('mum', 'Mum')],
      seed: (chat) async {
        await chat.chatWith('mum', name: 'Mum');
        await chat.incoming(
          'direct:mum',
          'see https://example.org/plan.',
          at: testNow,
        );
      },
    );
    await app.signIn(tester);
    app.router.go('/chat/direct:mum');
    await settle(tester, rounds: 10);

    await tapAndSettle(tester, find.byTooltip('More options'));
    await tapAndSettle(tester, find.text('Media, links and docs'));
    expect(find.text('No media yet'), findsOneWidget);
    await tapAndSettle(tester, find.text('Links'));
    expect(find.text('https://example.org/plan'), findsOneWidget);
    expect(find.text('example.org, 14:30'), findsOneWidget);
  });

  journeyTest('create a group from the Chats tab, open its info, add a '
      'member', (tester) async {
    final app = await Journey.start(tester);
    app.groups.candidates = const [
      GroupCandidate(
        account: 'mum',
        names: HelixPersonNames(phoneBookName: 'Mum'),
      ),
      GroupCandidate(
        account: 'erin',
        names: HelixPersonNames(phoneBookName: 'Erin'),
      ),
    ];
    await app.signIn(tester);

    await tapAndSettle(tester, find.byTooltip('More options').first);
    await tapAndSettle(tester, find.text('New group'));
    expect(find.text('New group'), findsWidgets);

    await tapAndSettle(tester, find.text('Mum'));
    await tester.enterText(find.byType(TextField).first, 'Book club');
    await tester.pump();
    await tapAndSettle(tester, find.byType(OrbitExtendedFab));
    expect(app.groups.calls, ['create Book club [mum]']);

    // The group's chat opened (the conversation route is registered); its
    // header opens the group info, and the owner can add people.
    expect(find.byTooltip('Voice call'), findsNothing, reason: 'a group chat');
    await tapAndSettle(tester, find.text('Book club').first);
    expect(find.text('Add members'), findsOneWidget);
    await tapAndSettle(tester, find.text('Add members'));
    await tapAndSettle(tester, find.text('Erin'));
    await tapAndSettle(tester, find.text('Add 1'));
    expect(app.groups.calls.last, 'add erin');
  });

  journeyTest('settings, devices, and back', (tester) async {
    final app = await Journey.start(tester);
    await app.signIn(tester);

    // Settings is behind your picture on Home (the prototype's You).
    await tapAndSettle(tester, find.byTooltip('Your profile and settings'));
    await tapAndSettle(tester, find.text('Devices'));
    expect(find.text('Pixel 8'), findsOneWidget);
    expect(find.text('Office laptop'), findsOneWidget);

    await tapAndSettle(tester, find.byTooltip('Back'));
    expect(find.text('Devices'), findsOneWidget);
    expect(find.text('Pixel 8'), findsNothing);
  });

  journeyTest('a group invite link shows the group, then joins it', (
    tester,
  ) async {
    final app = await Journey.start(
      tester,
      seed: (chat) => chat.db.conversationsDao.ensureGroup(
        'group:g1',
        title: 'Book club',
        now: DateTime(2026, 10, 3),
      ),
    );
    app.groups.set(null); // Not a member yet.
    await app.signIn(tester);

    final link = HelixDeepLink.tryParse(
      'https://helix.agiletechbd.com/open#HLX-GRP-dG9rZW4.a2V5',
    )!;
    routeDeepLink(app.router, link);
    await settle(tester, rounds: 10);

    // Opening a link only previews; joining is the person's button.
    expect(find.text('Book club'), findsOneWidget);
    expect(app.groups.calls, ['preview']);
    await tapAndSettle(tester, find.text('Join group'));
    expect(app.groups.calls, ['preview', 'join']);

    // Open group: the group's chat, through the conversation route.
    await tapAndSettle(tester, find.text('Open group'));
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Book club'), findsWidgets);
  });

  journeyTest('an invite link while signed in says so and changes nothing', (
    tester,
  ) async {
    final app = await Journey.start(tester, wholeApp: true);
    await app.signIn(tester);

    // The phone hands a running app a link the way MainActivity does.
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'com.helix.remote/links',
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall(
          'open',
          'https://helix.agiletechbd.com/open#HLX-INV-AAAA-BBBB-CCCC',
        ),
      ),
      (_) {},
    );
    await settle(tester, rounds: 10);

    expect(find.textContaining("You're already signed in"), findsOneWidget);
    expect(app.container.read(pendingLinkProvider), isNull);
    expect(find.text('Chats'), findsWidgets);

    // The toast goes by itself.
    await tester.pump(const Duration(seconds: 4));
    await settle(tester);
    expect(find.textContaining("You're already signed in"), findsNothing);
  });

  journeyTest("a person's share link opens the chat it names", (tester) async {
    final app = await Journey.start(tester, wholeApp: true);
    await app.signIn(tester);
    app.people.byHelixName['nadia'] = personRow(
      'nadia',
      phonebook: 'Nadia',
      helix: 'nadia',
    );

    // The same hand-off as an invite: the phone gives the running app the
    // link, and the name in it is looked up with this account's session.
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'com.helix.remote/links',
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('open', helixProfileLink('nadia')),
      ),
      (_) {},
    );
    await settle(tester, rounds: 10);

    expect(app.people.calls, contains('findByHelixName:nadia'));
    expect(app.people.calls, contains('openChat:nadia'));
    expect(app.container.read(pendingLinkProvider), isNull);
    expect(find.text('Nadia'), findsWidgets);

    // A name nobody can be found under leaves the chat alone and says so.
    app.router.go('/home');
    await settle(tester, rounds: 10);
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'com.helix.remote/links',
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('open', 'helix://u/ghost'),
      ),
      (_) {},
    );
    await settle(tester, rounds: 10);
    expect(find.textContaining('is not findable by name'), findsOneWidget);
    expect(app.people.calls, contains('findByHelixName:ghost'));
    expect(app.people.calls.where((c) => c.startsWith('openChat:')).length, 1);

    await tester.pump(const Duration(seconds: 4));
    await settle(tester);
    expect(find.textContaining('is not findable by name'), findsNothing);
  });
}
