import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:orbit_ui/src/brand/orbit_mark.dart';
import 'package:orbit_ui/src/components/button.dart';
import 'package:orbit_ui/src/components/fields.dart';
import 'package:orbit_ui/src/components/icon_button.dart';
import 'package:orbit_ui/src/components/overlays.dart';
import 'package:orbit_ui/src/components/toggles.dart';
import 'package:orbit_ui/src/icons/orbit_glyph.dart';
import 'package:orbit_ui/src/icons/orbit_icons.dart';
import 'package:orbit_ui/src/screens/signin/legal_sheet.dart';
import 'package:orbit_ui/src/theme/orbit_metrics.dart';
import 'package:orbit_ui/src/theme/orbit_text.dart';
import 'package:orbit_ui/src/theme/orbit_tokens.dart';

/// The steps of [SignInScreen] (`contracts/signin.md`).
enum SignInStep {
  /// Helix Global: your phone number.
  phone,

  /// A personal server: your phone number, with the server's badge
  /// (`signin-join`).
  serverPhone,

  /// The SMS code.
  smsCode,

  /// An account with a password: "Welcome back".
  password,

  /// A new account: your name, the Terms and an optional password.
  newAccount,

  /// The number already has an account: take it over.
  takeOver,

  /// The personal-server invite or recovery code (`signin-advanced*`).
  serverCode,

  /// Confirm the server a code points to (`signin-server`).
  serverConfirm,
}

/// What a typed setup code looks like.
enum SetupCodeKind { none, invite, recovery }

/// `SignInModel` (`contracts/signin.md`).
class SignInModel {
  const SignInModel({
    required this.step,
    this.countryCode = '+880',
    this.countries = const [],
    this.phoneDigits = '',
    this.phoneLabel = '',
    this.smsCode = '',
    this.displayName = '',
    this.setupCode = '',
    this.setupCodeKind = SetupCodeKind.none,
    this.isRecovery = false,
    this.serverBadge,
    this.pendingServerHost,
    this.termsAccepted = false,
    this.busy = false,
    this.error,
    this.showRecoveryOffer = false,
    this.showTerms = true,
    this.savedAccounts = const [],
    this.remember = true,
    this.legal = LegalDocumentsModel.preview,
  });

  final SignInStep step;
  final String countryCode;

  /// The country-code picker (Review 1): (code, country), Bangladesh first.
  final List<(String, String)> countries;
  final String phoneDigits;

  /// "+880 1711 000001", under the SMS-code and password titles.
  final String phoneLabel;
  final String smsCode;
  final String displayName;
  final String setupCode;
  final SetupCodeKind setupCodeKind;

  /// "Recover your account" rather than "Join the server".
  final bool isRecovery;

  /// "chat.rahman.family (Rahman Family)"; null on Helix Global.
  final String? serverBadge;
  final String? pendingServerHost;
  final bool termsAccepted;
  final bool busy;

  /// The sentence under the fields.
  final String? error;

  /// "Use a recovery code instead" under the error (a number that already
  /// has an account on a personal server).
  final bool showRecoveryOffer;

  /// The Terms checkbox on the name and take-over steps. Helix Global asks
  /// for them; a personal server has its own policies (the app's
  /// `SignInState.showsTerms`).
  final bool showTerms;

  /// The accounts this device remembers, on the Global phone step. Empty
  /// renders nothing, so a device without saved accounts sees the screen
  /// exactly as before.
  final List<SavedAccountModel> savedAccounts;

  /// Whether a successful sign-in is remembered on this device ("Remember
  /// me on this device", on by default).
  final bool remember;

  /// The documents the Terms and Privacy sheet shows: the app's real ones,
  /// or the prototype's placeholder text in the preview.
  final LegalDocumentsModel legal;

  bool get canGoBack => step != SignInStep.phone;
  bool get showAdvancedCorner =>
      step == SignInStep.phone || step == SignInStep.serverCode;
  bool get showLegalLink => step == SignInStep.phone;
}

