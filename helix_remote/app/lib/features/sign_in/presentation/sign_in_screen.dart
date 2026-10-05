import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/features/sign_in/application/sign_in_controller.dart';
import 'package:helix_remote/features/sign_in/application/sign_in_copy.dart';
import 'package:helix_remote/features/sign_in/application/sign_in_state.dart';
import 'package:helix_remote/features/sign_in/presentation/widgets/legal_documents_sheet.dart';
import 'package:helix_remote/features/sign_in/presentation/widgets/sign_in_fields.dart';
import 'package:helix_remote/features/sign_in/presentation/widgets/sign_in_frame.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// Sign-in: the Helix Global page, and the hidden personal-server path.
///
/// The screen owns no rules. It reads [SignInState] and calls the controller;
/// which page follows which, when the Terms are required and what an error
/// says all live in `application/`, so the Global path and the personal-server
/// path cannot drift apart.
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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(signInControllerProvider);
    final notifier = ref.read(signInControllerProvider.notifier);

    // Sign-in pages use the app icon's blue; the rest of the app keeps the
    // ordinary light theme. A local Theme, so nothing else is affected.
    return Theme(
      data: HelixThemes.signIn(
        highContrast: MediaQuery.highContrastOf(context),
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: KeyedSubtree(
          key: ValueKey('${state.mode.name}-${state.page.name}'),
          child: switch (state.page) {
            SignInPage.code => _CodePage(state: state, notifier: notifier),
            SignInPage.phone => _PhonePage(state: state, notifier: notifier),
            SignInPage.password => _PasswordPage(
              state: state,
              notifier: notifier,
            ),
            SignInPage.otp => _OtpPage(state: state, notifier: notifier),
            SignInPage.name => _NamePage(state: state, notifier: notifier),
          },
        ),
      ),
    );
  }
}

/// The hidden entry: an invite or recovery code, and the server it names.
class _CodePage extends StatelessWidget {
  const _CodePage({required this.state, required this.notifier});

  final SignInState state;
  final SignInController notifier;

