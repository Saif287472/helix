import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_admin/screens/guide/guide_wizard.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

class _FakeUrlLauncher extends UrlLauncherPlatform {
  final launched = <String>[];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add(url);
    return true;
  }
}

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: SizedBox(height: 900, child: child)),
);

Widget _wrapNarrow(Widget child) => MaterialApp(
  home: Scaffold(body: SizedBox(width: 320, height: 700, child: child)),
);

double? _progressValue(WidgetTester tester) => tester
    .widget<LinearProgressIndicator>(
      find.byKey(const Key('guide_progress_bar')),
    )
    .value;

void main() {
  testWidgets('starts on Welcome with Back disabled and progress at 1/8', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(const GuideWizard()));

    expect(find.text('Welcome to self-hosting Helix'), findsOneWidget);
    expect(find.text('Step 1 of 8'), findsOneWidget);
    expect(_progressValue(tester), closeTo(1 / 8, 0.0001));

    final back = tester.widget<OutlinedButton>(
      find.byKey(const Key('guide_back_button')),
    );
    expect(back.onPressed, isNull);
  });

  testWidgets('Next advances the page and updates the progress bar', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(const GuideWizard()));

    await tester.tap(find.byKey(const Key('guide_next_button')));
    await tester.pumpAndSettle();

    expect(find.text('How big a server do you need?'), findsOneWidget);
    expect(find.text('Step 2 of 8'), findsOneWidget);
    expect(_progressValue(tester), closeTo(2 / 8, 0.0001));

    final back = tester.widget<OutlinedButton>(
      find.byKey(const Key('guide_back_button')),
    );
    expect(back.onPressed, isNotNull);
  });

  testWidgets('Back returns to the previous page', (tester) async {
    await tester.pumpWidget(_wrap(const GuideWizard()));
    await tester.tap(find.byKey(const Key('guide_next_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('guide_back_button')));
    await tester.pumpAndSettle();

    expect(find.text('Welcome to self-hosting Helix'), findsOneWidget);
    expect(_progressValue(tester), closeTo(1 / 8, 0.0001));
  });

  testWidgets('Next is disabled on the last page', (tester) async {
    await tester.pumpWidget(_wrap(const GuideWizard()));

    for (var i = 0; i < 7; i++) {
      await tester.tap(find.byKey(const Key('guide_next_button')));
      await tester.pumpAndSettle();
    }

    expect(find.text('Backups and maintenance'), findsOneWidget);
    expect(find.text('Step 8 of 8'), findsOneWidget);
    final next = tester.widget<ElevatedButton>(
      find.byKey(const Key('guide_next_button')),
    );
    expect(next.onPressed, isNull);
  });

  testWidgets('tapping a progress chip jumps directly to that page', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(const GuideWizard()));

    await tester.ensureVisible(find.byKey(const Key('guide_page_chip_6')));
    await tester.tap(find.byKey(const Key('guide_page_chip_6')));
    await tester.pumpAndSettle();

    expect(find.text('Connect Helix Admin'), findsOneWidget);
    expect(find.text('Step 7 of 8'), findsOneWidget);
    expect(_progressValue(tester), closeTo(7 / 8, 0.0001));
  });

  testWidgets(
    'the hosting toggle switches between VPS and home-PC views at will',
    (tester) async {
      await tester.pumpWidget(_wrap(const GuideWizard()));
      await tester.ensureVisible(find.byKey(const Key('guide_page_chip_2')));
      await tester.tap(find.byKey(const Key('guide_page_chip_2')));
      await tester.pumpAndSettle();

      expect(find.textContaining('in no particular order'), findsOneWidget);
      expect(find.text('DigitalOcean'), findsOneWidget);

      await tester.tap(find.byKey(const Key('hosting_toggle_homePc')));
      await tester.pumpAndSettle();

      expect(find.text('DigitalOcean'), findsNothing);
      expect(find.textContaining('Raspberry Pi'), findsOneWidget);

      await tester.tap(find.byKey(const Key('hosting_toggle_vps')));
      await tester.pumpAndSettle();

      expect(find.text('DigitalOcean'), findsOneWidget);
    },
  );

  testWidgets('provider links invoke url_launcher with the right URL', (
    tester,
  ) async {
    final fake = _FakeUrlLauncher();
    UrlLauncherPlatform.instance = fake;

    await tester.pumpWidget(_wrap(const GuideWizard()));
    await tester.ensureVisible(find.byKey(const Key('guide_page_chip_2')));
    await tester.tap(find.byKey(const Key('guide_page_chip_2')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('provider_link_Hetzner')));
    await tester.pumpAndSettle();

    expect(fake.launched, equals(['https://www.hetzner.com']));
  });

  testWidgets('expansion tiles toggle their detail text on tap', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(const GuideWizard()));
    await tester.ensureVisible(find.byKey(const Key('guide_page_chip_3')));
    await tester.tap(find.byKey(const Key('guide_page_chip_3')));
    await tester.pumpAndSettle();

    expect(find.text('Quick install (Ubuntu/Debian)'), findsOneWidget);
    expect(find.textContaining('get.docker.com'), findsNothing);

    await tester.tap(find.text('Quick install (Ubuntu/Debian)'));
    await tester.pumpAndSettle();

    expect(find.textContaining('get.docker.com'), findsOneWidget);

    await tester.tap(find.text('Quick install (Ubuntu/Debian)'));
    await tester.pumpAndSettle();

    expect(find.textContaining('get.docker.com'), findsNothing);
  });

  testWidgets('the wizard renders with no server connected (never gated)', (
    tester,
  ) async {
    // GuideWizard takes no client/root dependency at all - this is the
    // structural guarantee that it can never be wrapped in a
    // LockedTabPlaceholder guard.
    await tester.pumpWidget(_wrap(const GuideWizard()));
    expect(find.text('Welcome to self-hosting Helix'), findsOneWidget);
    expect(find.textContaining('Connect a server'), findsNothing);
  });

  testWidgets(
    'the Back/Step/Next nav row stacks instead of overflowing on a narrow '
    'phone width',
    (tester) async {
      await tester.pumpWidget(_wrapNarrow(const GuideWizard()));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Step 1 of 8'), findsOneWidget);
      expect(find.byKey(const Key('guide_back_button')), findsOneWidget);
      expect(find.byKey(const Key('guide_next_button')), findsOneWidget);

      await tester.tap(find.byKey(const Key('guide_next_button')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Step 2 of 8'), findsOneWidget);
    },
  );
}
