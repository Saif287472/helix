import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:helix_remote/app/composition_root.dart';
import 'package:helix_remote/app/helix_code.dart';
import 'package:helix_remote/app/password_vault.dart';
import 'package:helix_remote/app/phone_hashing.dart';
import 'package:helix_remote/app/remote_account_validation.dart';
import 'package:helix_remote/app/remote_config.dart';
import 'package:helix_remote/app/remote_error_copy.dart';
import 'package:helix_remote/app/remote_rest_client.dart';
import 'package:helix_remote/screens/setup/setup_choices.dart';
import 'package:helix_remote/screens/setup/state/onboarding_state.dart';
import 'package:helix_remote_api/api/rest_client.dart';

/// Drives the sign-in pages.
///
/// Everything before the account exists on this device - the salt, the
/// password parameters, invite and recovery lookups, SMS codes - talks to the
/// server the flow is for through its own client. Only the last step touches
/// the app's composition root, and only when that root already points at the
/// same server; otherwise the flow ends with a choice object and the host
/// builds a root for the right server (see `HelixRemoteBootstrap`).
class OnboardingNotifier extends ChangeNotifier {
  OnboardingNotifier({
    RemoteCompositionRoot? root,
    HelixRemoteRestClient? client,
    HelixRemoteRestClient Function(String serverUrl)? clientFactory,
  }) : _root = root,
       _client = client,
       _clientFactory = clientFactory;

  final RemoteCompositionRoot? _root;
  final HelixRemoteRestClient? _client;
  final HelixRemoteRestClient Function(String serverUrl)? _clientFactory;
  final Map<String, HelixRemoteRestClient> _clients = {};
  final Map<String, String> _salts = {};

  OnboardingState _state = const OnboardingState();
  OnboardingState get state => _state;

  /// Set when the flow finished without a matching root; the host completes
  /// the sign-in with it.
  Object? completedChoice;

  RemotePasswordLookup? _passwordLookup;
  ({String serverUrl, String accountId, String recoveryCode})? _recovery;
  bool _recoverySmsRequired = true;

  void _set(OnboardingState next) {
    _state = next;
    notifyListeners();
  }

  /// Shows [message] on the current page.
  void showError(String message) => _fail(message);

  void _fail(String message) =>
      _set(_state.copyWith(isLoading: false, errorMessage: message));

  // ---------------------------------------------------------------------------
  // Which server
  // ---------------------------------------------------------------------------

  /// The server every request of this flow goes to.
  String get serverUrl => _state.isAdvanced
      ? (_state.serverUrl ?? kHelixGlobalServerUrl)
      : kHelixGlobalServerUrl;

  /// The app's root, when it already points at [serverUrl].
  RemoteCompositionRoot? get _matchingRoot {
    final root = _root;
    if (root == null) return null;
    final rootOrigin = root.devConfig.restBaseUri.origin;
    return rootOrigin == Uri.parse(serverUrl).origin ? root : null;
  }

  HelixRemoteRestClient _clientFor(String url) {
    final injected = _client;
    if (injected != null) return injected;
    return _clients.putIfAbsent(
      url,
      () =>
          _clientFactory?.call(url) ??
          HelixRemoteRestClientImpl(baseUri: Uri.parse(url), timeoutMs: 10000),
    );
  }

  HelixRemoteRestClient get _serverClient => _clientFor(serverUrl);

  Future<String> _salt({bool refresh = false}) async {
    final url = serverUrl;
    final cached = _salts[url];
    if (cached != null && !refresh) return cached;
    final salt = (await _serverClient.fetchDiscoverySalt())['salt'] as String?;
    if (salt == null || salt.isEmpty) {
      throw StateError('The server did not provide a phone-hash salt.');
    }
    return _salts[url] = salt;
  }

  String get phoneNumber => RemoteAccountValidation.normalizePhoneNumber(
    '${_state.countryCode}${_nationalDigits(_state.phoneNumber)}',
  );

  static String _nationalDigits(String typed) {
    final digits = typed.replaceAll(RegExp(r'[^\d]'), '');
    return digits.startsWith('0') ? digits.substring(1) : digits;
  }