  @override
  Widget build(BuildContext context) {
    final host = state.pendingServerHost;
    if (host != null) {
      // A code or link named a server. Nothing has been sent to it; the host
      // (not the name the server gives itself) is shown, and the person decides.
      return SignInFrame(
        title: 'Personal server',
        subtitle: SignInCopy.serverQuestion(host),
        isLoading: state.isLoading,
        errorMessage: state.errorMessage,
        onBack: notifier.declineServer,
        primaryLabel: 'Continue',
        onPrimary: notifier.confirmServer,
        secondary: TextButton(
          onPressed: state.isLoading ? null : notifier.declineServer,
          child: const Text('Cancel'),
        ),
        child: Text(
          SignInCopy.serverExplanation,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return SignInFrame(
      title: 'Personal server',
      subtitle: 'Enter the invite or recovery code from your server admin.',
      isLoading: state.isLoading,
      errorMessage: state.errorMessage,
      onBack: notifier.goBack,
      primaryLabel: 'Next',
      onPrimary: notifier.submitCode,
      corner: AdvancedModeCorner(onOpen: notifier.openAdvancedMode),
      child: CodeField(
        initial: state.codeString,
        enabled: !state.isLoading,
        detected: state.codeType,
        onChanged: notifier.updateCode,
        onSubmit: notifier.submitCode,
      ),
    );
  }
}

/// The page the app opens on. Helix Global only: a number, Next, and the
/// Terms link. No back button, because there is nothing before it.
class _PhonePage extends StatelessWidget {
  const _PhonePage({required this.state, required this.notifier});

  final SignInState state;
  final SignInController notifier;

  @override
  Widget build(BuildContext context) {
    final global = !state.isAdvanced;
    final title = global
        ? 'Sign in'
        : state.isRecovery
        ? 'Recover your account'
        : 'Join the server';

    return SignInFrame(
      title: title,
      subtitle: global
          ? 'Use your phone number to continue to Helix.'
          : state.isRecovery
          ? 'Enter the phone number of the account.'
          : 'Enter your phone number.',
      badge: _ServerBadge(state: state),
      // Global has no back button; the personal-server pages do.
      onBack: global ? null : notifier.goBack,
      isLoading: state.isLoading,
      errorMessage: state.errorMessage,
      primaryLabel: 'Next',
      onPrimary: notifier.submitPhone,
      footer: global
          ? TextButton(
              onPressed: () => showLegalDocumentsSheet(context),
              child: const Text('Terms & Privacy'),
            )
          : null,
      corner: global
          ? AdvancedModeCorner(onOpen: notifier.openAdvancedMode)
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PhoneField(
            enabled: !state.isLoading,
            onChanged: notifier.updateDigits,
            onSubmit: notifier.submitPhone,
          ),
          const SizedBox(height: HelixSpace.sm),
          Text(
            global
                ? 'New to Helix? Enter your number and we will set up your '
                      'account.'
                : 'Continuing moves your account to this phone.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Only reached when the verified account has a password.
class _PasswordPage extends StatelessWidget {
  const _PasswordPage({required this.state, required this.notifier});

  final SignInState state;
  final SignInController notifier;

  @override
  Widget build(BuildContext context) {
    return SignInFrame(
      title: 'Welcome back',
      subtitle: state.phoneLabel,
      badge: _ServerBadge(state: state),
      onBack: notifier.goBack,
      isLoading: state.isLoading,
      errorMessage: state.errorMessage,
      secondary: TextButton(
        onPressed: state.isLoading ? null : notifier.forgotPassword,
        child: const Text('Forgot password?'),
      ),
      primaryLabel: 'Sign in',
      onPrimary: notifier.signInWithPassword,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PasswordField(
            enabled: !state.isLoading,
            onChanged: notifier.updatePassword,
            onSubmit: notifier.signInWithPassword,
          ),
          const SizedBox(height: HelixSpace.sm),
          Text(
            'Your other devices stay signed in. Signing in with an SMS code '
            'instead signs them out.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          TextButton(
            onPressed: state.isLoading ? null : notifier.linkFromAnotherDevice,
            child: const Text('Link from another device instead'),
          ),
        ],
      ),
    );
  }
}

/// The SMS code.
class _OtpPage extends StatelessWidget {
  const _OtpPage({required this.state, required this.notifier});

  final SignInState state;
  final SignInController notifier;

  @override
  Widget build(BuildContext context) {
    return SignInFrame(
      title: 'Enter the code',
      subtitle: 'We sent a 6-digit code by SMS to ${state.phoneLabel}.',
      badge: _ServerBadge(state: state),
      onBack: notifier.goBack,
      isLoading: state.isLoading,
      errorMessage: state.errorMessage,
      secondary: TextButton(
        onPressed: state.isLoading ? null : notifier.resendOtp,
        child: const Text('Resend code'),
      ),
      primaryLabel: 'Next',
      onPrimary: notifier.submitOtp,
      child: OtpField(
        initial: state.otpCode,
        enabled: !state.isLoading,
        onChanged: notifier.updateOtpCode,
        onSubmit: notifier.submitOtp,
      ),
    );
  }
}

/// The last page: the name for a new account, or the confirmation that moves an
/// existing account to this phone.
class _NamePage extends StatelessWidget {
  const _NamePage({required this.state, required this.notifier});

  final SignInState state;
  final SignInController notifier;

  @override
  Widget build(BuildContext context) {
    final newAccount = state.isNewAccount;
    final needsTerms = newAccount && state.requiresTerms;

    return SignInFrame(
      title: newAccount ? 'Your name' : 'Welcome back',
      subtitle: newAccount
          ? 'This is how your contacts will see you.'
          : 'Accept the terms to continue to your account.',
      badge: _ServerBadge(state: state),
      onBack: notifier.goBack,
      isLoading: state.isLoading,
      errorMessage: state.errorMessage,
      secondary: newAccount
          ? TextButton(
              onPressed: state.isLoading
                  ? null
                  : () => notifier.completeSetup(skip: true),
              child: const Text('Skip'),
            )
          // Continuing signs the account's other devices out. Linking from one
          // of them does not, so it is offered first.
          : TextButton(
              onPressed: state.isLoading
                  ? null
                  : notifier.linkFromAnotherDevice,
              child: const Text('Link from another device instead'),
            ),
      primaryLabel: newAccount ? 'Create account' : 'Continue',
      onPrimary: () => notifier.completeSetup(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NameFields(
            askName: newAccount,
            initialName: state.displayName,
            showTerms: needsTerms,
            termsAccepted: state.tosAccepted,
            enabled: !state.isLoading,
            onNameChanged: notifier.updateDisplayName,
            onTermsChanged: notifier.setTosAccepted,
            onSubmit: () => notifier.completeSetup(),
          ),
          if (newAccount) ...[
            const SizedBox(height: HelixSpace.sm),
            // Optional. Without it the account can still be recovered, but
            // only with another device that is still signed in.
            Text(
              'Set a password (optional) so you can sign back in on a new '
              'phone without another device.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: HelixSpace.xs),
            PasswordField(
              enabled: !state.isLoading,
              labelText: 'Password (optional)',
              obscure: false,
              onChanged: notifier.updateNewPassword,
              onSubmit: () => notifier.completeSetup(),
            ),
          ],
        ],
      ),
    );
  }
}

/// Which server this is, when it is not Helix Global: its address, always, and
/// the name it gives itself after it. Never shown on Global: there is nothing to
/// disambiguate.
///
/// The address leads because it is where the traffic goes; the name is the
/// server's own claim and could say anything.
class _ServerBadge extends StatelessWidget {
  const _ServerBadge({required this.state});

  final SignInState state;

  @override
  Widget build(BuildContext context) {
    final host = state.pendingServerHost ?? state.serverHost;
    if (!state.isAdvanced || host == null) return const SizedBox.shrink();
    final name = state.serverName;
    final label = name == null || name.isEmpty ? host : '$host ($name)';
    return Semantics(
      label: 'Server: $label',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.dns_outlined,
            size: 16,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: HelixSpace.xxs),
          Flexible(
            child: Text(
              label,
              key: const ValueKey('server-badge'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
