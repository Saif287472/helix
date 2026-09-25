import 'package:flutter/material.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';
import 'package:helix_remote/l10n/helix_localizations.dart';
import 'package:helix_remote/app/composition_root.dart';
import 'package:helix_remote/screens/server_choice_screen.dart';
import 'package:helix_remote/screens/setup/state/onboarding_notifier.dart';
import 'package:helix_remote/screens/setup/state/onboarding_state.dart';
import 'package:helix_remote/screens/setup/steps/splash_step.dart';
import 'package:helix_remote/screens/setup/steps/server_selection_step.dart';
import 'package:helix_remote/screens/setup/steps/global_phone_step.dart';
import 'package:helix_remote/screens/setup/steps/global_otp_step.dart';
import 'package:helix_remote/screens/setup/steps/global_name_step.dart';
import 'package:helix_remote/screens/setup/steps/others_hub_step.dart';
import 'package:helix_remote/screens/setup/steps/host_guide_step.dart';
import 'package:helix_remote/screens/setup/steps/code_entry_step.dart';
import 'package:helix_remote/screens/setup/steps/personal_verify_step.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({
    super.key,
    this.onChoice,
    this.notifier,
    this.root,
    this.onChangeServerUrl,
    this.initialInviteCode,
    this.initialPhoneNumber,
    this.autoStartLaunch = true,
    this.initialRecoveryMode = false,
    this.initialServerUrl,
  });

  final void Function(Object? choice)? onChoice;
  final OnboardingNotifier? notifier;
  final RemoteCompositionRoot? root;
  final Future<void> Function(String url)? onChangeServerUrl;
  final String? initialInviteCode;
  final String? initialPhoneNumber;
  final bool autoStartLaunch;
  final bool initialRecoveryMode;
  final String? initialServerUrl;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  late final OnboardingNotifier _notifier;
  bool _createdLocalNotifier = false;
  bool _handledCompletion = false;
  bool _phoneRecoveryDialogScheduled = false;
  bool _phoneRecoveryDialogOpen = false;

  @override
  void initState() {
    super.initState();
    if (widget.notifier != null) {
      _notifier = widget.notifier!;
    } else {
      _notifier = OnboardingNotifier(
        root: widget.root,
        autoStartLaunch: widget.autoStartLaunch,
        onServerUrlChanged: widget.onChangeServerUrl,
      );
      _createdLocalNotifier = true;
    }

    if (widget.initialInviteCode != null &&
        widget.initialInviteCode!.isNotEmpty) {
      _notifier.updateCodeString(widget.initialInviteCode!);
    }
    if (widget.initialPhoneNumber != null &&
        widget.initialPhoneNumber!.isNotEmpty) {
      _notifier.updatePhoneNumber(widget.initialPhoneNumber!);
    }

    _notifier.addListener(_onNotifierUpdate);
    if (widget.initialRecoveryMode) {
      _notifier.beginPhoneRecovery(serverUrl: widget.initialServerUrl);
    }
  }

  @override
  void dispose() {
    _notifier.removeListener(_onNotifierUpdate);
    if (_createdLocalNotifier) {
      _notifier.dispose();
    }
    super.dispose();
  }

  void _onNotifierUpdate() {
    if (!mounted) return;
    if (_notifier.state.showPhoneRecoveryPrompt &&
        !_phoneRecoveryDialogScheduled &&
        !_phoneRecoveryDialogOpen) {
      _phoneRecoveryDialogScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        _phoneRecoveryDialogScheduled = false;
        await _showPhoneRecoveryDialog();
      });
    }
    if (_handledCompletion) return;
    if (_notifier.state.isComplete) {
      _handledCompletion = true;
      final choice = _notifier.continueOfflineChosen
          ? const ContinueOfflineChoice()
          : _notifier.completedChoice;
      widget.onChoice?.call(choice);
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).maybePop(choice);
      }
    }
  }

  Future<void> _showPhoneRecoveryDialog() async {
    if (!mounted || _phoneRecoveryDialogOpen) return;
    _phoneRecoveryDialogOpen = true;
    final l10n = HelixLocalizations.of(context);
    final recover = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(l10n.phoneAlreadyRegistered),
          content: Text(l10n.phoneAlreadyRegisteredRecoveryMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.enterRecoveryCode),
            ),
          ],
        );
      },
    );
    _phoneRecoveryDialogOpen = false;
    if (!mounted) return;
    if (recover == true) {
      _notifier.beginPhoneRecovery();
    } else {
      _notifier.dismissPhoneRecoveryPrompt();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width > 760;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: HelixInsets.symmetric(
                horizontal: isWide ? HelixSpace.xl : HelixSpace.md,
                vertical: HelixSpace.md,
              ),
              child: ListenableBuilder(
                listenable: _notifier,
                builder: (context, _) {
                  final state = _notifier.state;
                  final showBack =
                      state.step != OnboardingStep.splash &&
                      (state.step != OnboardingStep.serverSelection ||
                          (state.serverType == ServerType.global &&
                              state.globalSubStep != GlobalSubStep.phone) ||
                          (state.serverType == ServerType.others &&
                              state.othersOption == OthersOption.join &&
                              state.joinSubStep != JoinSubStep.code));

                  return Column(
                    children: [
                      if (showBack) ...[
                        Align(
                          alignment: Alignment.centerLeft,
                          child: IconButton(
                            icon: const Icon(Icons.arrow_back),
                            onPressed: state.isLoading
                                ? null
                                : _notifier.goBack,
                            tooltip: 'Back',
                          ),
                        ),
                        const SizedBox(height: HelixSpace.xs),
                      ],
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 250),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          child: KeyedSubtree(
                            key: ValueKey(state.step),
                            child: _buildStepContent(context, state),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepContent(BuildContext context, OnboardingState state) {
    final isPersonal = state.serverType == ServerType.others;

    switch (state.step) {
      case OnboardingStep.splash:
        return SplashStep(statusText: state.loadingStatus);

      case OnboardingStep.serverSelection:
        return ServerSelectionStep(
          selectedType: state.serverType,
          othersOption: state.othersOption ?? OthersOption.join,
          onSelectType: _notifier.setServerType,
          onSelectOthersOption: _notifier.setOthersOption,
          countryCode: state.countryCode,
          phoneNumber: state.phoneNumber,
          onCountryCodeChanged: _notifier.updateCountryCode,
          onPhoneChanged: _notifier.updatePhoneNumber,
          onRequestOtp: () => _notifier.requestOtp(isPersonal: isPersonal),
          otpCode: state.otpCode,
          onOtpChanged: _notifier.updateOtpCode,
          onVerifyOtp: () => _notifier.verifyOtp(isPersonal: isPersonal),
          displayName: state.displayName,
          onDisplayNameChanged: _notifier.updateDisplayName,
          tosAccepted: state.tosAccepted,
          onTosAcceptedChanged: _notifier.setTosAccepted,
          onCompleteSetup: ({bool skip = false}) =>
              _notifier.completeSetup(skip: skip, isPersonal: isPersonal),
          rememberDevice: state.rememberDevice,
          onRememberDeviceChanged: _notifier.toggleRememberDevice,
          codeString: state.codeString,
          showInfoPopover: state.showCodeInfoPopover,
          onCodeChanged: _notifier.updateCodeString,
          onToggleInfo: _notifier.toggleCodeInfoPopover,
          onVerifyCode: () => _notifier.resolveCode(),
          hostGuideStep: state.hostGuideStep,
          onHostStepChanged: _notifier.updateHostGuideStep,
          isLoading: state.isLoading,
          errorMessage: state.errorMessage,
          onProceed: _notifier.proceedFromServerSelection,
          onContinueOffline: _notifier.chooseOffline,
          globalSubStep: state.globalSubStep,
          joinSubStep: state.joinSubStep,
          connectedServerName: state.connectedServerName,
        );

      case OnboardingStep.globalPhone:
        return GlobalPhoneStep(
          countryCode: state.countryCode,
          phoneNumber: state.phoneNumber,
          isLoading: state.isLoading,
          errorMessage: state.errorMessage,
          onCountryCodeChanged: _notifier.updateCountryCode,
          onPhoneChanged: _notifier.updatePhoneNumber,
          onSubmit: () => _notifier.requestOtp(),
        );

      case OnboardingStep.globalOtp:
        return GlobalOtpStep(
          phoneNumber: '${state.countryCode} ${state.phoneNumber}',
          otpCode: state.otpCode,
          rememberDevice: state.rememberDevice,
          isLoading: state.isLoading,
          errorMessage: state.errorMessage,
          otpIsPlaceholder: state.otpIsPlaceholder,
          onOtpChanged: _notifier.updateOtpCode,
          onRememberDeviceChanged: _notifier.toggleRememberDevice,
          onSubmit: () => _notifier.verifyOtp(),
        );

      case OnboardingStep.globalName:
        return GlobalNameStep(
          displayName: state.displayName,
          tosAccepted: state.tosAccepted,
          onTosAcceptedChanged: _notifier.setTosAccepted,
          isLoading: state.isLoading,
          errorMessage: state.errorMessage,
          onNameChanged: _notifier.updateDisplayName,
          onSubmit: () => _notifier.completeSetup(skip: false),
          onSkip: () => _notifier.completeSetup(skip: true),
        );

      case OnboardingStep.othersHub:
        return OthersHubStep(onSelectOption: _notifier.setOthersOption);

      case OnboardingStep.hostGuide:
        return HostGuideStep(
          currentStep: state.hostGuideStep,
          onStepChanged: _notifier.updateHostGuideStep,
          onBackToOptions: () => _notifier.setOthersOption(OthersOption.join),
          onProceedToJoin: () => _notifier.setOthersOption(OthersOption.join),
        );

      case OnboardingStep.codeEntry:
        return CodeEntryStep(
          codeString: state.codeString,
          isLoading: state.isLoading,
          errorMessage: state.errorMessage,
          showInfoPopover: state.showCodeInfoPopover,
          onCodeChanged: _notifier.updateCodeString,
          onToggleInfo: _notifier.toggleCodeInfoPopover,
          onSubmit: () => _notifier.resolveCode(),
        );

      case OnboardingStep.personalVerify:
        return PersonalVerifyStep(
          connectedServerName: state.connectedServerName ?? 'Personal Server',
          codeType: state.codeType,
          countryCode: state.countryCode,
          phoneNumber: state.phoneNumber,
          otpCode: state.otpCode,
          rememberDevice: state.rememberDevice,
          displayName: state.displayName,
          isLoading: state.isLoading,
          loadingStatus: state.loadingStatus,
          errorMessage: state.errorMessage,
          onCountryCodeChanged: _notifier.updateCountryCode,
          onPhoneChanged: _notifier.updatePhoneNumber,
          onOtpChanged: _notifier.updateOtpCode,
          onRememberDeviceChanged: _notifier.toggleRememberDevice,
          onNameChanged: _notifier.updateDisplayName,
          onRequestOtp: ({bool isPersonal = true}) =>
              _notifier.requestOtp(isPersonal: isPersonal),
          onVerifyOtp: ({bool isPersonal = true}) =>
              _notifier.verifyOtp(isPersonal: isPersonal),
          onComplete: () => _notifier.completeSetup(isPersonal: true),
        );
    }
  }
}