  // ---------------------------------------------------------------------------
  // Advanced mode
  // ---------------------------------------------------------------------------

  /// Opens advanced mode (a personal server) on its code page.
  void openAdvancedMode({String? code}) {
    _resetAccountProgress();
    _recovery = null;
    _set(
      _state.copyWith(
        mode: SetupMode.advanced,
        page: SetupPage.code,
        codeString: code ?? _state.codeString,
        clearCodeType: true,
        clearServer: true,
        clearErrorMessage: true,
        isLoading: false,
      ),
    );
  }

  /// An invite or recovery link opened from outside the app: advanced mode
  /// with the code filled in and checked straight away.
  Future<bool> openWithCode(String code) {
    openAdvancedMode(code: code.trim());
    return submitCode();
  }

  /// Back to the simple Global page.
  void leaveAdvancedMode() {
    _resetAccountProgress();
    _recovery = null;
    _set(
      _state.copyWith(
        mode: SetupMode.global,
        page: SetupPage.phone,
        codeString: '',
        clearCodeType: true,
        clearServer: true,
        clearErrorMessage: true,
        isLoading: false,
      ),
    );
  }

  void updateCodeString(String code) {
    _set(_state.copyWith(codeString: code, clearErrorMessage: true));
  }

  /// What the typed code looks like, for the hint under the field.
  CodeType? get detectedCodeType {
    final raw = _state.codeString.trim();
    if (raw.isEmpty) return null;
    if (isHelixRecoveryCode(raw)) return CodeType.recovery;
    return CodeType.invitation;
  }

  /// The code page's "Next": works out whether the code is an invite or a
  /// recovery code, checks it with its server and moves on to the phone.
  Future<bool> submitCode() async {
    final raw = _state.codeString.trim();
    if (raw.isEmpty) {
      _fail('Enter the invite or recovery code you were given.');
      return false;
    }
    _set(_state.copyWith(isLoading: true, clearErrorMessage: true));

    final recovery = decodeHelixRecoveryCode(raw);
    if (recovery != null) {
      return _acceptRecoveryCode(recovery);
    }
    if (isHelixRecoveryCode(raw)) {
      _fail('This recovery code is not complete. Copy the whole code again.');
      return false;
    }

    final invite = decodeHelixInviteCode(raw);
    if (invite == null) {
      _fail(
        'This is not an invite or recovery code. Paste the whole HLX-INV- '
        'or HLX-REC- code you were given.',
      );
      return false;
    }
    return _acceptInvite(invite.serverUrl, invite.inviteCode);
  }

  Future<bool> _acceptRecoveryCode(
    ({String serverUrl, String accountId, String recoveryCode}) recovery,
  ) async {
    try {
      final response = await _clientFor(recovery.serverUrl).lookupRecovery(
        accountId: recovery.accountId,
        recoveryCode: recovery.recoveryCode,
      );
      if (response['valid'] != true) {
        _fail(switch (response['reason']) {
          'blocked' => 'The account this code is for has been blocked.',
          _ =>
            'This recovery code is not valid. It may have expired or been '
                'used already - ask your server admin for a new one.',
        });
        return false;
      }
      _recovery = recovery;
      _recoverySmsRequired = response['sms_required'] != false;
      _set(
        _state.copyWith(
          isLoading: false,
          codeType: CodeType.recovery,
          serverUrl: recovery.serverUrl,
          serverName: _nameOr(response['server_name'], 'Personal server'),
          page: SetupPage.phone,
        ),
      );
      return true;
    } catch (e) {
      _fail(_connectError(e, recovery.serverUrl));
      return false;
    }
  }

  Future<bool> _acceptInvite(String inviteServerUrl, String inviteCode) async {
    try {
      final lookup = await _clientFor(
        inviteServerUrl,
      ).lookupInvite(inviteCode: inviteCode);
      if (lookup['valid'] != true) {
        _fail(switch (lookup['reason']) {
          'already_used' => 'This invite code has already been used.',
          'cancelled' => 'This invite code was cancelled by the server admin.',
          'expired' => 'This invite code has expired.',
          _ => 'This invite code is not valid.',
        });
        return false;
      }
      _recovery = null;
      _set(
        _state.copyWith(
          isLoading: false,
          codeType: CodeType.invitation,
          serverUrl: inviteServerUrl,
          serverName: _nameOr(lookup['server_name'], 'Personal server'),
          inviteCode: inviteCode,
          page: SetupPage.phone,
        ),
      );
      return true;
    } catch (e) {
      _fail(_connectError(e, inviteServerUrl));
      return false;
    }
  }

