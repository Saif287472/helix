import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_ui/orbit_ui.dart';

/// Part C step 4: the themes page (`ThemeGalleryScreen`) and the row on
/// Appearance that opens it. How it looks is the compare tool's business; what
/// it does is here.
void main() {
  late OrbitTokens orbit;
  late OrbitTokens night;

  setUpAll(() {
    OrbitTokens load(String id) => OrbitTokens.fromThemeJson(
      jsonDecode(File('assets/themes/$id.json').readAsStringSync())
          as Map<String, Object?>,
    );
    orbit = load('orbit');
    night = load('night');
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

  /// Ends a test that raised a toast with no timer left pending.
  Future<void> drain(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5));
  }

  const themes = [
    ThemePackItem(
      id: 'orbit',
      name: 'Orbit',
      place: ThemePackPlace.onThisPhone,
      detail: 'Default · light',
      builtIn: true,
      inUse: true,
    ),
    ThemePackItem(
      id: 'night',
      name: 'Orbit Night',
      place: ThemePackPlace.onThisPhone,
      detail: 'Default · dark',
      builtIn: true,
    ),
    ThemePackItem(
      id: 'synthwave',
      name: 'Synthwave',
      place: ThemePackPlace.onThisPhone,
      detail: 'Neon · dark · 2.0 MB',
    ),
    ThemePackItem(
      id: 'hologram',
      name: 'hologram',
      detail: 'Its name arrives with the theme',
    ),
  ];

  testWidgets('splits what this phone can draw with from what is on offer', (
    tester,
  ) async {
    await show(
      tester,
      const ThemeGalleryScreen(
        model: ThemeGalleryModel(themes: themes, host: 'Orbit Home'),
      ),
    );
    // A group title is an eyebrow, and an eyebrow is drawn upper case.
    expect(find.text('ON THIS PHONE', findRichText: true), findsOneWidget);
    expect(find.text('ON ORBIT HOME', findRichText: true), findsOneWidget);
    expect(find.text('Orbit'), findsOneWidget);
    expect(find.text('In use'), findsOneWidget);
    expect(find.text('Built in'), findsOneWidget);
    // An offer has no name of its own: only the signed pack knows that.
    expect(find.text('hologram'), findsOneWidget);
    expect(find.text('Get'), findsOneWidget);
    expect(find.byTooltip('Delete Synthwave'), findsOneWidget);
    expect(find.text('More themes are on the way'), findsNothing);
  });

  testWidgets('Get, Use, Update and Delete each name the theme they are for', (
    tester,
  ) async {
    final got = <String>[];
    final used = <String>[];
    final updated = <String>[];
    final deleted = <String>[];
    await show(
      tester,
      ThemeGalleryScreen(
        model: const ThemeGalleryModel(
          themes: [
            ...themes,
            ThemePackItem(
              id: 'jungle',
              name: 'Jungle',
              place: ThemePackPlace.onThisPhone,
              updateAvailable: true,
            ),
          ],
        ),
        actions: ThemeGalleryActions(
          onGet: (id) async {
            got.add(id);
            return null;
          },
          onUse: (id) async {
            used.add(id);
            return '$id theme on';
          },
          onUpdate: (id) async {
            updated.add(id);
            return null;
          },
          onDelete: (id) async {
            deleted.add(id);
            return null;
          },
        ),
      ),
    );
    await tester.tap(find.text('Get'));
    await tester.pump();
    expect(got, ['hologram']);
    // Only a theme with a newer revision on the server is offered an update.
    expect(find.text('Update'), findsOneWidget);
    await tester.tap(find.text('Update'));
    await tester.pump();
    expect(updated, ['jungle']);
    // The row itself uses the theme, and says what the app said.
    await tester.tap(find.text('Synthwave'));
    await tester.pump();
    expect(used, ['synthwave']);
    expect(find.text('synthwave theme on'), findsOneWidget);
    await drain(tester);
    await tester.tap(find.byTooltip('Delete Synthwave'));
    await tester.pump();
    expect(deleted, ['synthwave']);
  });

  testWidgets('a theme that is in use cannot be used again, and a built-in one '
      'cannot be deleted', (tester) async {
    await show(
      tester,
      ThemeGalleryScreen(
        model: const ThemeGalleryModel(themes: themes),
        actions: ThemeGalleryActions(onUse: (_) async => null),
      ),
    );
    expect(find.byTooltip('Delete Orbit'), findsNothing);
    expect(find.byTooltip('Delete hologram'), findsNothing);
    await tester.tap(find.text('Orbit'));
    await tester.pump();
    expect(find.text('Jungle'), findsNothing);
  });

  testWidgets(
    'a running action waits, and nothing else on that row is tappable',
    (tester) async {
      await show(
        tester,
        const ThemeGalleryScreen(
          model: ThemeGalleryModel(
            themes: [
              ThemePackItem(id: 'hologram', name: 'hologram', busy: true),
            ],
          ),
        ),
      );
      expect(find.text('Get'), findsNothing);
      expect(find.byType(OrbitSpinner), findsOneWidget);
    },
  );

  testWidgets(
    'the offers load, and a server that cannot be reached says so and '
    'asks again',
    (tester) async {
      var retried = 0;
      await show(
        tester,
        const ThemeGalleryScreen(
          model: ThemeGalleryModel(status: ListStatus.loading),
        ),
      );
      expect(find.text('Checking what is on offer'), findsOneWidget);

      await show(
        tester,
        ThemeGalleryScreen(
          model: const ThemeGalleryModel(
            status: ListStatus.failed,
            error: 'You are offline.',
          ),
          actions: ThemeGalleryActions(onRetry: () => retried++),
        ),
      );
      expect(find.text('You are offline.'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await tester.pump();
      expect(retried, 1);
    },
  );

  testWidgets('a server with nothing to offer says so', (tester) async {
    await show(
      tester,
      const ThemeGalleryScreen(
        model: ThemeGalleryModel(
          themes: [
            ThemePackItem(
              id: 'orbit',
              name: 'Orbit',
              place: ThemePackPlace.onThisPhone,
              builtIn: true,
              inUse: true,
            ),
          ],
        ),
      ),
    );
    expect(find.textContaining('Nothing is on offer here yet'), findsOneWidget);
    expect(find.text('Get'), findsNothing);
  });

  testWidgets('Appearance offers the themes page, and says it when it cannot', (
    tester,
  ) async {
    var opened = 0;
    await show(
      tester,
      AppearanceScreen(
        model: AppearanceModel(
          current: orbit,
          themes: [
            ThemeChoice(tokens: orbit),
            ThemeChoice(tokens: night),
          ],
        ),
        actions: AppearanceActions(onGetMore: () => opened++),
      ),
    );
    await tester.tap(find.text('More themes'));
    await tester.pump();
    expect(opened, 1);
    expect(find.textContaining('More themes are on the way'), findsNothing);

    await show(
      tester,
      AppearanceScreen(
        model: AppearanceModel(
          current: orbit,
          themes: [ThemeChoice(tokens: orbit)],
        ),
      ),
    );
    expect(find.text('More themes'), findsNothing);
    expect(find.textContaining('More themes are on the way'), findsOneWidget);
  });
}
