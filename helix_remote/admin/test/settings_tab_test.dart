import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_admin/screens/settings_tab.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

SettingsTab _settingsTab({
  TextEditingController? urlController,
  VoidCallback? onOpenConnectGuide,
  VoidCallback? onOpenConnectServer,
  VoidCallback? onDisconnect,
  bool isConnected = false,
  bool appLockEnabled = false,
  ValueChanged<bool>? onAppLockChanged,
}) {
  return SettingsTab(
    isDarkMode: true,
    onDarkModeChanged: (_) {},
    urlController: urlController ?? TextEditingController(),
    isConnected: isConnected,
    onOpenConnectServer: onOpenConnectServer ?? () {},
    onDisconnect: onDisconnect ?? () {},
    onOpenConnectGuide: onOpenConnectGuide ?? () {},
    appLockEnabled: appLockEnabled,
    onAppLockChanged: onAppLockChanged,
  );
}

void main() {
  testWidgets(
    'the connection status card shows "Not connected" and reports a tap',
    (tester) async {
      var opened = false;
      await tester.pumpWidget(
        _wrap(_settingsTab(onOpenConnectServer: () => opened = true)),
      );

      expect(find.text('Not connected'), findsOneWidget);

      await tester.tap(
        find.byKey(const Key('settings_connection_status_card')),
      );
      await tester.pump();

      expect(opened, isTrue);
    },
  );

  testWidgets(
    'the connection status card shows the connected host, with a quick '
    'disconnect action',
    (tester) async {
      var disconnected = false;
      await tester.pumpWidget(
        _wrap(
          _settingsTab(
            isConnected: true,
            urlController: TextEditingController(
              text: 'https://helix.example.com',
            ),
            onDisconnect: () => disconnected = true,
          ),
        ),
      );

      expect(find.text('Connected'), findsOneWidget);
      expect(find.text('helix.example.com'), findsOneWidget);

      await tester.tap(find.byTooltip('Disconnect'));
      await tester.pump();

      expect(disconnected, isTrue);
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
          urlController: TextEditingController(),
          isConnected: false,
          onOpenConnectServer: () {},
          onDisconnect: () {},
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
