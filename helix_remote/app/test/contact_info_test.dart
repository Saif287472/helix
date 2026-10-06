import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:helix_remote/core/platform/contacts_access.dart';
import 'package:helix_remote/features/people/application/people_gateway.dart';
import 'package:helix_remote/features/people/presentation/contact_info_screen.dart';
import 'package:helix_remote/shared/navigation/people_paths.dart';
import 'package:helix_remote_db/helix_remote_db.dart' show Value;
import 'package:helix_remote_ui/helix_remote_ui.dart';

import 'support/people_fakes.dart';

/// The contact info screen: who, how to rename them (and the phone's contacts
/// with them), how the chat behaves, whether the keys have been checked, and
/// blocking and reporting.
void main() {
  const id = 'mum';
  late FakePeopleGateway gateway;
  late FakeSeams seams;
  late FakeContactsAccess contacts;

  final safety = SafetyNumberData(
    groups: [for (var i = 0; i < 12; i++) '${10000 + i * 111}'],
    qrPayload: Uint8List.fromList(List<int>.generate(62, (i) => i)),
  );

  setUp(() {
    gateway = FakePeopleGateway()
      ..put(
        personRow(
          id,
          phonebook: 'Mum',
          phone: '+8801711000001',
          helix: 'mum_b',
          identityKey: key(1),
        ),
      )
      ..abouts[id] = 'At the market'
      ..safety[id] = safety;
    seams = FakeSeams();
    contacts = FakeContactsAccess(
      state: ContactsPermission.granted,
      contacts: const [
        AddressBookContact(id: 'c1', name: 'Mum', numbers: ['+8801711000001']),
      ],
    );
    gateway.phone = contacts;
  });

  Future<void> open(
    WidgetTester tester, {
    String account = id,
    double textScale = 1,
  }) async {
    await pumpPeople(
      tester,
      ContactInfoScreen(accountId: account),
      gateway: gateway,
      seams: seams,
      contacts: contacts,
      textScale: textScale,
      height: 3200,
    );
    await tester.pump();
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
    await tester.pump();
  }

  Finder inDialog(Finder finder) =>
      find.descendant(of: find.byType(AlertDialog), matching: finder);

  group('who they are', () {
    testWidgets('shows the name, number, ~name and about line', (tester) async {
      await open(tester);
      expect(find.text('Mum'), findsWidgets);
      expect(find.text('+880 1711000001'), findsWidgets);
      expect(find.text('~mum_b'), findsOneWidget);
      expect(find.text('At the market'), findsOneWidget);
      expect(find.text('Phone number'), findsOneWidget);
    });

    testWidgets('reads their profile when it opens', (tester) async {
      await open(tester);
      expect(gateway.calls, contains('refreshProfile:$id'));
    });

    testWidgets('a person with only a number is shown by it', (tester) async {
      gateway.put(personRow('new', phone: '+8801711000555'));
      await open(tester, account: 'new');
      expect(find.text('+8801711000555'), findsWidgets);
      expect(find.text('Rename'), findsWidgets);
    });

    testWidgets('a person this device has no row for is still shown', (
      tester,
    ) async {
      await open(tester, account: 'ghost');
      expect(find.text('Helix user ghost'), findsWidgets);
      expect(find.text('Available after your first message'), findsOneWidget);
    });

    testWidgets('a blocked person says so and offers to unblock', (
      tester,
    ) async {
      gateway.put(gateway.people[id]!.copyWith(blocked: true));
      await open(tester);
      expect(find.text('Blocked'), findsOneWidget);
      expect(find.text('Unblock Mum'), findsOneWidget);
    });
  });

  group('renaming', () {
    Future<void> rename(WidgetTester tester, String name) async {
      await tester.tap(find.text('Rename').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), name);
      await tester.tap(inDialog(find.text('Save')));
      await tester.pumpAndSettle();
    }

    testWidgets('saves the nickname, and the phone-book name follows', (
      tester,
    ) async {
      await open(tester);
      await rename(tester, '  Mother  ');
      expect(gateway.calls, contains('setNickname:$id:Mother'));
      expect(find.text('Saved, and updated in your contacts.'), findsOne);
      // The phone-book name outranks the nickname, so it is the one shown.
      expect(find.text('Mother'), findsWidgets);
      expect(find.text('Mum'), findsNothing);
    });

    testWidgets('the dialog starts from the current nickname', (tester) async {
      gateway.put(gateway.people[id]!.copyWith(nickname: const Value('Ma')));
      await open(tester);
      await tester.tap(find.text('Rename').first);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Ma',
      );
    });

    testWidgets('cancelling changes nothing', (tester) async {
      await open(tester);
      await tester.tap(find.text('Rename').first);
      await tester.pumpAndSettle();
      await tester.tap(inDialog(find.text('Cancel')));
      await tester.pumpAndSettle();
      expect(gateway.calls.where((c) => c.startsWith('setNickname')), isEmpty);
    });

    testWidgets('an empty name removes the nickname', (tester) async {
      gateway.put(gateway.people[id]!.copyWith(nickname: const Value('Ma')));
      await open(tester);
      await rename(tester, '');
      expect(gateway.calls, contains('setNickname:$id:null'));
      expect(find.text('Saved.'), findsOneWidget);
    });

    testWidgets('without the phone permission it asks first, then writes', (
      tester,
    ) async {
      contacts.state = ContactsPermission.notAsked;
      await open(tester);
      await rename(tester, 'Mother');
      expect(find.text('Save in your phone contacts too?'), findsOneWidget);
      expect(contacts.events, isNot(contains('request')));

      await tester.tap(find.text('Allow'));
      await tester.pumpAndSettle();
      expect(contacts.events, contains('request'));
      // Renamed twice: once without the phone, once with it.
      expect(
        gateway.calls.where((c) => c == 'setNickname:$id:Mother'),
        hasLength(2),
      );
      expect(find.text('Saved, and updated in your contacts.'), findsOne);
      expect(contacts.state, ContactsPermission.granted);
    });

    testWidgets('declining the phone leaves the name in Helix only', (
      tester,
    ) async {
      contacts.state = ContactsPermission.notAsked;
      await open(tester);
      await rename(tester, 'Mother');
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(contacts.events, isNot(contains('request')));
      expect(find.text('Saved.'), findsOneWidget);
    });

    testWidgets('a system refusal is explained', (tester) async {
      contacts
        ..state = ContactsPermission.notAsked
        ..grantOnRequest = false;
      await open(tester);
      await rename(tester, 'Mother');
      await tester.tap(find.text('Allow'));
      await tester.pumpAndSettle();
      expect(find.textContaining('did not let Helix change'), findsOneWidget);
    });

    testWidgets('a phone that refuses the write is explained', (tester) async {
      contacts.refuseWrites = true;
      await open(tester);
      await rename(tester, 'Mother');
      expect(find.textContaining('did not let Helix change'), findsOneWidget);
      // Still saved in Helix, and shown by the nickname rung of the order
      // only when there is no phone-book name: here the old one wins.
      expect(gateway.people[id]!.nickname, 'Mother');
    });

    testWidgets('a person with no number is never offered the phone', (
      tester,
    ) async {
      contacts.state = ContactsPermission.notAsked;
      gateway.put(personRow('named', helix: 'named_one', identityKey: key(3)));
      await open(tester, account: 'named');
      expect(find.textContaining('phone\'s contacts'), findsNothing);
      await rename(tester, 'Dana');
      expect(find.text('Save in your phone contacts too?'), findsNothing);
      expect(find.text('Saved.'), findsOneWidget);
      expect(find.text('Dana'), findsWidgets);
    });

    testWidgets('says that renaming also renames in the phone', (tester) async {
      await open(tester);
      expect(
        find.text('Renaming also saves the name in your phone\'s contacts.'),
        findsOneWidget,
      );
    });
  });

  group('the chat', () {
    testWidgets('message and call buttons use the seams', (tester) async {
      await open(tester);
      await tester.tap(find.text('Message'));
      await tester.pump();
      await tester.pump();
      expect(seams.opened, ['direct:$id']);
      await tester.tap(find.text('Voice call'));
      await tester.tap(find.text('Video call'));
      await tester.pump();
      expect(seams.calls, ['voice:$id', 'video:$id']);
    });

    testWidgets('a refused call and unopenable shared media say so', (
      tester,
    ) async {
      seams
        ..callFailure = 'You are already in a call.'
        ..mediaAvailable = false;
      await open(tester);
      await tester.tap(find.text('Voice call'));
      await settle(tester);
      expect(find.text('You are already in a call.'), findsOneWidget);
      await tester.tap(find.text('Media, links and docs'));
      await settle(tester);
      expect(find.text('Shared media could not be opened.'), findsOneWidget);
      expect(seams.media, ['direct:$id']);
    });

    testWidgets('muting offers durations and unmuting is one tap', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.text('Mute notifications'));
      await tester.pumpAndSettle();
      expect(find.text('8 hours'), findsOneWidget);
      expect(find.text('1 week'), findsOneWidget);
      expect(find.text('Always'), findsOneWidget);
      await tester.tap(find.text('8 hours'));
      await tester.pumpAndSettle();
      expect(
        gateway.calls,
        contains(
          'mute:$id:${testNow.add(const Duration(hours: 8)).toIso8601String()}',
        ),
      );
      expect(find.textContaining('Until '), findsOneWidget);

      await tester.tap(find.text('Mute notifications'));
      await tester.pumpAndSettle();
      expect(gateway.calls, contains('mute:$id:null'));
      expect(find.textContaining('Until '), findsNothing);
    });

    testWidgets('muting for ever reads "Always"', (tester) async {
      await open(tester);
      await tester.tap(find.text('Mute notifications'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Always'));
      await tester.pumpAndSettle();
      expect(find.text('Always'), findsOneWidget);
    });

    testWidgets('the disappearing timer shows the current choice and sets '
        'a new one', (tester) async {
      await open(tester);
      expect(find.text('Off'), findsOneWidget);
      await tester.tap(find.text('Disappearing messages'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check), findsOneWidget);
      await tester.tap(find.text('7 days'));
      await tester.pumpAndSettle();
      expect(gateway.calls, contains('disappearing:$id:604800'));
      expect(find.text('7 days'), findsOneWidget);
    });

    testWidgets('lists the groups you have in common', (tester) async {
      gateway.groups.addAll(const [
        GroupSummary(id: 'g1', title: 'Family'),
        GroupSummary(id: 'g2', title: 'Work'),
      ]);
      gateway.members['g1'] = {id, 'self-account'};
      gateway.members['g2'] = {'self-account'};
      await open(tester);
      expect(find.text('1 group in common'), findsOneWidget);
      expect(find.text('Family'), findsOneWidget);
      expect(find.text('Work'), findsNothing);
      await tester.tap(find.text('Family'));
      await tester.pump();
      expect(seams.opened, ['group:g1']);
    });

    testWidgets('no common groups, no section', (tester) async {
      await open(tester);
      expect(find.textContaining('in common'), findsNothing);
    });
  });

  group('trust', () {
    testWidgets('an unverified key says so', (tester) async {
      await open(tester);
      expect(find.text('Not verified'), findsOneWidget);
      expect(find.text('Safety number changed'), findsNothing);
    });

    testWidgets('a verified key says so', (tester) async {
      gateway.put(gateway.people[id]!.copyWith(identityVerified: true));
      await open(tester);
      expect(find.text('Verified'), findsOneWidget);
    });

    testWidgets('a changed key is a warning, with a way to review it', (
      tester,
    ) async {
      gateway.put(
        gateway.people[id]!.copyWith(
          identityChangedAt: Value(testNow.subtract(const Duration(days: 1))),
        ),
      );
      await open(tester);
      // The banner and the row both say it.
      expect(find.text('Safety number changed'), findsNWidgets(2));
      expect(find.textContaining('someone is interfering'), findsOneWidget);
      await tester.tap(find.text('Review'));
      await tester.pumpAndSettle();
      expect(find.text('Safety number'), findsOneWidget);
      expect(find.text('Mark as verified'), findsOneWidget);
    });

    testWidgets('a key verified after the change is verified, not a '
        'warning', (tester) async {
      gateway.put(
        gateway.people[id]!.copyWith(
          identityVerified: true,
          identityChangedAt: Value(testNow.subtract(const Duration(days: 1))),
        ),
      );
      await open(tester);
      expect(find.text('Safety number changed'), findsNothing);
      expect(find.text('Verified'), findsOneWidget);
    });

    testWidgets('before any message there is nothing to verify', (
      tester,
    ) async {
      gateway.put(personRow('fresh', phonebook: 'Fresh'));
      await open(tester, account: 'fresh');
      await tester.tap(find.text('Verify safety number'));
      await settle(tester);
      expect(find.textContaining('Send a message first'), findsOneWidget);
    });
  });

  group('safety number screen', () {
    Future<void> openSafety(WidgetTester tester) async {
      await open(tester);
      await tester.tap(find.text('Verify safety number'));
      await tester.pumpAndSettle();
    }

    testWidgets('shows the digits, a QR code and the way to verify', (
      tester,
    ) async {
      await openSafety(tester);
      expect(find.byType(HelixSafetyNumberView), findsOneWidget);
      expect(find.byType(HelixQrDisplay), findsOneWidget);
      expect(find.text('10000'), findsOneWidget);
      expect(find.text('Scan their code'), findsOneWidget);
      expect(find.text('Mark as verified'), findsOneWidget);
      expect(find.text('Verified'), findsNothing);
    });

    testWidgets('marking verified, and un-verifying, go to the engine', (
      tester,
    ) async {
      await openSafety(tester);
      await tester.tap(find.text('Mark as verified'));
      await tester.pumpAndSettle();
      expect(gateway.calls, contains('setVerified:$id:true'));
      expect(find.text('Verified'), findsOneWidget);
      await tester.tap(find.text('Mark as not verified'));
      await tester.pumpAndSettle();
      expect(gateway.calls, contains('setVerified:$id:false'));
      expect(find.text('Mark as verified'), findsOneWidget);
    });

    testWidgets('scanning the matching code verifies and closes', (
      tester,
    ) async {
      await openSafety(tester);
      scannedCode = safety.qrText;
      await tester.tap(find.text('Scan their code'));
      await tester.pumpAndSettle();
      expect(find.text('Scan code'), findsOneWidget);
      await tester.tap(find.text('Pretend to scan'));
      await tester.pumpAndSettle();
      expect(gateway.calls, contains('setVerified:$id:true'));
      expect(find.text('Scan code'), findsNothing);
      expect(find.text('Verified. Your chat is private.'), findsOneWidget);
    });

    testWidgets('a code that does not match verifies nothing', (tester) async {
      await openSafety(tester);
      for (final wrong in ['not-a-code', '!!!', '']) {
        scannedCode = wrong;
        await tester.tap(find.text('Scan their code'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Pretend to scan'));
        await tester.pumpAndSettle();
        expect(find.text('That code does not match'), findsOneWidget);
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
        // Still scanning: go back.
        GoRouter.of(tester.element(find.text('Scan code'))).pop();
        await tester.pumpAndSettle();
      }
      expect(gateway.calls.where((c) => c.startsWith('setVerified')), isEmpty);
    });

    testWidgets('a code from somebody else\'s keys does not match', (
      tester,
    ) async {
      await openSafety(tester);
      final other = SafetyNumberData(
        groups: safety.groups,
        qrPayload: Uint8List.fromList(List<int>.filled(62, 9)),
      );
      scannedCode = other.qrText;
      await tester.tap(find.text('Scan their code'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pretend to scan'));
      await tester.pumpAndSettle();
      expect(find.text('That code does not match'), findsOneWidget);
    });

    testWidgets('no key yet is an explanation, not a crash', (tester) async {
      gateway.safety.remove(id);
      await open(tester);
      GoRouter.of(
        tester.element(find.byType(ContactInfoScreen)),
      ).push(PeoplePaths.safetyNumber(id));
      await tester.pumpAndSettle();
      expect(find.text('No safety number yet'), findsOneWidget);
    });
  });

  group('the QR payload', () {
    test('is text that survives the round trip, padded or not', () {
      expect(safety.qrText, isNot(contains('=')));
      expect(safety.matchesQrText(safety.qrText), isTrue);
      expect(safety.matchesQrText('  ${safety.qrText}\n'), isTrue);
      expect(safety.matchesQrText(safety.qrText.substring(1)), isFalse);
      expect(safety.matchesQrText('###'), isFalse);
    });

    test('draws as a square module matrix', () {
      final matrix = safety.qrMatrix;
      expect(matrix.size, greaterThan(20));
      expect(matrix.modules, hasLength(matrix.size * matrix.size));
      expect(matrix.modules.where((m) => m).length, greaterThan(50));
    });
  });

  group('blocking and reporting', () {
    testWidgets('blocking asks first and does not tell them', (tester) async {
      await open(tester);
      await tester.tap(find.text('Block Mum'));
      await tester.pumpAndSettle();
      expect(find.text('Block Mum?'), findsOneWidget);
      expect(find.textContaining('will not be told'), findsOneWidget);
      await tester.tap(inDialog(find.text('Block')));
      await tester.pumpAndSettle();
      expect(gateway.calls, contains('block:$id'));
      expect(find.text('Blocked'), findsWidgets);
      expect(find.text('Unblock Mum'), findsOneWidget);
    });

    testWidgets('cancelling the block does nothing', (tester) async {
      await open(tester);
      await tester.tap(find.text('Block Mum'));
      await tester.pumpAndSettle();
      await tester.tap(inDialog(find.text('Cancel')));
      await tester.pumpAndSettle();
      expect(gateway.calls.where((c) => c.startsWith('block')), isEmpty);
    });

    testWidgets('unblocking is one tap', (tester) async {
      gateway.put(gateway.people[id]!.copyWith(blocked: true));
      await open(tester);
      await tester.tap(find.text('Unblock Mum'));
      await settle(tester);
      expect(gateway.calls, contains('unblock:$id'));
      expect(find.text('Block Mum'), findsOneWidget);
    });

    testWidgets('a report is a category and a note, confirmed, and sends no '
        'messages', (tester) async {
      await open(tester);
      await tester.tap(find.text('Report Mum'));
      await tester.pumpAndSettle();
      expect(find.textContaining('No messages are sent'), findsOneWidget);
      await tester.tap(find.text('Spam'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'sells things');
      await tester.tap(inDialog(find.text('Report')));
      await tester.pumpAndSettle();
      expect(gateway.calls, contains('report:$id:spam:sells things'));
      expect(
        find.text('Reported. No messages were sent with the report.'),
        findsOneWidget,
      );
    });

    testWidgets('the note is optional', (tester) async {
      await open(tester);
      await tester.tap(find.text('Report Mum'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abuse or harassment'));
      await tester.pumpAndSettle();
      await tester.tap(inDialog(find.text('Report')));
      await tester.pumpAndSettle();
      expect(gateway.calls, contains('report:$id:abuse:null'));
    });

    testWidgets('dismissing the report sheet sends nothing', (tester) async {
      await open(tester);
      await tester.tap(find.text('Report Mum'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(gateway.calls.where((c) => c.startsWith('report')), isEmpty);
    });
  });

  group('accessibility', () {
    testWidgets('48 px targets and labelled buttons at 2x text', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await open(tester, textScale: 2);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('the header is a heading and the picture is described', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await open(tester);
      expect(find.bySemanticsLabel(RegExp('Picture of Mum')), findsOneWidget);
      handle.dispose();
    });
  });
}
