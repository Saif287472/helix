import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/engine/global_server.dart';
import 'package:helix_remote/core/engine/helix_runtime.dart';
import 'package:helix_remote/core/engine/post_sign_in.dart';
import 'package:helix_remote/core/engine/runtime_providers.dart';
import 'package:helix_remote/core/engine/server_policy.dart';
import 'package:helix_remote/core/engine/session_providers.dart';
import 'package:helix_remote/core/links/helix_code.dart';
import 'package:helix_remote/core/platform/saved_accounts.dart';
import 'package:helix_remote/core/router/app_router.dart';
import 'package:helix_remote/features/sign_in/application/sign_in_state.dart';
import 'package:helix_remote/features/sign_in/application/sign_in_view.dart';
import 'package:helix_remote/shared/route_paths.dart';
import 'package:helix_remote/features/sign_in/application/sign_in_copy.dart';
import 'package:helix_remote/features/sign_in/application/sign_in_countries.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart'
    show AccountStatusResponse;

/// The Orbit Home server. Sign-in opens here and nowhere else unless a
/// code, a link or the hidden corner says otherwise.
final kHelixGlobalServer = kGlobalServerUrl;

/// Drives sign-in: the page machine, the validation and every call to the
/// engine's [AccountService].
///
/// Nothing here is a widget, and nothing here draws. The screens read
/// [SignInState] and call these methods; the rules (which page follows which,
/// when the Terms are required, what an error says) live in one place so they
/// cannot drift between the Global and the personal-server path.
final signInControllerProvider =
    NotifierProvider<SignInController, SignInState>(SignInController.new);

/// What a number is on the server, asked before anything is texted (ADR-032).
///
/// A provider rather than a direct engine call so the page machine can be
/// walked with an answer of the tester's choosing. It is `autoDispose`: the
/// answer describes a moment, not a thing to cache, and a number that was not
/// registered a minute ago may have been registered since.
final signInAccountStatusProvider = FutureProvider.family
    .autoDispose<AccountStatusResponse, String>(
      (ref, number) async => (await ref.read(
        runtimeProvider.future,
      )).engine.account.accountStatus(number),
    );

final class SignInController extends Notifier<SignInState> {
  String? _challengeId;

  /// A server named by a code or link that is waiting for the person's yes.
  /// Nothing has been sent to it.
  Uri? _pendingServer;

  /// The one server the person approved on the code page. Anything else a code
  /// names has to be approved again.
  Uri? _approvedServer;

  @override
  SignInState build() {
    // A link is only ever applied once the app knows nobody is signed in, and
    // however it got here (a cold start, a warm one, a restore that finished
    // after the link did).
    ref.listen(pendingLinkProvider, (_, _) => _consumeWhenSettled());
    ref.listen(sessionRestoreProvider, (_, _) => _consumeWhenSettled());
    ref.listen(authStateProvider, (previous, next) {
      final now = next.value;
      final before = previous?.value;
      final signedIn = now == AppAuthState.ready;
      final signedOut =
          now == AppAuthState.signedOut &&
          (before == AppAuthState.ready || before == AppAuthState.revoked);
      // Whoever signs in, or out, leaves nothing of this flow behind: not the
      // half-entered page, not an approved server, not a parked link.
      if (signedIn || signedOut) _resetFlow();
      _consumeWhenSettled();
    });
    return const SignInState();
  }

  void _resetFlow() {
    _challengeId = null;
    _verificationToken = null;
    _verifiedAccountId = null;
    _pendingServer = null;
    _approvedServer = null;
    // A parked invite or recovery code goes with the flow it was for; a group
    // link waiting for an account does not.
    if (ref.read(pendingLinkProvider)?.setupCode != null) {
      ref.read(pendingLinkProvider.notifier).set(null);
    }
    state = const SignInState();
  }

  /// Whether the device is known to have no account, so a link may be used.
  /// Before the remembered server has been read (or while the engine is still
  /// deciding) a signed-in phone looks signed out; a link must not act then.
  bool get _knownSignedOut {
    if (ref.read(sessionRestoreProvider) == SessionRestore.pending) {
      return false;
    }
    final auth = ref.read(authStateProvider);
    if (auth.isLoading) return false;
    final value = auth.value;
    return value == AppAuthState.signedOut || value == AppAuthState.revoked;
  }

