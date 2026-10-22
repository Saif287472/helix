import 'package:flutter/material.dart';

import 'package:orbit_ui/src/components/avatar.dart';
import 'package:orbit_ui/src/components/button.dart';
import 'package:orbit_ui/src/components/chip_tag.dart';
import 'package:orbit_ui/src/components/codes.dart';
import 'package:orbit_ui/src/components/fields.dart';
import 'package:orbit_ui/src/components/list_rows.dart';
import 'package:orbit_ui/src/components/overlays.dart';
import 'package:orbit_ui/src/components/page_parts.dart';
import 'package:orbit_ui/src/components/pages.dart';
import 'package:orbit_ui/src/components/state_kit.dart';
import 'package:orbit_ui/src/components/toggles.dart';
import 'package:orbit_ui/src/components/you_parts.dart';
import 'package:orbit_ui/src/icons/orbit_glyph.dart';
import 'package:orbit_ui/src/icons/orbit_icons.dart';
import 'package:orbit_ui/src/screens/people/people_screens.dart'
    show OrbitScanFrame;
import 'package:orbit_ui/src/screens/signin/entry_screens.dart'
    show OrbitButtonRow, OrbitTransferCard;
import 'package:orbit_ui/src/screens/you/settings_screens.dart'
    show OrbitFormCard;
import 'package:orbit_ui/src/screens/you/you_screens.dart'
    show OrbitTileGrid, OrbitTopicTile;
import 'package:orbit_ui/src/theme/orbit_metrics.dart';
import 'package:orbit_ui/src/theme/orbit_text.dart';
import 'package:orbit_ui/src/theme/orbit_tokens.dart';

void _none() {}

// ----------------------------------------------------------------- devices

class DeviceItem {
  const DeviceItem({
    required this.id,
    required this.name,
    required this.platform,
    required this.whenLabel,
    this.isThis = false,
    this.icon = OrbitIcons.deviceMobile,
  });

  final String id;
  final String name;

  /// "Android" / "Windows".
  final String platform;

  /// "This device" / "Active 5 minutes ago".
  final String whenLabel;
  final bool isThis;
  final OrbitGlyph icon;
}

/// One line of security activity.
class ActivityItem {
  const ActivityItem({
    required this.icon,
    required this.title,
    required this.detail,
    this.check = false,
  });

  final OrbitGlyph icon;
  final String title;

  /// "Pixel 8 · Today, 08:02".
  final String detail;

  /// Worth a look: amber, with a Check tag.
  final bool check;
}

class DeviceListModel {
  const DeviceListModel({this.devices = const [], this.recent = const []});

  final List<DeviceItem> devices;
  final List<ActivityItem> recent;
}

class DeviceListActions {
  const DeviceListActions({
    this.onLinkNew,
    this.onRename,
    this.onRemove,
    this.onLost,
    this.onAllActivity,
    this.onSignOutOthers,
  });

  final VoidCallback? onLinkNew;
  final void Function(String id, String name)? onRename;
  final ValueChanged<String>? onRemove;
  final ValueChanged<String>? onLost;
  final VoidCallback? onAllActivity;
  final VoidCallback? onSignOutOthers;
}

void _confirm(
  BuildContext context,
  String title,
  String text,
  String yes,
  VoidCallback? run,
) => showOrbitDialog(
  context,
  title: title,
  text: text,
  actions: [
    const OrbitDialogAction('Cancel'),
    OrbitDialogAction(yes, kind: OrbitButtonKind.danger, onPressed: run),
  ],
);

/// `devices`: the devices signed in, Link a new device, recent security
/// activity, and Sign out all other devices.
class DeviceListScreen extends StatelessWidget {
  const DeviceListScreen({
    super.key,
    required this.model,
    this.actions = const DeviceListActions(),
  });

  final DeviceListModel model;
  final DeviceListActions actions;

  @override
  Widget build(BuildContext context) {
    final m = model;
    final a = actions;
    final n = m.devices.length;
    return OrbitYouPage(
      title: 'Devices',
      children: [
        OrbitHeroCard(
          icon: OrbitIcons.devices,
          title: '$n device${n == 1 ? '' : 's'} signed in',
          sub: 'Each can read your new messages',
          slot: Padding(
            padding: const EdgeInsets.only(top: 14),
            child: OrbitTileGrid(
              tiles: [
                for (final d in m.devices)
                  _DeviceCard(d, onTap: () => _sheet(context, d)),
              ],
            ),
          ),
        ),
        OrbitButtonRow(
          children: [
            OrbitButton(
              label: 'Link a new device',
              icon: OrbitIcons.qrCode,
              block: true,
              onPressed: a.onLinkNew ?? _none,
            ),
          ],
        ),
        const OrbitGroupTitle('Recent security activity'),
        OrbitCard(
          children: [
            for (final e in m.recent) _activityRow(e),
            OrbitListRow(
              title: 'See all activity',
              accent: true,
              end: OrbitRowEnd.chevron,
              onTap: a.onAllActivity,
            ),
          ],
        ),
        if (n > 1)
          OrbitDangerZone(
            footer:
                'Signed-out devices lose their messages. This phone stays '
                'signed in.',
            rows: [
              OrbitListRow(
                icon: OrbitIcons.signOut,
                title: 'Sign out all other devices',
                danger: true,
                onTap: () => _confirm(
                  context,
                  'Sign out all other devices?',
                  'Every device except this one will be signed out and lose '
                      'its messages.',
                  'Sign them out',
                  a.onSignOutOthers,
                ),
              ),
            ],
          ),
      ],
    );
  }

