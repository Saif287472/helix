import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_admin/screens/settings_tab.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

SettingsTab _settingsTab({
  String serverUrl = 'https://helix.example.com',
  VoidCallback? onOpenConnectGuide,
  VoidCallback? onSignOut,
  bool appLockEnabled = false,
  ValueChanged<bool>? onAppLockChanged,
}) {
  return SettingsTab(
    isDarkMode: true,
    onDarkModeChanged: (_) {},
    serverUrl: serverUrl,
    onSignOut: onSignOut ?? () {},
    onOpenConnectGuide: onOpenConnectGuide ?? () {},
    appLockEnabled: appLockEnabled,
    onAppLockChanged: onAppLockChanged,
  );
}

void main() {
  testWidgets(
    'the connection status card shows the connected host, with a sign out action',
    (tester) async {
      var signedOut = false;
      await tester.pumpWidget(
        _wrap(
          _settingsTab(
            serverUrl: 'https://helix.example.com',
            onSignOut: () => signedOut = true,
          ),
        ),
      );

      expect(find.text('Connected'), findsOneWidget);
      expect(find.text('helix.example.com'), findsOneWidget);

      await tester.tap(find.byKey(const Key('settings_sign_out_button')));
      await tester.pump();

      expect(signedOut, isTrue);
    },
  );

  testWidgets('the Dark Mode switch reflects its value and reports toggles', (
    tester,
  ) async {
    bool? toggledTo;
    await tester.pumpWidget(
      _wrap(
        SettingsTab(
          isDarkMode: true,
          onDarkModeChanged: (v) => toggledTo = v,
          serverUrl: 'https://helix.example.com',
          onSignOut: () {},
          onOpenConnectGuide: () {},
        ),
      ),
    );

    expect(find.text('Dark Mode'), findsOneWidget);
    await tester.tap(find.text('Dark Mode'));
    await tester.pump();

    expect(toggledTo, isFalse);
  });

  testWidgets('the App Lock switch reflects its value and reports toggles', (
    tester,
  ) async {
    bool? toggledTo;
    await tester.pumpWidget(
      _wrap(_settingsTab(onAppLockChanged: (value) => toggledTo = value)),
    );

    final switchWidget = tester.widget<Switch>(
      find.byKey(const Key('settings_app_lock_switch')),
    );
    expect(switchWidget.value, isFalse);

    await tester.tap(find.byKey(const Key('settings_app_lock_row')));
    await tester.pump();

    expect(toggledTo, isTrue);
  });

  testWidgets('the Self-Hosting Guide row opens the connect guide', (
    tester,
  ) async {
    var opened = false;
    await tester.pumpWidget(
      _wrap(_settingsTab(onOpenConnectGuide: () => opened = true)),
    );

    await tester.tap(find.text('Self-Hosting Guide'));
    await tester.pump();

    expect(opened, isTrue);
  });
}