  void _consumeWhenSettled() {
    if (!_knownSignedOut) return;
    if (ref.read(pendingLinkProvider)?.setupCode == null) return;
    // Fire and forget: the outcome is the state the screen shows.
    consumePendingCode();
  }

  // ------------------------------------------------------------- entering

  /// Opens the hidden personal-server entry. [code] arrives from a shared
  /// link, in which case it is checked straight away.
  Future<void> openAdvancedMode({String? code}) async {
    state = const SignInState(mode: SignInMode.advanced, page: SignInPage.code);
    if (code != null && code.trim().isNotEmpty) {
      updateCode(code.trim());
      await submitCode();
    }
  }

  /// The hidden corner's fourth tap, and a shared link, both land here.
  void leaveAdvancedMode() {
    _challengeId = null;
    _pendingServer = null;
    _approvedServer = null;
    state = const SignInState();
  }

  /// A shared link: opens advanced mode and checks the code at once.
  Future<void> openWithCode(String code) => openAdvancedMode(code: code.trim());

  /// Takes the code a link left in [pendingLinkProvider], if any. Called once
  /// when the screen appears, so a link tapped while the app was closed lands
  /// on the same path as one tapped while it was open.
  ///
  /// A link is used only when the device is known to be signed out (see
  /// [_knownSignedOut]); otherwise it stays parked, and is dropped when the
  /// person signs in or out. It never reaches a server on its own: the code
  /// page asks first (see [submitCode]).
  Future<void> consumePendingCode() async {
    if (!_knownSignedOut) return;
    final code = ref.read(pendingLinkProvider.notifier).take()?.setupCode;
    if (code == null || code.isEmpty) return;
    await openWithCode(code);
  }

  // -------------------------------------------------------------- editing

  void updateDigits(String value) =>
      state = state.copyWith(digits: value, clearError: true);

  /// The country picker. Only a code from [signInCountries] is taken.
  void setCountryCode(String code) {
    if (!signInCountries.any((c) => c.code == code)) return;
    state = state.copyWith(countryCode: code, clearError: true);
  }

  void updatePassword(String value) =>
      state = state.copyWith(password: value, clearError: true);

  void updateOtpCode(String value) => state = state.copyWith(
    otpCode: value,
    clearError: true,
    showPhoneRecoveryPrompt: false,
  );

  void updateCode(String value) =>
      state = state.copyWith(codeString: value, clearError: true);

  void updateDisplayName(String value) =>
      state = state.copyWith(displayName: value, clearError: true);

  void updateNewPassword(String value) =>
      state = state.copyWith(newPassword: value, clearError: true);

  void setTosAccepted(bool value) => state = state.copyWith(tosAccepted: value);

  /// The password page's "Remember me on this device".
  void setRemember(bool value) => state = state.copyWith(remember: value);

  /// The page's back arrow. Global's phone page has none: there is nothing
  /// before it, and a back button there would promise otherwise.
  void goBack() {
    _challengeId = null;
    switch (state.page) {
      case SignInPage.code:
        leaveAdvancedMode();
      case SignInPage.phone:
        if (state.isAdvanced) {
          _approvedServer = null;
          state = state.copyWith(
            page: SignInPage.code,
            clearCodeType: true,
            clearServerName: true,
            clearServerHost: true,
            codeString: '',
            clearError: true,
          );
        }
      // The SMS code is already used, so Back from the password goes to the
      // number, not to the take-over step (Review 1, Orbit port).
      case SignInPage.password:
      case SignInPage.otp:
      case SignInPage.name:
        state = state.copyWith(page: SignInPage.phone, clearError: true);
    }
  }

  // ----------------------------------------------------------- the code page

