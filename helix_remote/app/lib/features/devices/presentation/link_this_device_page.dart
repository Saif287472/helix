import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:helix_remote/features/devices/application/devices_providers.dart';
import 'package:helix_remote/features/devices/application/devices_models.dart';
import 'package:helix_remote/shared/widgets/inline_notice.dart';
import 'package:helix_remote/shared/widgets/key_code_display.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// Link this device to an existing account: shows a QR code for a signed-in
/// device to scan.
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
    final theme = Theme.of(context);

    if (state.step == LinkThisStep.confirming && state.proposal != null) {
      return _ConfirmAccount(proposal: state.proposal!);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Link this device'),
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        children: [
          const PageIntro(
            text:
                'On a device that is already signed in to your account, open '
                'Settings, Devices, Link a new device, and scan this code. '
                'Show it only to your own device.',
          ),
          if (state.step == LinkThisStep.failed && state.error != null)
            InlineNotice(
              kind: InlineNoticeKind.error,
              message: state.error!,
              action: TextButton(
                onPressed: ref.read(linkThisDeviceProvider.notifier).start,
                child: Text(state.expired ? 'Show a new code' : 'Try again'),
              ),
            ),
          if (state.qr != null && state.step != LinkThisStep.failed)
            Padding(
              padding: const EdgeInsets.all(HelixSpace.lg),
              child: Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: HelixRadius.card,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(HelixSpace.sm),
                    child: HelixQrDisplay(
                      matrix: state.qr!,
                      semanticLabel: 'QR code to link this device',
                    ),
                  ),
                ),
              ),
            ),
          if (state.check != null && state.step != LinkThisStep.failed)
            Semantics(
              label: 'Check number',
              value: state.check!.split('').join(' '),
              child: ExcludeSemantics(
                child: Column(
                  children: [
                    Text('Check number', style: theme.textTheme.labelLarge),
                    Text(
                      state.check!,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (state.step == LinkThisStep.starting)
            const Padding(
              padding: EdgeInsets.all(HelixSpace.lg),
              child: LinearProgressIndicator(),
            ),
          if (state.step == LinkThisStep.waiting)
            Padding(
              padding: const EdgeInsets.all(HelixSpace.md),
              child: Text(
                countdown == null
                    ? 'Waiting for approval...'
                    : 'Waiting for approval. Code expires in $countdown.',
                textAlign: TextAlign.center,
              ),
            ),
          if (state.step == LinkThisStep.finishing)
            const Padding(
              padding: EdgeInsets.all(HelixSpace.lg),
              child: Text(
                'Approved. Signing in...',
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }
}

/// "Is this your account?": shown after the other device approved the link and
/// before this device keeps anything. Anyone who has seen the QR code could
/// have approved it with an account of their own, so the person looks at whose
/// account it is: the masked number, the `~Helix name` and a key code that the
/// other device also shows.
class _ConfirmAccount extends ConsumerWidget {
  const _ConfirmAccount({required this.proposal});

  final LinkProposalView proposal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(linkThisDeviceProvider.notifier);
    final theme = Theme.of(context);
    final phone = proposal.phoneMask;
    final name = proposal.helixName;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Link this device'),
        leading: IconButton(
          tooltip: 'Cancel',
          icon: const Icon(Icons.close),
          onPressed: () {
            controller.rejectAccount();
            if (context.canPop()) context.pop();
          },
        ),
      ),
      body: ListView(
        children: [
          const PageIntro(
            title: 'Is this your account?',
            text:
                'Your other device approved the link. Check that this is your '
                'account before you continue. If you are not sure, say no: '
                'nothing is kept on this phone.',
          ),
          HelixSettingsSection(
            title: 'The account',
            children: [
              HelixSettingsTile(
                icon: Icons.phone_outlined,
                title: phone ?? 'No phone number',
                subtitle: 'Phone number, shown in part',
              ),
              if (name != null && name.isNotEmpty)
                HelixSettingsTile(
                  icon: Icons.alternate_email,
                  title: '~$name',
                  subtitle: 'Helix name',
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(HelixSpace.md),
            child: KeyCodeDisplay(label: 'Key code', code: proposal.keyCode),
          ),
          const PageIntro(
            text:
                'The same key code is shown on your other device. If it is '
                'different, or the account is not yours, choose No.',
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: HelixSpace.md),
            child: Text(
              "Choosing Yes gives this phone your account's keys. It can "
              'then read your new messages.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          BusyFilledButton(
            label: 'Yes, this is my account',
            icon: Icons.check,
            onPressed: controller.confirmAccount,
          ),
          BusyFilledButton(
            label: 'No, cancel',
            tonal: true,
            onPressed: controller.rejectAccount,
          ),
          const SizedBox(height: HelixSpace.lg),
        ],
      ),
    );
  }
}