  void _sheet(BuildContext context, DeviceItem d) {
    final a = actions;
    showOrbitSheet(
      context,
      title: d.name,
      text: '${d.platform} · ${d.whenLabel}',
      items: [
        OrbitMenuItem(
          icon: OrbitIcons.pencilSimple,
          label: 'Rename',
          onTap: () => showOrbitInputDialog(
            context,
            title: 'Rename device',
            label: 'Device name',
            value: d.name,
            onConfirm: (v) => a.onRename?.call(d.id, v),
          ),
        ),
        if (!d.isThis) ...[
          OrbitMenuItem(
            icon: OrbitIcons.xCircle,
            label: 'Remove this device',
            danger: true,
            onTap: () => _confirm(
              context,
              'Remove ${d.name}?',
              'It will be signed out and lose its messages. You can sign in '
                  'on it again later.',
              'Remove',
              () => a.onRemove?.call(d.id),
            ),
          ),
          OrbitMenuItem(
            icon: OrbitIcons.siren,
            label: 'Lost or stolen',
            sub: 'Remove it and note that it is no longer yours',
            danger: true,
            onTap: () => _confirm(
              context,
              'Lost or stolen?',
              '${d.name} will be signed out at once. Consider changing your '
                  'password too.',
              'Remove it',
              () => a.onLost?.call(d.id),
            ),
          ),
        ],
      ],
    );
  }
}

OrbitListRow _activityRow(ActivityItem e) => OrbitListRow(
  icon: e.check ? OrbitIcons.warning : e.icon,
  iconColor: e.check ? 4 : 7,
  title: e.title,
  sub: e.detail,
  trailing: e.check
      ? const OrbitTag(label: 'Check', tone: OrbitTagTone.warning)
      : null,
);

/// `.dev-card`: a device in the hero. This device is tinted `--accent-soft`.
class _DeviceCard extends StatelessWidget {
  const _DeviceCard(this.d, {required this.onTap});

