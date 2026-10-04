import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/features/profile/application/profile_providers.dart';
import 'package:helix_remote/features/profile/presentation/profile_page.dart';
import 'package:helix_remote_api/v2.dart' show ApiException, NetworkException;
import 'package:helix_remote_protocol/helix_remote_protocol.dart'
    show ErrorCode;

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

  Finder field(String label) => find.widgetWithText(TextField, label);

  testWidgets('starts from the saved profile and says who can see what', (
    tester,
  ) async {
    await open(tester);
    expect(
      tester.widget<TextField>(field('Name')).controller!.text,
      'Anna Khan',
    );
    expect(tester.widget<TextField>(field('About')).controller!.text, 'Busy');
    expect(
      find.textContaining('Only people you have messaged'),
      findsOneWidget,
    );
    expect(
      find.textContaining('stored on the server, not encrypted'),
      findsOneWidget,
    );
    expect(find.text('+88017*****01'), findsOneWidget);
    // The number is masked, never complete.
    expect(find.textContaining('88017123'), findsNothing);
  });

  testWidgets('saves the name and about together', (tester) async {
    final profile = await open(tester);
    await tester.enterText(field('Name'), '  Anna K  ');
    await tester.enterText(field('About'), 'At work');
    await tester.tap(find.text('Save'));
    await settle(tester);
    expect(profile.calls, contains('save:Anna K:At work'));
    expect(find.text('Saved.'), findsOneWidget);
  });

  testWidgets('an empty name is refused before anything is sent', (
    tester,
  ) async {
    final profile = await open(tester);
    await tester.enterText(field('Name'), '   ');
    await tester.tap(find.text('Save'));
    await settle(tester);
    expect(find.text('Enter the name people should see.'), findsOneWidget);
    expect(profile.calls.where((c) => c.startsWith('save')), isEmpty);
  });

  testWidgets('offline: save fails with words, not an exception', (
    tester,
  ) async {
    final profile = FakeProfileGateway()..saveFails = const NetworkException();
    await open(tester, gateway: profile);
    await tester.tap(find.text('Save'));
    await settle(tester);
    expect(find.textContaining('You are offline'), findsOneWidget);
    expect(find.textContaining('NetworkException'), findsNothing);
  });

  group('~Helix name', () {
    testWidgets('claims a normalised name', (tester) async {
      final profile = await open(tester);
      await tester.enterText(field('Your ~name'), '~Anna.K2');
      await tester.tap(find.text('Save ~name'));
      await settle(tester);
      expect(profile.calls, contains('helix:anna.k2'));
      expect(find.text('Your ~name is saved.'), findsOneWidget);
    });

    for (final (input, message) in [
      ('ab', 'Names are at least 3 characters.'),
      ('1abc', 'Names start with a letter.'),
      ('an na', 'Use only letters, numbers, dots and underscores.'),
    ]) {
      testWidgets('"$input" is refused locally', (tester) async {
        final profile = await open(tester);
        await tester.enterText(field('Your ~name'), input);
        await tester.tap(find.text('Save ~name'));
        await settle(tester);
        expect(find.text(message), findsOneWidget);
        expect(profile.calls.where((c) => c.startsWith('helix')), isEmpty);
      });
    }

    testWidgets(
      'the server refusing a name (taken or staff-like) is explained',
      (tester) async {
        final profile = FakeProfileGateway()
          ..helixNameFails = const ApiException(
            status: 409,
            code: ErrorCode.nameTaken,
          );
        await open(tester, gateway: profile);
        await tester.enterText(field('Your ~name'), 'support_team');
        await tester.tap(find.text('Save ~name'));
        await settle(tester);
        expect(find.text(helixNameUnavailable), findsOneWidget);
        expect(find.textContaining('mistaken for Helix staff'), findsWidgets);
      },
    );

    testWidgets('removing a name asks first', (tester) async {
      final profile = await open(tester);
      await reveal(tester, find.text('Remove my ~name'));
      await tester.tap(find.text('Remove my ~name'));
      await settle(tester);
      expect(find.text('Remove your ~name?'), findsOneWidget);
      await tester.tap(find.text('Remove'));
      await settle(tester);
      expect(profile.calls, contains('helix:clear'));
    });
  });

  group('photo', () {
    testWidgets('choosing a photo keeps it on this phone', (tester) async {
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
      expect(find.text('Remove photo'), findsOneWidget);
      expect(find.textContaining('kept on this phone'), findsOneWidget);

      await tester.tap(find.text('Remove photo'));
      await settle(tester);
      expect(avatars.saved, isNull);
    });

    testWidgets('backing out of the picker changes nothing', (tester) async {
      final avatars = FakeAvatarStore();
      await open(tester, images: FakeProfileImageSource(), avatars: avatars);
      await tester.tap(find.text('Choose a photo'));
      await settle(tester);
      expect(avatars.saved, isNull);
      expect(find.text('Photo updated.'), findsNothing);
    });

    testWidgets('a file that is not a picture is explained', (tester) async {
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

  testWidgets('works at twice the text size', (tester) async {
    await pumpPage(
      tester,
      const ProfilePage(),
      overrides: a3bOverrides(profile: FakeProfileGateway()),
      textScale: 2,
    );
    await settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Profile'), findsOneWidget);
  });
}
