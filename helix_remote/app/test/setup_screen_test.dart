import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote_api/api/rest_client.dart';
import 'package:helix_remote/app/remote_config.dart';
import 'package:helix_remote/l10n/helix_localizations.dart';
import 'package:helix_remote/screens/invite_entry_screen.dart';
import 'package:helix_remote/screens/server_choice_screen.dart';
import 'package:helix_remote/screens/setup/setup_screen.dart';
import 'package:helix_remote/screens/setup/state/onboarding_notifier.dart';
import 'package:helix_remote/screens/setup/state/onboarding_state.dart';

void main() {
  group('OnboardingNotifier & State', () {
    test('initializes with splash and advances to serverSelection', () async {
      final notifier = OnboardingNotifier(autoStartLaunch: false);
      expect(notifier.state.step, OnboardingStep.splash);
      expect(notifier.state.serverType, ServerType.global);

      notifier.updateState(
        (s) => s.copyWith(step: OnboardingStep.serverSelection),
      );
      expect(notifier.state.step, OnboardingStep.serverSelection);
    });

    test('Path A: Global server navigation and validation', () async {
      final notifier = OnboardingNotifier(
        autoStartLaunch: false,
        client: _OnboardingRestClient(),
      );
      notifier.updateState(
        (s) => s.copyWith(step: OnboardingStep.serverSelection),
      );

      notifier.proceedFromServerSelection();
      expect(notifier.state.globalSubStep, GlobalSubStep.phone);

      // Validation failure on short phone
      notifier.updatePhoneNumber('12');
      final failOtp = await notifier.requestOtp();
      expect(failOtp, isFalse);
      expect(notifier.state.errorMessage, isNotNull);

      // Valid phone request
      notifier.updatePhoneNumber('1712345678');
      final successOtp = await notifier.requestOtp();
      expect(successOtp, isTrue);
      expect(notifier.state.globalSubStep, GlobalSubStep.otp);

      // OTP verification bypass - allows any code or empty
      notifier.updateOtpCode('123');
      final bypassVerify = await notifier.verifyOtp();
      expect(bypassVerify, isTrue);
      expect(notifier.state.globalSubStep, GlobalSubStep.name);

      // Complete setup after accepting the Global legal documents.
      notifier.updateDisplayName('Alice');
      notifier.setTosAccepted(true);
      final complete = await notifier.completeSetup();
      expect(complete, isTrue);
      expect(notifier.state.isComplete, isTrue);
      final choice = notifier.completedChoice as ServerInviteChoice?;
      expect(choice?.serverUrl, kHelixGlobalServerUrl);
      expect(choice?.phoneNumber, contains('1712345678'));
      expect(choice?.tosAccepted, isTrue);
      expect(choice?.tosVersion, isNotEmpty);
    });

    test('Global registration cannot complete before ToS acceptance', () async {
      final notifier =
          OnboardingNotifier(
            autoStartLaunch: false,
            client: _OnboardingRestClient(),
          )..updateState(
            (s) => s.copyWith(
              step: OnboardingStep.serverSelection,
              globalSubStep: GlobalSubStep.name,
              phoneNumber: '1712345678',
              displayName: 'Alice',
            ),
          );

      final complete = await notifier.completeSetup();
      expect(complete, isFalse);
      expect(notifier.state.errorMessage, contains('accept'));
      expect(notifier.state.isComplete, isFalse);
    });

    test('Path B: Others option navigation (Host & Join)', () async {
      final notifier = OnboardingNotifier(autoStartLaunch: false);
      notifier.updateState(
        (s) => s.copyWith(
          step: OnboardingStep.serverSelection,
          serverType: ServerType.others,
        ),
      );

      // Sub-tab Host guide
      notifier.setOthersOption(OthersOption.host);
      expect(notifier.state.othersOption, OthersOption.host);
      expect(notifier.state.hostGuideStep, 0);

      notifier.updateHostGuideStep(2);
      expect(notifier.state.hostGuideStep, 2);

      // Sub-tab Join personal server
      notifier.setOthersOption(OthersOption.join);
      expect(notifier.state.othersOption, OthersOption.join);
      expect(notifier.state.joinSubStep, JoinSubStep.code);

      notifier.updateCodeString('INV-9921');
      final ok = await notifier.resolveCode();
      expect(ok, isTrue);
      expect(notifier.state.codeType, CodeType.invitation);
      expect(notifier.state.joinSubStep, JoinSubStep.phone);
    });

    test('duplicate-phone recovery prompt routes to recovery code entry', () {
      final notifier = OnboardingNotifier(autoStartLaunch: false)
        ..beginPhoneRecovery(serverUrl: 'https://global.example');

      expect(notifier.state.step, OnboardingStep.codeEntry);
      expect(notifier.state.serverType, ServerType.others);
      expect(notifier.state.codeType, CodeType.recovery);
      expect(notifier.state.serverNodeUrl, 'https://global.example');
    });

    test('Recovery code routing', () async {
      final notifier = OnboardingNotifier(autoStartLaunch: false);
      notifier.updateState(
        (s) => s.copyWith(
          step: OnboardingStep.serverSelection,
          serverType: ServerType.others,
          othersOption: OthersOption.join,
        ),
      );

      notifier.updateCodeString('REC-1122-RESTORE');
      final ok = await notifier.resolveCode();
      expect(ok, isTrue);
      expect(notifier.state.codeType, CodeType.recovery);
      expect(notifier.state.joinSubStep, JoinSubStep.recoverySync);
    });

    test('continue offline choice', () {
      final notifier = OnboardingNotifier(autoStartLaunch: false);
      notifier.chooseOffline();
      expect(notifier.continueOfflineChosen, isTrue);
      expect(notifier.state.isComplete, isTrue);
    });
  });

  group('SetupScreen Widget', () {
    testWidgets('renders splash step with status text', (tester) async {
      final notifier = OnboardingNotifier(autoStartLaunch: false);
      notifier.updateState(
        (s) => s.copyWith(
          step: OnboardingStep.splash,
          loadingStatus: 'Deploying Helix…',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: HelixLocalizations.localizationsDelegates,
          supportedLocales: HelixLocalizations.supportedLocales,
          home: SetupScreen(notifier: notifier),
        ),
      );

      expect(find.text('HELIX'), findsOneWidget);
      expect(find.text('The privacy you deserve'), findsOneWidget);
      expect(find.text('Deploying Helix…'), findsOneWidget);
    });

    testWidgets(
      'renders server selection step and responds to offline choice',
      (tester) async {
        final notifier = OnboardingNotifier(autoStartLaunch: false);
        notifier.updateState(
          (s) => s.copyWith(
            step: OnboardingStep.serverSelection,
            serverType: ServerType.global,
          ),
        );

        Object? choice;
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: HelixLocalizations.localizationsDelegates,
            supportedLocales: HelixLocalizations.supportedLocales,
            home: SetupScreen(notifier: notifier, onChoice: (c) => choice = c),
          ),
        );

        expect(find.text('Helix Global Server'), findsOneWidget);
        expect(find.text('Others'), findsOneWidget);
        expect(find.text('Request OTP'), findsOneWidget);
        expect(find.text('Continue offline for now'), findsOneWidget);

        await tester.ensureVisible(find.text('Continue offline for now'));
        await tester.tap(find.text('Continue offline for now'));
        await tester.pumpAndSettle();

        expect(choice, isA<ContinueOfflineChoice>());
      },
    );

    testWidgets('advances to otp step on request and handles back button', (
      tester,
    ) async {
      final notifier = OnboardingNotifier(
        autoStartLaunch: false,
        client: _OnboardingRestClient(),
      );
      notifier.updateState(
        (s) => s.copyWith(
          step: OnboardingStep.serverSelection,
          serverType: ServerType.global,
          phoneNumber: '1712345678',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: HelixLocalizations.localizationsDelegates,
          supportedLocales: HelixLocalizations.supportedLocales,
          home: SetupScreen(notifier: notifier),
        ),
      );

      expect(find.text('Please enter your phone number'), findsOneWidget);
      expect(find.text('Request OTP'), findsOneWidget);

      // Tap Request OTP to go to global otp
      await tester.ensureVisible(find.text('Request OTP'));
      await tester.tap(find.text('Request OTP'));
      await tester.pumpAndSettle();

      expect(find.text('Enter verification code'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);

      // Tap back button
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      expect(find.text('Please enter your phone number'), findsOneWidget);
    });

    testWidgets('Global final step exposes the legal acceptance sheet', (
      tester,
    ) async {
      final notifier =
          OnboardingNotifier(
            autoStartLaunch: false,
            client: _OnboardingRestClient(),
          )..updateState(
            (s) => s.copyWith(
              step: OnboardingStep.serverSelection,
              serverType: ServerType.global,
              globalSubStep: GlobalSubStep.name,
              displayName: 'Alice',
            ),
          );

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: HelixLocalizations.localizationsDelegates,
          supportedLocales: HelixLocalizations.supportedLocales,
          home: SetupScreen(notifier: notifier),
        ),
      );

      expect(
        find.text('I agree to the Terms of Service and Privacy Policy'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Read the legal documents'));
      await tester.tap(find.text('Read the legal documents'));
      await tester.pumpAndSettle();
      expect(find.text('Helix Global Terms of Service'), findsOneWidget);
      await tester.tap(find.text('Privacy'));
      await tester.pumpAndSettle();
      expect(find.text('Helix Global Privacy Policy'), findsOneWidget);
    });

    testWidgets('renders Others tab with segmented sub-tabs and code entry', (
      tester,
    ) async {
      final notifier = OnboardingNotifier(autoStartLaunch: false);
      notifier.updateState(
        (s) => s.copyWith(
          step: OnboardingStep.serverSelection,
          serverType: ServerType.others,
          othersOption: OthersOption.join,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: HelixLocalizations.localizationsDelegates,
          supportedLocales: HelixLocalizations.supportedLocales,
          home: SetupScreen(notifier: notifier),
        ),
      );

      expect(find.text('Choose a custom server option:'), findsOneWidget);
      expect(find.text('Join a personal server'), findsOneWidget);
      expect(find.text('Host your own server'), findsOneWidget);
      expect(find.text('Enter invitation or recovery code'), findsOneWidget);
      expect(find.text('CODE INPUT'), findsOneWidget);
      expect(find.text('Verify & Connect'), findsOneWidget);
    });
  });
}

class _OnboardingRestClient implements HelixRemoteRestClient {
  @override
  Future<Map<String, dynamic>> autoIssueGlobalInvite() async => {
    'invite_code': 'INV-TEST',
  };

  @override
  Future<Map<String, dynamic>> fetchDiscoverySalt() async => {
    'salt': base64.encode(List<int>.filled(32, 1)),
  };

  @override
  Future<Map<String, dynamic>> requestPhoneOtp({
    required String phoneHash,
    required String phoneNumber,
  }) async => {};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
