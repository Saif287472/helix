import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:helix_remote/features/devices/application/devices_providers.dart';
import 'package:orbit_ui/orbit_ui.dart';

/// Connector: Settings > Devices > Link a new device, drawn by `orbit_ui`'s
/// [ApproveDeviceScreen].
///
/// The new device shows a QR code; this page scans it (or takes it pasted),
/// shows what it is about to approve, and only then sends the account's keys.
/// Three checks sit between the scan and the send: the code must name this
/// server, the person must confirm a device they are holding and compare the
/// short number (then the new device shows this account's key code for its
/// own check), and the phone's own screen lock must be passed.
class ApproveDevicePage extends ConsumerWidget {
  const ApproveDevicePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(approveLinkProvider);
    final controller = ref.read(approveLinkProvider.notifier);
    final scanner = ref.watch(linkScannerProvider);

    Future<void> paste() async {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim() ?? '';
      if (text.isNotEmpty) controller.submit(text);
    }

    return ApproveDeviceScreen(
      model: ApproveDeviceModel(
        stage: switch (state.step) {
          ApproveStep.enter => ApproveStage.enter,
          ApproveStep.review => ApproveStage.review,
          ApproveStep.approving => ApproveStage.approving,
          ApproveStep.done => ApproveStage.done,
        },
        error: state.error,
        checkNumber: state.request?.check ?? '',
        serverHost: state.request?.serverHost ?? 'your server',
        accountKeyCode: state.request?.accountKeyCode,
        canScan: scanner != null,
        historySending: state.sendingHistory,
        historySent: state.historySent,
        historyError: state.historyError,
      ),
      camera: scanner == null
          ? null
          : (context) => scanner(context, controller.submit),
      actions: ApproveDeviceActions(
        onContinue: controller.submit,
        onPaste: paste,
        onApprove: controller.approve,
        onSendHistory: controller.sendHistory,
        onDone: () {
          if (context.canPop()) context.pop();
        },
      ),
    );
  }
}
