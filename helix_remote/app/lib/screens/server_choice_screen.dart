import 'package:flutter/material.dart';
import 'package:helix_remote/screens/setup/setup_screen.dart';
import 'package:helix_remote/screens/setup/state/onboarding_notifier.dart';
import 'package:helix_remote/screens/setup/state/onboarding_state.dart';

/// Returned when the user chooses to continue without connecting to a
/// server yet.
class ContinueOfflineChoice {
  const ContinueOfflineChoice();
}

/// First-launch welcome and server onboarding entry point.
/// Wraps [SetupScreen] to provide the complete, unified onboarding experience
/// matching Helix Welcome.
class ServerChoiceScreen extends StatefulWidget {
  const ServerChoiceScreen({super.key});

  @override
  State<ServerChoiceScreen> createState() => _ServerChoiceScreenState();
}

class _ServerChoiceScreenState extends State<ServerChoiceScreen> {
  late final OnboardingNotifier _notifier;

  @override
  void initState() {
    super.initState();
    _notifier = OnboardingNotifier(autoStartLaunch: false)
      ..updateState((s) => s.copyWith(step: OnboardingStep.serverSelection));
  }

  @override
  void dispose() {
    _notifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SetupScreen(
      notifier: _notifier,
      onChoice: (choice) {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop(choice);
        }
      },
    );
  }
}
