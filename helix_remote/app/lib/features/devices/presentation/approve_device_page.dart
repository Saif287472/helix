import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:helix_remote/features/devices/application/devices_providers.dart';
import 'package:helix_remote/shared/widgets/inline_notice.dart';
import 'package:helix_remote/shared/widgets/key_code_display.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// Settings > Devices > Link a new device.
///
/// The new device shows a QR code; this page scans it (or takes it pasted),
/// shows what it is about to approve, and only then sends the account's keys.
/// Three checks sit between the scan and the send: the code must name this
/// server, the person must confirm a device they are holding and compare the
/// short number, and the phone's own screen lock must be passed.
class ApproveDevicePage extends ConsumerStatefulWidget {
  const ApproveDevicePage({super.key});

  @override
  ConsumerState<ApproveDevicePage> createState() => _ApproveDevicePageState();
}

class _ApproveDevicePageState extends ConsumerState<ApproveDevicePage> {
  final TextEditingController _paste = TextEditingController();

  @override
  void dispose() {
    _paste.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(approveLinkProvider);
    final controller = ref.read(approveLinkProvider.notifier);
    final scanner = ref.watch(linkScannerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Link a new device')),
      body: switch (state.step) {
        ApproveStep.enter => ListView(
          children: [
            const PageIntro(
              text:
                  'On the new device, open Helix and choose to link it to an '
                  'existing account. It will show a QR code. Scan it here.',
            ),
            if (state.error != null)
              InlineNotice(kind: InlineNoticeKind.error, message: state.error!),
            if (scanner != null)
              SizedBox(
                height: 320,
                child: HelixQrScanFrame(
                  child: scanner(context, controller.submit),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(HelixSpace.md),
              child: TextField(
                controller: _paste,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: 'Or paste the code',
                  helperText: 'It starts with helix-link',
                ),
                onSubmitted: controller.submit,
              ),
            ),
            BusyFilledButton(
              label: 'Continue',
              onPressed: () => controller.submit(_paste.text),
            ),
          ],
        ),
        ApproveStep.review || ApproveStep.approving => ListView(
          children: [
            if (state.error != null)
              InlineNotice(kind: InlineNoticeKind.error, message: state.error!),
            PageIntro(
              title: 'Approve this device?',
              text:
                  'A device on ${state.request?.serverHost ?? 'your server'} '
                  'is asking to join your account. Once approved it can read '
                  'your new messages and can receive your history.',
            ),
            Padding(
              padding: const EdgeInsets.all(HelixSpace.md),
              child: KeyCodeDisplay(
                label: 'Check number',
                code: state.request?.check ?? '',
              ),
            ),
            if (state.request?.accountKeyCode != null)
              Padding(
                padding: const EdgeInsets.all(HelixSpace.md),
                child: KeyCodeDisplay(
                  label: 'Your account key code',
                  code: state.request!.accountKeyCode!,
                ),
              ),
            const PageIntro(
              text:
                  'The same number should be showing on the new device. If '
                  'it is not, or if the device is not in your hands right '
                  'now, do not approve it. The new device will then ask '
                  "whether the account is its owner's and show the key code "
                  'above: compare them. Nobody from Helix will ever ask you '
                  'to scan a code.',
            ),
            BusyFilledButton(
              label: 'Approve',
              icon: Icons.check,
              busy: state.step == ApproveStep.approving,
              onPressed: controller.approve,
            ),
            BusyFilledButton(
              label: 'Cancel',
              tonal: true,
              onPressed: state.step == ApproveStep.approving
                  ? null
                  : () {
                      controller.reset();
                      context.pop();
                    },
            ),
          ],
        ),
        ApproveStep.done => ListView(
          children: [
            const InlineNotice(
              kind: InlineNoticeKind.success,
              message:
                  'The device is joining your account. It will show up in '
                  'your device list in a moment, once its owner has '
                  'confirmed the account.',
            ),
            const PageIntro(
              title: 'Chat history',
              text:
                  'A new device starts without your old messages. You can '
                  'send them from this phone, encrypted: the new device '
                  'must accept them. Nothing is sent unless you choose to.',
            ),
            if (state.historyError != null)
              InlineNotice(
                kind: InlineNoticeKind.error,
                message: state.historyError!,
              ),
            if (state.historySent)
              const InlineNotice(
                kind: InlineNoticeKind.success,
                message:
                    'Your history is on its way. The new device will ask to '
                    'accept it under Settings, Backup.',
              )
            else
              BusyFilledButton(
                label: 'Send history to this device',
                icon: Icons.send_to_mobile_outlined,
                busy: state.sendingHistory,
                onPressed: controller.sendHistory,
              ),
            BusyFilledButton(
              label: 'Done',
              tonal: !state.historySent,
              onPressed: () => context.pop(),
            ),
          ],
        ),
      },
    );
  }
}