  static String _nameOr(Object? name, String fallback) {
    final trimmed = (name as String? ?? '').trim();
    return trimmed.isEmpty ? fallback : trimmed;
  }

  String _connectError(Object e, String url) {
    if (e is RemoteRestException) {
      return RemoteUserErrorCopy.registrationFailure(e, Uri.parse(url));
    }
    return 'Could not reach the server. Check your connection and try again.';
  }

  // ---------------------------------------------------------------------------
  // Phone
  // ---------------------------------------------------------------------------

  void updateCountryCode(String code) {
    _set(_state.copyWith(countryCode: code, clearErrorMessage: true));
  }

  void updatePhoneNumber(String phone) {
    _resetAccountProgress();
    _set(_state.copyWith(phoneNumber: phone, clearErrorMessage: true));
  }

  void _resetAccountProgress() {
    _passwordLookup = null;
    _state = _state.copyWith(
      password: '',
      otpCode: '',
      phoneHash: '',
      otpChallengeId: '',
      accountExists: false,
    );
  }

  /// The phone page's "Next". An account with a password goes to the
  /// password page - no SMS, no cost. Otherwise the SMS code is sent.
  Future<bool> submitPhone() async {
    final phone = phoneNumber;
    if (RemoteAccountValidation.phoneNumberError(phone) != null) {
      _fail('Enter a valid phone number.');
      return false;
    }
    _set(_state.copyWith(isLoading: true, clearErrorMessage: true));

    try {
      final hash = phoneHash(await _salt(), phone);
      final recovery = _recovery;
      if (_state.isRecovery && recovery != null) {
        final check = await _serverClient.lookupRecovery(
          accountId: recovery.accountId,
          recoveryCode: recovery.recoveryCode,
          phoneHash: hash,
        );
        if (check['valid'] != true) {
          _fail('This recovery code is no longer valid.');
          return false;
        }
        if (check['phone_matches'] != true) {
          _fail(
            'This phone number does not belong to the account this recovery '
            'code is for.',
          );
          return false;
        }
      }

      final lookup = await _lookupPassword(phone, hash);
      _passwordLookup = lookup;
      _state = _state.copyWith(
        phoneHash: hash,
        accountExists: lookup.accountExists || _state.isRecovery,
      );
      if (!lookup.hasPassword &&
          lookup.accountExists &&
          _state.codeType == CodeType.invitation) {
        // An invite is for a new account; this number already has one here
        // and it has no password, so the way back in is a recovery code.
        _set(_state.copyWith(isLoading: false, showPhoneRecoveryPrompt: true));
        return false;
      }
      if (lookup.hasPassword) {
        _set(
          _state.copyWith(
            isLoading: false,
            password: '',
            page: SetupPage.password,
          ),
        );
        return true;
      }
    } catch (e) {
      _fail(_connectError(e, serverUrl));
      return false;
    }
    return _startSmsStep();
  }

  Future<RemotePasswordLookup> _lookupPassword(
    String phone,
    String hash,
  ) async {
    final response = await _serverClient.getPasswordParams(phoneHash: hash);
    final hasPassword = response['has_password'] == true;
    return RemotePasswordLookup(
      phoneNumber: phone,
      phoneHash: hash,
      accountExists: response['account_exists'] == true,
      hasPassword: hasPassword,
      kdfParams: hasPassword
          ? PasswordKdfParams.fromJson(
              response['kdf_params'] as Map<String, dynamic>,
            )
          : null,
      kdfSalt: hasPassword ? response['kdf_salt'] as String? : null,
    );
  }

  /// No password (or a forgotten one): the SMS code. A recovery on a server
  /// that cannot send SMS goes straight to the reset - the administrator's
  /// code is all such a server has to go on.
  Future<bool> _startSmsStep() async {
    if (_state.isRecovery && !_recoverySmsRequired) {
      return _redeemRecovery();
    }
    return requestOtp();
  }

