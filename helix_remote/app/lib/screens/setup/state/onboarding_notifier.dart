import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:helix_remote_api/api/rest_client.dart';
import 'package:helix_remote/app/composition_root.dart';
import 'package:helix_remote/app/helix_code.dart';
import 'package:helix_remote/app/phone_hashing.dart';
import 'package:helix_remote/app/remote_config.dart';
import 'package:helix_remote/app/remote_error_copy.dart';
import 'package:helix_remote/app/remote_rest_client.dart';
import 'package:helix_remote/screens/invite_entry_screen.dart';
import 'package:helix_remote/screens/setup/state/onboarding_state.dart';

class OnboardingNotifier extends ChangeNotifier {
  OnboardingNotifier({
    RemoteCompositionRoot? root,
    HelixRemoteRestClient? client,
    bool autoStartLaunch = true,
    Future<void> Function(String url)? onServerUrlChanged,
  }) : _root = root,
       _client = client,
       _onServerUrlChanged = onServerUrlChanged {
    if (autoStartLaunch) {
      Future.microtask(_runLaunchSequence);
    }
  }

  final RemoteCompositionRoot? _root;
  final HelixRemoteRestClient? _client;
  final Future<void> Function(String url)? _onServerUrlChanged;
  OnboardingState _state = const OnboardingState();
  Timer? _launchTimer;

  OnboardingState get state => _state;
  Object? completedChoice;

  @override
  void dispose() {
    _launchTimer?.cancel();
    super.dispose();
  }

  void updateState(OnboardingState Function(OnboardingState current) update) {
    _state = update(_state);
    notifyListeners();
  }

  void _runLaunchSequence() {
    _state = _state.copyWith(
      isLoading: true,
      loadingStatus: 'Deploying Helix…',
    );
    notifyListeners();

    _launchTimer = Timer(const Duration(milliseconds: 300), () {
      _state = _state.copyWith(loadingStatus: 'Retrieving user data…');
      notifyListeners();

      _launchTimer = Timer(const Duration(milliseconds: 300), () {
        _state = _state.copyWith(
          step: OnboardingStep.serverSelection,
          isLoading: false,
        );
        notifyListeners();
      });
    });
  }

  void setServerType(ServerType type) {
    final rootTargetsGlobal =
        _root?.devConfig.restBaseUri.origin ==
        Uri.parse(kHelixGlobalServerUrl).origin;
    if (type == ServerType.global &&
        _root != null &&
        !rootTargetsGlobal &&
        _onServerUrlChanged != null) {
      // A saved personal-server root must never receive Global OTP or
      // registration traffic. Ask the host to rebuild the unauthenticated
      // root at the fixed Global endpoint before continuing.
      _state = _state.copyWith(
        serverType: type,
        connectedServerName: 'Helix Global Server',
        isLoading: true,
        clearErrorMessage: true,
      );
      notifyListeners();
      unawaited(_onServerUrlChanged(kHelixGlobalServerUrl));
      return;
    }

    _state = _state.copyWith(
      serverType: type,
      connectedServerName: type == ServerType.global
          ? 'Helix Global Server'
          : (_state.connectedServerName ?? 'Personal Server'),
    );
    notifyListeners();
  }

  void switchMainTab(ServerType tab) {
    setServerType(tab);
  }

  void switchOthersSubTab(OthersOption option) {
    setOthersOption(option);
  }

  void setOthersOption(OthersOption option) {
    final nextStep = _state.step == OnboardingStep.serverSelection
        ? OnboardingStep.serverSelection
        : (option == OthersOption.host
              ? OnboardingStep.hostGuide
              : OnboardingStep.codeEntry);
    _state = _state.copyWith(
      othersOption: option,
      step: nextStep,
      hostGuideStep: 0,
    );
    notifyListeners();
  }

  void setGlobalSubStep(GlobalSubStep subStep) {
    _state = _state.copyWith(
      globalSubStep: subStep,
      step: OnboardingStep.serverSelection,
    );
    notifyListeners();
  }

  void setJoinSubStep(JoinSubStep subStep) {
    _state = _state.copyWith(
      joinSubStep: subStep,
      step: OnboardingStep.serverSelection,
    );
    notifyListeners();
  }