/// `SignInActions` (`contracts/signin.md`).
class SignInActions {
  const SignInActions({
    this.onPhoneChanged,
    this.onCountryChanged,
    this.onPhoneNext,
    this.onSmsCodeChanged,
    this.onSmsCodeNext,
    this.onResendCode,
    this.onPasswordChanged,
    this.onSignIn,
    this.onForgotPassword,
    this.onLinkInstead,
    this.onNameChanged,
    this.onNewPasswordChanged,
    this.onTermsChanged,
    this.onCreateAccount,
    this.onSkipName,
    this.onTakeOver,
    this.onBack,
    this.onOpenAdvanced,
    this.onSetupCodeChanged,
    this.onSetupCodeNext,
    this.onConfirmServer,
    this.onCancelServer,
    this.onUseRecoveryCode,
    this.onSavedAccountTap,
    this.onSavedAccountForget,
    this.onRememberChanged,
  });

  final ValueChanged<String>? onPhoneChanged;
  final ValueChanged<String>? onCountryChanged;
  final Future<bool> Function()? onPhoneNext;
  final ValueChanged<String>? onSmsCodeChanged;
  final Future<bool> Function()? onSmsCodeNext;
  final Future<bool> Function()? onResendCode;
  final ValueChanged<String>? onPasswordChanged;
  final Future<bool> Function()? onSignIn;
  final VoidCallback? onForgotPassword;
  final VoidCallback? onLinkInstead;
  final ValueChanged<String>? onNameChanged;
  final ValueChanged<String>? onNewPasswordChanged;
  final ValueChanged<bool>? onTermsChanged;
  final Future<bool> Function()? onCreateAccount;
  final Future<bool> Function()? onSkipName;
  final Future<bool> Function()? onTakeOver;
  final VoidCallback? onBack;
  final VoidCallback? onOpenAdvanced;
  final ValueChanged<String>? onSetupCodeChanged;
  final Future<bool> Function()? onSetupCodeNext;
  final Future<bool> Function()? onConfirmServer;
  final VoidCallback? onCancelServer;
  final VoidCallback? onUseRecoveryCode;
  final ValueChanged<SavedAccountModel>? onSavedAccountTap;
  final ValueChanged<SavedAccountModel>? onSavedAccountForget;
  final ValueChanged<bool>? onRememberChanged;
}

/// Which sheet the preview opens with the screen (`signin-legal`,
/// `signin-country`).
enum SignInSheet { none, legal, countries }

/// An account this device remembers, shown on the phone step: tap it and
/// type its password, or, for one still signed in here, open it. Both lines
/// arrive ready to show.
class SavedAccountModel {
  const SavedAccountModel({
    required this.id,
    required this.title,
    required this.subtitle,
    this.forgettable = true,
  });

  /// Opaque to the screen; the app matches the row's tap and x back to the
  /// account it stands for.
  final String id;

  /// The first line: the account's name, or its number.
  final String title;

  /// The second line: the masked number, or the server.
  final String subtitle;

  /// Whether the row has an x. An account still signed in on the device has
  /// none: it is removed by signing it out.
  final bool forgettable;
}

/// `signin` (`prototype/js/screens/signin.js`; `.si-*` in `css/pages.css`):
/// one screen, eight steps.
///
/// A 56px top bar with Back; then, 8px 24px in and scrolling: the 64px logo
/// (18px above, 22px below), the title in the display face at 30px, the
/// subtitle at `--t-body` in `--ink-3`, the server badge, the fields 26px
/// down, the error, and the actions (a ghost button on the left, the primary
/// at least 120 wide on the right); at the bottom a 56px foot with "Terms &
/// Privacy" and the hidden corner that reveals "Advanced mode" after three
/// taps, each within 2s.
class SignInScreen extends StatefulWidget {
  const SignInScreen({
    super.key,
    required this.model,
    this.actions = const SignInActions(),
    this.openSheet = SignInSheet.none,
  });

  final SignInModel model;
  final SignInActions actions;
  final SignInSheet openSheet;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  var _taps = 0;
  Timer? _window;
  var _reveal = false;
  Timer? _hide;

  // The two fields the model can change from outside: a link fills the setup
  // code, and a resend clears the SMS code.
  late final _setup = TextEditingController(text: widget.model.setupCode);
  late final _sms = TextEditingController(text: widget.model.smsCode);

