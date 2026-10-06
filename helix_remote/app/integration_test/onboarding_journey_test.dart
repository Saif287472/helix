import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/core/engine/runtime_providers.dart';
import 'package:helix_remote/main.dart';
import 'package:integration_test/integration_test.dart';

/// Runs the sign-in journey on a real device or emulator.
///
/// The hidden corner is the one product rule a unit test cannot fully stand in
/// for: it depends on real taps landing in real coordinates inside a real
/// two-second window. Everything else about sign-in is covered headlessly by
/// `test/sign_in_flow_test.dart`.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'A1 integration: the hidden corner reaches personal-server entry',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          // No engine behind it: sign-in draws before anything is signed in, so
          // nothing may reach for the keystore or the network.
          overrides: [runtimeFactoryProvider.overrideWithValue(_unreachable)],
          child: const HelixRemoteApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sign in'), findsOneWidget);
      final corner = find.byKey(const ValueKey('advanced-mode-corner'));
      for (var i = 0; i < 3; i++) {
        await tester.tap(corner);
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(find.text('Advanced mode'), findsOneWidget);

      await tester.tap(find.text('Advanced mode'));
      await tester.pumpAndSettle();
      expect(find.text('Personal server'), findsOneWidget);
      expect(find.byKey(const ValueKey('code-field')), findsOneWidget);
    },
  );
}

/// A factory that must never be reached: this journey never signs in, so any
/// attempt to open a runtime fails loudly.
final RuntimeFactory _unreachable = _UnreachableFactory();

final class _UnreachableFactory implements RuntimeFactory {
  @override
  Future<Never> open({required Uri serverUrl}) =>
      throw StateError('this journey must not open an engine');
}
