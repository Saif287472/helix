import 'package:flutter/widgets.dart';
import 'package:orbit_ui/orbit_ui.dart';
import 'package:orbit_preview/theme_library.dart';

/// The You keys (`prototype/js/screens/you.js`, `topics.js`,
/// `appearance.js`) on the sample data.

const _me = HelixAvatarModel(name: OrbitFakes.meName);
const _masked = '+880 17•• ••0001';
const _server = 'Orbit Global';
const _host = 'helix.agiletechbd.com';

List<CheckupItem> _checks({required bool good}) => [
  const CheckupItem(
    key: 'backup',
    ok: true,
    icon: OrbitIcons.cloudCheck,
    title: 'Chat backup',
    okText: 'Backed up 5 hours ago',
    badText: 'No backup in the last 7 days',
    fixLabel: 'Back up',
    opens: YouTopic.backup,
  ),
  const CheckupItem(
    key: 'devices',
    ok: true,
    icon: OrbitIcons.devices,
    title: 'Linked devices',
    okText: '2 devices, both used this month',
    badText: 'A device has not been used for 30 days',
    fixLabel: 'Review',
    opens: YouTopic.devices,
  ),
  const CheckupItem(
    key: 'password',
    ok: true,
    icon: OrbitIcons.password,
    title: 'Password',
    okText: 'Set. You can sign in on a new phone',
    badText: 'No password set',
    fixLabel: 'Set one',
    opens: YouTopic.password,
  ),
  CheckupItem(
    key: 'recovery',
    ok: good,
    icon: OrbitIcons.key,
    title: 'Recovery backup',
    okText: 'Made today',
    badText: 'No recovery backup yet',
    fixLabel: 'Fix',
    opens: YouTopic.recovery,
  ),
  CheckupItem(
    key: 'lock',
    ok: good,
    icon: OrbitIcons.lockSimple,
    title: 'App lock',
    okText: 'On. Locks after 1 minute',
    badText: 'App lock is off',
    fixLabel: 'Turn on',
  ),
];

const _tiles = [
  YouTile(
    topic: YouTopic.appearance,
    icon: OrbitIcons.palette,
    colour: 6,
    title: 'Appearance',
    status: 'Orbit',
  ),
  YouTile(
    topic: YouTopic.privacy,
    icon: OrbitIcons.lockSimple,
    colour: 3,
    title: 'Privacy',
    status: 'Receipts on',
  ),
  YouTile(
    topic: YouTopic.notifications,
    icon: OrbitIcons.bell,
    colour: 4,
    title: 'Notifications',
    status: 'Sound on',
  ),
  YouTile(
    topic: YouTopic.chats,
    icon: OrbitIcons.chatCenteredText,
    colour: 1,
    title: 'Chats',
    status: 'Text default',
  ),
  YouTile(
    topic: YouTopic.devices,
    icon: OrbitIcons.devices,
    colour: 2,
    title: 'Devices',
    status: '2 linked',
  ),
  YouTile(
    topic: YouTopic.backup,
    icon: OrbitIcons.cloudArrowUp,
    colour: 0,
    title: 'Backup',
    status: '5 h ago',
  ),
];

YouModel _you({bool good = false}) => YouModel(
  name: OrbitFakes.meName,
  avatar: _me,
  about: 'Building Orbit',
  helixName: 'hasan',
  phoneMasked: _masked,
  serverName: _server,
  deviceCount: 2,
  checks: _checks(good: good),
  tiles: _tiles,
  storageLabel: '1.2 GB on this phone',
  versionLabel: '2.0.0',
  serverHost: _host,
  share: const ShareCodeModel(link: '$_host/u/hasan'),
);

/// The profile editor with the prototype's Save check: some ~names are
/// "taken".
class _PreviewProfile extends StatefulWidget {
  const _PreviewProfile({this.blank = false, this.taken = false});

  final bool blank;
  final bool taken;

  @override
  State<_PreviewProfile> createState() => _PreviewProfileState();
}

class _PreviewProfileState extends State<_PreviewProfile> {
  late var _taken = widget.taken;
  var _key = 0;

