import 'package:flutter/widgets.dart';
import 'package:orbit_ui/orbit_ui.dart';

/// The people keys (`prototype/js/screens/people.js`) on the sample data.

HelixPersonItem _p(String id) => OrbitFakes.people[id]!;

/// `TRUST` in the prototype.
TrustState _trust(String id) => switch (id) {
  'nadia' => TrustState.verified,
  'rafiq' => TrustState.keyChanged,
  'sadia' => TrustState.noKey,
  _ => TrustState.unverified,
};

/// `COMMON` in the prototype.
const _common = {
  'ammu': ['group:family'],
  'abbu': ['group:family'],
  'rumana': ['group:family'],
  'karim': ['group:family'],
  'sadia': ['group:design', 'group:studio'],
  'tanvir': ['group:design', 'group:studio', 'group:lunch'],
  'arif': ['group:design', 'group:lunch'],
  'nadia': ['group:design'],
};

String _chatTitle(String id) =>
    OrbitFakes.chats.where((c) => c.id == id).firstOrNull?.title ?? 'Group';

/// `DIGITS` in the prototype.
const _digits = [
  '37201',
  '84619',
  '05532',
  '77148',
  '26093',
  '51870',
  '94426',
  '13085',
  '60317',
  '48852',
  '29714',
  '06639',
];

ContactModel _contact(String id, {bool blockedByThem = false}) {
  final p = _p(id);
  return ContactModel(
    accountId: id,
    name: p.names.display,
    avatar: p.avatar,
    secondary: p.names.secondary,
    about: p.about,
    trust: _trust(id),
    blocked: p.blocked,
    blockedByThem: blockedByThem,
    nickname: p.names.nickname,
    numberLabel: p.names.number,
    helixName: p.names.helixName,
    muted: id == 'karim',
    disappearing: id == 'nadia' ? DisappearAfter.week : DisappearAfter.off,
    commonGroups: [
      for (final g in _common[id] ?? const <String>[])
        (id: g, title: _chatTitle(g)),
    ],
  );
}

SafetyNumberModel _safety(String id, {bool failed = false}) =>
    SafetyNumberModel(
      name: _p(id).names.display,
      trust: _trust(id),
      groups: _trust(id) == TrustState.noKey ? null : _digits,
      qrSeed: 'safety-$id',
      loadFailed: failed,
    );

/// The safety number keeps its own verified mark, so the button works.
class _PreviewSafety extends StatefulWidget {
  const _PreviewSafety(this.start);

  final SafetyNumberModel start;

  @override
  State<_PreviewSafety> createState() => _PreviewSafetyState();
}

class _PreviewSafetyState extends State<_PreviewSafety> {
  late var _trust = widget.start.trust;

  @override
  Widget build(BuildContext context) {
    final s = widget.start;
    return SafetyNumberScreen(
      model: SafetyNumberModel(
        name: s.name,
        trust: _trust,
        groups: s.groups,
        qrSeed: s.qrSeed,
        loadFailed: s.loadFailed,
      ),
      actions: SafetyNumberActions(
        onSetVerified: (v) => setState(
          () => _trust = v ? TrustState.verified : TrustState.unverified,
        ),
      ),
    );
  }
}

final Map<String, WidgetBuilder> peoplePreviews = {
  'contact': (_) => ContactScreen(model: _contact('nadia')),
  'contact-keychanged': (_) => ContactScreen(model: _contact('rafiq')),
  'contact-nokey': (_) => ContactScreen(model: _contact('sadia')),
  'contact-blocked': (_) => ContactScreen(model: _contact('shuvo')),
  'contact-number': (_) => ContactScreen(model: _contact('unknown')),
  'contact-blocked-me': (_) =>
      ContactScreen(model: _contact('tanvir', blockedByThem: true)),
  'safety': (_) => _PreviewSafety(_safety('nadia')),
  'safety-unverified': (_) => _PreviewSafety(_safety('arif')),
  'safety-changed': (_) => _PreviewSafety(_safety('rafiq')),
  'safety-none': (_) => _PreviewSafety(_safety('sadia')),
  'safety-failed': (_) => _PreviewSafety(_safety('arif', failed: true)),
  'scan': (_) => const ScanCodeScreen(model: ScanCodeModel()),
  'scan-nocamera': (_) =>
      const ScanCodeScreen(model: ScanCodeModel(hasCamera: false)),
  'scan-contact': (_) =>
      const ScanCodeScreen(model: ScanCodeModel(mode: ScanMode.contact)),
  'scan-refused': (_) =>
      const ScanCodeScreen(model: ScanCodeModel(cameraRefused: true)),
  'scan-contact-nocamera': (_) => const ScanCodeScreen(
    model: ScanCodeModel(mode: ScanMode.contact, hasCamera: false),
  ),
  'people': (_) => PeopleSearchScreen(
    model: PeopleSearchModel(
      people: [
        for (final p in OrbitFakes.people.values)
          if (p.id != 'unknown' && !p.blocked) p,
      ],
    ),
  ),
};
