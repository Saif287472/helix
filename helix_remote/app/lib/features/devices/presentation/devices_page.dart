import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:helix_remote/features/devices/application/devices_providers.dart';
import 'package:helix_remote/shared/route_paths.dart';
import 'package:helix_remote/shared/widgets/inline_notice.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// Settings > Devices: where this account is signed in.
///
/// The list is the server's, refreshed when the page opens and by pulling
/// down. Removing a device signs it out at once and it loses its messages;
/// "lost or stolen" says so to the server too. This device is not removable
/// here: signing it out is Settings > Account > Sign out.
class DevicesPage extends ConsumerStatefulWidget {
  const DevicesPage({super.key});

  @override
  ConsumerState<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends ConsumerState<DevicesPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(devicesActionsProvider.notifier).refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final devices = ref.watch(devicesProvider);
    final action = ref.watch(devicesActionsProvider);
    final notifier = ref.read(devicesActionsProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Devices')),
      body: RefreshIndicator(
        onRefresh: notifier.refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            if (action.busy) const LinearProgressIndicator(),
            if (action.error != null)
              InlineNotice(
                kind: InlineNoticeKind.error,
                message: action.error!,
                action: TextButton(
                  onPressed: notifier.refresh,
                  child: const Text('Try again'),
                ),
              ),
            if (action.notice != null)
              InlineNotice(
                kind: InlineNoticeKind.success,
                message: action.notice!,
              ),
            const PageIntro(
              text:
                  'These devices can read your messages. If you do not '
                  'recognise one, remove it and change your password.',
            ),
            switch (devices) {
              AsyncData(:final value) when value.isEmpty => const Padding(
                padding: EdgeInsets.all(HelixSpace.lg),
                child: Text('No devices to show yet.'),
              ),
              AsyncData(:final value) => HelixSettingsSection(
                title: 'Signed in',
                children: [
                  for (final device in value)
                    HelixSettingsTile(
                      icon: switch (device.kind) {
                        DevicePlatformKind.phone => Icons.smartphone,
                        DevicePlatformKind.desktop => Icons.computer,
                        DevicePlatformKind.other => Icons.devices_other,
                      },
                      title: device.title,
                      subtitle: device.subtitle,
                      showChevron: true,
                      onTap: () => _openActions(context, device),
                    ),
                ],
              ),
              AsyncError() => HelixErrorState(
                message: 'The device list could not be loaded.',
                onRetry: () => ref.invalidate(devicesProvider),
              ),
              _ => const Padding(
                padding: EdgeInsets.all(HelixSpace.lg),
                child: LinearProgressIndicator(),
              ),
            },
            HelixSettingsSection(
              children: [
                HelixSettingsTile(
                  icon: Icons.qr_code_scanner,
                  title: 'Link a new device',
                  subtitle: 'Scan the code shown on the new device',
                  showChevron: true,
                  onTap: () => context.push(RoutePaths.devicesLink),
                ),
                HelixSettingsTile(
                  icon: Icons.shield_outlined,
                  title: 'Security activity',
                  subtitle: 'Sign-ins, new devices and key changes',
                  showChevron: true,
                  onTap: () => context.push(RoutePaths.devicesActivity),
                ),
              ],
            ),
            HelixSettingsSection(
              footer:
                  'Signs every other device out of Helix. They lose their '
                  'messages and will need to sign in again.',
              children: [
                HelixSettingsTile(
                  icon: Icons.phonelink_erase,
                  title: 'Sign out all other devices',
                  destructive: true,
                  onTap: () => _confirmRevokeOthers(context),
                ),
              ],
            ),
            const SizedBox(height: HelixSpace.lg),
          ],
        ),
      ),
    );
  }

  Future<void> _openActions(BuildContext context, DeviceRowView device) async {
    final choice = await showHelixBottomSheet<_DeviceAction>(
      context,
      title: device.title,
      builder: (sheetContext) => Column(
        children: [
          HelixSettingsTile(
            icon: Icons.edit_outlined,
            title: 'Rename',
            onTap: () => Navigator.pop(sheetContext, _DeviceAction.rename),
          ),
          if (!device.isThisDevice) ...[
            HelixSettingsTile(
              icon: Icons.phonelink_erase,
              title: 'Remove this device',
              destructive: true,
              onTap: () => Navigator.pop(sheetContext, _DeviceAction.remove),
            ),
            HelixSettingsTile(
              icon: Icons.report_gmailerrorred_outlined,
              title: 'Lost or stolen',
              subtitle: 'Remove it and tell Helix it is no longer yours',
              destructive: true,
              onTap: () => Navigator.pop(sheetContext, _DeviceAction.lost),
            ),
          ],
        ],
      ),
    );
    if (choice == null || !context.mounted) return;
    final notifier = ref.read(devicesActionsProvider.notifier);
    switch (choice) {
      case _DeviceAction.rename:
        final name = await showHelixTextInputDialog(
          context,
          title: 'Rename device',
          label: 'Device name',
          initialValue: device.title,
          maxLength: 60,
        );
        if (name != null) await notifier.rename(device.id, name);
      case _DeviceAction.remove:
        final ok = await showHelixDestructiveDialog(
          context,
          title: 'Remove ${device.title}?',
          message:
              'It will be signed out and lose its messages. You can sign '
              'in on it again later.',
          action: 'Remove',
        );
        if (ok) await notifier.revoke(device.id);
      case _DeviceAction.lost:
        final ok = await showHelixDestructiveDialog(
          context,
          title: 'Lost or stolen?',
          message:
              '${device.title} will be signed out at once and Helix will '
              'note that it is no longer yours. Consider changing your '
              'password too.',
          action: 'Remove it',
        );
        if (ok) await notifier.revoke(device.id, lost: true);
    }
  }

  Future<void> _confirmRevokeOthers(BuildContext context) async {
    final ok = await showHelixDestructiveDialog(
      context,
      title: 'Sign out all other devices?',
      message:
          'Every device except this one will be signed out and will lose '
          'its messages. This phone stays signed in.',
      action: 'Sign them out',
    );
    if (ok) await ref.read(devicesActionsProvider.notifier).revokeOthers();
  }
}

enum _DeviceAction { rename, remove, lost }
