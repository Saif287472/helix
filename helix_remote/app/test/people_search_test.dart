import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/core/platform/contacts_access.dart';
import 'package:helix_remote/features/people/application/people_gateway.dart';
import 'package:helix_remote/features/people/presentation/people_search_screen.dart';
import 'package:helix_remote_api/v2.dart' show ApiException, NetworkException;
import 'package:helix_remote_protocol/helix_remote_protocol.dart'
    show ErrorCode;
import 'package:orbit_ui/orbit_ui.dart' show PeopleSearchMode;

import 'support/people_fakes.dart';

/// People search inside Chats and Calls: what the panel shows for each kind of
/// text, and what the network lookups do (and do not do).
void main() {
  late FakePeopleGateway gateway;
  late FakeSeams seams;

  setUp(() {
    gateway = FakePeopleGateway()
      ..put(personRow('mum', phonebook: 'Mum', phone: '+8801711000001'))
      ..put(personRow('sam', nickname: 'Sam Smith', helix: 'sam_s'))
      ..put(personRow('sam2', phonebook: 'Sam Jones', phone: '+8801711000333'))
      ..put(personRow('blocked', phonebook: 'Sam Blocked', blocked: true))
      ..put(personRow('stranger'))
      ..put(personRow('self-account', phonebook: 'Me'));
    seams = FakeSeams();
  });

  Future<WidgetTester> open(
    WidgetTester tester, {
    PeopleSearchMode mode = PeopleSearchMode.chats,
    FakeContactsAccess? contacts,
    double textScale = 1,
  }) async {
    await pumpPeople(
      tester,
      PeopleSearchScreen(mode: mode),
      gateway: gateway,
      seams: seams,
      contacts: contacts,
      textScale: textScale,
    );
    return tester;
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
  }

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    // The groups arrive on a later stream turn than the people, so the panel
    // needs the pumps it would take a real finger's pause.
    await settle(tester);
  }

  group('with nothing typed', () {
    testWidgets('lists the people the user knows, not blocked ones, not '
        'strangers, not themselves', (tester) async {
      await open(tester);
      await settle(tester);
      // A section label is an eyebrow, so it renders in capitals with the
      // count in the same line.
      expect(find.textContaining('PEOPLE ON ORBIT'), findsOneWidget);
      expect(find.text('Mum'), findsOneWidget);
      expect(find.text('Sam Smith'), findsOneWidget);
      expect(find.text('Sam Jones'), findsOneWidget);
      expect(find.text('Sam Blocked'), findsNothing);
      expect(find.text('Me'), findsNothing);
      expect(find.textContaining('Helix user'), findsNothing);
      // The line under a name is the number, or the ~Helix name.
      expect(find.text('+8801711000001'), findsOneWidget);
      expect(find.text('~sam_s'), findsOneWidget);
    });

    testWidgets('asks for the contacts once, with the privacy copy', (
      tester,
    ) async {
      final contacts = FakeContactsAccess(state: ContactsPermission.notAsked);
      await open(tester, contacts: contacts);
      await settle(tester);
      expect(find.text('Find your contacts on Orbit'), findsOneWidget);
      expect(find.textContaining('scrambled'), findsOneWidget);
      expect(find.textContaining('never leave your phone'), findsOneWidget);
      expect(contacts.events, isEmpty, reason: 'no dialog until asked');

      await tester.tap(find.text('Allow contacts'));
      await settle(tester);
      expect(contacts.events, ['request']);
      expect(gateway.calls, contains('syncPhoneBook'));
      expect(find.text('Find your contacts on Orbit'), findsNothing);
      expect(find.text('Refresh contacts'), findsOneWidget);
      expect(find.text('2 contacts are on Orbit.'), findsOneWidget);
    });

    testWidgets('a refusal leaves the people that are already known', (
      tester,
    ) async {
      final contacts = FakeContactsAccess(
        state: ContactsPermission.notAsked,
        grantOnRequest: false,
      );
      await open(tester, contacts: contacts);
      await settle(tester);
      await tester.tap(find.text('Allow contacts'));
      await settle(tester);
      expect(gateway.calls, isNot(contains('syncPhoneBook')));
      expect(find.text('Find your contacts on Orbit'), findsOneWidget);
      expect(find.text('Mum'), findsOneWidget);
    });

    testWidgets('a permanent refusal offers the system settings', (
      tester,
    ) async {
      final contacts = FakeContactsAccess(
        state: ContactsPermission.permanentlyDenied,
      );
      await open(tester, contacts: contacts);
      await settle(tester);
      expect(find.text('Allow contacts'), findsNothing);
      await tester.tap(find.text('Open settings'));
      await tester.pump();
      expect(contacts.events, ['openSettings']);
    });

    testWidgets('a platform with no address book shows no card at all', (
      tester,
    ) async {
      await open(tester, contacts: FakeContactsAccess(supported: false));
      await settle(tester);
      expect(find.text('Find your contacts on Orbit'), findsNothing);
      expect(find.text('Refresh contacts'), findsNothing);
      expect(find.text('Mum'), findsOneWidget);
    });

    testWidgets('an empty directory says how to find someone', (tester) async {
      gateway.people.clear();
      await open(tester);
      await settle(tester);
      expect(find.text('Nobody yet'), findsOneWidget);
      expect(find.textContaining('to find someone'), findsOneWidget);
    });

    testWidgets('refreshing contacts reports the budget being used up', (
      tester,
    ) async {
      gateway.syncError = const ApiException(
        status: 429,
        code: ErrorCode.rateLimited,
      );
      await open(tester);
      await settle(tester);
      await tester.tap(find.text('Refresh contacts'));
      await settle(tester);
      expect(
        find.textContaining('limit for checking contacts'),
        findsOneWidget,
      );
    });
  });

  group('typing a name', () {
    testWidgets('filters people and groups on this device, as you type', (
      tester,
    ) async {
      gateway.groups.addAll(const [
        GroupSummary(id: 'g1', title: 'Samosa club'),
        GroupSummary(id: 'g2', title: 'Family'),
      ]);
      await open(tester);
      await type(tester, 'sam');
      expect(find.text('Sam Smith'), findsOneWidget);
      expect(find.text('Sam Jones'), findsOneWidget);
      expect(find.text('Mum'), findsNothing);
      expect(find.text('Samosa club'), findsOneWidget);
      expect(find.text('Family'), findsNothing);
      expect(find.text('Sam Blocked'), findsNothing);
      // No network happened.
      expect(gateway.calls.where((c) => c.startsWith('find')), isEmpty);
    });

    testWidgets('a name that fits a Helix name offers the lookup, never '
        'runs it by itself', (tester) async {
      await open(tester);
      await type(tester, 'dana');
      expect(find.text('Find ~dana on Orbit'), findsOneWidget);
      // The Find row is the answer to an empty search, so there is no second
      // "No matches" under it.
      expect(find.text('No matches'), findsNothing);
      expect(gateway.calls.where((c) => c.startsWith('find')), isEmpty);
    });

    testWidgets('a name with a space has nothing to look up', (tester) async {
      await open(tester);
      await type(tester, 'Dana Smith');
      expect(find.textContaining('Find ~'), findsNothing);
      expect(find.text('No matches'), findsOneWidget);
    });

    testWidgets('part of a number finds people already known by it', (
      tester,
    ) async {
      await open(tester);
      await type(tester, '01711000001');
      expect(find.text('Mum'), findsOneWidget);
      expect(find.text('Sam Jones'), findsNothing);
    });
  });

  group('finding someone by number', () {
    final bob = personRow('bob', phone: '+8801711000002', helix: 'bob');

    testWidgets('reads the number in the account\'s country, and asks only '
        'when told to', (tester) async {
      gateway.byNumber['+8801711000002'] = bob;
      await open(tester);
      await type(tester, '01711-000002');
      expect(find.text('Find +880 1711000002 on Orbit'), findsOneWidget);
      expect(
        find.text('Only a scrambled version of the number is sent.'),
        findsOneWidget,
      );
      expect(gateway.calls.where((c) => c.startsWith('find')), isEmpty);

      await tester.tap(find.text('Find +880 1711000002 on Orbit'));
      await tester.pump();
      await tester.pump();
      expect(gateway.calls, contains('findByNumber:+8801711000002'));
      // The person found: shown by number (no other name), with the ~name.
      expect(find.text('+8801711000002'), findsOneWidget);
      expect(find.text('~bob'), findsOneWidget);
    });

    testWidgets('the keyboard\'s search key runs the lookup', (tester) async {
      gateway.byNumber['+8801711000002'] = bob;
      await open(tester);
      await type(tester, '+880 1711 000002');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      await tester.pump();
      expect(gateway.calls, contains('findByNumber:+8801711000002'));
    });

    testWidgets('shows searching, then the answer', (tester) async {
      gateway.lookupGate = Completer<void>();
      gateway.byNumber['+8801711000002'] = bob;
      await open(tester);
      await type(tester, '01711000002');
      await tester.tap(find.text('Find +880 1711000002 on Orbit'));
      await tester.pump();
      expect(find.text('Looking on Orbit...'), findsOneWidget);
      gateway.lookupGate!.complete();
      await tester.pump();
      await tester.pump();
      expect(find.text('Looking on Orbit...'), findsNothing);
      expect(find.text('~bob'), findsOneWidget);
    });

    testWidgets('a number nobody has says so, without saying why', (
      tester,
    ) async {
      await open(tester);
      await type(tester, '01711000099');
      await tester.tap(find.text('Find +880 1711000099 on Orbit'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Not on Orbit'), findsOneWidget);
      expect(find.textContaining('or they do not let people find'), findsOne);
    });

    testWidgets('your own number is recognised', (tester) async {
      gateway.byNumber['+8801711000000'] = personRow(
        'self-account',
        phone: '+8801711000000',
      );
      await open(tester);
      await type(tester, '01711000000');
      await tester.tap(find.text('Find +880 1711000000 on Orbit'));
      await tester.pump();
      await tester.pump();
      expect(find.text('That is you'), findsOneWidget);
    });

    testWidgets('the daily budget being used up is explained', (tester) async {
      gateway.lookupError = const ApiException(
        status: 429,
        code: ErrorCode.rateLimited,
      );
      await open(tester);
      await type(tester, '01711000002');
      await tester.tap(find.text('Find +880 1711000002 on Orbit'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Too many lookups'), findsOneWidget);
      expect(find.textContaining('Try again tomorrow'), findsOneWidget);
    });

    testWidgets('offline and other failures are plain sentences', (
      tester,
    ) async {
      gateway.lookupError = const NetworkException();
      await open(tester);
      await type(tester, '01711000002');
      await tester.tap(find.text('Find +880 1711000002 on Orbit'));
      await tester.pump();
      await tester.pump();
      expect(find.text('No connection'), findsOneWidget);

      gateway.lookupError = StateError('secret detail');
      // The answer row replaced the Find row; the keyboard's search key asks
      // again.
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      await tester.pump();
      expect(find.text('Could not look this up'), findsOneWidget);
      expect(find.textContaining('secret'), findsNothing);
    });

    testWidgets('editing the text drops an answer that no longer applies', (
      tester,
    ) async {
      await open(tester);
      await type(tester, '01711000099');
      await tester.tap(find.text('Find +880 1711000099 on Orbit'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Not on Orbit'), findsOneWidget);
      await type(tester, '01711000098');
      expect(find.text('Not on Orbit'), findsNothing);
    });

    testWidgets('a number with no country to read it in is explained, not '
        'looked up', (tester) async {
      final lonely = FakePeopleGateway(ownNumberValue: null)
        ..put(personRow('mum', phonebook: 'Mum'));
      await pumpPeople(
        tester,
        const PeopleSearchScreen(),
        gateway: lonely,
        seams: seams,
      );
      await type(tester, '01711000002');
      expect(find.textContaining('Without a country code'), findsOne);
      expect(find.textContaining('Find +'), findsNothing);
    });
  });

  group('finding someone by ~Helix name', () {
    testWidgets('looks the exact name up, in lower case', (tester) async {
      gateway.byHelixName['dana'] = personRow('dana', helix: 'dana');
      await open(tester);
      await type(tester, '~Dana');
      await tester.tap(find.text('Find ~dana on Orbit'));
      await tester.pump();
      await tester.pump();
      expect(gateway.calls, contains('findByHelixName:dana'));
      expect(find.text('~dana'), findsOneWidget);
    });

    testWidgets('a name nobody uses is "Not on Helix"', (tester) async {
      await open(tester);
      await type(tester, '~nobody_here');
      await tester.tap(find.text('Find ~nobody_here on Orbit'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Not on Orbit'), findsOneWidget);
    });
  });

  group('tapping a person', () {
    testWidgets('in Chats opens the conversation, creating it', (tester) async {
      await open(tester);
      await type(tester, 'mu');
      await tester.tap(find.text('Mum'));
      await tester.pump();
      await tester.pump();
      expect(gateway.calls, contains('openChat:mum'));
      expect(seams.opened, ['direct:mum']);
    });

    testWidgets('a group opens its conversation', (tester) async {
      gateway.groups.add(const GroupSummary(id: 'g1', title: 'Samosa club'));
      await open(tester);
      await type(tester, 'samosa');
      await tester.tap(find.text('Samosa club'));
      await tester.pump();
      expect(seams.opened, ['group:g1']);
    });

    testWidgets('in Calls it places a voice call, with a video button', (
      tester,
    ) async {
      await open(tester, mode: PeopleSearchMode.calls);
      await type(tester, 'mu');
      await tester.tap(find.text('Mum'));
      await tester.pump();
      expect(seams.calls, ['voice:mum']);
      await tester.tap(find.byTooltip('Video call Mum'));
      await tester.pump();
      expect(seams.calls, ['voice:mum', 'video:mum']);
      expect(seams.opened, isEmpty, reason: 'a call is not a chat');
    });

    testWidgets('a refused call shows the reason it gives', (tester) async {
      seams.callFailure = 'You are already in a call.';
      await open(tester, mode: PeopleSearchMode.calls);
      await type(tester, 'mu');
      await tester.tap(find.byTooltip('Voice call Mum'));
      await tester.pump();
      await tester.pump();
      expect(find.text('You are already in a call.'), findsOneWidget);
      // Let the toast's own timer run; it is pending otherwise.
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('a long press opens the contact info', (tester) async {
      await open(tester);
      await type(tester, 'mu');
      await tester.longPress(find.text('Mum'));
      await tester.pumpAndSettle();
      expect(find.text('Contact info'), findsOneWidget);
    });
  });

  group('accessibility', () {
    for (final mode in PeopleSearchMode.values) {
      testWidgets(
        '${mode.name}: 48 px targets and labelled buttons at 2x text',
        (tester) async {
          final handle = tester.ensureSemantics();
          await open(tester, mode: mode, textScale: 2);
          await type(tester, 'sam');
          expectTargets(tester);
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          handle.dispose();
        },
      );
    }

    testWidgets('a person row reads as a name and its second line', (
      tester,
    ) async {
      await open(tester);
      await type(tester, 'mu');
      expect(find.text('Mum'), findsOneWidget);
      expect(find.text('+8801711000001'), findsOneWidget);
    });
  });
}

/// Every target a finger can hit on this screen is at least 48 px, the
/// product rule (`AGENTS.md`). The one exception is the search field itself:
/// the design's bar is 46 px (`orbit/prototype/css/components.css`, `.search`)
/// and its field measures 42 px, and Part B must not change a design - so
/// this walks the tree and leaves the field out, rather than dropping the
/// check with it. See `orbit/DEVIATIONS.md`, "The search bar is 46 px".
void expectTargets(WidgetTester tester) {
  final root =
      tester.binding.renderViews.first.owner?.semanticsOwner?.rootSemanticsNode;
  expect(root, isNotNull, reason: 'the test asked for semantics');
  final small = <String>[];
  bool walk(SemanticsNode node) {
    final d = node.getSemanticsData();
    final tappable =
        d.hasAction(SemanticsAction.tap) ||
        d.hasAction(SemanticsAction.longPress);
    final size = d.rect.size;
    if (tappable &&
        !d.flagsCollection.isTextField &&
        size.width > 0 &&
        (size.width < 48 || size.height < 48)) {
      small.add('${d.label.isEmpty ? '<${node.id}>' : d.label} $size');
    }
    node.visitChildren(walk);
    return true;
  }

  walk(root!);
  expect(small, isEmpty, reason: 'tap targets under 48 px: $small');
}
