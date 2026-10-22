import 'package:flutter/widgets.dart';
import 'package:orbit_ui/orbit_ui.dart';

/// The pages under You's topics (`prototype/js/screens/settings.js`,
/// `devices_backup.js`, and Devices and Backup in `topics.js`) on the
/// sample data.

const _host = 'helix.agiletechbd.com';
const _masked = '+880 17•• ••0001';

const _terms = LegalDocument(
  title: 'Orbit Terms of Service',
  version: '3',
  body:
      'These terms explain how you may use Orbit and what we promise in '
      'return.\n\nYour account. You sign up with your phone number. Keep '
      'your password and your devices safe.\n\nYour messages. Messages and '
      'calls are end-to-end encrypted. The server stores them only until '
      'they are delivered and cannot read them.\n\nAcceptable use. Do not '
      'use Orbit to send spam, to harass people, or to break the law.',
);

const _privacy = LegalDocument(
  title: 'Orbit Privacy Policy',
  version: '4',
  body:
      'What the server keeps: your phone number, your devices and their '
      'public keys, and encrypted messages until they are delivered.\n\n'
      'What it never sees: the content of your messages and calls, your '
      'profile name, about line and picture.\n\nContacts are hashed on your '
      'phone before any check; names never leave it.',
);

const _devices = [
  DeviceItem(
    id: 'd1',
    name: 'Pixel 8',
    platform: 'Android',
    whenLabel: 'This device',
    isThis: true,
  ),
  DeviceItem(
    id: 'd2',
    name: 'Office PC',
    platform: 'Windows',
    whenLabel: 'Active 5 minutes ago',
    icon: OrbitIcons.desktop,
  ),
];

const _recent = [
  ActivityItem(
    icon: OrbitIcons.signIn,
    title: 'Signed in',
    detail: 'Pixel 8 - Today, 08:02',
  ),
  ActivityItem(
    icon: OrbitIcons.deviceMobile,
    title: 'A device was added',
    detail: 'Office PC - Yesterday, 18:40',
  ),
];

/// The approve flow with its own stage, so the buttons move it on.
class _PreviewApprove extends StatefulWidget {
  const _PreviewApprove(this.stage, {this.error});

  final ApproveStage stage;
  final String? error;

  @override
  State<_PreviewApprove> createState() => _PreviewApproveState();
}

class _PreviewApproveState extends State<_PreviewApprove> {
  late var _stage = widget.stage;
  late var _error = widget.error;
  var _sent = false;

  @override
  Widget build(BuildContext context) => ApproveDeviceScreen(
    model: ApproveDeviceModel(
      stage: _stage,
      error: _error,
      checkNumber: '72 914',
      serverHost: _host,
      historySent: _sent,
    ),
    actions: ApproveDeviceActions(
      onContinue: (code) => setState(() {
        if (!code.startsWith('helix-link')) {
          _error =
              'That is not an Orbit link code. Scan the code shown on the new '
              'device, or paste it exactly.';
        } else {
          _error = null;
          _stage = ApproveStage.review;
        }
      }),
      onApprove: () => setState(() => _stage = ApproveStage.done),
      onSendHistory: () => setState(() => _sent = true),
    ),
  );
}

const _secret = 'K7QM-X2PD-9WTR-4HNB-F6CZ-JY3V';

BackupModel _backup(BackupState s) => BackupModel(
  state: s,
  progress: 0.62,
  detail: '12,480 messages · 3.1 MB, encrypted',
  failedReason: 'You were on mobile data and backups wait for Wi-Fi',
  transfersWaiting: 1,
);

const _sendingOffered = TransferItem(
  id: 'out',
  title: 'Sending your history',
  status:
      'Sent. Your other device chooses whether to add it; it shows there '
      'under Backup.',
  outgoing: true,
  buttons: ['Cancel'],
);

const _waitingReady = TransferItem(
  id: 'in',
  title: 'History from Office PC',
  status: 'Ready to receive. Nothing is downloaded until you accept.',
  buttons: ['Accept', 'Decline'],
);

