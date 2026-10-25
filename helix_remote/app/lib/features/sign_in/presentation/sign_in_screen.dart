import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/features/sign_in/application/sign_in_controller.dart';
import 'package:helix_remote/features/sign_in/application/sign_in_countries.dart';
import 'package:helix_remote/features/sign_in/application/sign_in_state.dart';
import 'package:helix_remote/features/sign_in/application/sign_in_view.dart';
import 'package:helix_remote_domain/models.dart';
import 'package:orbit_ui/orbit_ui.dart' as orbit;

/// Sign-in: the Orbit screen (`orbit_ui`'s `SignInScreen`) on the app's
/// [SignInController].
///
/// A connector only: it turns [SignInState] into the screen's model and the
/// screen's actions into controller calls. Which step follows which, when
/// the Terms are required and what an error says all live in
/// `application/`, so the Global path and the personal-server path cannot
/// drift apart.
///
/// It builds with no arguments and no engine behind it, so a widget test can
/// put it on screen on its own.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  @override
  void initState() {
    super.initState();
    // A link that started the app is applied once, after the first frame, so
    // the provider exists and the screen does not build twice.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(signInControllerProvider.notifier).consumePendingCode();
      }
    });
  }

  /// Nothing is texted until the person has checked the number and agreed:
  /// a code goes to it, and the operator may charge for the message.
  ///
  /// Two ways in: the password page's "Forgot password?", where changing the
  /// number means going back to it, and the controller's own ask after it has
  /// checked the number and found no password to sign in with, where the page
  /// is still the number.
  void _confirmCode(
    String number, {
    required VoidCallback onCancel,
    required Future<bool> Function() onSend,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      orbit.showOrbitDialog(
        context,
        title: 'Send a code to $number?',
        text:
            'Check that this is your number. We will text a 6-digit code to '
            'it, and your mobile operator may charge you for the message.',
        actions: [
          orbit.OrbitDialogAction('Change number', onPressed: onCancel),
          orbit.OrbitDialogAction(
            'Send the code',
            kind: orbit.OrbitButtonKind.primary,
            onPressed: onSend,
          ),
        ],
      );
    });
  }

  void _askBeforeTexting(String number) => _confirmCode(
    number,
    onCancel: ref
        .read(signInControllerProvider.notifier)
        .cancelCodeConfirmation,
    onSend: ref.read(signInControllerProvider.notifier).useCodeInstead,
  );

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(signInControllerProvider);
    final saved = ref.watch(signInSavedAccountsProvider);
    final c = ref.read(signInControllerProvider.notifier);
    // The number is checked on the server before the next page is chosen, so
    // the ask comes from the controller and this is the only place that draws.
    ref.listen(signInControllerProvider, (previous, next) {
      if (!next.askBeforeCode || (previous?.askBeforeCode ?? false)) return;
      _askBeforeTexting(next.phoneLabel);
    });
    return orbit.SignInScreen(
      // A new step is a new screen, so its fields start from the model.
      key: ValueKey(_stepOf(state)),
      model: signInModel(state, saved),
      actions: orbit.SignInActions(
        onPhoneChanged: c.updateDigits,
        onCountryChanged: c.setCountryCode,
        onPhoneNext: c.submitPhone,
        onSmsCodeChanged: c.updateOtpCode,
        onSmsCodeNext: c.submitOtp,
        onResendCode: c.resendOtp,
        onPasswordChanged: c.updatePassword,
        onSignIn: c.signInWithPassword,
        onForgotPassword: () => _confirmCode(
          state.phoneLabel,
          onCancel: c.goBack,
          onSend: c.forgotPassword,
        ),
        onLinkInstead: c.linkFromAnotherDevice,
        onNameChanged: c.updateDisplayName,
        onNewPasswordChanged: c.updateNewPassword,
        onTermsChanged: c.setTosAccepted,
        onCreateAccount: c.completeSetup,
        onSkipName: () => c.completeSetup(skip: true),
        onTakeOver: c.completeSetup,
        onBack: state.pendingServerHost != null ? c.declineServer : c.goBack,
        onOpenAdvanced: c.openAdvancedMode,
        onSetupCodeChanged: c.updateCode,
        onSetupCodeNext: c.submitCode,
        onConfirmServer: c.confirmServer,
        onCancelServer: c.declineServer,
        onUseRecoveryCode: c.beginPhoneRecovery,
        onSavedAccountTap: (account) => c.pickSavedAccount(account.id),
        onSavedAccountForget: (account) => c.forgetSavedAccount(account.id),
        onRememberChanged: c.setRemember,
      ),
    );
  }
}

