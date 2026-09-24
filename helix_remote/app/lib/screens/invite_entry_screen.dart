import 'package:flutter/material.dart';
import 'package:helix_remote/screens/setup/setup_screen.dart';
import 'package:helix_remote/screens/setup/state/onboarding_notifier.dart';
import 'package:helix_remote/screens/setup/state/onboarding_state.dart';

/// Result of successfully validating a personal server + invite combo, with
/// the phone number collected alongside it on the same screen.
class ServerInviteChoice {
  const ServerInviteChoice({
    required this.serverUrl,
    required this.inviteCode,
    this.phoneNumber,
    this.serverName,
  });

  final String serverUrl;
  final String inviteCode;

  /// Display name the server's admin chose, when they set one. Null means
  /// unnamed, and the server is identified by its address instead.
  final String? serverName;

  /// E.164 phone number, or null for the Helix Global path (which doesn't
  /// collect one here - there's no "which server" step to attach it to).
  final String? phoneNumber;
}

/// "Personal server" entry screen. Wraps [SetupScreen] pre-configured
/// for the "Others" / Join personal server flow.
class InviteEntryScreen extends StatelessWidget {
  const InviteEntryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final notifier = OnboardingNotifier(autoStartLaunch: false)
      ..setServerType(ServerType.others)
      ..setOthersOption(OthersOption.join);

    return SetupScreen(
      notifier: notifier,
      onChoice: (choice) {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop(choice);
        }
      },
    );
  }
}
