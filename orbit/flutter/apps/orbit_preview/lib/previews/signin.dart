import 'package:flutter/widgets.dart';
import 'package:orbit_ui/orbit_ui.dart';

/// The sign-in keys (`prototype/js/screens/signin.js`) on the prototype's
/// sample values.
const _countries = [
  ('+880', 'Bangladesh'),
  ('+91', 'India'),
  ('+92', 'Pakistan'),
  ('+977', 'Nepal'),
  ('+60', 'Malaysia'),
  ('+966', 'Saudi Arabia'),
  ('+971', 'United Arab Emirates'),
  ('+44', 'United Kingdom'),
  ('+1', 'United States'),
];

const _errors = {
  'badPhone': 'This number looks too short. Check it and try again.',
  'taken':
      'This phone number already has an account on this server. Ask your '
      'server admin for a recovery code to sign back in.',
  'offline': 'Could not reach the server. Check your connection and try again.',
  'badCode': 'That code is not right. Check the SMS and try again.',
  'lockedPass':
      'Too many wrong passwords. Try again after 14:35, or use “Forgot '
      'password”.',
  'terms': 'Accept the Terms of Service and Privacy Policy to continue.',
  'badSetup':
      'This is not an invite or recovery code. Paste the whole HLX-INV- or '
      'HLX-REC- code you were given.',
};

SignInModel _m(
  SignInStep step, {
  String phone = '',
  String code = '',
  String name = '',
  String setup = '',
  String? error,
  bool recovery = false,
}) {
  final up = setup.trim().toUpperCase();
  return SignInModel(
    step: step,
    countries: _countries,
    phoneDigits: phone,
    phoneLabel: '+880 ${phone.isEmpty ? '1711 000001' : phone}',
    smsCode: code,
    displayName: name,
    setupCode: setup,
    setupCodeKind: up.startsWith('HLX-REC-')
        ? SetupCodeKind.recovery
        : up.startsWith('HLX-INV-')
        ? SetupCodeKind.invite
        : SetupCodeKind.none,
    isRecovery: recovery,
    // The badge is a personal server's; Helix Global steps have none.
    serverBadge: step == SignInStep.serverPhone
        ? 'chat.rahman.family (Rahman Family)'
        : null,
    pendingServerHost: 'chat.rahman.family',
    error: error == null ? null : _errors[error],
    showRecoveryOffer: error == 'taken',
  );
}

final Map<String, WidgetBuilder> signInPreviews = {
  'signin': (_) => SignInScreen(model: _m(SignInStep.phone)),
  'signin-phone-error': (_) => SignInScreen(
    model: _m(SignInStep.phone, phone: '1711 00', error: 'badPhone'),
  ),
  'signin-offline': (_) => SignInScreen(
    model: _m(SignInStep.phone, phone: '1711 000001', error: 'offline'),
  ),
  'signin-code': (_) =>
      SignInScreen(model: _m(SignInStep.smsCode, phone: '1711 000001')),
  'signin-code-error': (_) => SignInScreen(
    model: _m(
      SignInStep.smsCode,
      phone: '1711 000001',
      code: '482910',
      error: 'badCode',
    ),
  ),
  'signin-password': (_) =>
      SignInScreen(model: _m(SignInStep.password, phone: '1711 000001')),
  'signin-password-error': (_) => SignInScreen(
    model: _m(SignInStep.password, phone: '1711 000001', error: 'lockedPass'),
  ),
  'signin-name': (_) =>
      SignInScreen(model: _m(SignInStep.newAccount, phone: '1711 000001')),
  'signin-name-terms': (_) => SignInScreen(
    model: _m(
      SignInStep.newAccount,
      phone: '1711 000001',
      name: 'Hasan',
      error: 'terms',
    ),
  ),
  'signin-takeover': (_) => SignInScreen(model: _m(SignInStep.takeOver)),
  'signin-taken': (_) => SignInScreen(
    model: _m(SignInStep.serverPhone, phone: '1711 000001', error: 'taken'),
  ),
  'signin-country': (_) => SignInScreen(
    model: _m(SignInStep.phone),
    openSheet: SignInSheet.countries,
  ),
  'signin-advanced': (_) => SignInScreen(model: _m(SignInStep.serverCode)),
  'signin-advanced-rec': (_) => SignInScreen(
    model: _m(SignInStep.serverCode, setup: 'HLX-REC-7Q2M-K9TD-XR4P'),
  ),
  'signin-advanced-error': (_) => SignInScreen(
    model: _m(SignInStep.serverCode, setup: 'hello', error: 'badSetup'),
  ),
  'signin-server': (_) => SignInScreen(model: _m(SignInStep.serverConfirm)),
  'signin-join': (_) => SignInScreen(model: _m(SignInStep.serverPhone)),
  'signin-legal': (_) =>
      SignInScreen(model: _m(SignInStep.phone), openSheet: SignInSheet.legal),
};