  // ---------------------------------------------------------------------------
  // Password
  // ---------------------------------------------------------------------------

  void updatePassword(String value) {
    _set(_state.copyWith(password: value, clearErrorMessage: true));
  }

  /// Signs in with the password. This device joins the account; every other
  /// signed-in device stays signed in and nothing is reset.
  Future<bool> signInWithPassword() async {
    final lookup = _passwordLookup;
    final password = _state.password;
    if (lookup == null || !lookup.hasPassword) {
      _set(
        _state.copyWith(
          page: SetupPage.phone,
          errorMessage: 'Enter your phone number again.',
        ),
      );
      return false;
    }
    if (password.isEmpty) {
      _fail('Enter your password.');
      return false;
    }
    _set(_state.copyWith(isLoading: true, clearErrorMessage: true));
    try {
      final keys = await PasswordVault.deriveKeys(
        password: password,
        salt: lookup.kdfSalt!,
        params: lookup.kdfParams!,
      );
      final root = _matchingRoot;
      if (root != null) {
        await root.signInWithPasswordKeys(lookup: lookup, keys: keys);
      } else {
        // Check the password now, so a typo is reported on this page; the
        // host signs in with the keys once it has a root for this server.
        await _serverClient.verifyPassword(
          phoneHash: lookup.phoneHash,
          authKey: keys.authKey,
        );
        completedChoice = ServerPasswordChoice(
          serverUrl: serverUrl,
          lookup: lookup,
          keys: keys,
        );
      }
      _set(_state.copyWith(isLoading: false, isComplete: true, password: ''));
      return true;
    } catch (e) {
      _fail(passwordSignInErrorMessage(e));
      return false;
    }
  }

  /// "Forgot password": the SMS code instead. Signing in that way resets the
  /// account onto this device, so the others are signed out.
  Future<bool> forgotPassword() {
    _state = _state.copyWith(password: '');
    return _startSmsStep();
  }

  // ---------------------------------------------------------------------------
  // SMS code
  // ---------------------------------------------------------------------------

  void updateOtpCode(String otp) {
    _set(_state.copyWith(otpCode: otp, clearErrorMessage: true));
  }

  Future<bool> requestOtp() async {
    final phone = phoneNumber;
    _set(
      _state.copyWith(
        isLoading: true,
        clearErrorMessage: true,
        otpCode: '',
        otpChallengeId: '',
      ),
    );
    try {
      var hash = phoneHash(await _salt(), phone);
      Map<String, dynamic> response;
      try {
        response = await _serverClient.requestPhoneOtp(
          phoneHash: hash,
          phoneNumber: phone,
        );
      } on RemoteRestException catch (e) {
        // The server's salt changed since it was fetched; fetch it once more.
        if (e.serverCode != RemoteApiErrorCodes.discoverySaltStale) rethrow;
        hash = phoneHash(await _salt(refresh: true), phone);
        response = await _serverClient.requestPhoneOtp(
          phoneHash: hash,
          phoneNumber: phone,
        );
      }
      final challengeId = response['challenge_id'] as String? ?? '';
      if (challengeId.isEmpty) {
        throw StateError('The server did not return a usable SMS code.');
      }
      _set(
        _state.copyWith(
          isLoading: false,
          phoneHash: hash,
          otpChallengeId: challengeId,
          page: SetupPage.otp,
        ),
      );
      return true;
    } catch (e) {
      _fail(
        e is RemoteRestException
            ? RemoteUserErrorCopy.registrationFailure(e, Uri.parse(serverUrl))
            : RemoteUserErrorCopy.scrubDomain(e.toString()),
      );
      return false;
    }
  }