final Map<String, WidgetBuilder> settingsPreviews = {
  'password': (_) => const PasswordScreen(
    model: PasswordModel(lastChangedLabel: 'Last changed 3 weeks ago'),
  ),
  'password-set': (_) =>
      const PasswordScreen(model: PasswordModel(isSet: true)),
  'password-error': (_) => const PasswordScreen(
    model: PasswordModel(
      lastChangedLabel: 'Last changed 3 weeks ago',
      initialCurrent: 'old-password',
      initialNew: 'sunrise-42',
      initialConfirm: 'sunrise-24',
      showMismatch: true,
    ),
  ),
  'password-done': (_) =>
      const PasswordScreen(model: PasswordModel(stage: PasswordStage.done)),
  'password-linked': (_) => const PasswordScreen(
    model: PasswordModel(
      lastChangedLabel: 'Last changed 3 weeks ago',
      needsPhoneNumber: true,
    ),
  ),
  'password-wrong': (_) => const PasswordScreen(
    model: PasswordModel(
      lastChangedLabel: 'Last changed 3 weeks ago',
      initialCurrent: 'not-it',
      currentError: 'That is not your current password.',
      lockout: 'Too many tries. Try again in 15 minutes.',
    ),
  ),
  'delete-account': (_) =>
      const DeleteAccountScreen(model: DeleteAccountModel()),
  'delete-account-sms': (_) => const DeleteAccountScreen(
    model: DeleteAccountModel(proof: DeleteProof.sms, phoneMasked: _masked),
  ),
  'delete-account-key': (_) => const DeleteAccountScreen(
    model: DeleteAccountModel(proof: DeleteProof.key),
  ),
  'delete-account-linked': (_) => const DeleteAccountScreen(
    model: DeleteAccountModel(needsPhoneNumber: true),
  ),
  'blocked': (_) => BlockedScreen(
    model: BlockedModel(
      people: [
        BlockedPersonItem(
          account: 'shuvo',
          name: 'Shuvo',
          avatar: OrbitFakes.people['shuvo']!.avatar,
          detail: OrbitFakes.people['shuvo']!.names.number ?? '',
        ),
      ],
    ),
  ),
  'blocked-empty': (_) => const BlockedScreen(model: BlockedModel()),
  'about': (_) => const AboutScreen(
    model: AboutModel(
      versionLabel: 'Version 2.0.0 (412)',
      serverName: 'Orbit Global',
      serverHost: _host,
      termsVersion: '3',
      privacyVersion: '4',
    ),
  ),
  'about-no-crash': (_) => const AboutScreen(
    model: AboutModel(
      versionLabel: 'Version 2.0.0 (412)',
      serverName: 'Orbit Global',
      serverHost: _host,
      termsVersion: '3',
      privacyVersion: '4',
      crashReportsAccepted: false,
    ),
  ),
  'legal': (_) => const LegalScreen(
    model: LegalModel(terms: _terms, privacy: _privacy),
  ),
  'advanced': (_) => const AdvancedScreen(
    model: AdvancedModel(
      serverName: 'Orbit Global',
      serverHost: _host,
      serverVersion: '2.0.4',
      maxAttachmentLabel: '100 MB',
      termsVersion: '3',
      privacyVersion: '4',
      features: [
        (name: 'Crash reports accepted', on: true),
        (name: 'Minimal usage counts', on: false),
        (name: 'Group calls', on: false),
      ],
    ),
  ),
  'advanced-offline': (_) => const AdvancedScreen(
    model: AdvancedModel(
      serverName: 'Orbit Global',
      serverHost: _host,
      reachable: false,
    ),
  ),
  'devices': (_) => const DeviceListScreen(
    model: DeviceListModel(devices: _devices, recent: _recent),
  ),
  'approve-device': (_) => const _PreviewApprove(ApproveStage.enter),
  'approve-device-error': (_) => const _PreviewApprove(
    ApproveStage.enter,
    error:
        'That code has expired. Codes last ten minutes. Ask the new device to '
        'show a new one.',
  ),
  'approve-device-review': (_) => const _PreviewApprove(ApproveStage.review),
  'approve-device-done': (_) => const _PreviewApprove(ApproveStage.done),
  'activity': (_) => const SecurityActivityScreen(
    model: SecurityActivityModel(
      deviceCount: 2,
      thisWeek: [
        ActivityItem(
          icon: OrbitIcons.signIn,
          title: 'Signed in',
          detail: 'Pixel 8 · Today, 08:02',
        ),
        ActivityItem(
          icon: OrbitIcons.deviceMobile,
          title: 'A device was added',
          detail: 'Office PC · Yesterday, 18:40',
        ),
      ],
      earlier: [
        ActivityItem(
          icon: OrbitIcons.password,
          title: 'Password changed',
          detail: 'Pixel 8 · 24 September',
        ),
        ActivityItem(
          icon: OrbitIcons.key,
          title: 'Your account key was reset',
          detail: 'Pixel 8 · 2 September',
          check: true,
        ),
        ActivityItem(
          icon: OrbitIcons.xCircle,
          title: 'A device was removed',
          detail: 'Old Redmi · 1 September',
        ),
      ],
    ),
  ),
  'backup': (_) => BackupScreen(model: _backup(BackupState.ok)),
  'backup-running': (_) => BackupScreen(model: _backup(BackupState.running)),
  'backup-failed': (_) => BackupScreen(model: _backup(BackupState.failed)),
  'backup-never': (_) => BackupScreen(model: _backup(BackupState.never)),
  'restore-history': (_) =>
      const RestoreScreen(model: RestoreModel(afterSignIn: false)),
  'transfer': (_) => const TransferScreen(
    model: TransferModel(sending: [_sendingOffered], waiting: [_waitingReady]),
  ),
  'transfer-empty': (_) => const TransferScreen(model: TransferModel()),
  'transfer-stopped': (_) => const TransferScreen(
    model: TransferModel(
      sending: [
        TransferItem(
          id: 'out',
          title: 'Sending your history',
          status: 'Your other device declined it.',
          outgoing: true,
          buttons: ['Dismiss'],
        ),
      ],
      waiting: [
        TransferItem(
          id: 'in',
          title: 'History from Office PC',
          status: 'Stopped: the connection dropped.',
          progress: 0.4,
          buttons: ['Resume', 'Cancel'],
        ),
      ],
    ),
  ),
  'transfer-only-device': (_) => const TransferScreen(
    model: TransferModel(
      error:
          'This is your only device. Link another device first, then send '
          'your history to it.',
    ),
  ),
  'recovery': (_) =>
      const RecoveryScreen(model: RecoveryModel(secret: _secret)),
  'recovery-restore': (_) => const RecoveryScreen(
    model: RecoveryModel(secret: _secret, initialTab: RecoveryTab.restore),
  ),
  'recovery-made': (_) =>
      const RecoveryScreen(model: RecoveryModel(secret: _secret, made: true)),
};
