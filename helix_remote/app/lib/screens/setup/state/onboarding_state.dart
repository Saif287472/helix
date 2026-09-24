import 'package:flutter/foundation.dart';

enum OnboardingStep {
  splash,
  serverSelection,
  // Path A: Global Server
  globalPhone,
  globalOtp,
  globalName,
  // Path B: Others
  othersHub,
  hostGuide,
  codeEntry,
  personalVerify,
}

enum ServerType { global, others }

enum OthersOption { host, join }

enum GlobalSubStep { phone, otp, name }

enum JoinSubStep { code, phone, otp, name, recoverySync }

enum CodeType { invitation, recovery }

@immutable
class OnboardingState {
  const OnboardingState({
    this.step = OnboardingStep.splash,
    this.serverType = ServerType.global,
    this.othersOption = OthersOption.join,
    this.globalSubStep = GlobalSubStep.phone,
    this.joinSubStep = JoinSubStep.code,
    this.countryCode = '+880',
    this.phoneNumber = '',
    this.otpCode = '',
    this.rememberDevice = true,
    this.displayName = '',
    this.codeString = '',
    this.codeType,
    this.connectedServerName = 'Helix Global Server',
    this.serverNodeUrl,
    this.inviteCode,
    this.sessionToken,
    this.authToken,
    this.isExistingUser = false,
    this.isLoading = false,
    this.errorMessage,
    this.loadingStatus = 'Deploying Helix…',
    this.hostGuideStep = 0,
    this.showCodeInfoPopover = false,
    this.isComplete = false,
    this.otpIsPlaceholder = false,
  });

  final OnboardingStep step;
  final ServerType serverType;
  final OthersOption? othersOption;
  final GlobalSubStep globalSubStep;
  final JoinSubStep joinSubStep;
  final String countryCode;
  final String phoneNumber;
  final String otpCode;
  final bool rememberDevice;
  final String displayName;
  final String codeString;
  final CodeType? codeType;
  final String? connectedServerName;
  final String? serverNodeUrl;
  final String? inviteCode;
  final String? sessionToken;
  final String? authToken;
  final bool isExistingUser;
  final bool isLoading;
  final String? errorMessage;
  final String loadingStatus;
  final int hostGuideStep;
  final bool showCodeInfoPopover;
  final bool isComplete;
  final bool otpIsPlaceholder;

  OnboardingState copyWith({
    OnboardingStep? step,
    ServerType? serverType,
    OthersOption? othersOption,
    GlobalSubStep? globalSubStep,
    JoinSubStep? joinSubStep,
    String? countryCode,
    String? phoneNumber,
    String? otpCode,
    bool? rememberDevice,
    String? displayName,
    String? codeString,
    CodeType? codeType,
    String? connectedServerName,
    String? serverNodeUrl,
    String? inviteCode,
    String? sessionToken,
    String? authToken,
    bool? isExistingUser,
    bool? isLoading,
    String? errorMessage,
    bool clearErrorMessage = false,
    String? loadingStatus,
    int? hostGuideStep,
    bool? showCodeInfoPopover,
    bool? isComplete,
    bool? otpIsPlaceholder,
  }) {
    return OnboardingState(
      step: step ?? this.step,
      serverType: serverType ?? this.serverType,
      othersOption: othersOption ?? this.othersOption,
      globalSubStep: globalSubStep ?? this.globalSubStep,
      joinSubStep: joinSubStep ?? this.joinSubStep,
      countryCode: countryCode ?? this.countryCode,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      otpCode: otpCode ?? this.otpCode,
      rememberDevice: rememberDevice ?? this.rememberDevice,
      displayName: displayName ?? this.displayName,
      codeString: codeString ?? this.codeString,
      codeType: codeType ?? this.codeType,
      connectedServerName: connectedServerName ?? this.connectedServerName,
      serverNodeUrl: serverNodeUrl ?? this.serverNodeUrl,
      inviteCode: inviteCode ?? this.inviteCode,
      sessionToken: sessionToken ?? this.sessionToken,
      authToken: authToken ?? this.authToken,
      isExistingUser: isExistingUser ?? this.isExistingUser,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
      loadingStatus: loadingStatus ?? this.loadingStatus,
      hostGuideStep: hostGuideStep ?? this.hostGuideStep,
      showCodeInfoPopover: showCodeInfoPopover ?? this.showCodeInfoPopover,
      isComplete: isComplete ?? this.isComplete,
      otpIsPlaceholder: otpIsPlaceholder ?? this.otpIsPlaceholder,
    );
  }
}
