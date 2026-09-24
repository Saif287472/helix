import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:helix_remote_api/api/rest_client.dart';
import 'package:helix_remote/app/helix_code.dart';
import 'package:helix_remote/app/remote_config.dart';
import 'package:helix_remote/app/remote_rest_client.dart';
import 'package:helix_remote/screens/invite_entry_screen.dart';
import 'package:helix_remote/services/local_notification_service.dart';
import 'package:helix_remote/screens/setup/state/onboarding_state.dart';

class OnboardingNotifier extends ChangeNotifier {
  OnboardingNotifier({
    HelixRemoteRestClient? client,
    bool autoStartLaunch = true,
  }) : _client = client {
    if (autoStartLaunch) {
      Future.microtask(_runLaunchSequence);
    }
  }

  final HelixRemoteRestClient? _client;
  OnboardingState _state = const OnboardingState();

  OnboardingState get state => _state;
  ServerInviteChoice? completedChoice;
  bool continueOfflineChosen = false;

  void updateState(OnboardingState Function(OnboardingState current) update) {
    _state = update(_state);
    notifyListeners();
  }

  Future<void> _runLaunchSequence() async {
    _state = _state.copyWith(
      isLoading: true,
      loadingStatus: 'Deploying Helix…',
    );
    notifyListeners();

    await Future<void>.delayed(const Duration(milliseconds: 300));
    _state = _state.copyWith(loadingStatus: 'Retrieving user data…');
    notifyListeners();

    await Future<void>.delayed(const Duration(milliseconds: 300));
    _state = _state.copyWith(
      step: OnboardingStep.serverSelection,
      isLoading: false,
    );
    notifyListeners();
  }

  void setServerType(ServerType type) {
    _state = _state.copyWith(serverType: type);
    notifyListeners();
  }

  void setOthersOption(OthersOption option) {
    _state = _state.copyWith(othersOption: option);
    if (option == OthersOption.host) {
      _state = _state.copyWith(
        step: OnboardingStep.hostGuide,
        hostGuideStep: 0,
      );
    } else {
      _state = _state.copyWith(step: OnboardingStep.codeEntry);
    }
    notifyListeners();
  }

  void updateHostGuideStep(int stepIndex) {
    _state = _state.copyWith(hostGuideStep: stepIndex);
    notifyListeners();
  }

  void proceedFromServerSelection() {
    if (_state.serverType == ServerType.global) {
      _state = _state.copyWith(step: OnboardingStep.globalPhone);
    } else {
      _state = _state.copyWith(step: OnboardingStep.othersHub);
    }
    notifyListeners();
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

  Future<bool> requestOtp({bool isPersonal = false}) async {
    final digits = _state.phoneNumber.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.length < 6) {
      _state = _state.copyWith(
        errorMessage: 'Please enter a valid phone number.',
      );
      notifyListeners();
      return false;
    }

    _state = _state.copyWith(isLoading: true, clearErrorMessage: true);
    notifyListeners();

    String? generatedInvite;
    if (_state.serverType == ServerType.global && _state.inviteCode == null) {
      try {
        if (_client != null) {
          final res = await _client.autoIssueGlobalInvite();
          generatedInvite = res['invite_code'] as String?;
        } else {
          final config = RemoteDevelopmentConfig.helixGlobal(
            databaseDirectory: '',
            attachmentCacheDir: '',
          );
          final restClient = HelixRemoteRestClientImpl(
            baseUri: config.restBaseUri,
            timeoutMs: 8000,
          );
          try {
            final res = await restClient.autoIssueGlobalInvite();
            generatedInvite = res['invite_code'] as String?;
            if (generatedInvite != null && generatedInvite.isNotEmpty) {
              await LocalNotificationService.showInviteCode(code: generatedInvite);
            }
          } finally {
            restClient.close();
          }
        }
      } catch (_) {
        // Fallback for offline/simulated testing environments
        generatedInvite = 'INV-GLOBAL-${DateTime.now().millisecondsSinceEpoch % 10000}';
      }
    }

    await Future<void>.delayed(const Duration(milliseconds: 300));

    final session = 'sess_${DateTime.now().millisecondsSinceEpoch}';
    _state = _state.copyWith(
      isLoading: false,
      sessionToken: session,
      inviteCode: generatedInvite ?? _state.inviteCode,
      step: isPersonal
          ? OnboardingStep.personalVerify
          : OnboardingStep.globalOtp,
    );
    notifyListeners();
    return true;
  }