  @override
  Widget build(BuildContext context) => ProfileEditScreen(
    key: ValueKey(_key),
    model: ProfileEditModel(
      name: widget.blank ? '' : OrbitFakes.meName,
      about: widget.blank ? '' : 'Building Orbit',
      helixName: widget.blank ? '' : (widget.taken ? 'nadia' : 'hasan'),
      currentHelixName: widget.blank ? null : 'hasan',
      nameTaken: _taken,
      deviceCount: 2,
      meta: '$_masked · $_server',
    ),
    actions: ProfileEditActions(
      onSave: (name, about, helix) async {
        final bad =
            helix != 'hasan' &&
            (RegExp('admin|support|orbit|helix|official').hasMatch(helix) ||
                const ['nadia', 'arif', 'sadia'].contains(helix));
        if (!bad) return null;
        setState(() {
          _taken = true;
          _key++;
        });
        return '';
      },
    ),
  );
}

/// Appearance on the preview's own theme library.
class _PreviewAppearance extends StatelessWidget {
  const _PreviewAppearance();

  @override
  Widget build(BuildContext context) {
    final lib = OrbitThemeLibrary.loaded!;
    return AppearanceScreen(
      model: AppearanceModel(
        current: OrbitTokens.of(context),
        themes: [for (final t in lib.themes) ThemeChoice(tokens: t)],
      ),
    );
  }
}

PrivacyModel _privacy({bool lock = false, bool ask = false}) => PrivacyModel(
  meName: OrbitFakes.meName,
  meAvatar: _me,
  lockOn: lock,
  blockedCount: 1,
  blockedAvatar: OrbitFakes.people['shuvo']!.avatar,
  askNumber: ask,
);

NotificationsModel _notifications({bool off = false}) {
  final muted = OrbitFakes.chats.where((c) => c.muted).toList();
  return NotificationsModel(
    osOff: off,
    // The prototype's mock choice, kept so the `notifications` key holds.
    ringtone: 'Orbit (default)',
    muted: [
      for (final (i, c) in muted.indexed)
        MutedChatItem(
          id: c.id,
          title: c.title,
          avatar: c.avatar,
          label: i == 0 ? 'Muted for 8 hours' : 'Muted',
        ),
    ],
  );
}

StorageModel _storage() {
  const big = [
    ('group:family', 412, 380),
    ('direct:nadia', 260, 241),
    ('group:design', 198, 170),
    ('group:lunch', 64, 51),
    ('direct:arif', 38, 30),
  ];
  return StorageModel(
    totalLabel: '1.2 GB on this phone',
    splitLabel: '184 MB messages and keys · 1.0 GB media',
    downloadSummary:
        'Photos on Wi-Fi, voice always, videos and documents never',
    chats: [
      for (final (id, mb, media) in big)
        () {
          final c = OrbitFakes.chats.firstWhere((x) => x.id == id);
          return StorageChatItem(
            id: id,
            title: c.title,
            avatar: c.avatar,
            sizeLabel: '$mb MB',
            share: mb / 412,
            mediaLabel: '$media MB',
            documentsLabel: '${mb - media} MB',
          );
        }(),
    ],
  );
}

AccountModel _account({bool pass = true}) => AccountModel(
  name: OrbitFakes.meName,
  avatar: _me,
  phoneMasked: _masked,
  helixName: 'hasan',
  hasPassword: pass,
  passwordChangedLabel: 'Changed 3 weeks ago',
  deviceCount: 2,
  sinceLabel: 'Since Sep 2026',
);

final Map<String, WidgetBuilder> youPreviews = {
  'settings': (_) => YouScreen(model: _you()),
  'you-allgood': (_) => YouScreen(model: _you(good: true)),
  'you-share': (_) =>
      YouScreen(model: _you(), start: const YouStart(share: true)),
  'settings-search': (_) => YouScreen(
    model: _you(),
    start: const YouStart(query: 'pass'),
  ),
  'profile': (_) => const _PreviewProfile(),
  'profile-taken': (_) => const _PreviewProfile(taken: true),
  'profile-new': (_) => const _PreviewProfile(blank: true),
  'appearance': (_) => const _PreviewAppearance(),
  'privacy': (_) => PrivacyScreen(model: _privacy()),
  'privacy-lock': (_) => PrivacyScreen(model: _privacy(lock: true)),
  'privacy-number-needed': (_) => PrivacyScreen(model: _privacy(ask: true)),
  'notifications': (_) => NotificationsScreen(model: _notifications()),
  'notifications-off': (_) =>
      NotificationsScreen(model: _notifications(off: true)),
  'chats-settings': (_) =>
      const ChatsSettingsScreen(model: ChatsSettingsModel()),
  'storage': (_) => StorageScreen(model: _storage()),
  'account': (_) => AccountScreen(model: _account()),
  'account-nopass': (_) => AccountScreen(model: _account(pass: false)),
};
