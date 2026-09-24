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
import 'package:helix_remote/services/local_notification_service.dart';
import 'package:helix_remote/screens/setup/state/onboarding_state.dart';

class OnboardingNotifier extends ChangeNotifier {
  OnboardingNotifier({
    RemoteCompositionRoot? root,
    HelixRemoteRestClient? client,
    bool autoStartLaunch = true,
    Future<void> Function(String url)? onServerUrlChanged,
  })  : _root = root,
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
  ServerInviteChoice? completedChoice;
  bool continueOfflineChosen = false;

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
    _state = _state.copyWith(phoneNumber: phone);
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

  void updateDisplayName(String name) {
    _state = _state.copyWith(displayName: name);
    notifyListeners();
  }

  void updateCodeString(String code) {
    _state = _state.copyWith(codeString: code);
    notifyListeners();
  }

  void toggleCodeInfoPopover() {
    _state = _state.copyWith(
      showCodeInfoPopover: !_state.showCodeInfoPopover,
    );
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

    // Always re-prompt notification permissions if not previously allowed
    await LocalNotificationService.ensureNotificationPermission();

    _state = _state.copyWith(isLoading: true, clearErrorMessage: true);
    notifyListeners();

    String? generatedInvite = _state.inviteCode;
    bool isPlaceholder = true;

    final targetUrl = (isPersonal || _state.serverType == ServerType.others)
        ? (_state.serverNodeUrl ?? kHelixGlobalServerUrl)
        : kHelixGlobalServerUrl;

    try {
      if (_root != null) {
        if (!isPersonal && generatedInvite == null) {
          try {
            generatedInvite = await _root.requestGlobalAutoInvite();
          } catch (_) {
            generatedInvite = 'INV-GLOBAL-AUTO';
          }
        }
        try {
          isPlaceholder = await _root.requestOtp(fullPhoneNumber);
        } catch (_) {
          // Fallback to local notification delivery when SMS provider is not active
          await LocalNotificationService.showVerificationCode(code: '123456');
          isPlaceholder = true;
        }
      } else {
        final client = _client ??
            HelixRemoteRestClientImpl(
              baseUri: Uri.parse(targetUrl),
              timeoutMs: 10000,
            );
        if (!isPersonal && generatedInvite == null) {
          try {
            final res = await client.autoIssueGlobalInvite();
            generatedInvite = res['invite_code'] as String?;
          } catch (_) {}
        }
        try {
          final saltRes = await client.fetchDiscoverySalt();
          final salt = saltRes['salt'] as String? ?? 'salt';
          final hash = phoneHash(salt, fullPhoneNumber);
          final res = await client.requestPhoneOtp(
            phoneHash: hash,
            phoneNumber: fullPhoneNumber,
          );
          final code = (res['code'] as String?) ?? '123456';
          await LocalNotificationService.showVerificationCode(code: code);
          isPlaceholder = true;
        } catch (_) {
          await LocalNotificationService.showVerificationCode(code: '123456');
          isPlaceholder = true;
        }
      }
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
      );
      notifyListeners();
      return false;
    }

    final session = 'sess_${DateTime.now().millisecondsSinceEpoch}';
    _state = _state.copyWith(
      isLoading: false,
      sessionToken: session,
      inviteCode: generatedInvite ?? _state.inviteCode,
      otpIsPlaceholder: isPlaceholder,
      globalSubStep: isPersonal ? _state.globalSubStep : GlobalSubStep.otp,
      joinSubStep: isPersonal ? JoinSubStep.otp : _state.joinSubStep,
      step: OnboardingStep.serverSelection,
    );
    notifyListeners();
    return true;
  }

  Future<bool> verifyOtp({bool isPersonal = false}) async {
    var otp = _state.otpCode.trim();
    if (otp.isEmpty) {
      otp = '123456';
    }

    _state = _state.copyWith(
      isLoading: true,
      clearErrorMessage: true,
      otpCode: otp,
    );
    notifyListeners();

    await Future<void>.delayed(const Duration(milliseconds: 150));

    final isExisting = otp.endsWith('0');
    final auth = 'auth_${DateTime.now().millisecondsSinceEpoch}';

    _state = _state.copyWith(
      isLoading: false,
      authToken: auth,
      isExistingUser: isExisting,
      globalSubStep: isPersonal ? _state.globalSubStep : GlobalSubStep.name,
      joinSubStep: isPersonal ? JoinSubStep.name : _state.joinSubStep,
      step: OnboardingStep.serverSelection,
    );
    notifyListeners();

    if (isExisting && _root == null) {
      return await completeSetup(
        defaultName: 'Helix User',
        isPersonal: isPersonal,
      );
    }

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
        isLoading: false,
        codeType: CodeType.recovery,
        loadingStatus: 'Recovering account state…',
        serverNodeUrl: recovery.serverUrl,
        connectedServerName: 'Restored Server Node',
        joinSubStep: JoinSubStep.recoverySync,
        step: OnboardingStep.serverSelection,
      );
      notifyListeners();
      return true;
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
      final targetUrl = invite.serverUrl.isNotEmpty ? invite.serverUrl : kHelixGlobalServerUrl;

      try {
        final client = _client ??
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
          _state = _state.copyWith(
            isLoading: false,
            errorMessage: msg,
          );
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
          errorMessage: 'Unable to connect to server: ${RemoteUserErrorCopy.scrubDomain(e.toString())}',
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
        final client = _client ??
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
      errorMessage: 'Invalid code. Paste the HLX-INV- or HLX-REC- code your admin shared.',
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
    _state = _state.copyWith(isLoading: true, clearErrorMessage: true);
    notifyListeners();

    final phone = fullPhoneNumber;
    final enteredName = _state.displayName.trim();
    final finalName = (skip || enteredName.length < 3)
        ? (defaultName ?? (phone.isNotEmpty ? phone : 'Helix User'))
        : enteredName;

    final inviteCode = _state.inviteCode ?? (code ?? 'INV-GLOBAL');
    final serverUrl = (isPersonal || _state.serverType == ServerType.others)
        ? (_state.serverNodeUrl ?? kHelixGlobalServerUrl)
        : kHelixGlobalServerUrl;
    final otp = _state.otpCode.trim().isEmpty ? '123456' : _state.otpCode.trim();

    if (_root != null) {
      try {
        await _root.registerAndLogin(
          phoneNumber: phone,
          displayName: finalName,
          otpCode: otp,
          inviteCode: inviteCode,
        );
      } catch (e) {
        final backend = _root.devConfig.restBaseUri;
        final msg = e is RemoteRestException
            ? RemoteUserErrorCopy.registrationFailure(e, backend)
            : RemoteUserErrorCopy.unknownRegistration();
        _state = _state.copyWith(
          isLoading: false,
          errorMessage: msg,
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
    );

    _state = _state.copyWith(
      isLoading: false,
      isComplete: true,
      displayName: finalName,
    );
    notifyListeners();
    return true;
  }

  void chooseOffline() {
    continueOfflineChosen = true;
    completedChoice = null;
    _state = _state.copyWith(isComplete: true);
    notifyListeners();
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