  @override
  void didUpdateWidget(SignInScreen old) {
    super.didUpdateWidget(old);
    final m = widget.model;
    if (m.setupCode != old.model.setupCode && m.setupCode != _setup.text) {
      _setup.text = m.setupCode;
    }
    if (m.smsCode != old.model.smsCode && m.smsCode != _sms.text) {
      _sms.text = m.smsCode;
    }
  }

  /// Paste on the code field: the clipboard's text goes in as typed.
  Future<void> _paste() async {
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text?.trim();
    if (text == null || text.isEmpty || !mounted) return;
    _setup.text = text;
    widget.actions.onSetupCodeChanged?.call(text);
  }

  @override
  void initState() {
    super.initState();
    final sheet = widget.openSheet;
    if (sheet != SignInSheet.none) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        sheet == SignInSheet.legal ? _legal() : _countries();
      });
    }
  }

  @override
  void dispose() {
    _hide?.cancel();
    _window?.cancel();
    _setup.dispose();
    _sms.dispose();
    super.dispose();
  }

  void _legal() => showOrbitLegalSheet(context, docs: widget.model.legal);

  void _countries() {
    final m = widget.model;
    showOrbitSheet(
      context,
      title: 'Country code',
      items: [
        for (final (code, name) in m.countries)
          OrbitMenuItem(
            icon: OrbitIcons.globeSimple,
            label: '$name ($code)',
            on: code == m.countryCode,
            onTap: () => widget.actions.onCountryChanged?.call(code),
          ),
      ],
    );
  }

  void _reset() {
    _reveal = false;
    _taps = 0;
  }

  void _corner() {
    // A tap counts when it comes within 2 s of the last one. A timer rather
    // than the wall clock, so the window follows the app's clock (and a
    // test's).
    _window?.cancel();
    _taps++;
    _window = Timer(const Duration(seconds: 2), () => _taps = 0);
    if (_taps >= 3) {
      setState(() => _reveal = true);
      _hide?.cancel();
      _hide = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _reset());
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final m = widget.model;
    final a = widget.actions;
    final step = _step(t, m, a);
    final top = MediaQuery.paddingOf(context).top;
    return ColoredBox(
      color: t.bg,
      child: Padding(
        padding: EdgeInsets.only(top: top),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 56,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(
                  children: [
                    if (m.canGoBack)
                      OrbitIconButton(
                        icon: OrbitIcons.arrowLeft,
                        tooltip: 'Back',
                        onPressed: m.busy ? null : a.onBack,
                      ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 18, bottom: 22),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: [
                              BoxShadow(
                                // rgba(37, 99, 235, 0.45), the logo's glow.
                                color: const Color(0x732563EB),
                                offset: const Offset(0, 10),
                                blurRadius: orbitCssBlur(30),
                                spreadRadius: -10,
                              ),
                              BoxShadow(color: t.line, spreadRadius: 1),
                            ],
                          ),
                          child: const OrbitMark(size: 64),
                        ),
                      ),
                    ),
                    Semantics(
                      header: true,
                      child: OrbitText(
                        orbitTransform(step.title, t.displayTransform),
                        style: t.display(size: 30, height: 1.1),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: OrbitText.rich(
                        step.sub,
                        style: t.font.style(
                          size: OrbitType.body,
                          color: t.ink3,
                          height: 1.5,
                        ),
                      ),
                    ),
                    if (step.badge && m.serverBadge != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: _ServerBadge(m.serverBadge!),
                        ),
                      ),
                    const SizedBox(height: 26),
                    ...step.fields,
                    if (m.error != null) _Error(m.error!),
                    if (m.error != null && m.showRecoveryOffer)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Transform.translate(
                            offset: const Offset(0, -2),
                            child: OrbitButton(
                              label: 'Use a recovery code instead',
                              kind: OrbitButtonKind.secondary,
                              icon: OrbitIcons.key,
                              height: 40,
                              onPressed: a.onUseRecoveryCode ?? _none,
                            ),
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Row(
                        children: [
                          if (step.secondary != null)
                            Flexible(
                              child: OrbitButton(
                                label: step.secondary!,
                                kind: OrbitButtonKind.ghost,
                                onPressed: m.busy
                                    ? null
                                    : step.onSecondary ?? _none,
                              ),
                            ),
                          const SizedBox(width: 10),
                          const Spacer(),
                          ConstrainedBox(
                            constraints: const BoxConstraints(minWidth: 120),
                            child: OrbitButton(
                              label: m.busy ? '' : step.primary,
                              busy: m.busy,
                              onPressed: step.onPrimary ?? _none,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              height: 56,
              margin: const EdgeInsets.only(bottom: 18),
              padding: const EdgeInsets.only(left: 14, right: 10),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  if (m.showLegalLink)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _FootLink(onTap: _legal),
                    ),
                  if (m.showAdvancedCorner)
                    Positioned(
                      right: -10,
                      bottom: 0,
                      width: 152,
                      height: 56,
                      child: GestureDetector(
                        key: const ValueKey('advanced-mode-corner'),
                        behavior: HitTestBehavior.opaque,
                        // A hidden entry: nothing to announce until it is
                        // revealed, and then the button is announced.
                        excludeFromSemantics: true,
                        onTap: _corner,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: _reveal
                                ? OrbitButton(
                                    label: 'Advanced mode',
                                    kind: OrbitButtonKind.secondary,
                                    height: 40,
                                    fontSize: 13,
                                    onPressed: () {
                                      setState(() => _reset());
                                      a.onOpenAdvanced?.call();
                                    },
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  _Step _step(OrbitTokens t, SignInModel m, SignInActions a) {
    final phoneLine = m.phoneLabel.isEmpty
        ? '${m.countryCode} ${m.phoneDigits}'
        : m.phoneLabel;
    Widget phoneField(String helper) => OrbitTextField(
      key: const ValueKey('phone'),
      label: 'Phone number',
      prefix: m.countryCode,
      onPrefixTap: m.countries.isEmpty ? null : _countries,
      initialValue: m.phoneDigits,
      hint: '1711 000001',
      keyboardType: TextInputType.phone,
      helper: helper,
      autofillHints: const [AutofillHints.telephoneNumberNational],
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 -]'))],
      onChanged: a.onPhoneChanged,
      onSubmitted: (_) => a.onPhoneNext?.call(),
    );
    Widget ghost(
      String label,
      OrbitGlyph icon,
      VoidCallback? on, {
      double height = 40,
      double margin = 0,
    }) => Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(bottom: margin),
        child: OrbitButton(
          label: label,
          kind: OrbitButtonKind.ghost,
          icon: icon,
          height: height,
          padding: 4,
          onPressed: on ?? _none,
        ),
      ),
    );
    final terms = [
      if (m.showTerms) ...[
        OrbitCheckbox(
          label: 'I agree to the Orbit Terms of Service and Privacy Policy',
          on: m.termsAccepted,
          onChanged: a.onTermsChanged,
        ),
        Transform.translate(
          offset: const Offset(0, -2),
          child: ghost(
            'Read the Terms and Privacy Policy',
            OrbitIcons.bookOpenText,
            _legal,
            margin: 10 - 2,
          ),
        ),
      ],
    ];
    TextSpan plain(String s) => TextSpan(text: s);
    switch (m.step) {
      case SignInStep.phone:
        return _Step(
          title: 'Sign in',
          sub: plain('Use your phone number to continue to Orbit.'),
          fields: [
            phoneField(
              'New to Orbit? Enter your number and we will set up your account.',
            ),
            if (m.savedAccounts.isNotEmpty)
              _SavedAccounts(
                accounts: m.savedAccounts,
                onTap: a.onSavedAccountTap,
                onForget: a.onSavedAccountForget,
              ),
          ],
          primary: 'Next',
          onPrimary: _tap(a.onPhoneNext),
        );
      case SignInStep.serverPhone:
        return _Step(
          title: m.isRecovery ? 'Recover your account' : 'Join the server',
          sub: plain(
            m.isRecovery
                ? 'Enter the phone number of the account.'
                : 'Enter your phone number.',
          ),
          badge: true,
          fields: [phoneField('Continuing moves your account to this phone.')],
          primary: 'Next',
          onPrimary: _tap(a.onPhoneNext),
        );
      case SignInStep.smsCode:
        return _Step(
          title: 'Enter the code',
          sub: plain('We sent a 6-digit code by SMS to $phoneLine.'),
          badge: true,
          fields: [
            OrbitTextField(
              key: const ValueKey('code'),
              label: 'Enter code',
              controller: _sms,
              autofillHints: const [AutofillHints.oneTimeCode],
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              hint: '••••••',
              keyboardType: TextInputType.number,
              maxLength: 6,
              big: true,
              onChanged: (v) {
                a.onSmsCodeChanged?.call(v);
                if (v.length == 6) a.onSmsCodeNext?.call();
              },
            ),
          ],
          secondary: 'Resend code',
          onSecondary: () async {
            final ok = await a.onResendCode?.call() ?? true;
            if (ok && mounted) {
              showOrbitToast(context, 'A new code is on its way');
            }
          },
          primary: 'Next',
          onPrimary: _tap(a.onSmsCodeNext),
        );
      case SignInStep.password:
        return _Step(
          title: 'Welcome back',
          sub: plain(phoneLine),
          badge: true,
          fields: [
            OrbitTextField(
              key: const ValueKey('password'),
              label: 'Password',
              obscure: true,
              eye: true,
              autofillHints: const [AutofillHints.password],
              onChanged: a.onPasswordChanged,
              onSubmitted: (_) => a.onSignIn?.call(),
            ),
            OrbitCheckbox(
              key: const ValueKey('remember'),
              label: 'Remember me on this device',
              on: m.remember,
              onChanged: a.onRememberChanged,
            ),
            Transform.translate(
              offset: const Offset(0, -4),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(2, 0, 2, 4 - 4),
                child: OrbitText(
                  'New here, or no password yet? Use a code instead. A code '
                  'signs your other devices out.',
                  style: t.font.style(
                    size: OrbitType.caption,
                    color: t.ink3,
                    height: 1.45,
                  ),
                ),
              ),
            ),
            ghost(
              'Link from another device instead',
              OrbitIcons.qrCode,
              a.onLinkInstead,
              height: 44,
            ),
          ],
          secondary: 'Use a code instead',
          onSecondary: a.onForgotPassword,
          primary: 'Sign in',
          onPrimary: _tap(a.onSignIn),
        );
      case SignInStep.newAccount:
        return _Step(
          title: 'Your name',
          sub: plain('This is how your contacts will see you.'),
          badge: true,
          fields: [
            OrbitTextField(
              key: const ValueKey('name'),
              label: 'Your name',
              initialValue: m.displayName,
              maxLength: 80,
              autofillHints: const [AutofillHints.name],
              onChanged: a.onNameChanged,
            ),
            ...terms,
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 4, 2, 8),
              child: OrbitText(
                'Set a password, at least 8 characters. Next time you sign '
                'in with your number and this password, no code.',
                style: t.font.style(
                  size: OrbitType.caption,
                  color: t.ink3,
                  height: 1.45,
                ),
              ),
            ),
            OrbitTextField(
              key: const ValueKey('newPassword'),
              label: 'Password',
              eye: true,
              autofillHints: const [AutofillHints.newPassword],
              onChanged: a.onNewPasswordChanged,
            ),
          ],
          secondary: 'Skip',
          onSecondary: _tap(a.onSkipName),
          primary: 'Create account',
          onPrimary: _tap(a.onCreateAccount),
        );
      case SignInStep.takeOver:
        return _Step(
          title: 'Welcome back',
          sub: plain('Accept the terms to continue to your account.'),
          badge: true,
          fields: [
            const _WarningNotice(
              'Continuing moves your account to this phone and signs your '
              'other devices out.',
            ),
            ...terms,
            OrbitTextField(
              key: const ValueKey('newPassword'),
              label: 'New password',
              eye: true,
              autofillHints: const [AutofillHints.newPassword],
              onChanged: a.onNewPasswordChanged,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
              child: OrbitText(
                'At least 8 characters. Next time you sign in with your '
                'number and this password, no code.',
                style: t.font.style(
                  size: OrbitType.caption,
                  color: t.ink3,
                  height: 1.45,
                ),
              ),
            ),
          ],
          secondary: 'Link from another device instead',
          onSecondary: a.onLinkInstead,
          primary: 'Continue',
          onPrimary: _tap(a.onTakeOver),
        );
      case SignInStep.serverCode:
        final (ok, line) = switch (m.setupCodeKind) {
          SetupCodeKind.recovery => (
            true,
            'Recovery code: you will sign back in to your account.',
          ),
          SetupCodeKind.invite => (
            true,
            'Invite code: you will create an account on that server.',
          ),
          SetupCodeKind.none => (
            false,
            'Your server admin gives you this code.',
          ),
        };
        return _Step(
          title: 'Personal server',
          sub: plain(
            'Enter the invite or recovery code from your server admin.',
          ),
          fields: [
            OrbitTextField(
              key: const ValueKey('setup'),
              label: 'Invite or recovery code',
              controller: _setup,
              hint: 'HLX-INV-… or HLX-REC-…',
              mono: true,
              onPaste: _paste,
              onChanged: a.onSetupCodeChanged,
            ),
            Transform.translate(
              offset: const Offset(0, -6),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(2, 0, 2, 10 - 6),
                child: Row(
                  children: [
                    OrbitIcon(
                      ok ? OrbitIcons.checkCircle : OrbitIcons.info,
                      weight: ok ? OrbitIconWeight.fill : null,
                      size: OrbitType.caption,
                      color: ok ? t.success : t.ink3,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: OrbitText(
                        line,
                        style: t.font.style(
                          size: OrbitType.caption,
                          color: ok ? t.success : t.ink3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          primary: 'Next',
          onPrimary: _tap(a.onSetupCodeNext),
        );
      case SignInStep.serverConfirm:
        return _Step(
          title: 'Personal server',
          sub: TextSpan(
            children: [
              const TextSpan(text: 'This code wants to sign you in on '),
              TextSpan(
                text: m.pendingServerHost ?? '',
                style: t.mono.style(size: OrbitType.body, color: t.ink),
              ),
              const TextSpan(text: '.'),
            ],
          ),
          fields: [_ServerWarning(t)],
          secondary: 'Cancel',
          onSecondary: a.onCancelServer,
          primary: 'Continue',
          onPrimary: _tap(a.onConfirmServer),
        );
    }
  }
}

/// One step's words and parts.
class _Step {
  _Step({
    required this.title,
    required this.sub,
    required this.fields,
    required this.primary,
    this.onPrimary,
    this.secondary,
    this.onSecondary,
    this.badge = false,
  });

  final String title;
  final InlineSpan sub;
  final List<Widget> fields;
  final String primary;
  final VoidCallback? onPrimary;
  final String? secondary;
  final VoidCallback? onSecondary;
  final bool badge;
}

/// A button with no action given still looks live (the preview passes
/// none); the app always passes one.
void _none() {}

/// An action that reports whether it worked, as a tap.
VoidCallback? _tap(Future<bool> Function()? f) => f == null ? null : () => f();

/// `.si-error`: a filled warning at 18px, 8px before the sentence at
/// `--t-small` in `--danger`, line height 1.45; 2px above, 10px below.
class _Error extends StatelessWidget {
  const _Error(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.only(top: 2, bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: OrbitIcon(
                OrbitIcons.warningCircle,
                weight: OrbitIconWeight.fill,
                size: 18,
                color: t.danger,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OrbitText(
                text,
                style: t.font.style(
                  size: OrbitType.small,
                  color: t.danger,
                  height: 1.45,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The accounts this device remembers, under the phone field: a caption,
/// then a row per account, 4px apart.
class _SavedAccounts extends StatelessWidget {
  const _SavedAccounts({
    required this.accounts,
    required this.onTap,
    required this.onForget,
  });

  final List<SavedAccountModel> accounts;
  final ValueChanged<SavedAccountModel>? onTap;
  final ValueChanged<SavedAccountModel>? onForget;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OrbitText(
            'Saved accounts',
            style: t.font.style(size: OrbitType.caption, color: t.ink3),
          ),
          const SizedBox(height: 4),
          for (final account in accounts)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: _SavedAccountRow(
                account: account,
                onTap: () => onTap?.call(account),
                onForget: () => onForget?.call(account),
              ),
            ),
        ],
      ),
    );
  }
}

/// One saved account: 56px, the name over the masked number, an x on the
/// right. Tapping the row signs that number in.
class _SavedAccountRow extends StatelessWidget {
  const _SavedAccountRow({
    required this.account,
    required this.onTap,
    required this.onForget,
  });

  final SavedAccountModel account;
  final VoidCallback onTap;
  final VoidCallback onForget;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    return OrbitTapArea(
      child: Semantics(
        button: true,
        container: true,
        child: Material(
          type: MaterialType.transparency,
          borderRadius: BorderRadius.circular(t.rMd),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            splashFactory: NoSplash.splashFactory,
            hoverColor: t.accentSoft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          OrbitText(
                            account.title,
                            style: t.font.style(size: OrbitType.body),
                          ),
                          OrbitText(
                            account.subtitle,
                            style: t.font.style(
                              size: OrbitType.caption,
                              color: t.ink3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (account.forgettable)
                      OrbitIconButton(
                        icon: OrbitIcons.x,
                        tooltip: 'Forget ${account.title}',
                        onPressed: onForget,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `.si-badge`: the server a personal-server step talks to. 28px, 10px in,
/// corner 8, `--surface` with a `--line` edge, mono 11.5px in `--ink-2`
/// after a hard-drives icon.
class _ServerBadge extends StatelessWidget {
  const _ServerBadge(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border.all(color: t.line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          OrbitIcon(OrbitIcons.hardDrives, size: 11.5, color: t.ink2),
          const SizedBox(width: 6),
          Text(text, style: t.mono.style(size: 11.5, color: t.ink2)),
        ],
      ),
    );
  }
}

/// The take-over warning: `.inotice.warning` with no margin, 14px above the
/// checkbox, a filled devices icon.
class _WarningNotice extends StatelessWidget {
  const _WarningNotice(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: t.warningSoft,
        border: Border.all(color: t.warningLine),
        borderRadius: BorderRadius.circular(t.rMd),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: OrbitIcon(
              OrbitIcons.devices,
              weight: OrbitIconWeight.fill,
              size: 20,
              color: t.warning,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OrbitText(
              text,
              style: t.font.style(
                size: OrbitType.small,
                color: t.ink,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The server warning card: a `.card` 16px in, a hard-drives icon 12px
/// before the text at 14px in `--ink-2`, line height 1.5.
class _ServerWarning extends StatelessWidget {
  const _ServerWarning(this.t);

  final OrbitTokens t;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: t.surface,
      border: Border.all(color: t.line),
      borderRadius: BorderRadius.circular(t.rLg),
      boxShadow: t.shadowCard,
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OrbitIcon(OrbitIcons.hardDrives, size: 15, color: t.ink),
        const SizedBox(width: 12),
        Expanded(
          child: OrbitText(
            'Only continue if you know this server and expected this code. '
            'Your phone number and messages will be handled by it.',
            style: t.font.style(size: 14, color: t.ink2, height: 1.5),
          ),
        ),
      ],
    ),
  );
}

/// "Terms & Privacy" in the foot: a 40px ghost button 6px in, `--ink-3`.
class _FootLink extends StatelessWidget {
  const _FootLink({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    return OrbitTapArea(
      child: Semantics(
        button: true,
        child: Material(
          type: MaterialType.transparency,
          borderRadius: BorderRadius.circular(t.rPill),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            splashFactory: NoSplash.splashFactory,
            hoverColor: t.accentSoft,
            child: SizedBox(
              height: 40,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 7),
                child: Center(
                  widthFactor: 1,
                  child: Text(
                    'Terms & Privacy',
                    style: t.font.style(
                      size: OrbitType.small,
                      weight: 560,
                      color: t.ink3,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