  void updateHostGuideStep(int stepIndex) {
    _state = _state.copyWith(hostGuideStep: stepIndex);
    notifyListeners();
  }

  void proceedFromServerSelection() {
    if (_state.serverType == ServerType.global) {
      setGlobalSubStep(GlobalSubStep.phone);
    } else {
      _state = _state.copyWith(step: OnboardingStep.othersHub);
      notifyListeners();
    }
  }

  void updateCountryCode(String code) {
    _state = _state.copyWith(countryCode: code);
    notifyListeners();
  }

  void updatePhoneNumber(String phone) {
    _state = _state.copyWith(
      phoneNumber: phone,
      otpCode: '',
      phoneHash: '',
      otpChallengeId: '',
    );
    notifyListeners();
  }

  void updateOtpCode(String otp) {
    _state = _state.copyWith(otpCode: otp);
    notifyListeners();
  }

  void toggleRememberDevice(bool value) {
    _state = _state.copyWith(rememberDevice: value);
    notifyListeners();
  }

  void setTosAccepted(bool value) {
    _state = _state.copyWith(tosAccepted: value, clearErrorMessage: true);
    notifyListeners();
  }

  /// Moves a duplicate-phone registration into the existing recovery-code
  /// flow. The backend never returns an account id for this conflict, so the
  /// user must present a code issued by an administrator or the account's
  /// authorized recovery process.
  void beginPhoneRecovery({String? serverUrl}) {
    _state = _state.copyWith(
      serverType: ServerType.others,
      othersOption: OthersOption.join,
      step: OnboardingStep.codeEntry,
      joinSubStep: JoinSubStep.code,
      serverNodeUrl: serverUrl ?? _state.serverNodeUrl,
      codeType: CodeType.recovery,
      codeString: '',
      showPhoneRecoveryPrompt: false,
      clearErrorMessage: true,
    );
    notifyListeners();
  }

  void dismissPhoneRecoveryPrompt() {
    _state = _state.copyWith(
      showPhoneRecoveryPrompt: false,
      clearErrorMessage: true,
    );
    notifyListeners();
  }

  void updateDisplayName(String name) {
    _state = _state.copyWith(displayName: name);
    notifyListeners();
  }

  void updateCodeString(String code) {
    _state = _state.copyWith(codeString: code);
    notifyListeners();
  }

  void toggleCodeInfoPopover() {
    _state = _state.copyWith(showCodeInfoPopover: !_state.showCodeInfoPopover);
    notifyListeners();
  }

  String get fullPhoneNumber {
    final digits = _state.phoneNumber.replaceAll(RegExp(r'[^\d]'), '');
    final national = digits.startsWith('0') ? digits.substring(1) : digits;
    return '${_state.countryCode}$national';
  }

  Future<bool> requestOtp({bool isPersonal = false}) async {
    final digits = _state.phoneNumber.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.length < 6) {
      _state = _state.copyWith(
        errorMessage: 'Please enter a valid phone number.',
      );
      notifyListeners();
      return false;
    }

    final isGlobal = !isPersonal && _state.serverType == ServerType.global;
    _state = _state.copyWith(
      isLoading: true,
      clearErrorMessage: true,
      otpCode: '',
      phoneHash: '',
      otpChallengeId: '',
    );
    notifyListeners();

    // Helix Global does not use invitations at all: the server sends the OTP
    // to the entered number, and whether that number is brand new or already
    // owns an account is resolved server-side after the OTP is verified. So we
    // never request or surface an invite code on the Global path. Personal
    // servers keep whatever invite the user joined with.
    final inviteCode = isGlobal ? '' : (_state.inviteCode ?? '');
    final targetUrl = (isPersonal || _state.serverType == ServerType.others)
        ? (_state.serverNodeUrl ?? kHelixGlobalServerUrl)
        : kHelixGlobalServerUrl;

