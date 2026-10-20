import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_ui/orbit_ui.dart';

/// Phase 4 batch 8: You, the profile editor, Appearance and the topic
/// pages. How they look is checked against the prototype by the compare
/// tool.
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
    tester.view.physicalSize = const Size(412, 866);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(412, 866),
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

  CheckupItem check(String key, {required bool ok}) => CheckupItem(
    key: key,
    ok: ok,
    icon: OrbitIcons.key,
    title: key,
    okText: '$key fine',
    badText: '$key needs you',
    fixLabel: key == 'lock' ? 'Turn on' : 'Fix',
  );

  YouModel you({required bool good}) => YouModel(
    name: 'Hasan',
    avatar: const HelixAvatarModel(name: 'Hasan'),
    helixName: 'hasan',
    checks: [
      check('recovery', ok: good),
      check('lock', ok: good),
    ],
    tiles: const [
      YouTile(
        topic: YouTopic.privacy,
        icon: OrbitIcons.lockSimple,
        colour: 3,
        title: 'Privacy',
        status: 'Receipts on',
      ),
    ],
    share: const ShareCodeModel(link: 'helix.agiletechbd.com/u/hasan'),
  );

  testWidgets('the checkup shows only what needs attention', (tester) async {
    var fixed = 0;
    await show(
      tester,
      YouScreen(
        model: you(good: false),
        actions: YouActions(fixRecovery: () => fixed++),
      ),
    );
    expect(find.text('recovery needs you'), findsOneWidget);
    expect(find.text('1 of 2'), findsNothing);
    expect(find.text('0 of 2'), findsOneWidget);
    await tester.tap(find.text('Fix'));
    expect(fixed, 1);
    await show(tester, YouScreen(model: you(good: true)));
    expect(
      find.text('Everything that keeps your account safe is in place.'),
      findsOneWidget,
    );
  });

  testWidgets('turning on app lock asks first', (tester) async {
    var on = 0;
    await show(
      tester,
      YouScreen(
        model: you(good: false),
        actions: YouActions(
          turnOnAppLock: () async {
            on++;
            return null;
          },
        ),
      ),
    );
    await tester.tap(find.text('Turn on'));
    await tester.pumpAndSettle();
    expect(find.text('Turn on app lock?'), findsOneWidget);
    await tester.tap(find.text('Turn on').last);
    await tester.pumpAndSettle();
    expect(on, 1);
  });

  testWidgets('tiles and search open topics', (tester) async {
    final opened = <YouTopic>[];
    await show(
      tester,
      YouScreen(
        model: you(good: true),
        actions: YouActions(openTopic: opened.add),
      ),
    );
    await tester.tap(find.text('Privacy'));
    await tester.tap(find.byTooltip('Search settings'));
    await tester.pump();
    await tester.enterText(find.byType(EditableText), 'pass');
    await tester.pump();
    await tester.tap(find.text('Change password'));
    expect(opened, [YouTopic.privacy, YouTopic.password]);
  });

  testWidgets('the share sheet shows the link', (tester) async {
    await show(
      tester,
      YouScreen(model: you(good: true), start: const YouStart(share: true)),
    );
    await tester.pumpAndSettle();
    expect(find.text('helix.agiletechbd.com/u/hasan'), findsOneWidget);
    expect(find.text('Scan someone’s code'), findsOneWidget);
  });

  test('~name rules', () {
    expect(orbitNameState(''), isNull);
    expect(orbitNameState('ab')!.$1, isFalse);
    expect(orbitNameState('1abc')!.$1, isFalse);
    expect(orbitNameState('ab-c')!.$1, isFalse);
    expect(orbitNameState('~Anna.K')!.$1, isTrue);
    expect(orbitNameState('hasan', current: 'hasan')!.$2, 'This is your ~name');
  });

  testWidgets('the profile editor previews as you type and saves', (
    tester,
  ) async {
    (String, String, String)? saved;
    await show(
      tester,
      ProfileEditScreen(
        model: const ProfileEditModel(
          name: 'Hasan',
          helixName: 'hasan',
          currentHelixName: 'hasan',
        ),
        actions: ProfileEditActions(
          onSave: (n, a, h) async {
            saved = (n, a, h);
            return '';
          },
        ),
      ),
    );
    await tester.enterText(find.byType(EditableText).first, 'Hasan K');
    await tester.pump();
    expect(find.text('Hasan K'), findsWidgets);
    await tester.tap(find.text('Save'));
    expect(saved, ('Hasan K', '', 'hasan'));
  });

  testWidgets('Appearance marks the current theme and picks another', (
    tester,
  ) async {
    String? picked;
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
        actions: AppearanceActions(onPick: (id) async => picked = id),
      ),
    );
    expect(find.bySemanticsLabel('Orbit theme, selected'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('${night.meta.name} theme'));
    expect(picked, 'night');
    await tester.pump();
    expect(find.text('Orbit Night theme on'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('privacy: choices update the preview at once', (tester) async {
    final changes = <(String, Object)>[];
    await show(
      tester,
      PrivacyScreen(
        model: const PrivacyModel(
          meName: 'Hasan',
          meAvatar: HelixAvatarModel(name: 'Hasan'),
        ),
        actions: PrivacyActions(
          onChanged: (k, v) async {
            changes.add((k, v));
            return null;
          },
        ),
      ),
    );
    expect(find.text('online'), findsOneWidget);
    await tester.tap(find.text('Nobody').at(1));
    await tester.pump();
    expect(find.text('online'), findsNothing);
    expect(changes, [('online', false)]);
  });

  testWidgets('notifications: an alert tile turns off', (tester) async {
    final changes = <(String, bool)>[];
    await show(
      tester,
      NotificationsScreen(
        model: const NotificationsModel(),
        actions: NotificationsActions(onChanged: (k, v) => changes.add((k, v))),
      ),
    );
    expect(find.text('3 of 3 alerts on · previews hidden'), findsOneWidget);
    await tester.tap(find.text('Calls'));
    await tester.pump();
    expect(find.text('2 of 3 alerts on · previews hidden'), findsOneWidget);
    expect(changes, [('calls', false)]);
  });

  testWidgets('account: sign out asks first', (tester) async {
    var out = 0;
    await show(
      tester,
      AccountScreen(
        model: const AccountModel(
          name: 'Hasan',
          avatar: HelixAvatarModel(name: 'Hasan'),
          hasPassword: false,
        ),
        actions: AccountActions(onSignOut: () => out++),
      ),
    );
    expect(find.text('Set a password'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Sign out'), 200);
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(out, 0);
    await tester.tap(find.text('Sign out').last);
    await tester.pumpAndSettle();
    expect(out, 1);
  });
}
