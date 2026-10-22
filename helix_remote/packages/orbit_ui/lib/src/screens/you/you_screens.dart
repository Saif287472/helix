import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:orbit_ui/src/components/avatar.dart';
import 'package:orbit_ui/src/components/bars.dart';
import 'package:orbit_ui/src/components/button.dart';
import 'package:orbit_ui/src/components/chip_tag.dart';
import 'package:orbit_ui/src/components/codes.dart';
import 'package:orbit_ui/src/components/fields.dart';
import 'package:orbit_ui/src/components/icon_button.dart';
import 'package:orbit_ui/src/components/list_rows.dart';
import 'package:orbit_ui/src/components/overlays.dart';
import 'package:orbit_ui/src/components/page_parts.dart';
import 'package:orbit_ui/src/components/pages.dart';
import 'package:orbit_ui/src/components/state_kit.dart';
import 'package:orbit_ui/src/components/you_parts.dart';
import 'package:orbit_ui/src/icons/orbit_glyph.dart';
import 'package:orbit_ui/src/icons/orbit_icons.dart';
import 'package:orbit_ui/src/models/view_models.dart';
import 'package:orbit_ui/src/screens/signin/entry_screens.dart'
    show OrbitButtonRow;
import 'package:orbit_ui/src/theme/orbit_metrics.dart';
import 'package:orbit_ui/src/theme/orbit_text.dart';
import 'package:orbit_ui/src/theme/orbit_theme.dart';
import 'package:orbit_ui/src/theme/orbit_tokens.dart';
import 'package:orbit_ui/src/theme/pattern_painter.dart';

void _none() {}

/// Where a You tile or row goes (`contracts/you.md`).
enum YouTopic {
  appearance,
  privacy,
  notifications,
  chats,
  devices,
  backup,
  account,
  accounts,
  storage,
  about,
  advanced,
  profile,
  recovery,
  password,
  blocked,
}

// ------------------------------------------------------------ the profile

/// `profile(opts)` in `js/screens/you.js` (`.pf-orbit`): your photo is the
/// planet, a ring in the wordmark gradient circles it, and your ~name,
/// devices and encryption ride the ring as moons; under it your name, about
/// and masked number. [compact] is the profile editor's live preview.
class OrbitProfileOrbit extends StatelessWidget {
  const OrbitProfileOrbit({
    super.key,
    required this.name,
    required this.avatar,
    this.about = '',
    this.helixName,
    this.deviceCount = 1,
    this.meta = '',
    this.compact = false,
    this.onTap,
    this.onShare,
  });

  final String name;
  final HelixAvatarModel avatar;
  final String about;
  final String? helixName;
  final int deviceCount;

  /// "+880 17•• ••0001 · Orbit Global".
  final String meta;
  final bool compact;

  /// Opens the profile editor; null hides Edit profile and the QR button.
  final VoidCallback? onTap;

