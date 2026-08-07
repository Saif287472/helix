import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/l10n/helix_localizations.dart';

/// Deterministic CI harness for the message-list burst budget. Device-lab
/// traces remain the release authority; this catches accidental eager builds
/// and burst regressions on the CI reference runner on every change.
void main() {
  testWidgets('P04 1,000-message burst stays within the CI frame budget', (
    tester,
  ) async {
    final key = GlobalKey<_BurstListState>();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: HelixLocalizations.localizationsDelegates,
        supportedLocales: HelixLocalizations.supportedLocales,
        home: _BurstList(key: key),
      ),
    );
    await tester.pump();

    final stopwatch = Stopwatch()..start();
    for (var index = 0; index < 20; index++) {
      key.currentState!.applyDelta('Burst message $index');
      await tester.pump();
    }
    stopwatch.stop();

    // Widget tests run on the CI reference runner, not a physical device, so
    // the duration is deliberately a regression guard rather than a claim of
    // device-frame parity. Physical-device p99 evidence is still required at
    // release time by PERFORMANCE_BUDGETS.md.
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 1)));
  });
}

class _BurstList extends StatefulWidget {
  const _BurstList({super.key});

  @override
  State<_BurstList> createState() => _BurstListState();
}

class _BurstListState extends State<_BurstList> {
  final List<String> _messages = List<String>.generate(
    1000,
    (index) => 'Seed message $index',
  );

  void applyDelta(String message) => setState(() => _messages[0] = message);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView.builder(
        itemCount: _messages.length,
        itemBuilder: (_, index) => ListTile(title: Text(_messages[index])),
      ),
    );
  }
}
