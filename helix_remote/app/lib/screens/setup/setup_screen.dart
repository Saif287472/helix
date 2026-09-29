import 'package:flutter/material.dart';
import 'package:helix_remote/app/composition_root.dart';
import 'package:helix_remote/screens/setup/pages/phone_page.dart';
import 'package:helix_remote/screens/setup/pages/sign_in_fields.dart';
import 'package:helix_remote/screens/setup/state/onboarding_notifier.dart';
import 'package:helix_remote/screens/setup/state/onboarding_state.dart';
import 'package:helix_remote/screens/setup/steps/legal_documents_sheet.dart';
import 'package:helix_remote/screens/setup/widgets/sign_in_frame.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// Sign-in. Always opens on the simple Helix Global page: a phone number and
/// "Next". A personal server is behind the hidden advanced mode (see
/// [AdvancedModeCorner]) or an invite/recovery link.
class SetupScreen extends StatefulWidget {
  const SetupScreen({
    super.key,
    this.onChoice,
    this.notifier,
    this.root,
    this.initialCode,
    this.initialRecoveryMode = false,
    this.initialError,
  });

  /// Receives the finished sign-in when it has to be completed by the host
  /// (see [OnboardingNotifier.completedChoice]).
  final void Function(Object? choice)? onChoice;
  final OnboardingNotifier? notifier;
  final RemoteCompositionRoot? root;

  /// An invite or recovery code from a link: opens advanced mode with it.
  final String? initialCode;

  /// Opens advanced mode on the code page (a number that already has an
  /// account on a personal server needs a recovery code).
  final bool initialRecoveryMode;

  /// Why the last sign-in attempt failed, shown on the first page.
  final String? initialError;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  late final OnboardingNotifier _notifier;
  bool _ownsNotifier = false;
  bool _handledCompletion = false;
  bool _recoveryDialogOpen = false;

  @override
  void initState() {
    super.initState();
    final given = widget.notifier;
    if (given != null) {
      _notifier = given;
    } else {
      _notifier = OnboardingNotifier(root: widget.root);
      _ownsNotifier = true;
    }
    _notifier.addListener(_onNotifierUpdate);
    final code = widget.initialCode?.trim() ?? '';
    if (code.isNotEmpty) {
      _notifier.openWithCode(code);
    } else if (widget.initialRecoveryMode) {
      _notifier.openAdvancedMode();
    }
    final error = widget.initialError;
    if (error != null && error.isNotEmpty) _notifier.showError(error);
  }

  @override
  void didUpdateWidget(SetupScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final code = widget.initialCode?.trim() ?? '';
    if (code.isNotEmpty && code != oldWidget.initialCode?.trim()) {
      _notifier.openWithCode(code);
    }
  }

  @override
  void dispose() {
    _notifier.removeListener(_onNotifierUpdate);
    if (_ownsNotifier) _notifier.dispose();
    super.dispose();
  }

