import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/app/helix_code.dart';
import 'package:helix_remote/app/password_vault.dart';
import 'package:helix_remote/app/remote_rest_client.dart';
import 'package:helix_remote/screens/setup/setup_choices.dart';
import 'package:helix_remote/screens/setup/setup_screen.dart';
import 'package:helix_remote/screens/setup/state/onboarding_notifier.dart';
import 'package:helix_remote/screens/setup/state/onboarding_state.dart';
import 'package:helix_remote/screens/setup/widgets/sign_in_frame.dart';
import 'package:helix_remote_api/api/rest_client.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

import 'support/group_call_rest_stubs.dart';

const _personal = 'https://chat.example.org';

/// One fake server (or several - it records which URL each client was made
/// for) behind every sign-in call.
class _SignInServer with GroupCallRestStubs implements HelixRemoteRestClient {
  _SignInServer({
    this.hasPassword = false,
    this.accountExists = false,
    this.phoneMatches = true,
    this.smsRequired = true,
    this.inviteValid = true,
    this.recoveryValid = true,
    this.correctAuthKey,
  });

  bool hasPassword;
  bool accountExists;
  bool phoneMatches;
  bool smsRequired;
  bool inviteValid;
  bool recoveryValid;
  String? correctAuthKey;
  int otpRequests = 0;
  final recoveryLookups = <String?>[];

  static const kdfSalt = 'c2FsdHNhbHRzYWx0c2FsdA';

  @override
  Future<Map<String, dynamic>> fetchDiscoverySalt() async => {
    'salt': base64.encode(List<int>.filled(32, 1)),
  };

  @override
  Future<Map<String, dynamic>> getPasswordParams({
    required String phoneHash,
  }) async => {
    'account_exists': accountExists || hasPassword,
    'has_password': hasPassword,
    if (hasPassword) ...{
      'kdf_params': const PasswordKdfParams().toJson(),
      'kdf_salt': kdfSalt,
    },
  };

  @override
  Future<void> verifyPassword({
    required String phoneHash,
    required String authKey,
  }) async {
    if (authKey != correctAuthKey) {
      throw const RemoteRestException(
        message: '{"error":"Wrong","code":"password_incorrect"}',
        statusCode: 403,
        serverCode: 'password_incorrect',
        failureKind: RemoteRestFailureKind.http,
      );
    }
  }

  @override
  Future<Map<String, dynamic>> requestPhoneOtp({
    required String phoneHash,
    required String phoneNumber,
  }) async {
    otpRequests++;
    return {'challenge_id': 'otp_test'};
  }

  @override
  Future<Map<String, dynamic>> verifyPhoneOtp({
    required String phoneHash,
    required String otpCode,
    String? challengeId,
  }) async {
    if (otpCode != '123456') {
      throw const RemoteRestException(
        message: '{"error":"Incorrect verification code","code":"invalid_otp"}',
        statusCode: 400,
        serverCode: RemoteApiErrorCodes.invalidOtp,
        failureKind: RemoteRestFailureKind.http,
      );
    }
    return {'valid': true};
  }

  @override
  Future<Map<String, dynamic>> lookupInvite({
    required String inviteCode,
  }) async => inviteValid
      ? {'valid': true, 'server_name': 'Family server'}
      : {'valid': false, 'reason': 'expired'};