const _offer = [
  RestoreOfferModel(
    title: 'History from Galaxy S23',
    status: 'Ready to receive. Nothing is downloaded until you accept.',
  ),
];

final Map<String, WidgetBuilder> entryPreviews = {
  'restore': (_) => const RestoreScreen(model: RestoreModel(offers: _offer)),
  'restore-running': (_) => const RestoreScreen(
    model: RestoreModel(
      offers: _offer,
      status: RestoreStatus.running,
      step: 3,
      addedSoFar: '1,204 messages added so far',
    ),
  ),
  'restore-failed': (_) => const RestoreScreen(
    model: RestoreModel(offers: _offer, status: RestoreStatus.failed),
  ),
  'restore-done': (_) => const RestoreScreen(
    model: RestoreModel(offers: _offer, status: RestoreStatus.done),
  ),
  'restore-nothing': (_) => const RestoreScreen(
    model: RestoreModel(offers: _offer, status: RestoreStatus.nothing),
  ),
  'restore-locked': (_) => const RestoreScreen(
    model: RestoreModel(offers: _offer, status: RestoreStatus.locked),
  ),
  'link-device': (_) =>
      const LinkThisDeviceScreen(model: LinkThisDeviceModel()),
  'link-device-expired': (_) => const LinkThisDeviceScreen(
    model: LinkThisDeviceModel(phase: LinkThisDevicePhase.expired),
  ),
  'link-device-confirm': (_) => const LinkThisDeviceScreen(
    model: LinkThisDeviceModel(phase: LinkThisDevicePhase.confirm),
  ),
  'link-device-starting': (_) => const LinkThisDeviceScreen(
    model: LinkThisDeviceModel(phase: LinkThisDevicePhase.starting),
  ),
  'link-device-failed': (_) => const LinkThisDeviceScreen(
    model: LinkThisDeviceModel(phase: LinkThisDevicePhase.failed),
  ),
  'link-device-declined': (_) => const LinkThisDeviceScreen(
    model: LinkThisDeviceModel(phase: LinkThisDevicePhase.declined),
  ),
  'reset-window': (_) =>
      const ResetScreen(model: ResetModel(kind: ResetKind.window)),
  'reset-key': (_) =>
      const ResetScreen(model: ResetModel(kind: ResetKind.keyMissing)),
  'reset-decrypt': (_) =>
      const ResetScreen(model: ResetModel(kind: ResetKind.cannotDecrypt)),
  'reset-start-failed': (_) =>
      const ResetScreen(model: ResetModel(kind: ResetKind.start)),
  'reset-fine': (_) =>
      const ResetScreen(model: ResetModel(kind: ResetKind.fine)),
  'reset-failed': (_) => const ResetScreen(
    model: ResetModel(kind: ResetKind.keyMissing, failed: true),
  ),
  'lock': (_) => const LockScreen(),
  'lock-failed': (_) => const LockScreen(model: LockModel(failed: true)),
};
