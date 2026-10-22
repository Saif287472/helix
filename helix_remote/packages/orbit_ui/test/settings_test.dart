import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_ui/orbit_ui.dart';

/// Phase 4 batch 9: the settings pages, devices and backup. How they look
/// is checked against the prototype by the compare tool.
void main() {
  late OrbitTokens orbit;
  setUpAll(() {
    orbit = OrbitTokens.fromThemeJson(
      jsonDecode(File('assets/themes/orbit.json').readAsStringSync())
          as Map<String, Object?>,
    );
  });

  Future<void> show(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(412, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(412, 1800),
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

  testWidgets('password: the button turns on when every rule passes', (
    tester,
  ) async {
    String? saved;
    await show(
      tester,
      PasswordScreen(
        model: const PasswordModel(isSet: true),
        actions: PasswordActions(
          onSave: ({phone, current, required password}) => saved = password,
        ),
      ),
    );
    final fields = find.byType(EditableText);
    await tester.enterText(fields.at(0), 'sunrise-42');
    await tester.pump();
    await tester.tap(find.text('Set a password').last);
    expect(saved, isNull);
    await tester.enterText(fields.at(1), 'sunrise-42');
    await tester.pump();
    await tester.tap(find.text('Set a password').last);
    expect(saved, 'sunrise-42');
  });

  testWidgets('delete account: typing DELETE is required', (tester) async {
    var deleted = 0;
    await show(
      tester,
      DeleteAccountScreen(
        model: const DeleteAccountModel(proof: DeleteProof.key),
        actions: DeleteAccountActions(onDelete: ({phone, secret}) => deleted++),
      ),
    );
    final button = find.text('Delete my account').last;
    await tester.tap(button);
    await tester.pump();
    expect(deleted, 0);
    await tester.pumpAndSettle(const Duration(seconds: 5));
    await tester.enterText(find.byType(EditableText).first, 'DELETE');
    await tester.tap(button);
    expect(deleted, 1);
  });

  testWidgets('blocked: unblock asks first', (tester) async {
    String? unblocked;
    await show(
      tester,
      BlockedScreen(
        model: const BlockedModel(
          people: [
            BlockedPersonItem(
              account: 'shuvo',
              name: 'Shuvo',
              avatar: HelixAvatarModel(name: 'Shuvo'),
            ),
          ],
        ),
        actions: BlockedActions(onUnblock: (a) => unblocked = a),
      ),
    );
    expect(find.text('1 blocked person'), findsOneWidget);
    await tester.tap(find.text('Unblock'));
    await tester.pumpAndSettle();
    expect(unblocked, isNull);
    await tester.tap(find.text('Unblock').last);
    await tester.pumpAndSettle();
    expect(unblocked, 'shuvo');
  });

  testWidgets('legal switches documents', (tester) async {
    await show(
      tester,
      const LegalScreen(
        model: LegalModel(
          terms: LegalDocument(title: 'Terms', version: '3', body: 'T body'),
          privacy: LegalDocument(
            title: 'Privacy',
            version: '4',
            body: 'P body',
          ),
        ),
      ),
    );
    expect(find.text('T body'), findsOneWidget);
    await tester.tap(find.text('Privacy').first);
    await tester.pump();
    expect(find.text('P body'), findsOneWidget);
  });

  testWidgets('devices: a device sheet offers remove, not for this one', (
    tester,
  ) async {
    await show(
      tester,
      const DeviceListScreen(
        model: DeviceListModel(
          devices: [
            DeviceItem(
              id: 'a',
              name: 'Pixel 8',
              platform: 'Android',
              whenLabel: 'This device',
              isThis: true,
            ),
            DeviceItem(
              id: 'b',
              name: 'Office PC',
              platform: 'Windows',
              whenLabel: 'Active 5 minutes ago',
            ),
          ],
        ),
      ),
    );
    expect(find.text('2 devices signed in'), findsOneWidget);
    await tester.tap(find.text('Pixel 8'));
    await tester.pumpAndSettle();
    expect(find.text('Remove this device'), findsNothing);
    Navigator.of(tester.element(find.text('Rename'))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Office PC'));
    await tester.pumpAndSettle();
    expect(find.text('Remove this device'), findsOneWidget);
  });

  testWidgets('approve device: Continue waits for a code', (tester) async {
    String? code;
    await show(
      tester,
      ApproveDeviceScreen(
        model: const ApproveDeviceModel(),
        actions: ApproveDeviceActions(onContinue: (c) => code = c),
      ),
    );
    await tester.tap(find.text('Continue'));
    expect(code, isNull);
    await tester.enterText(find.byType(EditableText), 'helix-link:v2:x');
    await tester.pump();
    await tester.tap(find.text('Continue'));
    expect(code, 'helix-link:v2:x');
  });

  testWidgets('backup: failed says Try again', (tester) async {
    var ran = 0;
    await show(
      tester,
      BackupScreen(
        model: const BackupModel(state: BackupState.failed),
        actions: BackupActions(onBackUp: () => ran++),
      ),
    );
    expect(find.text('The last backup did not finish'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    expect(ran, 1);
  });

  testWidgets('backup: running shows the percentage of the history', (
    tester,
  ) async {
    await show(
      tester,
      const BackupScreen(
        model: BackupModel(state: BackupState.running, progress: 0.62),
      ),
    );
    expect(find.text('Backing up…'), findsOneWidget);
    expect(find.text('62%'), findsOneWidget);
  });

  testWidgets('backup: running with no total shows no number', (tester) async {
    await show(
      tester,
      const BackupScreen(model: BackupModel(state: BackupState.running)),
    );
    expect(find.text('Backing up…'), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
  });

  testWidgets('transfer: a waiting history can be accepted', (tester) async {
    (String, String)? acted;
    await show(
      tester,
      TransferScreen(
        model: const TransferModel(
          waiting: [
            TransferItem(
              id: 'in',
              title: 'History from Office PC',
              status:
                  'Ready to receive. Nothing is downloaded until you accept.',
              buttons: ['Accept', 'Decline'],
            ),
          ],
        ),
        actions: TransferActions(onAction: (id, a) => acted = (id, a)),
      ),
    );
    expect(find.text('1 waiting here'), findsOneWidget);
    await tester.tap(find.text('Accept'));
    expect(acted, ('in', 'Accept'));
  });

  testWidgets('transfer: a stopped history is not counted as waiting', (
    tester,
  ) async {
    await show(
      tester,
      const TransferScreen(
        model: TransferModel(
          waiting: [
            TransferItem(
              id: 'in',
              title: 'History from Office PC',
              status: 'Stopped: the connection dropped.',
              progress: 0.4,
              buttons: ['Resume', 'Cancel'],
            ),
          ],
        ),
      ),
    );
    expect(find.textContaining('waiting here'), findsNothing);
  });

  testWidgets('recovery: Create waits for "I saved it"', (tester) async {
    var created = 0;
    var saved = false;
    await show(
      tester,
      StatefulBuilder(
        builder: (context, setState) => RecoveryScreen(
          model: RecoveryModel(
            secret: 'K7QM-X2PD-9WTR-4HNB-F6CZ-JY3V',
            saved: saved,
          ),
          actions: RecoveryActions(
            onSaved: (v) => setState(() => saved = v),
            onCreate: () => created++,
          ),
        ),
      ),
    );
    final create = find.text('Create recovery backup');
    await tester.tap(create);
    expect(created, 0);
    await tester.tap(find.text('I saved it somewhere safe'));
    await tester.pump();
    await tester.tap(create);
    expect(created, 1);
  });
}