    try {
      final RemoteOtpRequestResult otpRequest;
      if (_root != null) {
        otpRequest = await _root.requestOtp(fullPhoneNumber);
      } else {
        final client =
            _client ??
            HelixRemoteRestClientImpl(
              baseUri: Uri.parse(targetUrl),
              timeoutMs: 10000,
            );
        final saltResponse = await client.fetchDiscoverySalt();
        var salt = saltResponse['salt'] as String?;
        if (salt == null || salt.isEmpty) {
          throw StateError(
            'The Global server did not provide a phone-hash salt.',
          );
        }
        var hash = phoneHash(salt, fullPhoneNumber);
        Map<String, dynamic> otpResponse;
        try {
          otpResponse = await client.requestPhoneOtp(
            phoneHash: hash,
            phoneNumber: fullPhoneNumber,
          );
        } on RemoteRestException catch (e) {
          // The server could not reproduce our hash from the number we sent,
          // so its salt has changed since we fetched it. Fetch once more and
          // retry; this path holds no cached salt, so a second failure is
          // genuine and the original error stands.
          if (e.serverCode != RemoteApiErrorCodes.discoverySaltStale) rethrow;
          final retrySalt =
              (await client.fetchDiscoverySalt())['salt'] as String?;
          if (retrySalt == null || retrySalt.isEmpty) rethrow;
          salt = retrySalt;
          hash = phoneHash(salt, fullPhoneNumber);
          otpResponse = await client.requestPhoneOtp(
            phoneHash: hash,
            phoneNumber: fullPhoneNumber,
          );
        }
        otpRequest = RemoteOtpRequestResult(
          phoneHash: hash,
          challengeId: otpResponse['challenge_id'] as String? ?? '',
        );
      }

      if (isGlobal && otpRequest.challengeId.isEmpty) {
        throw StateError(
          'The Global server did not return a usable OTP challenge.',
        );
      }

      _state = _state.copyWith(
        isLoading: false,
        inviteCode: inviteCode,
        phoneHash: otpRequest.phoneHash,
        otpChallengeId: otpRequest.challengeId,
        otpIsPlaceholder: false,
        globalSubStep: isPersonal ? _state.globalSubStep : GlobalSubStep.otp,
        joinSubStep: isPersonal ? JoinSubStep.otp : _state.joinSubStep,
        step: OnboardingStep.serverSelection,
      );
      notifyListeners();
      return true;
    } catch (e) {
      final msg = e is RemoteRestException
          ? RemoteUserErrorCopy.registrationFailure(
              e,
              _root?.devConfig.restBaseUri ?? Uri.parse(targetUrl),
            )
          : RemoteUserErrorCopy.scrubDomain(e.toString());
      _state = _state.copyWith(
        isLoading: false,
        errorMessage: msg,
        inviteCode: inviteCode,
      );
      notifyListeners();
      return false;
    }
  }

  Future<bool> verifyOtp({bool isPersonal = false}) async {
    final otp = _state.otpCode.trim();
    if (otp.isEmpty) {
      _state = _state.copyWith(
        errorMessage: 'Please enter the verification code sent to your phone.',
      );
      notifyListeners();
      return false;
    }
    final isGlobal = !isPersonal && _state.serverType == ServerType.global;
    if (isGlobal && !RegExp(r'^\d{6}$').hasMatch(otp)) {
      _state = _state.copyWith(
        errorMessage: 'Enter the six-digit verification code from your SMS.',
      );
      notifyListeners();
      return false;
    }

    _state = _state.copyWith(
      isLoading: true,
      clearErrorMessage: true,
      otpCode: otp,
    );
    notifyListeners();

    try {
      if (isGlobal) {
        if (_state.phoneHash.isEmpty) {
          throw StateError('Request a new verification code first.');
        }
        if (_root != null) {
          await _root.verifyOtp(
            phoneHash: _state.phoneHash,
            otpCode: otp,
            challengeId: _state.otpChallengeId,
          );
        } else {
          final targetUrl = _state.serverNodeUrl ?? kHelixGlobalServerUrl;
          final client =
              _client ??
              HelixRemoteRestClientImpl(
                baseUri: Uri.parse(targetUrl),
                timeoutMs: 10000,
              );
          final response = await client.verifyPhoneOtp(
            phoneHash: _state.phoneHash,
            otpCode: otp,
            challengeId: _state.otpChallengeId,
          );
          if (response['valid'] != true) {
            throw StateError(
              'The server did not accept the verification code.',
            );
          }
        }
      } else {
        // Preserve the existing personal-server behavior. Personal servers
        // may still use the older optimistic OTP step; Global is the path
        // that must validate before profile creation.
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
    } catch (e) {
      final backend =
          _root?.devConfig.restBaseUri ??
          Uri.parse(_state.serverNodeUrl ?? kHelixGlobalServerUrl);
      final msg = e is RemoteRestException
          ? RemoteUserErrorCopy.registrationFailure(e, backend)
          : RemoteUserErrorCopy.scrubDomain(e.toString());
      _state = _state.copyWith(
        isLoading: false,
        errorMessage: msg,
        globalSubStep: isGlobal ? GlobalSubStep.otp : _state.globalSubStep,
        joinSubStep: isGlobal ? _state.joinSubStep : JoinSubStep.name,
        step: OnboardingStep.serverSelection,
      );
      notifyListeners();
      return false;
    }

    _state = _state.copyWith(
      isLoading: false,
      isExistingUser: false,
      globalSubStep: isGlobal ? GlobalSubStep.name : _state.globalSubStep,
      joinSubStep: isGlobal ? _state.joinSubStep : JoinSubStep.name,
      step: OnboardingStep.serverSelection,
    );
    notifyListeners();

    return true;
  }

  Future<bool> resolveCode() async {
    final rawCode = _state.codeString.trim();
    if (rawCode.isEmpty) {
      _state = _state.copyWith(errorMessage: 'Please enter a code or link.');
      notifyListeners();
      return false;
    }

    _state = _state.copyWith(isLoading: true, clearErrorMessage: true);
    notifyListeners();

    await Future<void>.delayed(const Duration(milliseconds: 200));

    // 1. Try HLX-REC- recovery code
    final recovery = decodeHelixRecoveryCode(rawCode);
    if (recovery != null) {
      _state = _state.copyWith(
        isLoading: true,
        codeType: CodeType.recovery,
        loadingStatus: 'Recovering account state…',
        serverNodeUrl: recovery.serverUrl,
        connectedServerName: 'Restored Server Node',
        joinSubStep: JoinSubStep.recoverySync,
        step: OnboardingStep.serverSelection,
      );
      notifyListeners();

      if (_root != null) {
        try {
          await _root.recoverAccount(
            accountId: recovery.accountId,
            recoveryCode: recovery.recoveryCode,
          );
          completedChoice = ServerRecoveryChoice(
            serverUrl: recovery.serverUrl,
            accountId: recovery.accountId,
            recoveryCode: recovery.recoveryCode,
          );
          _state = _state.copyWith(isLoading: false, isComplete: true);
          notifyListeners();
          return true;
        } catch (e) {
          _state = _state.copyWith(
            isLoading: false,
            errorMessage:
                'Account recovery failed: ${RemoteUserErrorCopy.scrubDomain(e.toString())}',
            joinSubStep: JoinSubStep.code,
          );
          notifyListeners();
          return false;
        }
      } else {
        completedChoice = ServerRecoveryChoice(
          serverUrl: recovery.serverUrl,
          accountId: recovery.accountId,
          recoveryCode: recovery.recoveryCode,
        );
        _state = _state.copyWith(isLoading: false, isComplete: true);
        notifyListeners();
        return true;
      }
    }

    final upper = rawCode.toUpperCase();
    if (upper.startsWith('REC-') || upper.contains('RECOVERY')) {
      _state = _state.copyWith(
        isLoading: false,
        codeType: CodeType.recovery,
        loadingStatus: 'Recovering account state…',
        joinSubStep: JoinSubStep.recoverySync,
        step: OnboardingStep.serverSelection,
      );
      notifyListeners();
      return true;
    }

    // 2. Try HLX-INV- invite code or link
    final invite = decodeHelixInviteCode(rawCode);
    if (invite != null) {
      String resolvedServerName = 'Personal Server';
      final targetUrl = invite.serverUrl.isNotEmpty
          ? invite.serverUrl
          : kHelixGlobalServerUrl;

      try {
        final client =
            _client ??
            HelixRemoteRestClientImpl(
              baseUri: Uri.parse(targetUrl),
              timeoutMs: 10000,
            );
        final lookup = await client.lookupInvite(inviteCode: invite.inviteCode);
        if (lookup['valid'] != true) {
          final reason = lookup['reason'] as String?;
          final msg = switch (reason) {
            'already_used' => 'This invitation code has already been used.',
            'cancelled' => 'This invitation code was cancelled by the host.',
            'expired' => 'This invitation code has expired.',
            _ => 'This invitation code is invalid or has expired.',
          };
          _state = _state.copyWith(isLoading: false, errorMessage: msg);
          notifyListeners();
          return false;
        }
        final serverName = (lookup['server_name'] as String? ?? '').trim();
        if (serverName.isNotEmpty) {
          resolvedServerName = serverName;
        }
      } catch (e) {
        _state = _state.copyWith(
          isLoading: false,
          errorMessage:
              'Unable to connect to server: ${RemoteUserErrorCopy.scrubDomain(e.toString())}',
        );
        notifyListeners();
        return false;
      }

      if (_onServerUrlChanged != null && invite.serverUrl.isNotEmpty) {
        try {
          await _onServerUrlChanged(invite.serverUrl);
        } catch (_) {}
      }

      _state = _state.copyWith(
        isLoading: false,
        codeType: CodeType.invitation,
        connectedServerName: resolvedServerName,
        serverNodeUrl: targetUrl,
        inviteCode: invite.inviteCode,
        joinSubStep: JoinSubStep.phone,
        step: OnboardingStep.serverSelection,
      );
      notifyListeners();
      return true;
    }

    // 3. Fallback for bare invite codes (e.g. INV-9921)
    if (upper.startsWith('INV-') || !rawCode.contains(' ')) {
      String resolvedServerName = rawCode.length > 4
          ? 'Personal Server ${rawCode.substring(0, 4).toUpperCase()}'
          : 'Personal Server';

      final targetUrl = _state.serverNodeUrl ?? kHelixGlobalServerUrl;
      try {
        final client =
            _client ??
            HelixRemoteRestClientImpl(
              baseUri: Uri.parse(targetUrl),
              timeoutMs: 10000,
            );
        final lookup = await client.lookupInvite(inviteCode: rawCode);
        if (lookup['valid'] == true) {
          final serverName = (lookup['server_name'] as String? ?? '').trim();
          if (serverName.isNotEmpty) {
            resolvedServerName = serverName;
          }
        }
      } catch (_) {}

      _state = _state.copyWith(
        isLoading: false,
        codeType: CodeType.invitation,
        connectedServerName: resolvedServerName,
        inviteCode: rawCode,
        joinSubStep: JoinSubStep.phone,
        step: OnboardingStep.serverSelection,
      );
      notifyListeners();
      return true;
    }

    _state = _state.copyWith(
      isLoading: false,
      errorMessage:
          'Invalid code. Paste the HLX-INV- or HLX-REC- code your admin shared.',
    );
    notifyListeners();
    return false;
  }

  Future<bool> completeSetup({
    String? defaultName,
    String? code,
    bool isPersonal = false,
    bool skip = false,
  }) async {
    final requiresTos = !isPersonal && _state.serverType == ServerType.global;
    if (requiresTos && !_state.tosAccepted) {
      _state = _state.copyWith(
        errorMessage:
            'Please read and accept the Terms of Service and Privacy Policy before continuing.',
      );
      notifyListeners();
      return false;
    }

    _state = _state.copyWith(
      isLoading: true,
      clearErrorMessage: true,
      showPhoneRecoveryPrompt: false,
    );
    notifyListeners();

    final phone = fullPhoneNumber;
    final enteredName = _state.displayName.trim();
    final finalName = (skip || enteredName.length < 3)
        ? (defaultName ?? (phone.isNotEmpty ? phone : 'Helix User'))
        : enteredName;

    // Helix Global signs up with no invitation code - the phone OTP is the
    // only credential. Personal servers still require a real invite code.
    // (`requiresTos` is true for exactly the same Global-only path.)
    //
    // No fallbacks. This used to substitute '123456' for a missing OTP and
    // 'INV-GLOBAL' for a missing invite, so a user who skipped verification
    // was registered against a hardcoded credential on a real server.
    // `verifyOtp` already produces a specific message for an empty or
    // malformed code; these guards only catch a path that reached here without
    // going through it, and they fail loudly rather than inventing something.
    final enteredOtp = _state.otpCode.trim();
    if (enteredOtp.isEmpty) {
      _state = _state.copyWith(
        isLoading: false,
        errorMessage:
            'Enter the verification code sent to your phone before '
            'continuing.',
      );
      notifyListeners();
      return false;
    }
    final enteredInvite = _state.inviteCode ?? code;
    if (!requiresTos && (enteredInvite == null || enteredInvite.isEmpty)) {
      _state = _state.copyWith(
        isLoading: false,
        errorMessage:
            'This server needs an invite code. Paste the HLX-INV- code your '
            'administrator shared.',
      );
      notifyListeners();
      return false;
    }
    final inviteCode = requiresTos ? '' : enteredInvite!;
    final serverUrl = (isPersonal || _state.serverType == ServerType.others)
        ? (_state.serverNodeUrl ?? kHelixGlobalServerUrl)
        : kHelixGlobalServerUrl;
    final otp = enteredOtp;

    if (_root != null) {
      try {
        await _root.registerAndLogin(
          phoneNumber: phone,
          phoneHashOverride: _state.phoneHash,
          displayName: finalName,
          otpCode: otp,
          otpChallengeId: _state.otpChallengeId,
          inviteCode: inviteCode,
          tosAccepted: requiresTos && _state.tosAccepted,
          tosVersion: _state.tosVersion,
        );
      } catch (e) {
        final backend = _root.devConfig.restBaseUri;
        final isPhoneConflict =
            e is RemoteRestException &&
            e.serverCode == RemoteApiErrorCodes.phoneAlreadyRegistered;
        final isOtpError =
            e is RemoteRestException &&
            e.serverCode == RemoteApiErrorCodes.invalidOtp;
        final msg = e is RemoteRestException
            ? RemoteUserErrorCopy.registrationFailure(e, backend)
            : RemoteUserErrorCopy.unknownRegistration();
        _state = _state.copyWith(
          isLoading: false,
          errorMessage: isPhoneConflict ? null : msg,
          clearErrorMessage: isPhoneConflict,
          showPhoneRecoveryPrompt: isPhoneConflict,
          globalSubStep: isOtpError && requiresTos
              ? GlobalSubStep.otp
              : _state.globalSubStep,
          joinSubStep: isOtpError && !requiresTos
              ? JoinSubStep.otp
              : _state.joinSubStep,
        );
        notifyListeners();
        return false;
      }
    }

    completedChoice = ServerInviteChoice(
      serverUrl: serverUrl,
      inviteCode: inviteCode,
      phoneNumber: phone,
      serverName: _state.connectedServerName,
      displayName: finalName,
      otpCode: otp,
      phoneHash: _state.phoneHash,
      otpChallengeId: _state.otpChallengeId,
      tosAccepted: requiresTos && _state.tosAccepted,
      tosVersion: _state.tosVersion,
    );

    _state = _state.copyWith(
      isLoading: false,
      isComplete: true,
      displayName: finalName,
    );
    notifyListeners();
    return true;
  }

  void goBack() {
    if (_state.serverType == ServerType.global) {
      if (_state.globalSubStep == GlobalSubStep.name) {
        setGlobalSubStep(GlobalSubStep.otp);
      } else if (_state.globalSubStep == GlobalSubStep.otp) {
        setGlobalSubStep(GlobalSubStep.phone);
      } else {
        _state = _state.copyWith(
          step: OnboardingStep.serverSelection,
          globalSubStep: GlobalSubStep.phone,
        );
      }
    } else {
      if (_state.othersOption == OthersOption.join) {
        switch (_state.joinSubStep) {
          case JoinSubStep.name:
            setJoinSubStep(JoinSubStep.otp);
            break;
          case JoinSubStep.otp:
            setJoinSubStep(JoinSubStep.phone);
            break;
          case JoinSubStep.phone:
            setJoinSubStep(JoinSubStep.code);
            break;
          case JoinSubStep.code:
          case JoinSubStep.recoverySync:
            setServerType(ServerType.global);
            break;
        }
      } else {
        setOthersOption(OthersOption.join);
      }
    }
    notifyListeners();
  }
}