  /// Checks the SMS code without using it up, then finishes a recovery or
  /// moves on to the name page.
  Future<bool> submitOtp() async {
    final otp = _state.otpCode.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(otp)) {
      _fail('Enter the six-digit code from the SMS.');
      return false;
    }
    if (_state.phoneHash.isEmpty || _state.otpChallengeId.isEmpty) {
      _fail('Request a new code first.');
      return false;
    }
    _set(
      _state.copyWith(isLoading: true, clearErrorMessage: true, otpCode: otp),
    );
    try {
      final response = await _serverClient.verifyPhoneOtp(
        phoneHash: _state.phoneHash,
        otpCode: otp,
        challengeId: _state.otpChallengeId,
      );
      if (response['valid'] != true) {
        throw StateError('That code is not right.');
      }
    } catch (e) {
      _fail(
        e is RemoteRestException
            ? RemoteUserErrorCopy.registrationFailure(e, Uri.parse(serverUrl))
            : 'That code is not right. Check the SMS and try again.',
      );
      return false;
    }
    if (_state.isRecovery) return _redeemRecovery();
    _set(_state.copyWith(isLoading: false, page: SetupPage.name));
    return true;
  }

  /// Today's destructive recovery: resets the account onto this device and
  /// signs every other device out.
  Future<bool> _redeemRecovery() async {
    final recovery = _recovery;
    if (recovery == null) {
      leaveAdvancedMode();
      return false;
    }
    _set(_state.copyWith(isLoading: true, clearErrorMessage: true));
    final otp = _state.otpCode.isEmpty ? null : _state.otpCode;
    final challenge = _state.otpChallengeId.isEmpty
        ? null
        : _state.otpChallengeId;
    final root = _matchingRoot;
    if (root == null) {
      completedChoice = ServerRecoveryChoice(
        serverUrl: recovery.serverUrl,
        accountId: recovery.accountId,
        recoveryCode: recovery.recoveryCode,
        phoneHash: _state.phoneHash,
        phoneNumber: phoneNumber,
        otpCode: otp,
        otpChallengeId: challenge,
      );
      _set(_state.copyWith(isLoading: false, isComplete: true));
      return true;
    }
    try {
      await root.recoverAccount(
        accountId: recovery.accountId,
        recoveryCode: recovery.recoveryCode,
        phoneHash: _state.phoneHash,
        phoneNumber: phoneNumber,
        otpCode: otp,
        otpChallengeId: challenge,
      );
      _set(_state.copyWith(isLoading: false, isComplete: true));
      return true;
    } catch (e) {
      _fail(
        e is RemoteRestException
            ? RemoteUserErrorCopy.registrationFailure(e, Uri.parse(serverUrl))
            : 'Could not restore the account. Please try again.',
      );
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Name and terms
  // ---------------------------------------------------------------------------

  void updateDisplayName(String name) {
    _set(_state.copyWith(displayName: name));
  }

  void setTosAccepted(bool value) {
    _set(_state.copyWith(tosAccepted: value, clearErrorMessage: true));
  }

  /// Helix Global asks every account to accept its terms; personal servers
  /// have their own operator policies.
  bool get requiresTerms => !_state.isAdvanced;

  /// Creates the account (or, for an existing Global account without a
  /// password, brings it onto this device) with the verified SMS code.
  Future<bool> completeSetup({bool skip = false}) async {
    if (requiresTerms && !_state.tosAccepted) {
      _fail('Accept the Terms of Service and Privacy Policy to continue.');
      return false;
    }
    final otp = _state.otpCode.trim();
    if (otp.isEmpty) {
      _set(
        _state.copyWith(
          page: SetupPage.otp,
          errorMessage: 'Enter the code sent to your phone first.',
        ),
      );
      return false;
    }
    final inviteCode = _state.isAdvanced ? (_state.inviteCode ?? '') : '';
    if (_state.isAdvanced && inviteCode.isEmpty) {
      _fail('This server needs an invite code.');
      return false;
    }
    _set(
      _state.copyWith(
        isLoading: true,
        clearErrorMessage: true,
        showPhoneRecoveryPrompt: false,
      ),
    );

    final phone = phoneNumber;
    final entered = _state.displayName.trim();
    final name = (skip || entered.isEmpty) ? phone : entered;

    final root = _matchingRoot;
    if (root != null) {
      try {
        await root.registerAndLogin(
          phoneNumber: phone,
          phoneHashOverride: _state.phoneHash,
          displayName: name,
          otpCode: otp,
          otpChallengeId: _state.otpChallengeId,
          inviteCode: inviteCode,
          tosAccepted: requiresTerms && _state.tosAccepted,
          tosVersion: _state.tosVersion,
        );
      } catch (e) {
        final isPhoneConflict =
            e is RemoteRestException &&
            e.serverCode == RemoteApiErrorCodes.phoneAlreadyRegistered;
        final isOtpError =
            e is RemoteRestException &&
            e.serverCode == RemoteApiErrorCodes.invalidOtp;
        _set(
          _state.copyWith(
            isLoading: false,
            errorMessage: isPhoneConflict
                ? null
                : (e is RemoteRestException
                      ? RemoteUserErrorCopy.registrationFailure(
                          e,
                          root.devConfig.restBaseUri,
                        )
                      : RemoteUserErrorCopy.unknownRegistration()),
            clearErrorMessage: isPhoneConflict,
            showPhoneRecoveryPrompt: isPhoneConflict,
            page: isOtpError ? SetupPage.otp : _state.page,
          ),
        );
        return false;
      }
    } else {
      completedChoice = ServerInviteChoice(
        serverUrl: serverUrl,
        inviteCode: inviteCode,
        phoneNumber: phone,
        serverName: _state.serverName,
        displayName: name,
        otpCode: otp,
        phoneHash: _state.phoneHash,
        otpChallengeId: _state.otpChallengeId,
        tosAccepted: requiresTerms && _state.tosAccepted,
        tosVersion: _state.tosVersion,
      );
    }
    _set(
      _state.copyWith(isLoading: false, isComplete: true, displayName: name),
    );
    return true;
  }

  /// A personal server said this number already has an account: the way in
  /// is the recovery code the server admin can issue.
  void beginPhoneRecovery() {
    openAdvancedMode(code: '');
  }

  void dismissPhoneRecoveryPrompt() {
    _set(
      _state.copyWith(showPhoneRecoveryPrompt: false, clearErrorMessage: true),
    );
  }

  // ---------------------------------------------------------------------------
  // Back
  // ---------------------------------------------------------------------------

  bool get canGoBack => _state.page != SetupPage.phone || _state.isAdvanced;

  void goBack() {
    if (_state.isLoading) return;
    switch (_state.page) {
      case SetupPage.name:
      case SetupPage.password:
        _resetAccountProgress();
        _set(_state.copyWith(page: SetupPage.phone, clearErrorMessage: true));
      case SetupPage.otp:
        _set(
          _state.copyWith(
            page: _passwordLookup?.hasPassword == true
                ? SetupPage.password
                : SetupPage.phone,
            otpCode: '',
            clearErrorMessage: true,
          ),
        );
      case SetupPage.phone:
        if (_state.isAdvanced) {
          _resetAccountProgress();
          _set(_state.copyWith(page: SetupPage.code, clearErrorMessage: true));
        }
      case SetupPage.code:
        leaveAdvancedMode();
    }
  }
}

/// What to tell the user when a password sign-in fails.
String passwordSignInErrorMessage(Object error) {
  if (error is RemotePasswordKeyMismatch) {
    return 'This password no longer unlocks your account. Use "Forgot '
        'password" to reset it with an SMS code.';
  }
  if (error is RemoteRestException) {
    switch (error.serverCode) {
      case 'password_incorrect':
        return 'That password is not right. Try again, or use "Forgot '
            'password".';
      case 'password_locked':
        final until = error.serverDetails?['locked_until'];
        if (until is int) {
          final time = DateTime.fromMillisecondsSinceEpoch(until);
          final hh = time.hour.toString().padLeft(2, '0');
          final mm = time.minute.toString().padLeft(2, '0');
          return 'Too many wrong passwords. Try again after $hh:$mm, or use '
              '"Forgot password".';
        }
        return 'Too many wrong passwords. Try again later, or use "Forgot '
            'password".';
      case 'account_blocked':
      case 'phone_blocked':
        return 'This account has been blocked.';
    }
    if (error.isTransportFailure) {
      return 'Could not reach the server. Check your connection and try '
          'again.';
    }
  }
  return 'Could not sign in. Please try again.';
}
