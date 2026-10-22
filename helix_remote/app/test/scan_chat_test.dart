import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/core/links/deep_link.dart';
import 'package:helix_remote/features/people/presentation/scan_chat_screen.dart';
import 'package:helix_remote_db/helix_remote_db.dart' show directConversationId;

import 'support/people_fakes.dart';

/// Scan-to-chat: the code on another person's share sheet is the same link you
/// could send you as text, so scanning it does what tapping it does - look the
/// `~name` up with this account's session and open the chat.
void main() {
  tearDown(() => scannedCode = '');

  testWidgets('a scanned share code opens the chat it names', (tester) async {
    final gateway = FakePeopleGateway()
      ..byHelixName['anna'] = personRow('acct-1', helix: 'anna');
    final seams = FakeSeams();
    scannedCode = helixProfileLink('anna');

    await pumpPeople(
      tester,
      const ScanChatScreen(),
      gateway: gateway,
      seams: seams,
    );
    await tester.tap(find.text('Pretend to scan'));
    await tester.pumpAndSettle();

    expect(seams.opened, [directConversationId('acct-1')]);
    expect(find.text('Found them. Opening your chat.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('a code that is not a share link costs no lookup', (
    tester,
  ) async {
    final gateway = FakePeopleGateway();
    final seams = FakeSeams();
    scannedCode = 'https://example.com/not-a-helix-code';

    await pumpPeople(
      tester,
      const ScanChatScreen(),
      gateway: gateway,
      seams: seams,
    );
    await tester.tap(find.text('Pretend to scan'));
    await tester.pumpAndSettle();

    expect(gateway.calls, isEmpty, reason: 'nothing is sent for a wrong code');
    expect(seams.opened, isEmpty);
    expect(find.text('That is not a share code'), findsOneWidget);
  });

  testWidgets('a name that answers to nobody is said, and scanning goes on', (
    tester,
  ) async {
    final gateway = FakePeopleGateway();
    final seams = FakeSeams();
    scannedCode = helixProfileLink('ghost');

    await pumpPeople(
      tester,
      const ScanChatScreen(),
      gateway: gateway,
      seams: seams,
    );
    await tester.tap(find.text('Pretend to scan'));
    await tester.pumpAndSettle();

    expect(gateway.calls, contains('findByHelixName:ghost'));
    expect(seams.opened, isEmpty);
    expect(find.text('That is not a share code'), findsOneWidget);
  });
}
