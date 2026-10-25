import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/core/engine/runtime_providers.dart';
import 'package:helix_remote/core/lifecycle/app_lifecycle_host.dart';
import 'package:helix_remote/core/notifications/message_alerts.dart';

/// Coming back to the app (B20).
void main() {
  /// Signed out is the normal state of the sign-in page. Resuming there used
  /// to await a runtime provider that can only throw `NoServerChosen` (and
  /// retries doing so) from a future nothing awaited, which the zone handler
  /// recorded as a crash on every return to the app (AUD-14b-4). The old host
  /// leaves that provider loading when the test ends, which Riverpod reports;
  /// the new one never asks it.
  testWidgets('resuming with nobody signed in throws nothing', (tester) async {
    final alerts = RunningAppAlerts(
      inForeground: () => true,
      onScreen: () => null,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [runningAppAlertsProvider.overrideWithValue(alerts)],
        child: const MaterialApp(
          home: AppLifecycleHost(child: Text('sign in')),
        ),
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AppLifecycleHost)),
    );
    expect(container.read(activeAccountProvider), isNull);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    // Let the runtime provider answer (it throws, as it does signed out).
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
  });
}