  final DeviceItem d;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    return Semantics(
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 120),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: d.isThis ? t.accentSoft : t.bg,
            border: Border.all(color: d.isThis ? t.accentLine : t.line),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // An `<i>` at 26px keeps a 1.4 line box.
              SizedBox(
                height: 26 * 1.4,
                child: Center(
                  child: OrbitIcon(
                    d.icon,
                    weight: OrbitIconWeight.fill,
                    size: 26,
                    color: t.accentInk,
                  ),
                ),
              ),
              const SizedBox(height: 9),
              OrbitText(
                d.name,
                style: t.font.style(size: 14, weight: 640, color: t.ink),
              ),
              const SizedBox(height: 3),
              OrbitText(
                d.platform,
                style: t.font.style(
                  size: 12,
                  color: d.isThis ? t.accentInk : t.ink3,
                ),
              ),
              const SizedBox(height: 9),
              OrbitTag(
                label: d.isThis
                    ? 'This device'
                    : d.whenLabel.replaceFirst('Active ', ''),
                tone: d.isThis ? OrbitTagTone.accent : OrbitTagTone.plain,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --------------------------------------------------- link a new device

enum ApproveStage { enter, review, approving, done }

class ApproveDeviceModel {
  const ApproveDeviceModel({
    this.stage = ApproveStage.enter,
    this.error,
    this.checkNumber = '',
    this.serverHost = '',
    this.accountKeyCode,
    this.canScan = true,
    this.historySending = false,
    this.historySent = false,
    this.historyError,
    this.unlockWhat = 'your fingerprint, face or phone PIN',
    this.unlockButton = 'Use fingerprint',
  });

  final ApproveStage stage;
  final String? error;

  /// "72 914": what both devices must show.
  final String checkNumber;
  final String serverHost;

  /// The account's key code, shown on this device for the new device's "Is
  /// this your account?" check; null when this device cannot read it.
  final String? accountKeyCode;

  /// False where the platform has no camera: paste only.
  final bool canScan;
  final bool historySending;
  final bool historySent;
  final String? historyError;
  final String unlockWhat;
  final String unlockButton;
}

class ApproveDeviceActions {
  const ApproveDeviceActions({
    this.onContinue,
    this.onPaste,
    this.onApprove,
    this.onSendHistory,
    this.onDone,
  });

  final ValueChanged<String>? onContinue;
  final VoidCallback? onPaste;

  /// After the device unlock is confirmed.
  final VoidCallback? onApprove;
  final VoidCallback? onSendHistory;
  final VoidCallback? onDone;
}

const _linkSteps = ['Scan', 'Check', 'Done'];

/// `approve-device`: link a new device from this one. Scan or paste its
/// code, check the number, approve, then send it your history.
class ApproveDeviceScreen extends StatefulWidget {
  const ApproveDeviceScreen({
    super.key,
    required this.model,
    this.actions = const ApproveDeviceActions(),
    this.camera,
  });

  final ApproveDeviceModel model;
  final ApproveDeviceActions actions;

  /// The live camera inside the scan frame.
  final WidgetBuilder? camera;

  @override
  State<ApproveDeviceScreen> createState() => _ApproveDeviceScreenState();
}

class _ApproveDeviceScreenState extends State<ApproveDeviceScreen> {
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.model;
    final a = widget.actions;
    final done = a.onDone ?? () => Navigator.maybePop(context);
    final List<Widget> body;
    switch (m.stage) {
      case ApproveStage.enter:
        body = [
          OrbitHeroCard(
            icon: OrbitIcons.qrCode,
            title: 'Scan the new device',
            sub: 'Its code lasts ten minutes',
            slot: Column(
              children: [
                const _Steps(_linkSteps, 0),
                if (m.canScan)
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 320),
                        child: LayoutBuilder(
                          builder: (context, c) => OrbitScanFrame(
                            width: c.maxWidth,
                            height: 210,
                            child: widget.camera?.call(context),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (m.error != null)
            OrbitInlineNotice(kind: OrbitNoticeKind.error, text: m.error!),
          const OrbitGroupTitle('Or paste the code'),
          OrbitFormCard(
            children: [
              OrbitTextField(
                label: 'Link code',
                controller: _code,
                hint: 'helix-link:…',
                mono: true,
                helper: 'It starts with helix-link',
                onPaste: a.onPaste ?? _none,
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
          OrbitButtonRow(
            children: [
              OrbitButton(
                label: 'Continue',
                block: true,
                onPressed: _code.text.trim().isEmpty
                    ? null
                    : () => a.onContinue?.call(_code.text.trim()),
              ),
            ],
          ),
          const OrbitSectionFoot(
            'On the new device, open Orbit and choose to link it to an '
            'existing account. It shows a QR code. Nobody from Orbit will '
            'ever ask you to scan one.',
          ),
        ];
      case ApproveStage.review:
      case ApproveStage.approving:
        body = [
          if (m.error != null)
            OrbitInlineNotice(kind: OrbitNoticeKind.error, text: m.error!),
          OrbitHeroCard(
            icon: OrbitIcons.devices,
            title: 'Approve this device?',
            sub: 'A device on ${m.serverHost} wants to join',
            slot: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _Steps(_linkSteps, 1),
                OrbitCodeBox(
                  label: 'Check number',
                  code: m.checkNumber,
                  size: OrbitCodeSize.huge,
                ),
              ],
            ),
          ),
          if (m.accountKeyCode != null)
            OrbitCodeBox(
              label: 'Your account key code',
              code: m.accountKeyCode!,
              note:
                  'The new device shows this code after you approve. Compare '
                  'it there before its owner says yes.',
            ),
          const OrbitInlineNotice(
            kind: OrbitNoticeKind.warning,
            text:
                'Check that the new device shows the same number. Do not '
                'approve a device you are not holding.',
          ),
          const OrbitSectionFoot(
            'Once approved it can read your new messages and can receive '
            'your history. The new device then shows your account key code '
            'to check.',
          ),
          OrbitButtonRow(
            column: true,
            children: [
              OrbitButton(
                label: 'Approve',
                icon: OrbitIcons.check,
                iconWeight: OrbitIconWeight.bold,
                busy: m.stage == ApproveStage.approving,
                block: true,
                onPressed: () => showOrbitDialog(
                  context,
                  title: 'Approve a new device for your Orbit account',
                  text: 'Confirm with ${m.unlockWhat}.',
                  actions: [
                    const OrbitDialogAction('Cancel'),
                    OrbitDialogAction(
                      m.unlockButton,
                      kind: OrbitButtonKind.primary,
                      onPressed: a.onApprove,
                    ),
                  ],
                ),
              ),
              OrbitButton(
                label: 'Cancel',
                kind: OrbitButtonKind.secondary,
                block: true,
                onPressed: () => Navigator.maybePop(context),
              ),
            ],
          ),
        ];
      case ApproveStage.done:
        body = [
          const OrbitHeroCard(
            art: OrbitStatusRing(state: OrbitRingState.ok),
            title: 'The device is joining',
            sub: 'It shows in your list once its owner confirms the account',
            slot: _Steps(_linkSteps, 3),
          ),
          if (m.historyError != null)
            OrbitInlineNotice(
              kind: OrbitNoticeKind.error,
              text: m.historyError!,
            ),
          OrbitSection(
            title: 'Chat history',
            footer: 'The new device asks before it accepts your history.',
            rows: [
              OrbitListRow(
                icon: OrbitIcons.paperPlaneTilt,
                iconColor: 0,
                title: m.historySent
                    ? 'History on its way'
                    : 'Send your history to it',
                sub: m.historySent
                    ? 'The new device asks to accept it under You, Backup'
                    : 'Your past messages are not on the new device yet',
                trailing: m.historySent
                    ? const OrbitTag(
                        label: 'Sent',
                        tone: OrbitTagTone.success,
                        icon: OrbitIcons.check,
                      )
                    : OrbitButton(
                        label: 'Send',
                        kind: OrbitButtonKind.secondary,
                        height: 38,
                        busy: m.historySending,
                        onPressed: m.historySending
                            ? null
                            : (a.onSendHistory ?? _none),
                      ),
              ),
            ],
          ),
          OrbitButtonRow(
            children: [
              OrbitButton(label: 'Done', block: true, onPressed: done),
            ],
          ),
        ];
    }
    return OrbitYouPage(title: 'Link a new device', children: body);
  }
}

// ------------------------------------------------------ security activity

class SecurityActivityModel {
  const SecurityActivityModel({
    this.thisWeek = const [],
    this.earlier = const [],
    this.deviceCount = 1,
  });

  final List<ActivityItem> thisWeek;
  final List<ActivityItem> earlier;
  final int deviceCount;
}

class SecurityActivityActions {
  const SecurityActivityActions({this.onDevices, this.onPassword});

  final VoidCallback? onDevices;
  final VoidCallback? onPassword;
}

/// `activity`: sign-ins, devices and key changes, newest first.
class SecurityActivityScreen extends StatelessWidget {
  const SecurityActivityScreen({
    super.key,
    required this.model,
    this.actions = const SecurityActivityActions(),
  });

  final SecurityActivityModel model;
  final SecurityActivityActions actions;

  @override
  Widget build(BuildContext context) {
    final m = model;
    final all = [...m.thisWeek, ...m.earlier];
    final check = all.where((e) => e.check).length;
    return OrbitYouPage(
      title: 'Security activity',
      children: [
        OrbitHeroCard(
          icon: OrbitIcons.shieldCheck,
          title: 'Security activity',
          sub: '${all.length} recent events',
          pills: [
            if (check > 0)
              OrbitHeroPill(
                icon: OrbitIcons.warning,
                text: '$check to check',
                tone: OrbitPillTone.warn,
              ),
            OrbitHeroPill(
              icon: OrbitIcons.devices,
              text: '${m.deviceCount} devices now',
            ),
          ],
        ),
        if (m.thisWeek.isNotEmpty)
          OrbitSection(
            title: 'This week',
            rows: [for (final e in m.thisWeek) _activityRow(e)],
          ),
        if (m.earlier.isNotEmpty)
          OrbitSection(
            title: 'Earlier',
            footer:
                'Your account’s sign-ins, devices and key changes. Nothing '
                'here includes your messages.',
            rows: [for (final e in m.earlier) _activityRow(e)],
          ),
        OrbitSection(
          title: 'Something you do not recognise?',
          rows: [
            OrbitListRow(
              icon: OrbitIcons.devices,
              iconColor: 0,
              title: 'Review your devices',
              sub: 'Remove any you do not know',
              end: OrbitRowEnd.chevron,
              onTap: actions.onDevices,
            ),
            OrbitListRow(
              icon: OrbitIcons.password,
              iconColor: 1,
              title: 'Change your password',
              end: OrbitRowEnd.chevron,
              onTap: actions.onPassword,
            ),
          ],
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ backup

enum BackupState { ok, running, failed, never }

class BackupModel {
  const BackupModel({
    this.state = BackupState.ok,
    this.progress = 0,
    this.lastLabel = '5 hours ago',
    this.detail = '',
    this.failedReason = '',
    this.daily = true,
    this.mobileData = false,
    this.transfersWaiting = 0,
    this.recoveryMade = false,
    this.recoveryLabel = 'Today',
  });

  final BackupState state;

  /// 0 to 1 while running.
  final double progress;

  /// "5 hours ago" / "just now".
  final String lastLabel;

  /// "12,480 messages · 3.1 MB, encrypted".
  final String detail;
  final String failedReason;
  final bool daily;
  final bool mobileData;
  final int transfersWaiting;
  final bool recoveryMade;
  final String recoveryLabel;
}

class BackupActions {
  const BackupActions({
    this.onBackUp,
    this.onDaily,
    this.onMobileData,
    this.onRestore,
    this.onTransfer,
    this.onRecovery,
    this.onDeleteServerBackup,
  });

  final VoidCallback? onBackUp;
  final ValueChanged<bool>? onDaily;
  final ValueChanged<bool>? onMobileData;
  final VoidCallback? onRestore;
  final VoidCallback? onTransfer;
  final VoidCallback? onRecovery;
  final VoidCallback? onDeleteServerBackup;
}

/// `backup`: the last backup and Back up now, automatic backup, moving
/// your history, the recovery backup, and deleting the server copy.
class BackupScreen extends StatefulWidget {
  const BackupScreen({
    super.key,
    required this.model,
    this.actions = const BackupActions(),
  });

  final BackupModel model;
  final BackupActions actions;

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  late var _daily = widget.model.daily;
  late var _mobile = widget.model.mobileData;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final m = widget.model;
    final a = widget.actions;
    final (Widget ring, String title, String sub) = switch (m.state) {
      BackupState.running => (
        OrbitStatusRing(
          state: OrbitRingState.run,
          progress: m.progress,
          size: 64,
        ),
        'Backing up…',
        m.detail,
      ),
      BackupState.failed => (
        const OrbitStatusRing(state: OrbitRingState.bad, size: 64),
        'The last backup did not finish',
        m.failedReason,
      ),
      BackupState.never => (
        const OrbitStatusRing(
          state: OrbitRingState.idle,
          icon: OrbitIcons.cloudSlash,
          size: 64,
        ),
        'Not backed up yet',
        'Back up now to keep your chats if you lose this phone',
      ),
      BackupState.ok => (
        const OrbitStatusRing(state: OrbitRingState.ok, size: 64),
        'Backed up ${m.lastLabel}',
        m.detail,
      ),
    };
    final rec = m.recoveryMade;
    final (recBg, recInk) = OrbitAvatar.palette(t, rec ? 3 : 4);
    return OrbitYouPage(
      title: 'Backup',
      children: [
        OrbitHeroCard(art: ring, title: title, sub: sub),
        OrbitButtonRow(
          children: [
            // While running the prototype's inline `opacity: .6` replaces
            // the disabled 45% rather than adding to it.
            IgnorePointer(
              ignoring: m.state == BackupState.running,
              child: Opacity(
                opacity: m.state == BackupState.running ? 0.6 : 1,
                child: OrbitButton(
                  label: m.state == BackupState.failed
                      ? 'Try again'
                      : 'Back up now',
                  icon: OrbitIcons.cloudArrowUp,
                  block: true,
                  onPressed: a.onBackUp ?? _none,
                ),
              ),
            ),
          ],
        ),
        const OrbitSectionFoot(
          'Your chats and references to your files, encrypted on this phone '
          'with a key only your devices have. Files themselves, unsent and '
          'view-once messages are not included.',
        ),
        OrbitSection(
          title: 'Automatic',
          rows: [
            OrbitListRow(
              icon: OrbitIcons.arrowsClockwise,
              iconColor: 0,
              title: 'Back up every day',
              sub: 'While Orbit is open, and when a new device joins',
              end: OrbitRowEnd.toggle,
              on: _daily,
              onChanged: (v) {
                setState(() => _daily = v);
                a.onDaily?.call(v);
              },
            ),
            OrbitListRow(
              icon: OrbitIcons.cellSignalFull,
              iconColor: 4,
              title: 'Use mobile data',
              sub: 'Otherwise backups wait for Wi-Fi',
              end: OrbitRowEnd.toggle,
              on: _mobile,
              onChanged: (v) {
                setState(() => _mobile = v);
                a.onMobileData?.call(v);
              },
            ),
          ],
        ),
        const OrbitGroupTitle('Move your history'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: OrbitSpace.gutter),
          child: OrbitTileGrid(
            tiles: [
              OrbitTopicTile(
                icon: OrbitIcons.cloudArrowDown,
                colour: 2,
                title: 'Restore',
                status: 'From your backup',
                onTap: a.onRestore,
              ),
              OrbitTopicTile(
                icon: OrbitIcons.devices,
                colour: 0,
                title: 'Send to a device',
                status: m.transfersWaiting > 0
                    ? '${m.transfersWaiting} waiting'
                    : 'To your other devices',
                onTap: a.onTransfer,
              ),
            ],
          ),
        ),
        const OrbitGroupTitle('Recovery backup'),
        _RecCard(
          ok: rec,
          child: OrbitListRow(
            minHeight: 72,
            leading: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: recBg,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Center(
                child: OrbitIcon(
                  OrbitIcons.key,
                  weight: OrbitIconWeight.fill,
                  size: 19,
                  color: recInk,
                ),
              ),
            ),
            title: rec ? 'Recovery backup made' : 'No recovery backup yet',
            sub: rec
                ? 'Opens only with the secret you saved'
                : 'For when you lose every device. Only a secret you keep '
                      'opens it.',
            trailing: rec
                ? OrbitTag(
                    label: m.recoveryLabel,
                    tone: OrbitTagTone.success,
                    icon: OrbitIcons.check,
                  )
                : OrbitButton(
                    label: 'Create',
                    kind: OrbitButtonKind.secondary,
                    height: 38,
                    onPressed: a.onRecovery ?? _none,
                  ),
          ),
        ),
        OrbitDangerZone(
          footer:
              'Deletes the copy on the server only. Your devices keep their '
              'messages.',
          rows: [
            OrbitListRow(
              icon: OrbitIcons.trash,
              title: 'Delete my server backup',
              danger: true,
              onTap: () => _confirm(
                context,
                'Delete the server backup?',
                'Orbit deletes the encrypted backup it keeps for you. A new '
                    'one is made on the next run if daily backup is on.',
                'Delete',
                a.onDeleteServerBackup,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// `.card.rec-card`: one row; its edge turns `--success-line` once made.
class _RecCard extends StatelessWidget {
  const _RecCard({required this.ok, required this.child});

  final bool ok;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    if (!ok) return OrbitCard(children: [child]);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: OrbitSpace.gutter),
      child: Container(
        decoration: BoxDecoration(
          color: t.surface,
          border: Border.all(color: t.successLine),
          borderRadius: BorderRadius.circular(t.rLg),
          boxShadow: t.shadowCard,
        ),
        child: child,
      ),
    );
  }
}

// --------------------------------------------------------------- transfers

/// One device-to-device transfer: where it has got to, the bar while it
/// runs, and the buttons that make sense now (the shared transfer row).
class TransferItem {
  const TransferItem({
    required this.id,
    required this.title,
    required this.status,
    this.outgoing = false,
    this.progress,
    this.buttons = const [],
  });

  final String id;
  final String title;

  /// Where it has got to, or why it stopped.
  final String status;
  final bool outgoing;

  /// 0..1 while it runs and the size is known.
  final double? progress;

  /// Button labels: Accept, Resume, Try again, Decline, Pause, Cancel,
  /// Dismiss. [TransferActions.onAction] gets the label.
  final List<String> buttons;
}

class TransferModel {
  const TransferModel({
    this.sending = const [],
    this.waiting = const [],
    this.error,
    this.busy = false,
    this.incomingLoading = false,
    this.incomingFailed = false,
  });

  final List<TransferItem> sending;
  final List<TransferItem> waiting;

  /// "This is your only device. …"
  final String? error;
  final bool busy;

  /// The offers are still being read, or could not be read.
  final bool incomingLoading;
  final bool incomingFailed;
}

class TransferActions {
  const TransferActions({this.onSend, this.onAction, this.onRetry});

  final VoidCallback? onSend;

  /// A button on a card: its id and the button's label.
  final void Function(String id, String action)? onAction;
  final VoidCallback? onRetry;
}

/// `transfer`: send your history to your other devices, and what is
/// waiting here.
class TransferScreen extends StatelessWidget {
  const TransferScreen({
    super.key,
    required this.model,
    this.actions = const TransferActions(),
  });

  final TransferModel model;
  final TransferActions actions;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final m = model;
    final waiting = m.waiting
        .where(
          (x) =>
              x.buttons.contains('Accept') ||
              x.buttons.contains('Resume') ||
              x.buttons.contains('Try again'),
        )
        .length;
    final err = m.error;
    return OrbitYouPage(
      title: 'Send to my other devices',
      children: [
        OrbitHeroCard(
          icon: OrbitIcons.devices,
          title: 'Send your history',
          sub: 'To your own devices only',
          pills: [
            const OrbitHeroPill(
              icon: OrbitIcons.lockSimple,
              text: 'Encrypted on this phone',
            ),
            const OrbitHeroPill(
              icon: OrbitIcons.handPointing,
              text: 'Your other device chooses',
            ),
            if (waiting > 0)
              OrbitHeroPill(
                icon: OrbitIcons.downloadSimple,
                text: '$waiting waiting here',
                tone: OrbitPillTone.accent,
              ),
          ],
        ),
        OrbitButtonRow(
          children: [
            OrbitButton(
              label: 'Send my history',
              icon: OrbitIcons.paperPlaneTilt,
              busy: m.busy,
              block: true,
              onPressed: actions.onSend ?? _none,
            ),
          ],
        ),
        if (err != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              OrbitSpace.gutter,
              10,
              OrbitSpace.gutter,
              0,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: OrbitIcon(
                    OrbitIcons.warningCircle,
                    weight: OrbitIconWeight.fill,
                    size: 18,
                    color: t.danger,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OrbitText(
                    err,
                    style: t.font.style(
                      size: OrbitType.small,
                      color: t.danger,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
        const OrbitSectionFoot(
          'Files are not included. Your history is sent encrypted, and your '
          'other device chooses whether to add it.',
        ),
        if (m.sending.isNotEmpty) ...[
          const OrbitGroupTitle('Sending'),
          for (final x in m.sending) _card(x),
        ],
        const OrbitGroupTitle('Waiting for this phone'),
        if (m.incomingLoading)
          const OrbitPageLoading(label: 'Loading transfers…')
        else if (m.incomingFailed)
          OrbitLoadFailed(
            title: 'Transfers could not be loaded.',
            onRetry: actions.onRetry,
          )
        else if (m.waiting.isEmpty)
          const OrbitSectionFoot(
            'Nothing is waiting. When another of your devices sends its '
            'history, it shows up here.',
            top: 0,
          )
        else
          for (final x in m.waiting) _card(x),
      ],
    );
  }

  Widget _card(TransferItem x) {
    return OrbitTransferCard(
      title: x.title,
      status: x.status,
      icon: x.outgoing ? OrbitIcons.uploadSimple : OrbitIcons.downloadSimple,
      iconWeight: OrbitIconWeight.bold,
      progress: x.progress,
      actions: [
        for (final label in x.buttons)
          OrbitButton(
            label: label,
            kind: switch (label) {
              'Accept' || 'Resume' || 'Try again' => OrbitButtonKind.primary,
              'Dismiss' => OrbitButtonKind.ghost,
              _ => OrbitButtonKind.secondary,
            },
            height: 38,
            padding: 14,
            fontSize: 13,
            onPressed: model.busy && label != 'Pause' && label != 'Cancel'
                ? null
                : () => actions.onAction?.call(x.id, label),
          ),
      ],
    );
  }
}

// --------------------------------------------------------- recovery backup

enum RecoveryTab { create, restore }

class RecoveryModel {
  const RecoveryModel({
    required this.secret,
    this.initialTab = RecoveryTab.create,
    this.made = false,
    this.madeLabel = 'Made today',
    this.created = false,
    this.createdNothing = false,
    this.restored,
    this.handoffNote,
    this.error,
    this.busy = false,
    this.saved = false,
  });

  /// Shown only now: "K7QM-X2PD-…".
  final String secret;
  final RecoveryTab initialTab;

  /// One exists already; a new one replaces it.
  final bool made;

  /// "Made today", "Made 3 days ago".
  final String madeLabel;

  /// Just created here.
  final bool created;

  /// The backup had no history in it.
  final bool createdNothing;

  /// "Restored 2,318 messages." once a restore finishes.
  final String? restored;

  /// What copying or sharing did ("Copied. …", "It could not be shared…").
  final String? handoffNote;

  /// Why making or restoring the backup failed.
  final String? error;
  final bool busy;

  /// "I saved it somewhere safe".
  final bool saved;
}

class RecoveryActions {
  const RecoveryActions({
    this.onCopy,
    this.onShare,
    this.onSaved,
    this.onCreate,
    this.onRestore,
    this.onDelete,
  });

  final VoidCallback? onCopy;
  final VoidCallback? onShare;
  final ValueChanged<bool>? onSaved;
  final VoidCallback? onCreate;
  final ValueChanged<String>? onRestore;
  final VoidCallback? onDelete;
}

const _recSteps = ['Save the secret', 'Confirm', 'Create'];

/// `recovery`: make a recovery backup (save the secret, confirm, create),
/// or restore from one.
class RecoveryScreen extends StatefulWidget {
  const RecoveryScreen({
    super.key,
    required this.model,
    this.actions = const RecoveryActions(),
  });

  final RecoveryModel model;
  final RecoveryActions actions;

  @override
  State<RecoveryScreen> createState() => _RecoveryScreenState();
}

class _RecoveryScreenState extends State<RecoveryScreen> {
  late var _tab = widget.model.initialTab;
  final _secret = TextEditingController();

  @override
  void dispose() {
    _secret.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final m = widget.model;
    final a = widget.actions;
    final made = m.created || m.made;
    final replacing = made && !m.created;
    final at = m.created
        ? 3
        : m.saved
        ? 2
        : m.handoffNote != null
        ? 1
        : 0;
    final create = <Widget>[
      if (m.created) ...[
        OrbitInlineNotice(
          kind: OrbitNoticeKind.success,
          text: m.createdNothing
              ? 'There was no history to back up yet.'
              : 'Recovery backup created.',
        ),
        const OrbitSectionFoot(
          'The secret is not stored anywhere on this phone or on the server. '
          'If you lose it, this backup cannot be opened.',
        ),
      ] else ...[
        if (replacing)
          const OrbitInlineNotice(
            kind: OrbitNoticeKind.warning,
            text:
                'You already have a recovery backup. Making a new one '
                'replaces it, and the secret you saved stops working.',
          ),
        const OrbitGroupTitle('Your recovery secret'),
        if (m.secret.isEmpty && m.error == null)
          const OrbitPageLoading(label: 'Making a secret…')
        else if (m.secret.isNotEmpty) ...[
          OrbitCard(
            dividers: false,
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
            children: [
              OrbitCodeBox(
                label: 'Shown only now',
                code: m.secret,
                size: OrbitCodeSize.secret,
                margin: const EdgeInsets.only(top: 10),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: OrbitButton(
                        label: 'Copy',
                        icon: OrbitIcons.copy,
                        kind: OrbitButtonKind.secondary,
                        onPressed: m.busy ? null : (a.onCopy ?? _none),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OrbitButton(
                        label: 'Share',
                        icon: OrbitIcons.shareNetwork,
                        kind: OrbitButtonKind.secondary,
                        onPressed: m.busy ? null : (a.onShare ?? _none),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          OrbitSectionFoot(
            m.handoffNote ??
                'Save it away from this phone, like in a password manager or '
                    'on paper.',
          ),
          OrbitFormCard(
            children: [
              OrbitCheckbox(
                label: 'I saved it somewhere safe',
                on: m.saved,
                top: 0,
                onChanged: m.busy ? null : (v) => a.onSaved?.call(v),
              ),
            ],
          ),
          OrbitButtonRow(
            children: [
              OrbitButton(
                label: 'Create recovery backup',
                icon: OrbitIcons.key,
                block: true,
                busy: m.busy,
                onPressed: m.saved && !m.busy ? (a.onCreate ?? _none) : null,
              ),
            ],
          ),
        ],
      ],
    ];
    final restore = <Widget>[
      const OrbitGroupTitle('Restore'),
      OrbitFormCard(
        children: [
          OrbitTextField(
            label: 'Recovery secret',
            controller: _secret,
            hint: 'XXXX-XXXX-XXXX-XXXX-XXXX-XXXX',
            mono: true,
            enabled: !m.busy,
            helper: 'Exactly as you saved it, with the dashes',
          ),
        ],
      ),
      if (m.restored != null)
        OrbitInlineNotice(kind: OrbitNoticeKind.success, text: m.restored!),
      OrbitButtonRow(
        children: [
          OrbitButton(
            label: 'Restore from recovery backup',
            block: true,
            busy: m.busy,
            onPressed: m.busy
                ? null
                : () {
                    if (_secret.text.trim().isEmpty) {
                      showOrbitToast(
                        context,
                        'Type your recovery secret first.',
                      );
                      return;
                    }
                    a.onRestore?.call(_secret.text.trim());
                  },
          ),
        ],
      ),
    ];
    return OrbitYouPage(
      title: 'Recovery backup',
      children: [
        OrbitHeroCard(
          icon: OrbitIcons.key,
          title: 'Recovery backup',
          sub: 'For when you lose every device',
          slot: _tab == RecoveryTab.create ? _Steps(_recSteps, at) : null,
          pills: [
            made
                ? OrbitHeroPill(
                    icon: OrbitIcons.checkCircle,
                    text: m.madeLabel,
                    tone: OrbitPillTone.ok,
                  )
                : const OrbitHeroPill(
                    icon: OrbitIcons.warningCircle,
                    text: 'Not made yet',
                    tone: OrbitPillTone.warn,
                  ),
            const OrbitHeroPill(
              icon: OrbitIcons.lockSimple,
              text: 'Only your secret opens it',
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            OrbitSpace.gutter,
            14,
            OrbitSpace.gutter,
            0,
          ),
          child: OrbitSegmented<RecoveryTab>(
            options: const [
              OrbitSegment(RecoveryTab.create, 'Create'),
              OrbitSegment(RecoveryTab.restore, 'Restore'),
            ],
            value: _tab,
            onChanged: m.busy ? null : (v) => setState(() => _tab = v),
          ),
        ),
        if (m.error != null)
          OrbitInlineNotice(kind: OrbitNoticeKind.error, text: m.error!),
        ...(_tab == RecoveryTab.create ? create : restore),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 0),
          child: OrbitText(
            'Orbit cannot reset or recover a recovery secret.',
            textAlign: TextAlign.center,
            style: t.font.style(
              size: OrbitType.caption,
              color: t.ink3,
              height: 1.5,
            ),
          ),
        ),
        if (made)
          OrbitDangerZone(
            rows: [
              OrbitListRow(
                icon: OrbitIcons.trash,
                title: 'Delete my recovery backup',
                sub: 'The secret you saved stops working',
                danger: true,
                onTap: () => _confirm(
                  context,
                  'Delete your recovery backup?',
                  'The secret you saved stops working. Your chats on your '
                      'devices are not affected.',
                  'Delete',
                  a.onDelete,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

/// `Kit.steps` in a hero's slot: the step pills, 14px down and at the
/// start, as `.hc-pills` lays them out.
class _Steps extends StatelessWidget {
  const _Steps(this.labels, this.current);

  final List<String> labels;
  final int current;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 14),
    child: Align(
      alignment: Alignment.centerLeft,
      child: OrbitStepPills(labels: labels, current: current),
    ),
  );
}
