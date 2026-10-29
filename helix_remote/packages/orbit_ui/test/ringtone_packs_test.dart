import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_ui/orbit_ui.dart';

/// Part C step 5: the ringtones page (`RingtoneGalleryScreen`) and the
/// Notifications row that opens it. The prototype has no such screen, so how it
/// looks is this plan's own business; what it does is here.
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

  /// Ends a test that raised a toast with no timer left pending.
  Future<void> drain(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5));
  }

  const ringtones = [
    RingtoneGalleryItem(
      id: '',
      name: 'Phone’s ringtone',
      place: ThemePackPlace.onThisPhone,
      detail: 'What the phone rings with for every other call',
      phone: true,
      inUse: true,
    ),
    RingtoneGalleryItem(
      id: 'chime',
      name: 'chime',
      place: ThemePackPlace.onThisPhone,
      detail: '24 KB',
    ),
    RingtoneGalleryItem(
      id: 'sitar',
      name: 'sitar',
      detail: '88 KB to download',
    ),
  ];

  testWidgets('splits what this phone can ring with from what is on offer', (
    tester,
  ) async {
    await show(
      tester,
      const RingtoneGalleryScreen(
        model: RingtoneGalleryModel(ringtones: ringtones, host: 'Orbit Home'),
      ),
    );
    // A group title is an eyebrow, and an eyebrow is drawn upper case.
    expect(find.text('ON THIS PHONE', findRichText: true), findsOneWidget);
    expect(find.text('ON ORBIT HOME', findRichText: true), findsOneWidget);
    expect(find.text('Ringtones'), findsOneWidget);
    expect(find.text('In use'), findsOneWidget);
    // A sound pack has no name of its own: the id the publisher signed is it.
    expect(find.text('chime'), findsOneWidget);
    expect(find.text('sitar'), findsOneWidget);
    expect(find.text('Get'), findsOneWidget);
    expect(find.byTooltip('Delete chime'), findsOneWidget);
    // The phone's own ringtone is never something this app can delete.
    expect(find.byTooltip('Delete Phone’s ringtone'), findsNothing);
    // A downloaded sound is on this phone, so its pack is explained.
    expect(find.textContaining('signed pack'), findsOneWidget);
  });

  testWidgets(
    'Get, Use, Update and Delete each name the ringtone they are for',
    (tester) async {
      final got = <String>[];
      final used = <String>[];
      final updated = <String>[];
      final deleted = <String>[];
      await show(
        tester,
        RingtoneGalleryScreen(
          model: const RingtoneGalleryModel(
            ringtones: [
              RingtoneGalleryItem(
                id: '',
                name: 'Phone’s ringtone',
                place: ThemePackPlace.onThisPhone,
                phone: true,
              ),
              RingtoneGalleryItem(
                id: 'chime',
                name: 'chime',
                place: ThemePackPlace.onThisPhone,
                inUse: true,
              ),
              RingtoneGalleryItem(
                id: 'tabla',
                name: 'tabla',
                place: ThemePackPlace.onThisPhone,
                updateAvailable: true,
              ),
              RingtoneGalleryItem(id: 'sitar', name: 'sitar'),
            ],
          ),
          actions: RingtoneGalleryActions(
            onGet: (id) async {
              got.add(id);
              return null;
            },
            onUse: (id) async {
              used.add(id);
              return id.isEmpty ? 'Phone’s ringtone on' : '$id ringtone on';
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
      expect(got, ['sitar']);
      expect(find.text('Update'), findsOneWidget);
      await tester.tap(find.text('Update'));
      await tester.pump();
      expect(updated, ['tabla']);
      // The row itself rings with the sound, and says what the app said.
      await tester.tap(find.text('Phone’s ringtone'));
      await tester.pump();
      expect(used, ['']);
      expect(find.text('Phone’s ringtone on'), findsOneWidget);
      await drain(tester);
      await tester.tap(find.byTooltip('Delete chime'));
      await tester.pump();
      expect(deleted, ['chime']);
    },
  );

  testWidgets(
    'a downloaded ringtone is explained, and the sound in use is not tappable',
    (tester) async {
      await show(
        tester,
        RingtoneGalleryScreen(
          model: const RingtoneGalleryModel(ringtones: ringtones),
          actions: RingtoneGalleryActions(onUse: (_) async => null),
        ),
      );
      expect(find.textContaining('signed pack'), findsOneWidget);
      // The phone's own row is already in use, so tapping it changes nothing.
      await tester.tap(find.text('Phone’s ringtone'));
      await tester.pump();
      expect(find.text('sitar'), findsOneWidget);
    },
  );

  testWidgets(
    'a running action waits, and nothing else on that row is tappable',
    (tester) async {
      await show(
        tester,
        const RingtoneGalleryScreen(
          model: RingtoneGalleryModel(
            ringtones: [
              RingtoneGalleryItem(id: 'sitar', name: 'sitar', busy: true),
            ],
          ),
        ),
      );
      expect(find.text('Get'), findsNothing);
      expect(find.byType(OrbitSpinner), findsOneWidget);
    },
  );

  testWidgets(
    'the offers load, and a server that cannot be reached says so and asks '
    'again',
    (tester) async {
      var retried = 0;
      await show(
        tester,
        const RingtoneGalleryScreen(
          model: RingtoneGalleryModel(status: ListStatus.loading),
        ),
      );
      expect(find.text('Checking what is on offer'), findsOneWidget);

      await show(
        tester,
        RingtoneGalleryScreen(
          model: const RingtoneGalleryModel(
            status: ListStatus.failed,
            error: 'You are offline.',
          ),
          actions: RingtoneGalleryActions(onRetry: () => retried++),
        ),
      );
      expect(find.text('You are offline.'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await tester.pump();
      expect(retried, 1);
    },
  );

  testWidgets('an empty offer list says what the app knows about it', (
    tester,
  ) async {
    await show(
      tester,
      const RingtoneGalleryScreen(
        model: RingtoneGalleryModel(
          ringtones: [
            RingtoneGalleryItem(
              id: '',
              name: 'Phone’s ringtone',
              place: ThemePackPlace.onThisPhone,
              phone: true,
              inUse: true,
            ),
          ],
        ),
      ),
    );
    expect(find.textContaining('Nothing is on offer here yet'), findsOneWidget);
    expect(find.text('Get'), findsNothing);
    // Nothing here is a pack, so there is no pack's words to explain.
    expect(find.textContaining('signed pack'), findsNothing);

    await show(
      tester,
      const RingtoneGalleryScreen(
        model: RingtoneGalleryModel(
          ringtones: [
            RingtoneGalleryItem(
              id: '',
              name: 'Phone’s ringtone',
              place: ThemePackPlace.onThisPhone,
              phone: true,
              inUse: true,
            ),
          ],
          emptyNote: 'Nothing on offer here is a sound pack this app can use.',
        ),
      ),
    );
    expect(
      find.textContaining('is a sound pack this app can use'),
      findsOneWidget,
    );
    expect(find.textContaining('Nothing is on offer here yet'), findsNothing);
  });

  testWidgets('a sound this build carries is chosen, never deleted', (
    tester,
  ) async {
    final used = <String>[];
    await show(
      tester,
      RingtoneGalleryScreen(
        model: const RingtoneGalleryModel(
          ringtones: [
            RingtoneGalleryItem(
              id: '',
              name: 'Phone’s ringtone',
              place: ThemePackPlace.onThisPhone,
              phone: true,
            ),
            RingtoneGalleryItem(
              id: 'orbit.silver-bell',
              name: 'Silver Bell',
              place: ThemePackPlace.onThisPhone,
              builtIn: true,
            ),
          ],
        ),
        actions: RingtoneGalleryActions(
          onUse: (id) async {
            used.add(id);
            return null;
          },
        ),
      ),
    );
    expect(find.text('Silver Bell'), findsOneWidget);
    // It came with the app, so there is nothing to download, update or delete.
    expect(find.byTooltip('Delete Silver Bell'), findsNothing);
    expect(find.text('Get'), findsNothing);

    await tester.tap(find.text('Silver Bell'));
    await tester.pump();
    expect(used, ['orbit.silver-bell']);
  });

  testWidgets('Notifications says what a call rings with, and opens the page', (
    tester,
  ) async {
    var opened = 0;
    await show(
      tester,
      NotificationsScreen(
        model: const NotificationsModel(ringtone: 'chime'),
        actions: NotificationsActions(onOpenRingtones: () => opened++),
      ),
    );
    await tester.tap(find.text('Ringtone'));
    await tester.pump();
    expect(opened, 1);
    expect(find.text('chime'), findsOneWidget);

    // Where a chosen sound could not ring, the row is not drawn at all.
    await show(
      tester,
      const NotificationsScreen(model: NotificationsModel(showRingtone: false)),
    );
    expect(find.text('Ringtone'), findsNothing);
  });
}