  /// Checks an invite or recovery code and, when it is good, points the app at
  /// the server it names.
  Future<bool> submitCode() async {
    final raw = state.codeString.trim();
    if (raw.isEmpty) {
      return _fail(SignInCopy.emptyCode);
    }
    // A prefix with nothing after it is a truncated paste or a half-typed
    // code. It is caught here so the person is told the code is incomplete
    // rather than shown a decoder error they cannot act on.
    if (_isTruncated(raw)) return _fail(SignInCopy.truncatedCode);
    final upper = raw.toUpperCase();
    final isRecovery = upper.startsWith(kHelixRecoveryPrefix);
    final isInvite = upper.startsWith(kHelixInvitePrefix);
    if (!isRecovery && !isInvite) return _fail(SignInCopy.notACode);
    final type = isRecovery
        ? SignInCodeType.recovery
        : SignInCodeType.invitation;

    // The two decoders return differently shaped records, so each branch keeps
    // its own names rather than widening them to a map.
    final invite = isInvite ? decodeHelixInviteCode(raw) : null;
    final recovery = isRecovery ? decodeHelixRecoveryCode(raw) : null;
    final serverUrlText = invite?.serverUrl ?? recovery?.serverUrl;
    if (serverUrlText == null) return _fail(SignInCopy.notACode);

    final serverUrl = Uri.tryParse(serverUrlText);
    if (serverUrl == null || !serverUrl.hasScheme) {
      return _fail(SignInCopy.notACode);
    }
    // Before anything is sent: cleartext, a look-alike host and an address
    // with a user name in it are refused, whatever the code says.
    if (ServerPolicy.check(serverUrl) != null) {
      return _fail(SignInCopy.insecureServer);
    }
    // A server that came out of a code or a link is somebody else's choice.
    // The person is shown its host and asked before the first request.
    if (!_isApproved(serverUrl)) {
      _pendingServer = serverUrl;
      state = state.copyWith(
        pendingServerHost: ServerPolicy.displayHost(serverUrl),
        isLoading: false,
        clearError: true,
      );
      return false;
    }

    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final runtime = await _runtimeFor(serverUrl);
      final api = runtime.api.identity;
      // A code is checked before the phone page so a typo, an expired invite
      // or a cancelled one is reported where it was pasted, not two pages
      // later.
      if (isInvite) {
        final result = await api.inviteLookup(invite!.inviteCode);
        if (!result.valid) {
          return _fail(SignInCopy.inviteInvalid(result.reason));
        }
        state = state.copyWith(serverName: result.serverName);
      } else {
        final result = await api.recoveryLookup(recovery!.recoveryCode);
        if (!result.valid) return _fail(SignInCopy.recoveryInvalid);
        state = state.copyWith(serverName: result.serverName);
      }
      final global = ServerPolicy.isGlobal(serverUrl);
      state = state.copyWith(
        serverHost: global ? null : ServerPolicy.displayHost(serverUrl),
        clearServerHost: global,
        codeType: type,
        page: SignInPage.phone,
        isLoading: false,
        clearError: true,
      );
      return true;
    } on Object catch (error) {
      return _fail(SignInCopy.connectFailure(error), loading: false);
    }
  }

  bool _isApproved(Uri server) =>
      ServerPolicy.isGlobal(server) ||
      (_approvedServer != null &&
          ServerPolicy.sameServer(_approvedServer!, server));

  /// The person said yes to the server in [SignInState.pendingServerHost]:
  /// the code is checked against it now, and not before.
  Future<bool> confirmServer() async {
    final server = _pendingServer;
    if (server == null) return false;
    _approvedServer = server;
    _pendingServer = null;
    state = state.copyWith(clearPendingServer: true);
    return submitCode();
  }

  /// The person said no. The code is forgotten and nothing was sent.
  void declineServer() {
    _pendingServer = null;
    _approvedServer = null;
    state = state.copyWith(
      clearPendingServer: true,
      codeString: '',
      clearError: true,
    );
  }

  /// After an invite was entered for a number that already has an account:
  /// the invite cannot be used, and a recovery code is the way back in.
  void beginPhoneRecovery() {
    _challengeId = null;
    _approvedServer = null;
    state = state.copyWith(
      page: SignInPage.code,
      codeString: '',
      clearCodeType: true,
      clearServerName: true,
      clearServerHost: true,
      showPhoneRecoveryPrompt: false,
      clearError: true,
    );
  }

  // ----------------------------------------------------------- the phone page

  /// Asks the server what this number is, before anything is texted
  /// (ADR-032), and opens the page that fits the answer.
  ///
  /// A number with an account and a password signs in with the number and the
  /// password alone, never a code (the owner, 2026-10-21). Every other answer
  /// goes through a code: a new number is never asked for a password it cannot
  /// have, and an account with no password cannot get one set by a caller who
  /// never proved the number - the code is what authorises the new password on
  /// the page after it.
  ///
  /// A server that cannot answer (an older build, no network, a limit) keeps
  /// the page order this app has always had: the password, with "Use a code
  /// instead" under it.
  Future<bool> submitPhone() async {
    final number = state.e164;
    if (number == null) return _fail(SignInCopy.badPhoneNumber);
    // Checked here so a short number is never sent (Review 1, Orbit port).
    final national = number.length - state.countryCode.length;
    if (national < signInMinDigits(state.countryCode)) {
      return _fail(SignInCopy.phoneTooShort);
    }
    // Already signed in on this device: open it, rather than sign it in a
    // second time beside itself.
    final here = _signedInHere(number);
    if (here != null) {
      await ref.read(accountsProvider.notifier).switchTo(here);
      return true;
    }

    state = state.copyWith(isLoading: true, clearError: true);
    final AccountStatusResponse status;
    try {
      // The server this page signs in to is settled before anything is asked.
      _chooseServer();
      status = await ref.read(signInAccountStatusProvider(number).future);
    } on Object {
      return _openPasswordPage();
    }
    final canUsePassword = status.accountExists && status.hasPassword;
    if (canUsePassword) return _openPasswordPage();
    // Everything else ends with a code, and a code is only texted after the
    // person has read the number back and said yes.
    state = state.copyWith(
      isLoading: false,
      password: '',
      accountExists: status.accountExists,
      hasPassword: status.hasPassword,
      askBeforeCode: true,
      clearError: true,
    );
    return true;
  }

  /// The number-and-password page, with nothing left in the field.
  bool _openPasswordPage() {
    state = state.copyWith(
      page: SignInPage.password,
      password: '',
      isLoading: false,
      clearError: true,
    );
    return true;
  }

  /// "Change number" on the ask-first dialog. Nothing was sent; the person
  /// stays on the number and can correct it and try again.
  void cancelCodeConfirmation() => state = state.copyWith(askBeforeCode: false);

  /// "Use a code instead": texts a code to the number and moves to it. After
  /// the code the person sets a password (a new account, an account without
  /// one, or a forgotten one).
  Future<bool> useCodeInstead() async {
    final number = state.e164;
    if (number == null) return _fail(SignInCopy.badPhoneNumber);
    state = state.copyWith(
      isLoading: true,
      clearError: true,
      password: '',
      askBeforeCode: false,
    );
    try {
      final runtime = await _currentRuntime();
      final challenge = await runtime.engine.account.requestPhoneCode(number);
      _challengeId = challenge.challengeId;
      state = state.copyWith(page: SignInPage.otp, isLoading: false);
      return true;
    } on Object catch (error) {
      return _fail(SignInCopy.connectFailure(error), loading: false);
    }
  }

  /// Checks the SMS code. What happens next depends on what the number turns
  /// out to be: a new account, an existing one with a password, or an
  /// existing one without.
  Future<bool> submitOtp() async {
    final challengeId = _challengeId;
    if (challengeId == null) return _fail(SignInCopy.requestCodeFirst);
    if (!RegExp(r'^\d{6}$').hasMatch(state.otpCode)) {
      return _fail(SignInCopy.badOtpFormat);
    }

    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final runtime = await _currentRuntime();
      final verified = await runtime.engine.account.verifyPhone(
        challengeId,
        state.otpCode,
      );
      // The verification token is single-use and short-lived; it is presented
      // by register() below, so it is read from the response and held only
      // until then.
      _verificationToken = verified.verificationToken;
      _verifiedAccountId = verified.accountId;
      // The code is only asked for when the password is not the way in, so
      // the next page always sets one.
      state = state.copyWith(
        page: SignInPage.name,
        accountExists: verified.accountExists,
        hasPassword: verified.hasPassword,
        isLoading: false,
        clearError: true,
      );
      return true;
    } on Object catch (error) {
      return _fail(SignInCopy.wrongOtp(error), loading: false);
    }
  }

  String? _verificationToken;
  String? _verifiedAccountId;

  /// Asks for the code again.
  Future<bool> resendOtp() async {
    final number = state.e164;
    if (number == null) return false;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final runtime = await _currentRuntime();
      final challenge = await runtime.engine.account.requestPhoneCode(number);
      _challengeId = challenge.challengeId;
      state = state.copyWith(otpCode: '', isLoading: false);
      return true;
    } on Object catch (error) {
      return _fail(SignInCopy.connectFailure(error), loading: false);
    }
  }

  // -------------------------------------------------------- the password page

  /// Signs in with the password. The password never leaves the device: the
  /// engine derives the auth key and sends only that.
  Future<bool> signInWithPassword() async {
    final number = state.e164;
    if (number == null) return _fail(SignInCopy.badPhoneNumber);
    if (state.password.isEmpty) return _fail(SignInCopy.emptyPassword);

    state = state.copyWith(isLoading: true, clearError: true);
    // Read before signing in: a successful sign-in resets this flow, and the
    // box the person unticked goes with it.
    final remember = state.remember;
    try {
      final runtime = await _currentRuntime();
      // The account may already have a history on another device or in a
      // backup, so the restore step is asked for before the engine signs in:
      // the router acts on it the moment the session exists.
      ref.read(postSignInProvider.notifier).offerRestore();
      await runtime.engine.account.signInWithPassword(
        phoneNumber: number,
        password: state.password,
      );
      await _keepAccount(number);
      if (remember) await _rememberAccount(number, runtime.serverUrl);
      state = state.copyWith(
        completed: true,
        isLoading: false,
        // The password is not kept in UI state a moment longer than it is
        // needed.
        password: '',
      );
      return true;
    } on Object catch (error) {
      ref.read(postSignInProvider.notifier).done();
      return _fail(SignInCopy.passwordRejected(error), loading: false);
    }
  }

  /// "Use a code instead" on the password page.
  Future<bool> forgotPassword() => useCodeInstead();

  /// Opens the setup page directly, as a verified code does.
  @visibleForTesting
  void showSetupPageForTest() =>
      state = state.copyWith(page: SignInPage.name, clearError: true);

  // ------------------------------------------------------------ the name page

  /// Creates the account, or takes the existing one over with the verified
  /// code. Both end with this device signed in.
  Future<bool> completeSetup({bool skip = false}) async {
    if (state.requiresTerms && !state.tosAccepted) {
      return _fail(SignInCopy.termsNotAccepted);
    }
    final token = _verificationToken;
    if (token == null) {
      state = state.copyWith(page: SignInPage.otp);
      return _fail(SignInCopy.enterCodeFirst);
    }
    // Everyone who comes in by code leaves with a password, so the next
    // sign-in needs only the number and the password.
    if (state.newPassword.length < 8) {
      return _fail('Set a password of at least 8 characters.');
    }
    final number = state.e164;
    if (number == null) return _fail(SignInCopy.badPhoneNumber);

    // Read before register(): the moment the device is signed in this flow is
    // reset (`_resetFlow`), and the name typed on this page goes with it.
    final name = skip ? '' : state.displayName.trim();
    final remember = state.remember;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final runtime = await _currentRuntime();
      final invite = state.codeType == SignInCodeType.invitation
          ? decodeHelixInviteCode(state.codeString)?.inviteCode
          : null;
      await runtime.engine.account.register(
        verificationToken: token,
        inviteCode: invite,
        password: state.newPassword,
        accountId: state.accountExists ? _verifiedAccountId : null,
        replaceExisting: state.accountExists,
        phoneNumber: number,
        deviceName: (await ref.read(engineConfigProvider.future)).deviceName,
      );
      if (name.isNotEmpty) {
        // Best effort: a failure here must not undo a registration that
        // already succeeded.
        try {
          await runtime.engine.people.setOwnProfile(name: name);
        } on Object {
          // The profile can be set again from Settings.
        }
      }
      await _keepAccount(number, name: name);
      if (remember) {
        await _rememberAccount(number, runtime.serverUrl, name: name);
      }
      state = state.copyWith(
        completed: true,
        isLoading: false,
        newPassword: '',
        otpCode: '',
      );
      return true;
    } on Object catch (error) {
      return _fail(SignInCopy.registrationFailed(error), loading: false);
    }
  }

  // -------------------------------------------------------------- internals

  /// The runtime for the server this sign-in is on.
  Future<HelixRuntime> _currentRuntime() {
    _chooseServer();
    return ref.read(runtimeProvider.future);
  }

  /// Points this sign-in at its server. Sign-in opens on Orbit Home, so a
  /// device that has not chosen another server (a first install, or one that
  /// just signed out) is pointed at it before anything is asked.
  ///
  /// The Global page is Orbit Home, always: a personal server a person once
  /// approved (and backed out of) must not keep receiving what they type here.
  void _chooseServer() {
    final current = ref.read(serverUrlProvider);
    final wantGlobal = !state.isAdvanced;
    if (current == null || (wantGlobal && !ServerPolicy.isGlobal(current))) {
      ref.read(accountsProvider.notifier).useServer(kGlobalServerUrl);
    }
  }

  /// "Link from another device instead": shows this device's QR code for a
  /// signed-in device to scan, which signs in without a password or an SMS
  /// code and without signing any other device out.
  void linkFromAnotherDevice() {
    ref.read(appRouterProvider).push(RoutePaths.linkThisDevice);
  }

  /// The runtime for [serverUrl], switching servers if needed. Changing the
  /// server tears the old runtime down first, so two never hold the database.
  Future<HelixRuntime> _runtimeFor(Uri serverUrl) {
    if (ref.read(serverUrlProvider) != serverUrl) {
      ref.read(accountsProvider.notifier).useServer(serverUrl);
    }
    return ref.read(runtimeProvider.future);
  }

  /// The account on this device with [number] on the server this page signs
  /// in to, if there is one.
  String? _signedInHere(String number) {
    final server = state.isAdvanced
        ? ref.read(serverUrlProvider)
        : kGlobalServerUrl;
    if (server == null) return null;
    for (final slot in ref.read(accountsProvider).signedIn) {
      if (slot.e164 == number && slot.server == server.toString()) {
        return slot.id;
      }
    }
    return null;
  }

  /// The account is signed in on this device: it is listed, and opened again
  /// at the next start.
  Future<void> _keepAccount(String number, {String name = ''}) =>
      ref.read(accountsProvider.notifier).signedIn(e164: number, name: name);

  /// Adds the number to the sign-in page's saved accounts, most recent
  /// first. The list lives on the device across sign-outs; a password is
  /// never in it.
  Future<void> _rememberAccount(
    String number,
    Uri serverUrl, {
    String name = '',
  }) => ref
      .read(savedAccountsProvider.notifier)
      .remember(
        SavedAccountEntry(
          e164: number,
          server: serverUrl.toString(),
          name: name,
        ),
      );

  /// A saved account on the phone page. One still signed in on this device
  /// opens; otherwise its number goes in and the password page opens (the
  /// number signed in here once, so it is not re-asked).
  void pickSavedAccount(String id) {
    if (id.startsWith(signedInLinePrefix)) {
      unawaited(
        ref
            .read(accountsProvider.notifier)
            .switchTo(id.substring(signedInLinePrefix.length)),
      );
      return;
    }
    final e164 = id;
    var code = SignInState.defaultCountryCode;
    var best = 0;
    for (final c in signInCountries) {
      if (e164.startsWith(c.code) && c.code.length > best) {
        best = c.code.length;
        code = c.code;
      }
    }
    state = state.copyWith(
      countryCode: code,
      digits: e164.substring(best),
      page: SignInPage.password,
      password: '',
      clearError: true,
    );
  }

  /// The x on a saved account: the number is forgotten. Nothing on the
  /// server or in any signed-in data changes.
  Future<void> forgetSavedAccount(String e164) =>
      ref.read(savedAccountsProvider.notifier).forget(e164);

  /// Puts [message] on the current page and reports false, so every caller
  /// can `return _fail(...)`.
  bool _fail(String message, {bool? loading}) {
    state = state.copyWith(
      errorMessage: message,
      isLoading: loading ?? false,
      showPhoneRecoveryPrompt:
          state.isAdvanced && state.codeType == SignInCodeType.invitation,
    );
    return false;
  }
}

/// True when [raw] starts with a Helix prefix but carries no payload after it.
///
/// A person who pasted `HLX-REC-` and nothing else needs to be told the code is
/// incomplete; the same goes for one whose payload does not decode.
bool _isTruncated(String raw) {
  final upper = raw.toUpperCase();
  final prefix = upper.startsWith(kHelixRecoveryPrefix)
      ? kHelixRecoveryPrefix
      : upper.startsWith(kHelixInvitePrefix)
      ? kHelixInvitePrefix
      : null;
  if (prefix == null) return false;
  final payload = upper.substring(prefix.length);
  if (payload.isEmpty) return true;
  // The payload is opaque base64, so it cannot be counted for separators: a
  // code is complete when it decodes into all of its parts, and a paste cut
  // short does not.
  return prefix == kHelixRecoveryPrefix
      ? decodeHelixRecoveryCode(raw) == null
      : decodeHelixInviteCode(raw) == null;
}