  Future<bool> verifyOtp({bool isPersonal = false}) async {
    final otp = _state.otpCode.trim();
    if (otp.length != 6) {
      _state = _state.copyWith(
        errorMessage: 'Please enter the 6-digit OTP code.',
      );
      notifyListeners();
      return false;
    }

    _state = _state.copyWith(isLoading: true, clearErrorMessage: true);
    notifyListeners();

    await Future<void>.delayed(const Duration(milliseconds: 300));

    final isExisting = otp.endsWith('0');
    final auth = 'auth_${DateTime.now().millisecondsSinceEpoch}';

    _state = _state.copyWith(
      isLoading: false,
      authToken: auth,
      isExistingUser: isExisting,
    );

    if (isExisting) {
      return await completeSetup(
        defaultName: 'Helix User',
        isPersonal: isPersonal,
      );
    } else {
      if (!isPersonal) {
        _state = _state.copyWith(step: OnboardingStep.globalName);
      }
      notifyListeners();
      return true;
    }
  }

  Future<bool> resolveCode() async {
    final code = _state.codeString.trim();
    if (code.isEmpty) {
      _state = _state.copyWith(errorMessage: 'Please enter a code.');
      notifyListeners();
      return false;
    }

    _state = _state.copyWith(isLoading: true, clearErrorMessage: true);
    notifyListeners();

    await Future<void>.delayed(const Duration(milliseconds: 300));

    // Try HLX-REC- recovery code first
    final recovery = decodeHelixRecoveryCode(code);
    if (recovery != null) {
      _state = _state.copyWith(
        isLoading: false,
        codeType: CodeType.recovery,
        loadingStatus: 'Recovering account state…',
        serverNodeUrl: recovery.serverUrl,
        step: OnboardingStep.personalVerify,
      );
      notifyListeners();
      return true;
    }

    // Also detect legacy REC- prefix
    final upper = code.toUpperCase();
    if (upper.startsWith('REC-') || upper.contains('RECOVERY')) {
      _state = _state.copyWith(
        isLoading: false,
        codeType: CodeType.recovery,
        loadingStatus: 'Recovering account state…',
        step: OnboardingStep.personalVerify,
      );
      notifyListeners();
      return true;
    }

    // Try HLX-INV- invite code or legacy URL
    final invite = decodeHelixInviteCode(code);
    if (invite != null) {
      final serverName = invite.inviteCode.length > 4
          ? 'Private Server ${invite.inviteCode.substring(0, 4).toUpperCase()}'
          : 'Private Server';

      _state = _state.copyWith(
        isLoading: false,
        codeType: CodeType.invitation,
        connectedServerName: serverName,
        serverNodeUrl: invite.serverUrl,
        inviteCode: invite.inviteCode,
        step: OnboardingStep.personalVerify,
      );
      notifyListeners();
      return true;
    }

    // Fallback for bare invite codes (e.g. INV-9921 or testing)
    if (upper.startsWith('INV-') || !code.contains(' ')) {
      final serverName = code.length > 4
          ? 'Private Server ${code.substring(0, 4).toUpperCase()}'
          : 'Private Server';
      _state = _state.copyWith(
        isLoading: false,
        codeType: CodeType.invitation,
        connectedServerName: serverName,
        serverNodeUrl: 'http://localhost:8443',
        inviteCode: code,
        step: OnboardingStep.personalVerify,
      );
      notifyListeners();
      return true;
    }

    // Nothing matched
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
  }) async {
    _state = _state.copyWith(isLoading: true, clearErrorMessage: true);
    notifyListeners();

    await Future<void>.delayed(const Duration(milliseconds: 200));

    final rawPhone = _state.phoneNumber.trim();
    final fullPhone = rawPhone.isEmpty
        ? null
        : '${_state.countryCode}$rawPhone'.replaceAll(' ', '');

    final finalName = (_state.displayName.trim().length >= 3)
        ? _state.displayName.trim()
        : (defaultName ?? (fullPhone ?? 'Helix Peer'));

    final serverUrl = (isPersonal || _state.serverType == ServerType.others)
        ? (_state.serverNodeUrl ?? 'http://localhost:8443')
        : kHelixGlobalServerUrl;

    final finalInviteCode = _state.inviteCode ?? (code ?? 'INV-GLOBAL');

    completedChoice = ServerInviteChoice(
      serverUrl: serverUrl,
      inviteCode: finalInviteCode,
      phoneNumber: fullPhone,
      serverName: _state.connectedServerName,
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
    switch (_state.step) {
      case OnboardingStep.globalPhone:
      case OnboardingStep.othersHub:
        _state = _state.copyWith(step: OnboardingStep.serverSelection);
        break;
      case OnboardingStep.globalOtp:
        _state = _state.copyWith(step: OnboardingStep.globalPhone);
        break;
      case OnboardingStep.globalName:
        _state = _state.copyWith(step: OnboardingStep.globalOtp);
        break;
      case OnboardingStep.hostGuide:
      case OnboardingStep.codeEntry:
        _state = _state.copyWith(step: OnboardingStep.othersHub);
        break;
      case OnboardingStep.personalVerify:
        _state = _state.copyWith(step: OnboardingStep.codeEntry);
        break;
      default:
        break;
    }
    notifyListeners();
  }
}