  void _onNotifierUpdate() {
    if (!mounted) return;
    final state = _notifier.state;
    if (state.showPhoneRecoveryPrompt && !_recoveryDialogOpen) {
      _recoveryDialogOpen = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _askForRecovery());
    }
    if (state.isComplete && !_handledCompletion) {
      _handledCompletion = true;
      final choice = _notifier.completedChoice;
      widget.onChoice?.call(choice);
      final navigator = Navigator.of(context);
      if (navigator.canPop()) navigator.maybePop(choice);
    }
  }

  Future<void> _askForRecovery() async {
    if (!mounted) return;
    final recover = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('This number already has an account'),
        content: const Text(
          'This phone number already has an account on this server. Ask your '
          'server admin for a recovery code to sign back in.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Enter recovery code'),
          ),
        ],
      ),
    );
    _recoveryDialogOpen = false;
    if (!mounted) return;
    if (recover == true) {
      _notifier.beginPhoneRecovery();
    } else {
      _notifier.dismissPhoneRecoveryPrompt();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: HelixThemes.signIn(
        highContrast: MediaQuery.highContrastOf(context),
      ),
      child: ListenableBuilder(
        listenable: _notifier,
        builder: (context, _) => AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: KeyedSubtree(
            key: ValueKey('${_notifier.state.mode}-${_notifier.state.page}'),
            child: _page(context, _notifier.state),
          ),
        ),
      ),
    );
  }

  String get _phoneLabel {
    final state = _notifier.state;
    final digits = state.phoneNumber.trim();
    return digits.isEmpty
        ? _notifier.phoneNumber
        : '${state.countryCode} $digits';
  }

  Widget? _serverBadge(OnboardingState state) {
    final name = state.serverName;
    if (!state.isAdvanced || name == null) return null;
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Server: $name',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.secondaryContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.dns_outlined,
                size: 16,
                color: scheme.onSecondaryContainer,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: scheme.onSecondaryContainer),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _page(BuildContext context, OnboardingState state) {
    final n = _notifier;
    final loading = state.isLoading;
    final theme = Theme.of(context);
    final note = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    switch (state.page) {
      case SetupPage.code:
        return SignInFrame(
          title: 'Personal server',
          subtitle: 'Enter the invite or recovery code from your server admin.',
          isLoading: loading,
          errorMessage: state.errorMessage,
          onBack: n.leaveAdvancedMode,
          primaryLabel: 'Next',
          onPrimary: n.submitCode,
          child: CodeField(
            initial: state.codeString,
            enabled: !loading,
            detected: n.detectedCodeType,
            onChanged: n.updateCodeString,
            onSubmit: n.submitCode,
          ),
        );

      case SetupPage.phone:
        final global = !state.isAdvanced;
        return SignInFrame(
          title: global
              ? 'Sign in'
              : (state.isRecovery ? 'Recover your account' : 'Join the server'),
          subtitle: global
              ? 'Use your phone number to continue to Helix.'
              : (state.isRecovery
                    ? 'Enter the phone number of the account.'
                    : 'Enter your phone number.'),
          badge: _serverBadge(state),
          isLoading: loading,
          errorMessage: state.errorMessage,
          onBack: global ? null : n.goBack,
          primaryLabel: 'Next',
          onPrimary: n.submitPhone,
          footer: global
              ? TextButton(
                  onPressed: () => showLegalDocumentsSheet(context),
                  child: const Text('Terms & Privacy'),
                )
              : null,
          corner: global
              ? AdvancedModeCorner(onOpen: n.openAdvancedMode)
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PhoneFields(
                countryCode: state.countryCode,
                phoneNumber: state.phoneNumber,
                enabled: !loading,
                onCountryCodeChanged: n.updateCountryCode,
                onPhoneChanged: n.updatePhoneNumber,
                onSubmit: n.submitPhone,
              ),
              if (global) ...[
                const SizedBox(height: HelixSpace.sm),
                Text(
                  'New to Helix? Enter your number and we will set up your '
                  'account.',
                  style: note,
                ),
              ],
            ],
          ),
        );

      case SetupPage.password:
        return SignInFrame(
          title: 'Welcome back',
          subtitle: _phoneLabel,
          badge: _serverBadge(state),
          isLoading: loading,
          errorMessage: state.errorMessage,
          onBack: n.goBack,
          primaryLabel: 'Sign in',
          onPrimary: n.signInWithPassword,
          secondary: TextButton(
            onPressed: loading ? null : n.forgotPassword,
            child: const Text('Forgot password?'),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PasswordField(
                enabled: !loading,
                onChanged: n.updatePassword,
                onSubmit: n.signInWithPassword,
              ),
              const SizedBox(height: HelixSpace.sm),
              Text(
                'Your other devices stay signed in. Signing in with an SMS '
                'code instead signs them out.',
                style: note,
              ),
            ],
          ),
        );

      case SetupPage.otp:
        return SignInFrame(
          title: 'Enter the code',
          subtitle: 'We sent a 6-digit code by SMS to $_phoneLabel.',
          badge: _serverBadge(state),
          isLoading: loading,
          errorMessage: state.errorMessage,
          onBack: n.goBack,
          primaryLabel: 'Next',
          onPrimary: n.submitOtp,
          secondary: TextButton(
            onPressed: loading ? null : n.requestOtp,
            child: const Text('Resend code'),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OtpField(
                initial: state.otpCode,
                enabled: !loading,
                onChanged: n.updateOtpCode,
                onSubmit: n.submitOtp,
              ),
              if (state.isRecovery || state.accountExists) ...[
                const SizedBox(height: HelixSpace.sm),
                Text(
                  'Continuing moves your account to this phone and signs out '
                  'your other devices.',
                  style: note,
                ),
              ],
            ],
          ),
        );

      case SetupPage.name:
        final newAccount = !state.accountExists;
        final needsTerms = n.requiresTerms;
        final canSubmit = !needsTerms || state.tosAccepted;
        void submit() {
          if (canSubmit) n.completeSetup();
        }

        return SignInFrame(
          title: newAccount ? 'Your name' : 'Welcome back',
          subtitle: newAccount
              ? 'This is how your contacts will see you.'
              : 'Accept the terms to continue to your account.',
          badge: _serverBadge(state),
          isLoading: loading,
          errorMessage: state.errorMessage,
          onBack: n.goBack,
          primaryLabel: newAccount ? 'Create account' : 'Continue',
          onPrimary: canSubmit ? submit : null,
          secondary: newAccount
              ? TextButton(
                  onPressed: loading || !canSubmit
                      ? null
                      : () => n.completeSetup(skip: true),
                  child: const Text('Skip'),
                )
              : null,
          child: NameFields(
            askName: newAccount,
            initialName: state.displayName,
            showTerms: needsTerms,
            termsAccepted: state.tosAccepted,
            enabled: !loading,
            onNameChanged: n.updateDisplayName,
            onTermsChanged: n.setTosAccepted,
            onSubmit: submit,
          ),
        );
    }
  }
}
