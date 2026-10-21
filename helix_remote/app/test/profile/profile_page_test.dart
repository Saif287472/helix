import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/features/profile/application/profile_providers.dart';
import 'package:helix_remote/features/profile/presentation/profile_page.dart';
import 'package:helix_remote_api/v2.dart' show ApiException, NetworkException;
import 'package:helix_remote_protocol/helix_remote_protocol.dart'
    show ErrorCode;
import 'package:orbit_ui/orbit_ui.dart' as orbit;

import '../support/a3b_fakes.dart';

/// A 1x1 PNG, enough for the avatar path.
final Uint8List _png = Uint8List.fromList(const [
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4, 0x89, 0x00, 0x00, 0x00,
  0x0d, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9c, 0x63, 0xf8, 0xff, 0xff, 0x3f,
  0x00, 0x05, 0xfe, 0x02, 0xfe, 0xa7, 0x35, 0x81, 0x84, 0x00, 0x00, 0x00,
  0x00, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82,
]);

/// A widget test that ends by taking the page down and letting the last Orbit
/// toast (4 s at most) go, so no timer is left pending.
void profileTest(String name, Future<void> Function(WidgetTester) body) =>
    testWidgets(name, (tester) async {
      await body(tester);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
    });

void main() {
  Future<FakeProfileGateway> open(
    WidgetTester tester, {
    FakeProfileGateway? gateway,
    FakeProfileImageSource? images,
    FakeAvatarStore? avatars,
  }) async {
    useTallWindow(tester);
    final profile = gateway ?? FakeProfileGateway();
    await pumpPage(
      tester,
      const ProfilePage(),
      overrides: a3bOverrides(
        profile: profile,
        imageSource: images,
        avatars: avatars,
      ),
    );
    await settle(tester);
    return profile;
  }

  /// The text in the Orbit field labelled [label].
  Finder field(String label) => find.descendant(
    of: find.widgetWithText(orbit.OrbitTextField, label),
    matching: find.byType(EditableText),
  );

  String textOf(WidgetTester tester, String label) =>
      tester.widget<EditableText>(field(label)).controller.text;

  profileTest('starts from the saved profile and says who sees what', (
    tester,
  ) async {
    await open(tester);
    expect(textOf(tester, 'Name'), 'Anna Khan');
    expect(textOf(tester, 'About'), 'Busy');
    expect(
      find.textContaining(RegExp('who sees what', caseSensitive: false)),
      findsOneWidget,
    );
    // ADR-030: the operator sees the name; about and photo are encrypted.
    expect(find.textContaining('and Orbit’s operator'), findsOneWidget);
    expect(find.text('Only people you message'), findsOneWidget);
    // The number is never shown complete.
    expect(find.textContaining('88017123'), findsNothing);
  });

  profileTest('saves the name and about together', (tester) async {
    final profile = await open(tester);
    await tester.enterText(field('Name'), '  Anna K  ');
    await tester.enterText(field('About'), 'At work');
    await tester.tap(find.text('Save'));
    await settle(tester);
    expect(profile.calls, contains('save:Anna K:At work'));
    expect(find.text('Profile saved'), findsOneWidget);
  });

  profileTest('an empty name is refused before anything is sent', (
    tester,
  ) async {
    final profile = await open(tester);
    await tester.enterText(field('Name'), '   ');
    await tester.tap(find.text('Save'));
    await settle(tester);
    expect(find.text('Enter the name people should see.'), findsOneWidget);
    expect(profile.calls.where((c) => c.startsWith('save')), isEmpty);
  });

  profileTest('offline: save fails with words, not an exception', (
    tester,
  ) async {
    final profile = FakeProfileGateway()..saveFails = const NetworkException();
    await open(tester, gateway: profile);
    await tester.tap(find.text('Save'));
    await settle(tester);
    expect(find.textContaining('You are offline'), findsOneWidget);
    expect(find.textContaining('NetworkException'), findsNothing);
  });

  group('~Orbit name', () {
    profileTest('Save claims a normalised name with the profile', (
      tester,
    ) async {
      final profile = await open(tester);
      await tester.enterText(field('~Orbit name'), 'Anna.K2');
      await tester.tap(find.text('Save'));
      await settle(tester);
      expect(profile.calls, contains('helix:anna.k2'));
      expect(find.text('Profile saved'), findsOneWidget);
    });

    for (final (input, message) in [
      ('ab', 'Names are at least 3 characters.'),
      ('1abc', 'Names start with a letter.'),
      ('an na', 'Use only letters, numbers, dots and underscores.'),
    ]) {
      profileTest('"$input" is refused locally', (tester) async {
        final profile = await open(tester);
        await tester.enterText(field('~Orbit name'), input);
        await tester.pump();
        expect(find.text(message), findsOneWidget);
        await tester.tap(find.text('Save'));
        await settle(tester);
        expect(find.text('Fix your ~name first'), findsOneWidget);
        expect(profile.calls.where((c) => c.startsWith('helix')), isEmpty);
      });
    }

    profileTest(
      'the server refusing a name (taken or staff-like) is explained',
      (tester) async {
        final profile = FakeProfileGateway()
          ..helixNameFails = const ApiException(
            status: 409,
            code: ErrorCode.nameTaken,
          );
        await open(tester, gateway: profile);
        await tester.enterText(field('~Orbit name'), 'support_team');
        await tester.tap(find.text('Save'));
        await settle(tester);
        expect(find.text(helixNameUnavailable), findsOneWidget);
        expect(find.text('Profile saved'), findsNothing);
      },
    );

    profileTest('removing a name asks first', (tester) async {
      final profile = await open(tester);
      await reveal(tester, find.text('Remove my ~name'));
      await tester.tap(find.text('Remove my ~name'));
      await settle(tester);
      expect(find.text('Remove your ~name?'), findsOneWidget);
      await tester.tap(find.text('Remove').last);
      await settle(tester);
      expect(profile.calls, contains('helix:clear'));
    });
  });

  group('photo', () {
    profileTest('choosing a photo keeps it on this phone', (tester) async {
      final avatars = FakeAvatarStore();
      await open(
        tester,
        images: FakeProfileImageSource(picked: _png),
        avatars: avatars,
      );
      await tester.tap(find.text('Choose a photo'));
      await settle(tester);
      expect(avatars.saved, _png);
      expect(find.text('Photo updated.'), findsOneWidget);
      expect(find.text('Change photo'), findsOneWidget);

      await tester.tap(find.text('Remove'));
      await settle(tester);
      expect(avatars.saved, isNull);
    });

    profileTest('backing out of the picker changes nothing', (tester) async {
      final avatars = FakeAvatarStore();
      await open(tester, images: FakeProfileImageSource(), avatars: avatars);
      await tester.tap(find.text('Choose a photo'));
      await settle(tester);
      expect(avatars.saved, isNull);
      expect(find.text('Photo updated.'), findsNothing);
    });

    profileTest('a file that is not a picture is explained', (tester) async {
      await open(tester, images: FakeProfileImageSource(fails: true));
      await tester.tap(find.text('Choose a photo'));
      await settle(tester);
      expect(
        find.textContaining('could not be read as a picture'),
        findsOneWidget,
      );
    });
  });

  group('rules', () {
    test('~name normalisation and validation match the server pattern', () {
      expect(ProfileRules.normaliseHelixName(' ~Anna.K '), 'anna.k');
      expect(ProfileRules.helixNameProblem('anna.k'), isNull);
      expect(ProfileRules.helixNameProblem('a' * 33), isNotNull);
      expect(ProfileRules.helixNameProblem(''), isNotNull);
    });

    test('name and about limits', () {
      expect(ProfileRules.nameProblem('Anna'), isNull);
      expect(ProfileRules.nameProblem('a' * 51), isNotNull);
      expect(ProfileRules.aboutProblem('a' * 140), isNotNull);
    });
  });

  profileTest('works at twice the text size', (tester) async {
    await pumpPage(
      tester,
      const ProfilePage(),
      overrides: a3bOverrides(profile: FakeProfileGateway()),
      textScale: 2,
    );
    await settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Edit profile'), findsWidgets);
  });
}