  @override
  Future<Map<String, dynamic>> lookupRecovery({
    required String accountId,
    required String recoveryCode,
    String? phoneHash,
  }) async {
    recoveryLookups.add(phoneHash);
    if (!recoveryValid) return {'valid': false, 'reason': 'invalid'};
    return {
      'valid': true,
      'server_name': 'Family server',
      'sms_required': smsRequired,
      if (phoneHash != null) 'phone_matches': phoneMatches,
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

String get _recoveryCode => encodeHelixRecoveryCode(
  serverUrl: _personal,
  accountId: 'acct_1',
  recoveryCode: 'rec_secret',
);

String get _inviteCode =>
    encodeHelixInviteCode(serverUrl: _personal, inviteCode: 'INV-1');

OnboardingNotifier _notifier(_SignInServer server, {List<String>? urls}) =>
    OnboardingNotifier(
      clientFactory: (url) {
        urls?.add(url);
        return server;
      },
    );

Future<String> _authKey(String password) async =>
    (await PasswordVault.deriveKeys(
      password: password,
      salt: _SignInServer.kdfSalt,
      params: const PasswordKdfParams(),
    )).authKey;

void main() {
  group('Global sign-in', () {
    test('opens on the phone page, with nothing to wait for', () {
      final n = OnboardingNotifier();
      expect(n.state.mode, SetupMode.global);
      expect(n.state.page, SetupPage.phone);
      expect(n.state.isLoading, isFalse);
    });

    test(
      'a number with a password goes to the password page, no SMS',
      () async {
        final server = _SignInServer(hasPassword: true);
        final n = _notifier(server)..updatePhoneNumber('1700000000');

        expect(await n.submitPhone(), isTrue);

        expect(n.state.page, SetupPage.password);
        expect(server.otpRequests, 0);
      },
    );

    test('the right password signs in with keys, never the password', () async {
      final server = _SignInServer(
        hasPassword: true,
        correctAuthKey: await _authKey('correct horse'),
      );
      final n = _notifier(server)..updatePhoneNumber('1700000000');
      await n.submitPhone();

      n.updatePassword('correct horse');
      expect(await n.signInWithPassword(), isTrue);

      expect(n.state.isComplete, isTrue);
      expect(n.state.password, isEmpty);
      final choice = n.completedChoice! as ServerPasswordChoice;
      expect(choice.keys.authKey, server.correctAuthKey);
      expect(choice.serverUrl, isNot(_personal));
    });

    test('a wrong password stays on the page with a clear message', () async {
      final server = _SignInServer(hasPassword: true, correctAuthKey: 'x');
      final n = _notifier(server)..updatePhoneNumber('1700000000');
      await n.submitPhone();

      n.updatePassword('wrong password');
      expect(await n.signInWithPassword(), isFalse);

      expect(n.state.page, SetupPage.password);
      expect(n.state.errorMessage, contains('password is not right'));
    });

    test('"Forgot password" sends the SMS code instead', () async {
      final server = _SignInServer(hasPassword: true);
      final n = _notifier(server)..updatePhoneNumber('1700000000');
      await n.submitPhone();

      await n.forgotPassword();

      expect(server.otpRequests, 1);
      expect(n.state.page, SetupPage.otp);
    });

    test('a new number: SMS code, then name and terms', () async {
      final server = _SignInServer();
      final n = _notifier(server)..updatePhoneNumber('1700000000');

      await n.submitPhone();
      expect(n.state.page, SetupPage.otp);

      n.updateOtpCode('000000');
      expect(await n.submitOtp(), isFalse);
      expect(n.state.page, SetupPage.otp);

      n.updateOtpCode('123456');
      expect(await n.submitOtp(), isTrue);
      expect(n.state.page, SetupPage.name);
      expect(n.state.accountExists, isFalse);

      n.updateDisplayName('Alice');
      expect(await n.completeSetup(), isFalse, reason: 'terms not accepted');
      n.setTosAccepted(true);
      expect(await n.completeSetup(), isTrue);

      final choice = n.completedChoice! as ServerInviteChoice;
      expect(choice.inviteCode, isEmpty);
      expect(choice.displayName, 'Alice');
      expect(choice.otpCode, '123456');
      expect(choice.tosAccepted, isTrue);
    });

    test('an existing account without a password skips the name', () async {
      final server = _SignInServer(accountExists: true);
      final n = _notifier(server)..updatePhoneNumber('1700000000');
      await n.submitPhone();
      n.updateOtpCode('123456');
      await n.submitOtp();

      expect(n.state.page, SetupPage.name);
      expect(n.state.accountExists, isTrue);
    });
  });

  group('Advanced mode', () {
    test('an invite code goes to the phone page of that server', () async {
      final urls = <String>[];
      final server = _SignInServer();
      final n = _notifier(server, urls: urls)..openAdvancedMode();
      expect(n.state.page, SetupPage.code);

      n.updateCodeString(_inviteCode);
      expect(n.detectedCodeType, CodeType.invitation);
      expect(await n.submitCode(), isTrue);

      expect(n.state.page, SetupPage.phone);
      expect(n.state.codeType, CodeType.invitation);
      expect(n.state.serverName, 'Family server');
      expect(n.serverUrl, _personal);
      expect(urls, everyElement(_personal));
    });

    test('an expired invite says so and stays on the code page', () async {
      final n = _notifier(_SignInServer(inviteValid: false))
        ..openAdvancedMode(code: _inviteCode);

      expect(await n.submitCode(), isFalse);

      expect(n.state.page, SetupPage.code);
      expect(n.state.errorMessage, contains('expired'));
    });

    test(
      'a used or expired recovery code is refused on the code page',
      () async {
        final n = _notifier(_SignInServer(recoveryValid: false))
          ..openAdvancedMode(code: _recoveryCode);

        expect(await n.submitCode(), isFalse);

        expect(n.state.page, SetupPage.code);
        expect(n.state.errorMessage, contains('recovery code is not valid'));
      },
    );

    test('something that is not a code is refused', () async {
      final n = _notifier(_SignInServer())..openAdvancedMode(code: 'hello');
      expect(await n.submitCode(), isFalse);
      expect(n.state.errorMessage, contains('not an invite or recovery code'));
    });

    test('a recovery code with a password signs in without a reset', () async {
      final server = _SignInServer(
        hasPassword: true,
        correctAuthKey: await _authKey('correct horse'),
      );
      final n = _notifier(server)..openAdvancedMode(code: _recoveryCode);
      expect(n.detectedCodeType, CodeType.recovery);

      expect(await n.submitCode(), isTrue);
      expect(n.state.isRecovery, isTrue);
      expect(n.state.page, SetupPage.phone);

      n.updatePhoneNumber('1700000000');
      expect(await n.submitPhone(), isTrue);
      expect(server.recoveryLookups.last, isNotNull, reason: 'phone checked');
      expect(n.state.page, SetupPage.password);

      n.updatePassword('correct horse');
      expect(await n.signInWithPassword(), isTrue);
      final choice = n.completedChoice! as ServerPasswordChoice;
      expect(choice.serverUrl, _personal);
    });

    test('a recovery code for someone else\'s number is refused', () async {
      final n = _notifier(_SignInServer(phoneMatches: false))
        ..openAdvancedMode(code: _recoveryCode);
      await n.submitCode();
      n.updatePhoneNumber('1700000000');

      expect(await n.submitPhone(), isFalse);

      expect(n.state.page, SetupPage.phone);
      expect(n.state.errorMessage, contains('does not belong'));
    });

    test('a recovery without a password resets with the SMS code', () async {
      final server = _SignInServer();
      final n = _notifier(server)..openAdvancedMode(code: _recoveryCode);
      await n.submitCode();
      n.updatePhoneNumber('1700000000');
      await n.submitPhone();
      expect(n.state.page, SetupPage.otp);

      n.updateOtpCode('123456');
      expect(await n.submitOtp(), isTrue);

      final choice = n.completedChoice! as ServerRecoveryChoice;
      expect(choice.accountId, 'acct_1');
      expect(choice.recoveryCode, 'rec_secret');
      expect(choice.otpCode, '123456');
      expect(choice.otpChallengeId, 'otp_test');
      expect(choice.phoneHash, isNotEmpty);
      expect(choice.phoneNumber, '+8801700000000');
    });

    test('a server without SMS resets straight after the phone', () async {
      final server = _SignInServer(smsRequired: false);
      final n = _notifier(server)..openAdvancedMode(code: _recoveryCode);
      await n.submitCode();
      n.updatePhoneNumber('1700000000');

      expect(await n.submitPhone(), isTrue);

      expect(server.otpRequests, 0);
      expect(n.completedChoice, isA<ServerRecoveryChoice>());
    });

    test('an invite for a number that already has an account asks for a '
        'recovery code', () async {
      final n = _notifier(_SignInServer(accountExists: true))
        ..openAdvancedMode(code: _inviteCode);
      await n.submitCode();
      n.updatePhoneNumber('1700000000');

      expect(await n.submitPhone(), isFalse);
      expect(n.state.showPhoneRecoveryPrompt, isTrue);

      n.beginPhoneRecovery();
      expect(n.state.page, SetupPage.code);
      expect(n.state.codeString, isEmpty);
    });

    test('a link opens advanced mode and checks its code at once', () async {
      final n = _notifier(_SignInServer());
      expect(await n.openWithCode(_inviteCode), isTrue);
      expect(n.state.mode, SetupMode.advanced);
      expect(n.state.page, SetupPage.phone);
    });

    test('back from the code page returns to the Global page', () {
      final n = _notifier(_SignInServer())..openAdvancedMode();
      n.goBack();
      expect(n.state.mode, SetupMode.global);
      expect(n.state.page, SetupPage.phone);
    });
  });

  group('SetupScreen', () {
    Future<void> pump(WidgetTester tester, OnboardingNotifier notifier) =>
        tester.pumpWidget(
          MaterialApp(
            theme: HelixThemes.light(),
            home: SetupScreen(notifier: notifier),
          ),
        );

    testWidgets('the Global page is just a phone number and Next', (
      tester,
    ) async {
      await pump(tester, OnboardingNotifier());

      expect(find.text('Sign in'), findsOneWidget);
      expect(find.byKey(const ValueKey('phone-field')), findsOneWidget);
      expect(find.text('Next'), findsOneWidget);
      expect(find.text('Advanced mode'), findsNothing);
      expect(find.textContaining('Host your own'), findsNothing);
      expect(find.byTooltip('Back'), findsNothing);
    });

    testWidgets('three taps in the corner reveal Advanced mode; a fourth '
        'opens it', (tester) async {
      await pump(tester, OnboardingNotifier());
      final corner = find.byKey(const ValueKey('advanced-mode-corner'));

      await tester.tap(corner);
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.tap(corner);
      await tester.pump(const Duration(milliseconds: 1500));
      expect(find.text('Advanced mode'), findsNothing);
      await tester.tap(corner);
      await tester.pump();
      expect(find.text('Advanced mode'), findsOneWidget);

      await tester.tap(find.text('Advanced mode'));
      await tester.pumpAndSettle();
      expect(find.text('Personal server'), findsOneWidget);
      expect(find.byKey(const ValueKey('code-field')), findsOneWidget);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Sign in'), findsOneWidget);
    });

    testWidgets('taps too far apart do not count, and the button hides again', (
      tester,
    ) async {
      await pump(tester, OnboardingNotifier());
      final corner = find.byKey(const ValueKey('advanced-mode-corner'));

      await tester.tap(corner);
      await tester.tap(corner);
      await tester.pump(
        AdvancedModeCorner.tapWindow + const Duration(milliseconds: 100),
      );
      await tester.tap(corner);
      await tester.pump();
      expect(find.text('Advanced mode'), findsNothing);

      await tester.tap(corner);
      await tester.tap(corner);
      await tester.pump();
      expect(find.text('Advanced mode'), findsOneWidget);
      await tester.pump(
        AdvancedModeCorner.tapWindow + const Duration(milliseconds: 100),
      );
      expect(find.text('Advanced mode'), findsNothing);
    });

    testWidgets('the name page carries the terms and the legal documents', (
      tester,
    ) async {
      final n = _notifier(_SignInServer())..updatePhoneNumber('1700000000');
      await n.submitPhone();
      n.updateOtpCode('123456');
      await n.submitOtp();
      await pump(tester, n);

      expect(find.byKey(const ValueKey('name-field')), findsOneWidget);
      final create = find.widgetWithText(FilledButton, 'Create account');
      expect(tester.widget<FilledButton>(create).onPressed, isNull);

      await tester.tap(find.byKey(const ValueKey('terms-checkbox')));
      await tester.pump();
      expect(tester.widget<FilledButton>(create).onPressed, isNotNull);

      await tester.ensureVisible(
        find.text('Read the Terms and Privacy Policy'),
      );
      await tester.tap(find.text('Read the Terms and Privacy Policy'));
      await tester.pumpAndSettle();
      expect(find.text('Helix Global Terms of Service'), findsOneWidget);
    });
  });
}