/// The screen's model for [state] and the saved accounts in their words
/// (`orbit/contracts/signin.md`).
@visibleForTesting
orbit.SignInModel signInModel(SignInState state, List<SavedAccountLine> saved) {
  final host = state.pendingServerHost ?? state.serverHost;
  final name = state.serverName;
  return orbit.SignInModel(
    step: _stepOf(state),
    countryCode: state.countryCode,
    countries: [for (final c in signInCountries) (c.code, c.name)],
    phoneDigits: state.digits,
    phoneLabel: state.phoneLabel,
    smsCode: state.otpCode,
    displayName: state.displayName,
    setupCode: state.codeString,
    setupCodeKind: switch (setupCodeLook(state.codeString)) {
      SetupCodeLook.none => orbit.SetupCodeKind.none,
      SetupCodeLook.invite => orbit.SetupCodeKind.invite,
      SetupCodeLook.recovery => orbit.SetupCodeKind.recovery,
    },
    isRecovery: state.isRecovery,
    // The address leads because it is where the traffic goes; the name is
    // the server's own claim and could say anything.
    serverBadge: !state.isAdvanced || host == null
        ? null
        : name == null || name.isEmpty
        ? host
        : '$host ($name)',
    pendingServerHost: state.pendingServerHost,
    termsAccepted: state.tosAccepted,
    showTerms: state.showsTerms,
    busy: state.isLoading,
    error: state.errorMessage,
    showRecoveryOffer: state.showPhoneRecoveryPrompt,
    savedAccounts: [
      for (final line in saved)
        orbit.SavedAccountModel(
          id: line.id,
          title: line.title,
          subtitle: line.detail,
          forgettable: !opensSignedInAccount(line),
        ),
    ],
    remember: state.remember,
    legal: _legal,
  );
}

orbit.SignInStep _stepOf(SignInState s) => switch (s.page) {
  SignInPage.code when s.pendingServerHost != null =>
    orbit.SignInStep.serverConfirm,
  SignInPage.code => orbit.SignInStep.serverCode,
  SignInPage.phone when s.isAdvanced => orbit.SignInStep.serverPhone,
  SignInPage.phone => orbit.SignInStep.phone,
  SignInPage.otp => orbit.SignInStep.smsCode,
  SignInPage.password => orbit.SignInStep.password,
  SignInPage.name when s.isNewAccount => orbit.SignInStep.newAccount,
  SignInPage.name => orbit.SignInStep.takeOver,
};

/// The real documents: they are what people agree to. The version shown is
/// `HelixLegalDocuments.termsVersion`; registration sends the protocol
/// package's copy of the same constant, and a test keeps the two equal
/// (AUD-15-3).
const _legal = orbit.LegalDocumentsModel(
  terms: orbit.LegalDocumentModel(
    title: HelixLegalDocuments.termsTitle,
    version: HelixLegalDocuments.termsVersion,
    effectiveDate: HelixLegalDocuments.effectiveDate,
    text: HelixLegalDocuments.termsOfService,
  ),
  privacy: orbit.LegalDocumentModel(
    title: HelixLegalDocuments.privacyTitle,
    version: HelixLegalDocuments.privacyVersion,
    effectiveDate: HelixLegalDocuments.effectiveDate,
    text: HelixLegalDocuments.privacyPolicy,
  ),
);