  /// The QR button; null hides it.
  final VoidCallback? onShare;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final planet = compact ? 76.0 : 92.0;
    final handle = (helixName ?? '').isEmpty ? 'No ~name yet' : '~$helixName';
    Widget moon(OrbitGlyph icon, String text, {bool fill = false}) => Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border.all(color: t.line),
        borderRadius: BorderRadius.circular(t.rPill),
        boxShadow: t.shadowCard,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          OrbitIcon(
            icon,
            weight: fill ? OrbitIconWeight.fill : null,
            size: 13,
            color: t.accent,
          ),
          const SizedBox(width: 5),
          Text(text, style: t.mono.style(size: 11, color: t.ink2)),
        ],
      ),
    );
    final system = SizedBox(
      height: planet + 70,
      child: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth;
          final ringW = math.min(310.0, w * 0.94);
          final ring = Size(ringW, planet * 0.92);
          return Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: Size(w, planet + 70),
                painter: _Ring(t.wordmarkGradient, ring, half: false),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  // CSS paints its first shadow on top; Flutter paints its
                  // last on top, so the page-colour ring goes last.
                  boxShadow: [
                    BoxShadow(
                      color: t.accent,
                      offset: const Offset(0, 16),
                      blurRadius: 34,
                      spreadRadius: -14,
                    ),
                    BoxShadow(color: t.bg, spreadRadius: 4),
                  ],
                ),
                child: OrbitAvatar(avatar: avatar, size: planet, round: true),
              ),
              CustomPaint(
                size: Size(w, planet + 70),
                painter: _Ring(t.wordmarkGradient, ring, half: true),
              ),
              Positioned(
                left: w * 0.01,
                top: (planet + 70) * 0.58,
                child: moon(OrbitIcons.at, handle),
              ),
              Positioned(
                right: w * 0.01,
                top: (planet + 70) * 0.13,
                child: moon(
                  OrbitIcons.devices,
                  deviceCount == 1 ? '1 device' : '$deviceCount devices',
                ),
              ),
              Positioned(
                right: w * 0.17,
                bottom: (planet + 70) * 0.03,
                child: moon(OrbitIcons.lockSimple, 'E2E', fill: true),
              ),
            ],
          );
        },
      ),
    );
    final body = Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        children: [
          system,
          OrbitText(
            name.isEmpty ? 'Add your name' : name,
            textAlign: TextAlign.center,
            style: t.display(size: 24, height: 1.15),
          ),
          if (about.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: OrbitText(
                about,
                textAlign: TextAlign.center,
                style: t.font.style(size: 14, color: t.ink2),
              ),
            ),
          if (meta.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: OrbitText(
                meta,
                textAlign: TextAlign.center,
                style: t.mono.style(
                  size: 11,
                  color: t.ink3,
                  letterSpacingEm: 0.04,
                ),
              ),
            ),
          if (onTap != null)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: t.surface,
                      border: Border.all(color: t.line),
                      borderRadius: BorderRadius.circular(t.rPill),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        OrbitIcon(
                          OrbitIcons.pencilSimple,
                          size: 15,
                          color: t.accentInk,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Edit profile',
                          style: t.font.style(
                            size: 13.5,
                            weight: 600,
                            color: t.accentInk,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (onShare != null) ...[
                    const SizedBox(width: 8),
                    Tooltip(
                      message: 'Share your Orbit code',
                      excludeFromSemantics: true,
                      child: Semantics(
                        button: true,
                        label: 'Share your Orbit code',
                        child: GestureDetector(
                          onTap: onShare,
                          child: Container(
                            width: OrbitSpace.target,
                            height: OrbitSpace.target,
                            decoration: BoxDecoration(
                              color: t.surface,
                              border: Border.all(color: t.line),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: OrbitIcon(
                                OrbitIcons.qrCode,
                                size: 20,
                                color: t.ink2,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
    if (onTap == null) return body;
    return Semantics(
      button: true,
      label: 'Edit your profile',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: body,
      ),
    );
  }
}

/// `.pfo-ring`: a 1.5px ellipse in the wordmark gradient, tipped -11°. The
/// back copy is at 45% behind the planet; the front copy, only its lower
/// half (`clip-path: inset(50% 0 0 0)` before the turn), goes over it.
class _Ring extends CustomPainter {
  const _Ring(this.gradient, this.ring, {required this.half});

  final Gradient gradient;
  final Size ring;
  final bool half;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCenter(
      center: Offset.zero,
      width: ring.width,
      height: ring.height,
    );
    canvas
      ..save()
      ..translate(size.width / 2, size.height / 2)
      ..rotate(-11 * math.pi / 180);
    if (half) {
      canvas.clipRect(
        Rect.fromLTRB(rect.left - 2, 0, rect.right + 2, rect.bottom + 2),
      );
    }
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..shader = gradient.createShader(rect);
    if (!half) {
      canvas.saveLayer(
        rect.inflate(2),
        Paint()..color = const Color(0x73000000),
      );
    }
    canvas.drawOval(rect.deflate(0.75), paint);
    if (!half) canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(_Ring old) =>
      old.gradient != gradient || old.ring != ring || old.half != half;
}

// ---------------------------------------------------------- the checkup

class CheckupItem {
  const CheckupItem({
    required this.key,
    required this.ok,
    required this.icon,
    required this.title,
    required this.okText,
    required this.badText,
    required this.fixLabel,
    this.opens,
  });

  final String key;
  final bool ok;
  final OrbitGlyph icon;
  final String title;
  final String okText;
  final String badText;
  final String fixLabel;

  /// The page a passing check opens.
  final YouTopic? opens;
}

/// `.checkup`: the privacy checkup card. A head with the score, a bar, and
/// only what needs attention (or every check, in the sheet).
class _Checkup extends StatelessWidget {
  const _Checkup({
    required this.checks,
    required this.showAll,
    required this.onFix,
    required this.onOpen,
    this.onSeeAll,
    this.margin = const EdgeInsets.fromLTRB(
      OrbitSpace.gutter,
      14,
      OrbitSpace.gutter,
      0,
    ),
  });

  final List<CheckupItem> checks;
  final bool showAll;
  final ValueChanged<String> onFix;
  final ValueChanged<YouTopic> onOpen;
  final VoidCallback? onSeeAll;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final ok = checks.where((c) => c.ok).length;
    final bad = checks.where((c) => !c.ok).toList();
    final good = bad.isEmpty && !showAll;
    final items = showAll ? checks : bad;
    return Container(
      margin: margin,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border.all(color: t.line),
        borderRadius: BorderRadius.circular(t.rLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              OrbitIcon(
                bad.isEmpty ? OrbitIcons.shieldCheck : OrbitIcons.shieldWarning,
                weight: OrbitIconWeight.fill,
                size: 19,
                color: good ? t.success : t.warning,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: OrbitText('Privacy checkup', style: t.display(size: 15)),
              ),
              Text(
                '$ok of ${checks.length}',
                style: t.mono.style(size: 12, color: t.ink3),
              ),
            ],
          ),
          Container(
            height: 5,
            margin: const EdgeInsets.only(top: 10, bottom: 6),
            decoration: BoxDecoration(
              color: t.line,
              borderRadius: BorderRadius.circular(5),
            ),
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: checks.isEmpty ? 0 : ok / checks.length,
              child: Container(
                decoration: BoxDecoration(
                  color: t.success,
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
            ),
          ),
          if (good)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: OrbitText(
                'Everything that keeps your account safe is in place.',
                style: t.font.style(size: 13, color: t.ink3, height: 1.45),
              ),
            )
          else
            for (final c in items) _item(t, c),
          if (!showAll)
            Align(
              alignment: Alignment.centerLeft,
              child: OrbitTapArea(
                child: GestureDetector(
                  onTap: onSeeAll,
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 40),
                    padding: const EdgeInsets.only(top: 10, bottom: 6),
                    child: Text(
                      good
                          ? 'See all checks'
                          : 'See all ${checks.length} checks',
                      style: t.font.style(
                        size: 13,
                        weight: 600,
                        color: t.accentInk,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// `.ck-item`: every one has a `--line-2` rule above it (the head and the
  /// bar are its `div` siblings, so `:first-of-type` never matches it).
  Widget _item(OrbitTokens t, CheckupItem c) => Container(
    constraints: const BoxConstraints(minHeight: 52),
    decoration: BoxDecoration(
      border: Border(top: BorderSide(color: t.line2)),
    ),
    child: Row(
      children: [
        OrbitIcon(
          c.ok ? OrbitIcons.checkCircle : OrbitIcons.warningCircle,
          weight: OrbitIconWeight.fill,
          size: 20,
          color: c.ok ? t.success : t.warning,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              OrbitText(
                c.ok ? c.title : c.badText,
                style: t.font.style(size: 14, weight: 560, color: t.ink),
              ),
              if (c.ok)
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: OrbitText(
                    c.okText,
                    style: t.font.style(size: 12, color: t.ink3),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        if (c.ok && c.opens != null)
          OrbitIconButton(
            icon: OrbitIcons.caretRight,
            tooltip: 'Open ${c.title}',
            small: true,
            onPressed: () => onOpen(c.opens!),
          )
        else if (!c.ok)
          OrbitButton(
            label: c.fixLabel,
            kind: c.key == 'lock'
                ? OrbitButtonKind.primary
                : OrbitButtonKind.secondary,
            height: 36,
            padding: 14,
            fontSize: 13,
            onPressed: () => onFix(c.key),
          ),
      ],
    ),
  );
}

// --------------------------------------------------------------- You page

/// A tile on the You page: its topic, look and live status.
class YouTile {
  const YouTile({
    required this.topic,
    required this.icon,
    required this.colour,
    required this.title,
    required this.status,
  });

  final YouTopic topic;
  final OrbitGlyph icon;
  final int colour;
  final String title;
  final String status;
}

/// What the share sheet shows: your code and link.
///
/// [qr] is the real matrix of [link], when the app can encode one. Without it
/// the sheet draws the prototype's pattern for [qrSeed], which is only ever
/// what the design preview shows.
class ShareCodeModel {
  const ShareCodeModel({
    required this.link,
    this.qrSeed = 'my-helix-code',
    this.qr,
  });

  final String link;
  final String qrSeed;
  final HelixQrMatrix? qr;
}

class YouModel {
  const YouModel({
    required this.name,
    required this.avatar,
    this.about = '',
    this.helixName,
    this.phoneMasked,
    this.serverName = '',
    this.deviceCount = 1,
    this.checks = const [],
    this.tiles = const [],
    this.storageLabel = '',
    this.versionLabel = '',
    this.serverHost = '',
    this.unlockWhat = 'your fingerprint, face or phone PIN',
    this.share,
  });

  final String name;
  final HelixAvatarModel avatar;
  final String about;
  final String? helixName;
  final String? phoneMasked;
  final String serverName;
  final int deviceCount;
  final List<CheckupItem> checks;
  final List<YouTile> tiles;
  final String storageLabel;

  /// "2.0.0".
  final String versionLabel;
  final String serverHost;

  /// "Windows Hello" on a window; the phone's own lock otherwise.
  final String unlockWhat;
  final ShareCodeModel? share;
}

class YouActions {
  const YouActions({
    this.openProfile,
    this.openTopic,
    this.fixRecovery,
    this.turnOnAppLock,
    this.copyShareLink,
    this.shareLink,
    this.scanCode,
    this.onBack,
  });

  final VoidCallback? openProfile;
  final ValueChanged<YouTopic>? openTopic;
  final VoidCallback? fixRecovery;

  /// After "Turn on app lock?": the phone's own unlock follows. Answers a
  /// sentence when the lock could not be turned on, which the page toasts.
  final Future<String?> Function()? turnOnAppLock;
  final VoidCallback? copyShareLink;
  final VoidCallback? shareLink;
  final VoidCallback? scanCode;
  final VoidCallback? onBack;
}

/// Preview start states for the You page.
class YouStart {
  const YouStart({this.query, this.share = false});

  /// Opens the search with this text.
  final String? query;

  /// Opens the share sheet.
  final bool share;
}

/// `settings-page` ("You"): your profile as an orbit, the privacy checkup,
/// the topic tiles, the other rows, and the version. ⌕ searches settings.
class YouScreen extends StatefulWidget {
  const YouScreen({
    super.key,
    required this.model,
    this.actions = const YouActions(),
    this.start = const YouStart(),
  });

  final YouModel model;
  final YouActions actions;
  final YouStart start;

  @override
  State<YouScreen> createState() => _YouScreenState();
}

class _YouScreenState extends State<YouScreen> {
  late bool _searching = widget.start.query != null;
  late final _q = TextEditingController(text: widget.start.query ?? '');

  YouModel get _m => widget.model;
  YouActions get _a => widget.actions;

  @override
  void initState() {
    super.initState();
    if (widget.start.share) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _shareSheet();
      });
    }
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  List<(YouTopic, OrbitGlyph, int, String, String)> get _rows => [
    (
      YouTopic.account,
      OrbitIcons.userCircle,
      7,
      'Account',
      'Number, password, sign out, delete',
    ),
    (
      YouTopic.accounts,
      OrbitIcons.usersThree,
      2,
      'Accounts',
      'Switch, add or remove accounts on this phone',
    ),
    (
      YouTopic.storage,
      OrbitIcons.database,
      6,
      'Storage and data',
      _m.storageLabel,
    ),
    (
      YouTopic.about,
      OrbitIcons.question,
      5,
      'Help and about',
      'Version, terms, privacy policy',
    ),
    (
      YouTopic.advanced,
      OrbitIcons.wrench,
      7,
      'Advanced',
      'Server details and connection',
    ),
  ];

  List<(YouTopic, OrbitGlyph, int, String, String)> get _searchable => [
    for (final t in _m.tiles) (t.topic, t.icon, t.colour, t.title, t.status),
    ..._rows,
    (
      YouTopic.profile,
      OrbitIcons.identificationCard,
      0,
      'Edit profile',
      'Name, about, photo, ~name',
    ),
    (
      YouTopic.recovery,
      OrbitIcons.key,
      4,
      'Recovery backup',
      'A backup only your secret opens',
    ),
    (
      YouTopic.password,
      OrbitIcons.password,
      0,
      'Change password',
      'Sign in on a new phone',
    ),
    (
      YouTopic.blocked,
      OrbitIcons.prohibit,
      7,
      'Blocked',
      'People who cannot reach you',
    ),
  ];

  void _open(YouTopic t) => _a.openTopic?.call(t);

  void _fix(String key) {
    if (key == 'recovery') {
      _a.fixRecovery?.call();
    } else if (key == 'lock') {
      showOrbitDialog(
        context,
        title: 'Turn on app lock?',
        text:
            'Orbit will ask for ${_m.unlockWhat} when you open it. Calls still '
            'ring while it is locked.',
        actions: [
          const OrbitDialogAction('Cancel'),
          OrbitDialogAction(
            'Turn on',
            kind: OrbitButtonKind.primary,
            onPressed: _turnOnLock,
          ),
        ],
      );
    } else {
      // The other checks are fixed on their own page.
      final opens = _m.checks.where((c) => c.key == key).firstOrNull?.opens;
      if (opens != null) _open(opens);
    }
  }

  Future<void> _turnOnLock() async {
    final refused = await _a.turnOnAppLock?.call();
    if (refused != null && mounted) {
      showOrbitToast(context, refused, error: true);
    }
  }

  void _allChecks() => showOrbitSheet(
    context,
    title: 'Privacy checkup',
    text:
        'What keeps your account and your messages safe, and what still '
        'needs a moment.',
    body: Builder(
      builder: (sheet) => Padding(
        padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
        child: _Checkup(
          checks: _m.checks,
          showAll: true,
          margin: EdgeInsets.zero,
          onFix: (k) {
            Navigator.maybePop(sheet);
            _fix(k);
          },
          onOpen: (t) {
            Navigator.maybePop(sheet);
            _open(t);
          },
        ),
      ),
    ),
  );

  void _shareSheet() {
    final share = _m.share;
    if (share == null) return;
    showOrbitSheet(
      context,
      body: Builder(
        builder: (sheet) => _ShareSheet(
          model: _m,
          share: share,
          actions: _a,
          close: () => Navigator.maybePop(sheet),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    if (_searching) return _search(t);
    final m = _m;
    final meta = [
      if ((m.phoneMasked ?? '').isNotEmpty) m.phoneMasked!,
      if (m.serverName.isNotEmpty) m.serverName,
    ].join(' · ');
    return OrbitYouPage(
      title: 'You',
      onBack: _a.onBack,
      actions: [
        OrbitIconButton(
          icon: OrbitIcons.magnifyingGlass,
          tooltip: 'Search settings',
          onPressed: () => setState(() => _searching = true),
        ),
      ],
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            OrbitSpace.gutter,
            6,
            OrbitSpace.gutter,
            0,
          ),
          child: OrbitProfileOrbit(
            name: m.name,
            avatar: m.avatar,
            about: m.about,
            helixName: m.helixName,
            deviceCount: m.deviceCount,
            meta: meta,
            onTap: _a.openProfile ?? _none,
            onShare: m.share == null ? null : _shareSheet,
          ),
        ),
        _Checkup(
          checks: m.checks,
          showAll: false,
          onFix: _fix,
          onOpen: _open,
          onSeeAll: _allChecks,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            OrbitSpace.gutter,
            14,
            OrbitSpace.gutter,
            0,
          ),
          child: OrbitTileGrid(
            tiles: [
              for (final tile in m.tiles)
                OrbitTopicTile(
                  icon: tile.icon,
                  colour: tile.colour,
                  title: tile.title,
                  status: tile.status,
                  onTap: () => _open(tile.topic),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        OrbitCard(
          children: [
            for (final (topic, icon, colour, title, sub) in _rows)
              OrbitListRow(
                icon: icon,
                iconColor: colour,
                title: title,
                sub: sub,
                end: OrbitRowEnd.chevron,
                onTap: () => _open(topic),
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 22),
          child: OrbitText(
            'Orbit ${m.versionLabel} · ${m.serverHost}',
            textAlign: TextAlign.center,
            style: t.mono.style(size: 11, color: t.ink3),
          ),
        ),
      ],
    );
  }

  Widget _search(OrbitTokens t) {
    final top = MediaQuery.paddingOf(context).top;
    final q = _q.text.trim().toLowerCase();
    final hits = [
      for (final h in _searchable)
        if (q.isNotEmpty && '${h.$4} ${h.$5}'.toLowerCase().contains(q)) h,
    ];
    final Widget body;
    if (q.isEmpty) {
      body = ListView(
        children: const [
          OrbitEmptyState(
            icon: OrbitIcons.magnifyingGlass,
            title: 'Search settings',
            text: 'Try “receipts”, “backup” or “password”.',
          ),
        ],
      );
    } else if (hits.isEmpty) {
      body = ListView(
        children: [
          OrbitEmptyState(
            icon: OrbitIcons.magnifyingGlassMinus,
            title: 'No settings match “${_q.text.trim()}”',
            text: 'Try a different word.',
          ),
        ],
      );
    } else {
      body = ListView(
        padding: const EdgeInsets.only(top: 12),
        children: [
          OrbitCard(
            children: [
              for (final (topic, icon, colour, title, sub) in hits)
                OrbitListRow(
                  icon: icon,
                  iconColor: colour,
                  title: title,
                  sub: sub,
                  end: OrbitRowEnd.chevron,
                  onTap: () => _open(topic),
                ),
            ],
          ),
        ],
      );
    }
    return OrbitPageBackground(
      child: Padding(
        padding: EdgeInsets.only(top: top),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OrbitAppBar(
              leadTooltip: 'Close search',
              onLead: () => setState(() {
                _searching = false;
                _q.clear();
              }),
              titleWidget: SizedBox(
                height: 44,
                child: OrbitSearchField(
                  hint: 'Search settings',
                  controller: _q,
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}

/// `.stiles`: two columns of topic tiles, 10px apart.
class OrbitTileGrid extends StatelessWidget {
  const OrbitTileGrid({super.key, required this.tiles});

  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (var i = 0; i < tiles.length; i += 2) ...[
        if (i > 0) const SizedBox(height: 10),
        // Both tiles of a row are built alike, so they are the same height
        // without stretching them (an intrinsic pass would round the text
        // differently from the real one).
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: tiles[i]),
            const SizedBox(width: 10),
            Expanded(
              child: i + 1 < tiles.length ? tiles[i + 1] : const SizedBox(),
            ),
          ],
        ),
      ],
    ],
  );
}

/// `.stile`: at least 104px, 14px in, corner `--r-lg` on `--surface`; a
/// 36px icon tile, the title (display face, 15px) and the status in mono.
class OrbitTopicTile extends StatelessWidget {
  const OrbitTopicTile({
    super.key,
    required this.icon,
    required this.colour,
    required this.title,
    required this.status,
    this.onTap,
  });

  final OrbitGlyph icon;
  final int colour;
  final String title;
  final String status;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final (bg, ink) = OrbitAvatar.palette(t, colour);
    final shape = RoundedRectangleBorder(
      side: BorderSide(color: t.line),
      borderRadius: BorderRadius.circular(t.rLg),
    );
    return Material(
      color: t.surface,
      shape: shape,
      child: InkWell(
        onTap: onTap,
        customBorder: shape,
        hoverColor: Colors.transparent,
        splashFactory: NoSplash.splashFactory,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 104),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Center(child: OrbitIcon(icon, size: 19, color: ink)),
                ),
                const SizedBox(height: 10),
                OrbitText(title, style: t.display(size: 15)),
                const SizedBox(height: 4),
                OrbitText(status, style: t.mono.style(size: 11, color: t.ink3)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The share sheet: the small orbit, your QR code and link, Copy and Share,
/// and Scan someone's code.
class _ShareSheet extends StatelessWidget {
  const _ShareSheet({
    required this.model,
    required this.share,
    required this.actions,
    required this.close,
  });

  final YouModel model;
  final ShareCodeModel share;
  final YouActions actions;
  final VoidCallback close;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    VoidCallback then(VoidCallback? run) => () {
      close();
      run?.call();
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              OrbitSpace.gutter,
              4,
              OrbitSpace.gutter,
              0,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 96,
                  height: 60,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CustomPaint(
                        size: const Size(96, 60),
                        painter: _Ring(
                          t.wordmarkGradient,
                          const Size(92, 44 * 0.92),
                          half: false,
                        ),
                      ),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(color: t.surface, spreadRadius: 3),
                          ],
                        ),
                        child: OrbitAvatar(
                          avatar: model.avatar,
                          size: 44,
                          round: true,
                        ),
                      ),
                      CustomPaint(
                        size: const Size(96, 60),
                        painter: _Ring(
                          t.wordmarkGradient,
                          const Size(92, 44 * 0.92),
                          half: true,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    OrbitText(model.name, style: t.display(size: 18)),
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: OrbitText(
                        '~${model.helixName ?? ''}',
                        style: t.mono.style(size: 12, color: t.ink3),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 20, bottom: 6),
            child: Center(
              child: OrbitQrCard(
                child: OrbitQr(seed: share.qrSeed, matrix: share.qr),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
            child: OrbitText(
              'Anyone who scans this can message you. Your number stays '
              'hidden.',
              textAlign: TextAlign.center,
              style: t.font.style(
                size: OrbitType.caption,
                color: t.ink3,
                height: 1.5,
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.fromLTRB(
              OrbitSpace.gutter,
              14,
              OrbitSpace.gutter,
              0,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: t.field,
              borderRadius: BorderRadius.circular(10),
            ),
            child: OrbitText(
              share.link,
              textAlign: TextAlign.center,
              style: t.mono.style(size: 12, color: t.ink),
            ),
          ),
          OrbitButtonRow(
            children: [
              OrbitButton(
                label: 'Copy link',
                icon: OrbitIcons.copy,
                kind: OrbitButtonKind.secondary,
                onPressed: then(actions.copyShareLink),
              ),
              OrbitButton(
                label: 'Share',
                icon: OrbitIcons.shareNetwork,
                onPressed: then(actions.shareLink),
              ),
            ],
          ),
          OrbitButtonRow(
            top: 8,
            children: [
              OrbitButton(
                label: 'Scan someone’s code',
                icon: OrbitIcons.scan,
                kind: OrbitButtonKind.ghost,
                block: true,
                onPressed: then(actions.scanCode),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------- edit profile

/// Whether a ~name follows the rules (`nameState` in the prototype). Null
/// for an empty one; whether it is free is the server's answer on Save.
(bool ok, String text)? orbitNameState(String value, {String? current}) {
  final n = value.replaceFirst(RegExp('^~'), '').trim().toLowerCase();
  if (n.isEmpty) return null;
  if (n == current) return (true, 'This is your ~name');
  if (n.length < 3) return (false, 'Names are at least 3 characters.');
  if (!RegExp('^[a-z]').hasMatch(n)) {
    return (false, 'Names start with a letter.');
  }
  if (!RegExp(r'^[a-z0-9._]+$').hasMatch(n)) {
    return (false, 'Use only letters, numbers, dots and underscores.');
  }
  return (true, '~$n looks good. Orbit checks that it is free when you save.');
}

/// Whether the saved profile has come.
enum ProfileEditStatus { loading, failed, ready }

class ProfileEditModel {
  const ProfileEditModel({
    this.status = ProfileEditStatus.ready,
    this.name = '',
    this.about = '',
    this.helixName = '',
    this.currentHelixName,
    this.photo,
    this.avatarColor = 0,
    this.canPickPhoto = true,
    this.nameTaken = false,
    this.nameError,
    this.aboutError,
    this.helixNameError,
    this.findableByName = true,
    this.deviceCount = 1,
    this.meta = '',
    this.saving = false,
  });

  final ProfileEditStatus status;

  /// What is saved: the fields start from it once.
  final String name;
  final String about;
  final String helixName;

  /// The ~name you have now.
  final String? currentHelixName;
  final ImageProvider? photo;

  /// [HelixAvatarModel.colorIndex] for the preview without a photo.
  final int avatarColor;

  /// False where the platform cannot pick a picture: no photo buttons.
  final bool canPickPhoto;

  /// The server refused the ~name on Save (the preview's sample).
  final bool nameTaken;

  /// Why Save did not take a field, under it ([helixNameError] is the
  /// server's refusal when it has one).
  final String? nameError;
  final String? aboutError;
  final String? helixNameError;

  /// "Find me by ~name" is on: the ~name row says anyone can look it up.
  final bool findableByName;
  final int deviceCount;
  final String meta;
  final bool saving;
}

class ProfileEditActions {
  const ProfileEditActions({
    this.onSave,
    this.onChoosePhoto,
    this.onRemovePhoto,
    this.onRemoveHelixName,
    this.onRetry,
  });

  /// Saves the three fields. Null when everything was saved: the page says
  /// "Profile saved" and closes. Otherwise a sentence to toast (empty when
  /// the reason is under a field).
  final Future<String?> Function(String name, String about, String helixName)?
  onSave;

  /// The answer to toast ("Photo updated.", a failure); null says nothing.
  final Future<String?> Function()? onChoosePhoto;
  final Future<String?> Function()? onRemovePhoto;

  /// Null when the ~name was removed; else why not.
  final Future<String?> Function()? onRemoveHelixName;
  final VoidCallback? onRetry;
}

/// `profile`: a live preview of your orbit as you type, the photo, Name,
/// About and ~Orbit name, who sees what, and Remove my ~name.
class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({
    super.key,
    required this.model,
    this.actions = const ProfileEditActions(),
  });

  final ProfileEditModel model;
  final ProfileEditActions actions;

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  late final _name = TextEditingController(text: widget.model.name);
  late final _about = TextEditingController(text: widget.model.about);
  late final _helix = TextEditingController(text: widget.model.helixName);
  late var _taken = widget.model.nameTaken;

  /// The server's refusal of the ~name, until the field changes.
  late String? _helixRefusal = widget.model.helixNameError;

  @override
  void didUpdateWidget(ProfileEditScreen old) {
    super.didUpdateWidget(old);
    final m = widget.model;
    // The fields start from the saved profile once, when it arrives.
    if (old.model.status != ProfileEditStatus.ready &&
        m.status == ProfileEditStatus.ready) {
      _name.text = m.name;
      _about.text = m.about;
      _helix.text = m.helixName;
    }
    if (m.helixNameError != old.model.helixNameError) {
      _helixRefusal = m.helixNameError;
    }
  }

  Future<void> _say(Future<String?> Function()? action) async {
    final said = await action?.call();
    if (said != null && said.isNotEmpty && mounted) {
      showOrbitToast(context, said);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _about.dispose();
    _helix.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final ns = orbitNameState(
      _helix.text,
      current: widget.model.currentHelixName,
    );
    if (ns != null && !ns.$1) {
      showOrbitToast(context, 'Fix your ~name first');
      return;
    }
    if (_name.text.trim().isEmpty) {
      showOrbitToast(context, 'Enter the name people should see.');
      return;
    }
    final save = widget.actions.onSave;
    if (save == null) return;
    final said = await save(
      _name.text.trim(),
      _about.text.trim(),
      _helix.text.replaceFirst(RegExp('^~'), '').trim().toLowerCase(),
    );
    if (!mounted) return;
    if (said == null) {
      showOrbitToast(context, 'Profile saved');
      Navigator.maybePop(context);
    } else if (said.isNotEmpty) {
      showOrbitToast(context, said, error: true);
    }
  }

  Future<void> _removeHelixName() async {
    final remove = widget.actions.onRemoveHelixName;
    final refused = remove == null ? null : await remove();
    if (!mounted) return;
    if (refused == null) {
      setState(_helix.clear);
      if (remove != null) showOrbitToast(context, 'Your ~name is removed.');
    } else {
      showOrbitToast(context, refused, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final m = widget.model;
    final a = widget.actions;
    final ns = orbitNameState(_helix.text, current: m.currentHelixName);
    final shownHandle = ns != null && ns.$1
        ? _helix.text.replaceFirst(RegExp('^~'), '').toLowerCase()
        : m.currentHelixName ?? '';
    final hasPhoto = m.photo != null;
    final top = MediaQuery.paddingOf(context).top;
    if (m.status != ProfileEditStatus.ready) {
      return OrbitPageBackground(
        child: Padding(
          padding: EdgeInsets.only(top: top),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OrbitAppBar(
                title: 'Edit profile',
                onLead: () => Navigator.maybePop(context),
              ),
              if (m.status == ProfileEditStatus.loading) ...const [
                SizedBox(height: 120),
                OrbitPageLoading(),
              ] else
                OrbitLoadFailed(
                  title: 'Your profile could not be loaded.',
                  onRetry: a.onRetry,
                ),
            ],
          ),
        ),
      );
    }
    final helixError = ns != null && !ns.$1
        ? ns.$2
        : _helixRefusal ??
              (_taken
                  ? 'That name is not available. It may already be taken, or '
                        'it may be one that could be mistaken for Orbit staff. '
                        'Try another.'
                  : '');
    Widget vis(OrbitGlyph icon, String what, String who, Widget tag) =>
        OrbitListRow(
          leading: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: t.field,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Center(child: OrbitIcon(icon, size: 19, color: t.ink2)),
          ),
          title: what,
          titleWidget: OrbitText(
            what,
            style: t.font.style(size: 14, weight: 520, color: t.ink),
          ),
          sub: who,
          trailing: tag,
          minHeight: 52,
        );
    return OrbitPageBackground(
      child: Padding(
        padding: EdgeInsets.only(top: top),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OrbitAppBar(
              title: 'Edit profile',
              onLead: () => Navigator.maybePop(context),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: OrbitButton(
                    label: 'Save',
                    kind: OrbitButtonKind.ghost,
                    busy: m.saving,
                    onPressed: _save,
                  ),
                ),
              ],
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 36),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      OrbitSpace.gutter,
                      10,
                      OrbitSpace.gutter,
                      6,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // The eyebrow is inline in a body-text line box, so
                        // it sits lower and the line is taller than itself.
                        const Padding(
                          padding: EdgeInsets.only(left: 4, top: 4),
                          child: OrbitEyebrow('Live preview'),
                        ),
                        const SizedBox(height: 10),
                        OrbitProfileOrbit(
                          compact: true,
                          name: _name.text,
                          about: _about.text,
                          helixName: shownHandle,
                          deviceCount: m.deviceCount,
                          meta: m.meta,
                          avatar: HelixAvatarModel(
                            name: _name.text.isEmpty ? 'You' : _name.text,
                            image: m.photo,
                            colorIndex: m.avatarColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (m.canPickPhoto)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        OrbitSpace.gutter,
                        4,
                        OrbitSpace.gutter,
                        0,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: OrbitButton(
                              label: hasPhoto
                                  ? 'Change photo'
                                  : 'Choose a photo',
                              icon: OrbitIcons.image,
                              kind: OrbitButtonKind.secondary,
                              block: true,
                              onPressed: m.saving
                                  ? null
                                  : () => _say(a.onChoosePhoto),
                            ),
                          ),
                          if (hasPhoto) ...[
                            const SizedBox(width: 8),
                            OrbitButton(
                              label: 'Remove',
                              kind: OrbitButtonKind.ghost,
                              tint: t.danger,
                              onPressed: m.saving
                                  ? null
                                  : () => _say(a.onRemovePhoto),
                            ),
                          ],
                        ],
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      OrbitSpace.gutter,
                      18,
                      OrbitSpace.gutter,
                      0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        OrbitTextField(
                          label: 'Name',
                          controller: _name,
                          maxLength: 50,
                          counter: true,
                          hint: 'How people see you',
                          error: m.nameError ?? '',
                          onChanged: (_) => setState(() {}),
                        ),
                        OrbitTextField(
                          label: 'About',
                          controller: _about,
                          maxLength: 139,
                          counter: true,
                          hint: 'A line about you',
                          error: m.aboutError ?? '',
                          onChanged: (_) => setState(() {}),
                        ),
                        OrbitTextField(
                          label: '~Orbit name',
                          controller: _helix,
                          prefix: '~',
                          mono: true,
                          hint: 'anna.k',
                          error: helixError,
                          helper: ns != null && ns.$1 && helixError.isEmpty
                              ? ns.$2
                              : '3 to 32 letters, numbers, dots or '
                                    'underscores, starting with a letter.',
                          helperOk: ns != null && ns.$1 && helixError.isEmpty,
                          onChanged: (_) => setState(() {
                            _taken = false;
                            _helixRefusal = null;
                          }),
                        ),
                      ],
                    ),
                  ),
                  const OrbitGroupTitle('Who sees what'),
                  OrbitCard(
                    children: [
                      vis(
                        OrbitIcons.user,
                        'Name',
                        'People you message, and Orbit’s operator',
                        const OrbitTag(label: 'Operator sees it'),
                      ),
                      vis(
                        OrbitIcons.image,
                        'About and photo',
                        'Only people you message',
                        const OrbitTag(
                          label: 'Encrypted',
                          tone: OrbitTagTone.success,
                          icon: OrbitIcons.lockSimple,
                        ),
                      ),
                      if (m.findableByName)
                        vis(
                          OrbitIcons.at,
                          '~Orbit name',
                          'Anyone can look it up to message you',
                          const OrbitTag(label: 'Public'),
                        )
                      else
                        vis(
                          OrbitIcons.at,
                          '~Orbit name',
                          'Nobody can look it up while “Find me by ~name” is '
                              'off',
                          const OrbitTag(
                            label: 'Hidden',
                            tone: OrbitTagTone.accent,
                          ),
                        ),
                      vis(
                        OrbitIcons.phone,
                        'Phone number',
                        'Hidden from people. Orbit’s operator can see it',
                        const OrbitTag(
                          label: 'Hidden',
                          tone: OrbitTagTone.accent,
                        ),
                      ),
                    ],
                  ),
                  if (_helix.text.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    OrbitCard(
                      children: [
                        OrbitListRow(
                          icon: OrbitIcons.trash,
                          title: 'Remove my ~name',
                          sub: 'People can still message you by number',
                          danger: true,
                          onTap: () => showOrbitDialog(
                            context,
                            title: 'Remove your ~name?',
                            text:
                                'People will no longer find you by '
                                '~${_helix.text}. Someone else may claim it.',
                            actions: [
                              const OrbitDialogAction('Cancel'),
                              OrbitDialogAction(
                                'Remove',
                                kind: OrbitButtonKind.danger,
                                onPressed: _removeHelixName,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --------------------------------------------------------------- Appearance

/// One theme to pick: its tokens draw its own card.
class ThemeChoice {
  const ThemeChoice({required this.tokens});

  final OrbitTokens tokens;
}

class AppearanceModel {
  const AppearanceModel({required this.current, required this.themes});

  final OrbitTokens current;
  final List<ThemeChoice> themes;
}

class AppearanceActions {
  const AppearanceActions({this.onPick});

  /// Draws the app in this theme from now on; the page then says
  /// "Orbit Night theme on".
  final Future<void> Function(String id)? onPick;
}

/// `appearance`: the current theme, then a card per theme drawn in that
/// theme (a mini chat), light ones then dark ones.
class AppearanceScreen extends StatelessWidget {
  const AppearanceScreen({
    super.key,
    required this.model,
    this.actions = const AppearanceActions(),
  });

  final AppearanceModel model;
  final AppearanceActions actions;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final cur = model.current.meta;
    Widget grid(bool dark) {
      final list = [
        for (final c in model.themes)
          if (c.tokens.meta.dark == dark) c,
      ];
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: OrbitSpace.gutter),
        child: OrbitTileGrid(
          tiles: [
            for (final c in list)
              _ThemeCard(
                tokens: c.tokens,
                on: c.tokens.meta.id == cur.id,
                onTap: c.tokens.meta.id == cur.id
                    ? null
                    : () async {
                        final pick = actions.onPick;
                        if (pick == null) return;
                        await pick(c.tokens.meta.id);
                        if (context.mounted) {
                          showOrbitToast(
                            context,
                            '${c.tokens.meta.name} theme on',
                          );
                        }
                      },
              ),
          ],
        ),
      );
    }

    return OrbitYouPage(
      title: 'Appearance',
      children: [
        OrbitHeroCard(
          icon: OrbitIcons.palette,
          title: cur.name,
          sub: '${cur.vibe} · ${cur.dark ? 'dark' : 'light'}',
          slot: Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Row(
              children: [
                for (final s in cur.swatches) ...[
                  Container(
                    width: 22,
                    height: 22,
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                      color: s,
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(color: const Color(0x1F000000)),
                    ),
                  ),
                ],
                // `margin-left: auto`: the pill sits at the end, and wraps
                // under rather than overflowing when the text is large.
                const Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: OrbitPills(
                      pills: [
                        OrbitHeroPill(
                          icon: OrbitIcons.lockSimple,
                          text: 'Stays until you change it',
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const OrbitGroupTitle('Light'),
        grid(false),
        const OrbitGroupTitle('Dark'),
        grid(true),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 0),
          child: OrbitText(
            'Each theme changes colours, type, shapes and patterns. More '
            'themes are on the way.',
            textAlign: TextAlign.center,
            style: t.font.style(
              size: OrbitType.caption,
              color: t.ink3,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}

/// `.theme-card`: a mini chat drawn in its own theme, then its name and
/// vibe; the current one has an `--accent` ring and a tick.
class _ThemeCard extends StatelessWidget {
  const _ThemeCard({required this.tokens, required this.on, this.onTap});

  final OrbitTokens tokens;
  final bool on;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Theme(
    data: OrbitTheme.of(tokens),
    child: Builder(
      builder: (context) {
        final t = OrbitTokens.of(context);
        final m = t.meta;
        Widget bubble(String text, {required bool out}) => Align(
          alignment: out ? Alignment.centerRight : Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: null,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 140),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: out ? t.out : t.inBubble,
                border: Border.all(color: out ? t.outLine : t.inLine),
                borderRadius: BorderRadius.circular(t.bubbleR).copyWith(
                  topLeft: out ? null : Radius.circular(t.bubbleCut),
                  topRight: out ? Radius.circular(t.bubbleCut) : null,
                ),
              ),
              child: Text(
                text,
                style: t.font.style(
                  size: 11,
                  color: out ? t.outInk : t.inInk,
                  height: 1.3,
                ),
              ),
            ),
          ),
        );
        return Semantics(
          button: true,
          selected: on,
          label: '${m.name} theme${on ? ', selected' : ''}',
          excludeSemantics: true,
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: t.bg,
                border: Border.all(color: on ? t.accent : t.line),
                borderRadius: BorderRadius.circular(20),
                boxShadow: on
                    ? [BoxShadow(color: t.accent, spreadRadius: 2)]
                    : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: OrbitPatternBackground(
                      pattern: t.chatPattern,
                      color: t.chatBg,
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 132),
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              height: 26,
                              child: Row(
                                children: [
                                  const OrbitWordmark(size: 20),
                                  const Spacer(),
                                  if (on)
                                    Container(
                                      width: 22,
                                      height: 22,
                                      decoration: BoxDecoration(
                                        color: t.accent,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Center(
                                        child: OrbitIcon(
                                          OrbitIcons.check,
                                          weight: OrbitIconWeight.bold,
                                          size: 12,
                                          color: t.onAccent,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 6),
                            bubble('Got a minute?', out: false),
                            const SizedBox(height: 6),
                            bubble('Sure, what’s up?', out: true),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  height: 20,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                  ),
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: t.inverse,
                                    borderRadius: BorderRadius.circular(
                                      t.rPill,
                                    ),
                                  ),
                                  child: Text(
                                    'Chats',
                                    style: t.font.style(
                                      size: 9.5,
                                      weight: 700,
                                      color: t.onInverse,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  width: 20,
                                  height: 20,
                                  decoration: BoxDecoration(
                                    color: t.accent,
                                    shape: BoxShape.circle,
                                    boxShadow: t.glow,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        OrbitText(m.name, style: t.display(size: 15)),
                        const SizedBox(height: 1),
                        OrbitText(
                          m.vibe,
                          style: t.mono.style(size: 11, color: t.ink3),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}
