import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:helix_remote/features/devices/application/devices_models.dart';
import 'package:helix_remote/features/devices/application/devices_providers.dart';
import 'package:orbit_ui/orbit_ui.dart';

/// Link this device to an existing account: the Orbit `LinkThisDeviceScreen`
/// on [LinkThisDeviceController]. It shows a QR code for a signed-in device
/// to scan, then "Is this your account?".
///
/// The new device has no account yet, so this is reachable while signed out.
/// Nothing here is a secret that outlives the code (it expires in ten minutes
/// and is single use), but it is still a bearer code: the page says to show it
/// only to your own device.
class LinkThisDevicePage extends ConsumerStatefulWidget {
  const LinkThisDevicePage({super.key});

  @override
  ConsumerState<LinkThisDevicePage> createState() => _LinkThisDevicePageState();
}

class _LinkThisDevicePageState extends ConsumerState<LinkThisDevicePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(linkThisDeviceProvider.notifier).start();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(linkThisDeviceProvider);
    final countdown = ref.watch(linkCountdownProvider).value;
    final c = ref.read(linkThisDeviceProvider.notifier);
    void leave() {
      if (context.canPop()) context.pop();
    }

    return LinkThisDeviceScreen(
      model: linkThisDeviceModel(state, countdown: countdown),
      actions: LinkThisDeviceActions(
        onNewCode: c.start,
        onYes: c.confirmAccount,
        onNo: c.rejectAccount,
        // The confirm step's X is a no first; leaving counts as no anyway.
        onCancel: () {
          if (state.step == LinkThisStep.confirming) c.rejectAccount();
          leave();
        },
      ),
    );
  }
}

/// The screen's model for [state] (`orbit/contracts/signin.md`, Link this
/// device).
@visibleForTesting
LinkThisDeviceModel linkThisDeviceModel(
  LinkThisDeviceState state, {
  String? countdown,
}) {
  final proposal = state.proposal;
  final phase = switch (state.step) {
    LinkThisStep.starting => LinkThisDevicePhase.starting,
    // At zero the code is expired, before the failure arrives (fixes B12).
    LinkThisStep.waiting when countdown == 'Expired' =>
      LinkThisDevicePhase.expired,
    LinkThisStep.waiting => LinkThisDevicePhase.waiting,
    LinkThisStep.confirming when proposal != null =>
      LinkThisDevicePhase.confirm,
    LinkThisStep.confirming => LinkThisDevicePhase.waiting,
    LinkThisStep.finishing => LinkThisDevicePhase.approved,
    LinkThisStep.failed when state.problem == LinkProblem.expired =>
      LinkThisDevicePhase.expired,
    LinkThisStep.failed when state.problem == LinkProblem.declined =>
      LinkThisDevicePhase.declined,
    LinkThisStep.failed => LinkThisDevicePhase.failed,
  };
  final name = proposal?.helixName;
  return LinkThisDeviceModel(
    phase: phase,
    qr: state.qr,
    checkNumber: state.check ?? '',
    expiresIn: countdown ?? '',
    failureText: state.error,
    maskedPhone: proposal?.phoneMask ?? 'No phone number',
    helixName: name == null || name.isEmpty ? '' : '~$name',
    keyCode: proposal?.keyCode ?? '',
    showSimulate: false,
  );
}
