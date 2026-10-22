import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:orbit_ui/src/components/avatar.dart';
import 'package:orbit_ui/src/components/bars.dart';
import 'package:orbit_ui/src/components/button.dart';
import 'package:orbit_ui/src/components/chat_rows.dart';
import 'package:orbit_ui/src/components/codes.dart';
import 'package:orbit_ui/src/components/list_rows.dart';
import 'package:orbit_ui/src/components/overlays.dart';
import 'package:orbit_ui/src/components/page_bits.dart';
import 'package:orbit_ui/src/components/page_parts.dart';
import 'package:orbit_ui/src/components/pages.dart';
import 'package:orbit_ui/src/components/state_kit.dart';
import 'package:orbit_ui/src/icons/orbit_glyph.dart';
import 'package:orbit_ui/src/icons/orbit_icons.dart';
import 'package:orbit_ui/src/models/view_models.dart';
import 'package:orbit_ui/src/screens/home/home_models.dart'
    show MuteFor, PeoplePanelActions, PeoplePanelModel;
import 'package:orbit_ui/src/screens/home/people_panel.dart';
import 'package:orbit_ui/src/screens/signin/entry_screens.dart'
    show OrbitButtonRow;
import 'package:orbit_ui/src/theme/orbit_metrics.dart';
import 'package:orbit_ui/src/theme/orbit_text.dart';
import 'package:orbit_ui/src/theme/orbit_tokens.dart';
import 'package:orbit_ui/src/theme/pattern_painter.dart';

/// How far you can trust a chat's keys (`contracts/people_groups.md`).
enum TrustState { noKey, unverified, verified, keyChanged }

/// When a direct chat's messages disappear.
enum DisappearAfter {
  off('Off'),
  day('24 hours'),
  week('7 days'),
  days90('90 days');

  const DisappearAfter(this.label);
  final String label;
}

enum ReportReason {
  spam('Spam'),
  abuse('Abuse or harassment'),
  impersonation('Pretending to be someone else'),
  other('Something else');

  const ReportReason(this.label);
  final String label;
}

class PersonReport {
  const PersonReport(this.reason, this.note);

  final ReportReason reason;
  final String note;
}

/// What a rename did (`RenameOutcome` in the app).
enum RenameResult {
  /// Saved here and in the phone's contacts.
  savedEverywhere,

  /// Saved here only (no number, or not asked).
  saved,

  /// Saved here; the phone's contacts need permission first.
  needsPhonePermission,

  /// Saved here; the phone refused to change its contacts.
  phoneRefused,
}

/// A missing action does nothing, rather than drawing its button disabled.
void _none() {}

/// The amber "Safety number changed" banner, with Review when it can open
/// the safety number.
Widget _keyBanner(String name, {VoidCallback? onReview, bool review = true}) =>
    OrbitBanner(
      kind: OrbitNoticeKind.warning,
      icon: OrbitIcons.shieldWarning,
      title: 'Safety number changed',
      text:
          'Your safety number with $name changed. That usually means they '
          'got a new phone or reinstalled Orbit. It can also mean someone is '
          'interfering. Compare safety numbers with them to be sure.',
      actions: [if (review) OrbitNoticeAction('Review', onReview ?? _none)],
      // `.banner`'s `8px 16px`, with `margin-top: 14px` inline.
      margin: const EdgeInsets.fromLTRB(
        OrbitSpace.gutter,
        14,
        OrbitSpace.gutter,
        8,
      ),
    );

// ------------------------------------------------------------- contact info

class ContactModel {
  const ContactModel({
    required this.accountId,
    required this.name,
    required this.avatar,
    this.secondary,
    this.about,
    this.trust = TrustState.unverified,
    this.blocked = false,
    this.blockedByThem = false,
    this.nickname,
    this.numberLabel,
    this.helixName,
    this.muted = false,
    this.muteLabel,
    this.disappearing = DisappearAfter.off,
    this.commonGroups = const [],
    this.loading = false,
    this.loadFailed = false,
  });

  final String accountId;
  final String name;
  final HelixAvatarModel avatar;
  final String? secondary;
  final String? about;
  final TrustState trust;
  final bool blocked;
  final bool blockedByThem;
  final String? nickname;
  final String? numberLabel;
  final String? helixName;
  final bool muted;
  final String? muteLabel;
  final DisappearAfter disappearing;
  final List<({String id, String title})> commonGroups;
  final bool loading;
  final bool loadFailed;
}

class ContactActions {
  const ContactActions({
    this.onMessage,
    this.onCall,
    this.onRename,
    this.onSaveToPhoneContacts,
    this.onMute,
    this.onSetDisappearing,
    this.onOpenSharedMedia,
    this.onOpenSafetyNumber,
    this.onOpenGroup,
    this.onBlock,
    this.onUnblock,
    this.onReport,
    this.onRetry,
  });

  final VoidCallback? onMessage;

  /// Null when the call started, else the sentence to show.
  final Future<String?> Function({required bool video})? onCall;

  /// Blank clears the nickname.
  final Future<RenameResult> Function(String name)? onRename;

  /// After "Allow": asks the phone for permission, then saves there too.
  final Future<RenameResult> Function(String name)? onSaveToPhoneContacts;

  /// Null unmutes.
  final ValueChanged<MuteFor?>? onMute;
  final ValueChanged<DisappearAfter>? onSetDisappearing;

  /// False when it could not open.
  final Future<bool> Function()? onOpenSharedMedia;
  final VoidCallback? onOpenSafetyNumber;
  final ValueChanged<String>? onOpenGroup;

  /// False when it did not work (offline).
  final Future<bool> Function()? onBlock;
  final Future<bool> Function()? onUnblock;

  /// False when the report could not be sent.
  final Future<bool> Function(PersonReport report)? onReport;
  final VoidCallback? onRetry;
}

/// `contact`: one person. Their picture, name, number and about; Message,
/// Voice call and Video call; then Name, Chat and Encryption sections,
/// groups in common, and Block and Report.
class ContactScreen extends StatelessWidget {
  const ContactScreen({
    super.key,
    required this.model,
    this.actions = const ContactActions(),
  });

  final ContactModel model;
  final ContactActions actions;

  static const _failed =
      'That did not work. Check your connection and try again.';

  void _say(BuildContext context, String? text, {bool error = false}) {
    if (text != null && context.mounted) {
      showOrbitToast(context, text, error: error);
    }
  }

  static String _renamed(RenameResult r) => switch (r) {
    RenameResult.savedEverywhere => 'Saved, and updated in your contacts.',
    RenameResult.phoneRefused =>
      'Saved in Orbit. Your phone did not let Orbit change your contacts.',
    RenameResult.saved || RenameResult.needsPhonePermission => 'Saved.',
  };

  /// Saves the name; when the phone's contacts need permission, asks first
  /// ("Not now" keeps it in Orbit only).
  Future<void> _rename(BuildContext context, String name) async {
    final rename = actions.onRename;
    if (rename == null) return;
    final result = await rename(name);
    if (!context.mounted) return;
    if (result != RenameResult.needsPhonePermission) {
      _say(context, _renamed(result));
      return;
    }
    await showOrbitDialog(
      context,
      title: 'Save in your phone contacts too?',
      text:
          'Orbit needs permission to change your contacts to keep this name '
          'there as well.',
      actions: [
        OrbitDialogAction('Not now', onPressed: () => _say(context, 'Saved.')),
        OrbitDialogAction(
          'Allow',
          kind: OrbitButtonKind.primary,
          onPressed: () async {
            final save = actions.onSaveToPhoneContacts;
            final again = save == null ? RenameResult.saved : await save(name);
            if (context.mounted) _say(context, _renamed(again));
          },
        ),
      ],
    );
  }

  Future<void> _call(BuildContext context, {required bool video}) async {
    final refusal = await actions.onCall?.call(video: video);
    if (context.mounted) _say(context, refusal, error: true);
  }

  Future<void> _sharedMedia(BuildContext context) async {
    final open = actions.onOpenSharedMedia;
    if (open == null) return;
    if (!await open() && context.mounted) {
      _say(context, 'Shared media could not be opened.', error: true);
    }
  }

  Future<void> _block(BuildContext context, {required bool block}) async {
    final run = block ? actions.onBlock : actions.onUnblock;
    if (run == null) return;
    final ok = await run();
    if (!context.mounted) return;
    if (ok) {
      _say(context, block ? 'Blocked.' : 'Unblocked.');
    } else {
      _say(context, _failed, error: true);
    }
  }

  Future<void> _report(BuildContext context, PersonReport report) async {
    final send = actions.onReport;
    if (send == null) return;
    final ok = await send(report);
    if (!context.mounted) return;
    if (ok) {
      _say(context, 'Reported. No messages were sent with the report.');
    } else {
      _say(
        context,
        'The report could not be sent. Try again in a moment.',
        error: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final m = model;
    final a = actions;
    if (m.loading || m.loadFailed) {
      return OrbitPage(
        title: 'Contact info',
        children: [
          if (m.loading) ...[
            const SizedBox(height: 120),
            const OrbitPageLoading(),
          ] else
            OrbitLoadFailed(
              title: 'This person could not be loaded.',
              onRetry: a.onRetry,
            ),
        ],
      );
    }
    final n = m.name;
    final trustSub = switch (m.trust) {
      TrustState.verified => 'Verified',
      TrustState.keyChanged => 'Safety number changed',
      TrustState.unverified => 'Not verified',
      TrustState.noKey => 'Available after your first message',
    };
    final common = m.commonGroups;
    final number = m.numberLabel;
    final danger = t.font.style(size: 13.5, color: t.danger, height: 1.4);
    return OrbitPage(
      title: 'Contact info',
      children: [
        OrbitProfileHero(
          avatar: m.avatar,
          size: 112,
          name: n,
          verified: m.trust == TrustState.verified,
          sub: m.secondary ?? '',
          about: m.about ?? '',
          extra: [
            if (m.blocked)
              OrbitText(
                'Blocked',
                style: danger.copyWith(fontWeight: FontWeight.w600),
              ),
            if (m.blockedByThem)
              OrbitText.rich(
                TextSpan(
                  children: [
                    WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: OrbitIcon(
                        OrbitIcons.prohibit,
                        size: 13.5,
                        color: t.danger,
                      ),
                    ),
                    TextSpan(text: ' $n has blocked you.'),
                  ],
                ),
                style: danger,
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            OrbitSpace.gutter,
            16,
            OrbitSpace.gutter,
            4,
          ),
          child: Row(
            children: [
              Expanded(
                child: _Tile(OrbitIcons.chatCircle, 'Message', a.onMessage),
              ),
              if (!m.blockedByThem) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: _Tile(
                    OrbitIcons.phone,
                    'Voice call',
                    () => _call(context, video: false),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _Tile(
                    OrbitIcons.videoCamera,
                    'Video call',
                    () => _call(context, video: true),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (m.trust == TrustState.keyChanged)
          _keyBanner(n, onReview: a.onOpenSafetyNumber),
        OrbitSection(
          title: 'Name',
          footer: number != null
              ? 'Renaming also saves the name in your phone’s contacts.'
              : '',
          rows: [
            OrbitListRow(
              icon: OrbitIcons.pencilSimple,
              iconColor: 0,
              title: 'Rename',
              sub: (m.nickname ?? '').isNotEmpty
                  ? m.nickname!
                  : 'Choose a name only you see',
              end: OrbitRowEnd.chevron,
              onTap: () => showOrbitInputDialog(
                context,
                title: 'Rename',
                label: 'Name',
                value: (m.nickname ?? '').isNotEmpty ? m.nickname! : n,
                onConfirm: (v) => _rename(context, v.trim()),
              ),
            ),
            if (number != null)
              OrbitListRow(
                icon: OrbitIcons.phone,
                iconColor: 3,
                title: number,
                titleWidget: OrbitText(
                  number,
                  style: t.mono.style(size: OrbitType.body, color: t.ink),
                ),
                sub: 'Phone number',
              ),
            if (m.helixName != null)
              OrbitListRow(
                icon: OrbitIcons.at,
                iconColor: 1,
                title: '~${m.helixName}',
                sub: 'Orbit name',
              ),
          ],
        ),
        OrbitSection(
          title: 'Chat',
          rows: [
            OrbitListRow(
              icon: OrbitIcons.images,
              iconColor: 2,
              title: 'Media, links and docs',
              end: OrbitRowEnd.chevron,
              onTap: () => _sharedMedia(context),
            ),
            OrbitListRow(
              icon: OrbitIcons.bellSlash,
              iconColor: 4,
              title: 'Mute notifications',
              sub: m.muted ? (m.muteLabel ?? 'Always') : '',
              end: OrbitRowEnd.toggle,
              on: m.muted,
              onChanged: (on) {
                if (!on) {
                  a.onMute?.call(null);
                  return;
                }
                showOrbitSheet(
                  context,
                  title: 'Mute notifications',
                  items: [
                    for (final f in MuteFor.values)
                      OrbitMenuItem(
                        icon: OrbitIcons.bellSlash,
                        label: f.label,
                        onTap: () => a.onMute?.call(f),
                      ),
                  ],
                );
              },
            ),
            OrbitListRow(
              icon: OrbitIcons.timer,
              iconColor: 5,
              title: 'Disappearing messages',
              value: m.disappearing.label,
              end: OrbitRowEnd.chevron,
              onTap: () => showOrbitSheet(
                context,
                title: 'Disappearing messages',
                text:
                    'New messages in this chat are deleted from both phones '
                    'after the time you choose. Earlier messages are not '
                    'changed.',
                items: [
                  for (final d in DisappearAfter.values)
                    OrbitMenuItem(
                      icon: OrbitIcons.timer,
                      label: d.label,
                      on: d == m.disappearing,
                      onTap: () => a.onSetDisappearing?.call(d),
                    ),
                ],
              ),
            ),
          ],
        ),
        OrbitSection(
          title: 'Encryption',
          footer:
              'Messages and calls with $n are end-to-end encrypted. Only the '
              'two of you can read them.',
          rows: [
            OrbitListRow(
              icon: OrbitIcons.shieldCheck,
              iconColor: 3,
              title: 'Verify safety number',
              sub: trustSub,
              subLeading: switch (m.trust) {
                TrustState.verified => OrbitIcon(
                  OrbitIcons.sealCheck,
                  weight: OrbitIconWeight.fill,
                  size: 12,
                  color: t.success,
                ),
                TrustState.keyChanged => OrbitIcon(
                  OrbitIcons.warning,
                  weight: OrbitIconWeight.fill,
                  size: 12,
                  color: t.warning,
                ),
                _ => null,
              },
              subInk: switch (m.trust) {
                TrustState.verified => t.success,
                TrustState.keyChanged => t.warning,
                _ => null,
              },
              end: OrbitRowEnd.chevron,
              onTap: m.trust == TrustState.noKey
                  ? () => showOrbitToast(
                      context,
                      'Send a message first. A safety number needs both of '
                      'your keys.',
                    )
                  : a.onOpenSafetyNumber,
            ),
          ],
        ),
        if (common.isNotEmpty)
          OrbitSection(
            title: common.length == 1
                ? '1 group in common'
                : '${common.length} groups in common',
            rows: [
              for (final g in common)
                OrbitListRow(
                  icon: OrbitIcons.usersThree,
                  iconColor: 0,
                  iconWeight: OrbitIconWeight.fill,
                  title: g.title,
                  end: OrbitRowEnd.chevron,
                  onTap: () => a.onOpenGroup?.call(g.id),
                ),
            ],
          ),
        OrbitSection(
          rows: [
            if (m.blocked)
              OrbitListRow(
                icon: OrbitIcons.prohibit,
                title: 'Unblock $n',
                onTap: () => _block(context, block: false),
              )
            else
              OrbitListRow(
                icon: OrbitIcons.prohibit,
                title: 'Block $n',
                danger: true,
                onTap: () => showOrbitDialog(
                  context,
                  title: 'Block $n?',
                  text:
                      'They will not be able to message or call you. Orbit '
                      'tells them that you blocked them.',
                  actions: [
                    const OrbitDialogAction('Cancel'),
                    OrbitDialogAction(
                      'Block',
                      kind: OrbitButtonKind.primary,
                      onPressed: () => _block(context, block: true),
                    ),
                  ],
                ),
              ),
            OrbitListRow(
              icon: OrbitIcons.flag,
              title: 'Report $n',
              danger: true,
              onTap: () => showOrbitSheet(
                context,
                title: 'Report $n',
                // The note is sent too (`contracts/people_groups.md`).
                text:
                    'Orbit learns who you reported, why, and your note. No '
                    'messages are sent with the report.',
                items: [
                  for (final r in ReportReason.values)
                    OrbitMenuItem(
                      icon: OrbitIcons.flag,
                      label: r.label,
                      onTap: () => showOrbitInputDialog(
                        context,
                        title: 'Add a note (optional)',
                        label: 'What happened?',
                        maxLength: 500,
                        confirmLabel: 'Report',
                        onConfirm: (note) =>
                            _report(context, PersonReport(r, note.trim())),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// `.tile`: an action square on `--surface` (at least 72px, corner
/// `--r-lg`), a 22px `--accent` icon over its 12.5px label.
class _Tile extends StatelessWidget {
  const _Tile(this.icon, this.label, this.onPressed);

  final OrbitGlyph icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final shape = RoundedRectangleBorder(
      side: BorderSide(color: t.line),
      borderRadius: BorderRadius.circular(t.rLg),
    );
    return Material(
      color: t.surface,
      shape: shape,
      child: InkWell(
        onTap: onPressed,
        customBorder: shape,
        hoverColor: t.accentSoft,
        splashFactory: NoSplash.splashFactory,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 72),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OrbitIcon(icon, size: 22, color: t.accent),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: t.font.style(size: 12.5, weight: 560, color: t.ink2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ safety number

class SafetyNumberModel {
  const SafetyNumberModel({
    required this.name,
    this.trust = TrustState.unverified,
    this.groups,
    this.qrSeed,
    this.qr,
    this.loading = false,
    this.loadFailed = false,
  });

  final String name;
  final TrustState trust;

  /// Twelve groups of five digits; null when there is no number yet.
  final List<String>? groups;

  /// The preview's stand-in for the code.
  final String? qrSeed;

  /// The app's code: the modules to draw.
  final HelixQrMatrix? qr;
  final bool loading;
  final bool loadFailed;
}

class SafetyNumberActions {
  const SafetyNumberActions({this.onScan, this.onSetVerified, this.onRetry});

  final VoidCallback? onScan;
  final ValueChanged<bool>? onSetVerified;
  final VoidCallback? onRetry;
}

/// `safety`: the QR code and the 60 digits to compare, Scan their code, and
/// Mark as verified.
class SafetyNumberScreen extends StatelessWidget {
  const SafetyNumberScreen({
    super.key,
    required this.model,
    this.actions = const SafetyNumberActions(),
  });

  final SafetyNumberModel model;
  final SafetyNumberActions actions;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final m = model;
    final a = actions;
    final groups = m.groups;
    final verified = m.trust == TrustState.verified;
    final List<Widget> body;
    if (m.loading) {
      body = const [SizedBox(height: 120), OrbitPageLoading()];
    } else if (m.loadFailed) {
      body = [
        OrbitLoadFailed(
          title: 'The safety number could not be worked out.',
          sub: 'Try again in a moment.',
          onRetry: a.onRetry,
        ),
      ];
    } else if (m.trust == TrustState.noKey || groups == null) {
      body = const [
        OrbitEmptyState(
          icon: OrbitIcons.shield,
          title: 'No safety number yet',
          text:
              'Send a message first. A safety number needs both of your keys.',
        ),
      ];
    } else {
      final digits = t.mono.style(
        size: 18,
        weight: 560,
        color: t.ink,
        letterSpacingEm: 0.06,
      );
      body = [
        if (m.trust == TrustState.keyChanged) _keyBanner(m.name, review: false),
        Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 6),
          child: Center(
            child: Semantics(
              container: true,
              image: true,
              label: 'QR code for the safety number with ${m.name}',
              excludeSemantics: true,
              child: OrbitQrCard(
                child: OrbitQr(seed: m.qrSeed ?? m.name, matrix: m.qr),
              ),
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
          decoration: BoxDecoration(
            color: t.surface,
            border: Border.all(color: t.line),
            borderRadius: BorderRadius.circular(t.rLg),
          ),
          child: Column(
            children: [
              for (var r = 0; r < groups.length; r += 4) ...[
                if (r > 0) const SizedBox(height: 12),
                Row(
                  children: [
                    for (var c = r; c < r + 4 && c < groups.length; c++) ...[
                      if (c > r) const SizedBox(width: 6),
                      Expanded(
                        child: OrbitText(
                          groups[c],
                          textAlign: TextAlign.center,
                          style: digits,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
              if (verified) ...[
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OrbitIcon(
                      OrbitIcons.shieldCheck,
                      weight: OrbitIconWeight.fill,
                      size: 13,
                      color: t.success,
                    ),
                    const SizedBox(width: 6),
                    OrbitText(
                      'Verified',
                      style: t.font.style(
                        size: 13,
                        weight: 600,
                        color: t.success,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            OrbitSpace.gutter + 6,
            14,
            OrbitSpace.gutter + 6,
            0,
          ),
          child: OrbitText(
            'To check that your chat with ${m.name} is private, compare this '
            'number with the one on their phone, or scan their QR code. If '
            'they match, nobody can be listening in.',
            style: t.font.style(size: 13, color: t.ink3, height: 1.5),
          ),
        ),
        OrbitButtonRow(
          column: true,
          children: [
            OrbitButton(
              label: 'Scan their code',
              icon: OrbitIcons.qrCode,
              block: true,
              onPressed: a.onScan ?? _none,
            ),
            OrbitButton(
              label: verified ? 'Mark as not verified' : 'Mark as verified',
              kind: OrbitButtonKind.secondary,
              block: true,
              onPressed: () => a.onSetVerified?.call(!verified),
            ),
          ],
        ),
      ];
    }
    return OrbitPage(title: 'Safety number', children: body);
  }
}

// --------------------------------------------------------------- scan code

enum ScanMode { safetyNumber, contact }

class ScanCodeModel {
  const ScanCodeModel({
    this.mode = ScanMode.safetyNumber,
    this.hasCamera = true,
    this.cameraRefused = false,
  });

  final ScanMode mode;
  final bool hasCamera;
  final bool cameraRefused;
}

class ScanCodeActions {
  const ScanCodeActions({
    this.onOpenSettings,
    this.onMatch,
    this.onMismatch,
    this.onCode,
  });

  final VoidCallback? onOpenSettings;

  /// The preview's stand-ins for a code the camera read.
  final VoidCallback? onMatch;
  final VoidCallback? onMismatch;

  /// A code the camera read: true when it answers - a safety number that
  /// matches, a share code that names someone you can message - and the page
  /// then closes. False says what went wrong and scanning goes on.
  final Future<bool> Function(String text)? onCode;
}

/// The live camera inside the frame; it reports each code it reads to
/// [onCode].
typedef ScanCameraSlot =
    Widget Function(BuildContext context, ValueChanged<String> onCode);

/// `scan`: a night page. The camera in a rounded frame with four corner
/// marks and a sweeping line, and what to point it at. Without a camera, or
/// when it was refused, it says what to do instead.
///
/// A code is checked one at a time, and what one means depends on the mode:
/// a safety number that matches says "Verified. Your chat is private." and
/// goes back to the number; a contact code that matches opens the chat it
/// names. Either way a mismatch is said, and scanning goes on.
class ScanCodeScreen extends StatefulWidget {
  const ScanCodeScreen({
    super.key,
    required this.model,
    this.actions = const ScanCodeActions(),
    this.camera,
  });

  final ScanCodeModel model;
  final ScanCodeActions actions;

  /// The live camera, inside the frame.
  final ScanCameraSlot? camera;

  @override
  State<ScanCodeScreen> createState() => _ScanCodeScreenState();
}

class _ScanCodeScreenState extends State<ScanCodeScreen> {
  static const _bg = Color(0xFF06080F);
  static const _hint = Color(0xFFD6DCEA);

  /// A code is being checked: new ones wait.
  var _busy = false;

  Future<void> _code(String text) async {
    final check = widget.actions.onCode;
    if (check == null || _busy) return;
    _busy = true;
    final contact = widget.model.mode == ScanMode.contact;
    try {
      final match = await check(text);
      if (!mounted) return;
      if (match) {
        showOrbitToast(
          context,
          contact
              ? 'Found them. Opening your chat.'
              : 'Verified. Your chat is private.',
        );
        await Navigator.maybePop(context);
        return;
      }
      await showOrbitDialog(
        context,
        title: contact
            ? 'That is not a share code'
            : 'That code does not match',
        text: contact
            ? 'It does not name anyone you can message. Either it is not a '
                  'link from this app, or that person is not findable by name '
                  'on your server.'
            : 'The code on their phone is not the one Orbit expects for this '
                  'chat. Do not trust this chat until you have compared the numbers '
                  'with them in person.',
        actions: const [OrbitDialogAction('OK', kind: OrbitButtonKind.primary)],
      );
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final m = widget.model;
    final a = widget.actions;
    final camera = widget.camera;
    final top = MediaQuery.paddingOf(context).top;
    final contact = m.mode == ScanMode.contact;
    final hint = t.font.style(size: 14, color: _hint, height: 1.5);
    Widget body;
    if (m.cameraRefused) {
      body = OrbitPermissionCard(
        kind: OrbitPermission.camera,
        denied: true,
        dark: true,
        text:
            'Allow camera access for Orbit in your phone’s settings to scan a '
            'code.',
        onPressed: a.onOpenSettings ?? _none,
      );
    } else if (!m.hasCamera) {
      body = ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 260),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const OrbitIcon(OrbitIcons.cameraSlash, size: 14, color: _hint),
            OrbitText(
              contact
                  ? 'This device has no camera to scan with. Ask them to send '
                        'you their Orbit link instead.'
                  : 'This device has no camera to scan with. Compare the '
                        'numbers on both phones instead.',
              textAlign: TextAlign.center,
              style: hint,
            ),
          ],
        ),
      );
    } else {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          OrbitScanFrame(child: camera?.call(context, _code)),
          const SizedBox(height: 22),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: OrbitText(
              contact
                  ? 'Point the camera at someone’s Orbit code to start a chat'
                  : 'Point the camera at the code on their phone',
              textAlign: TextAlign.center,
              style: hint,
            ),
          ),
          // The prototype's demo buttons, where there is no real camera.
          if (camera == null) ...[
            const SizedBox(height: 22),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _NightPill('Simulate a match', a.onMatch),
                const SizedBox(width: 10),
                _NightPill('Simulate a mismatch', a.onMismatch),
              ],
            ),
          ],
        ],
      );
    }
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: ColoredBox(
        color: OrbitNight.night,
        child: Padding(
          padding: EdgeInsets.only(top: top),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OrbitAppBar(
                title: 'Scan code',
                background: _bg,
                rule: false,
                ink: const Color(0xFFFFFFFF),
                onLead: () => Navigator.maybePop(context),
              ),
              Expanded(
                child: ColoredBox(
                  color: _bg,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(child: body),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NightPill extends StatelessWidget {
  const _NightPill(this.label, this.onPressed);

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final shape = RoundedRectangleBorder(
      side: const BorderSide(color: OrbitNight.buttonLine),
      borderRadius: BorderRadius.circular(t.rMd),
    );
    return Material(
      color: OrbitNight.buttonBg,
      shape: shape,
      child: InkWell(
        onTap: onPressed ?? () {},
        customBorder: shape,
        splashFactory: NoSplash.splashFactory,
        child: SizedBox(
          height: 48,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Center(
              widthFactor: 1,
              child: Text(
                label,
                style: t.font.style(
                  size: OrbitType.small,
                  weight: 600,
                  color: const Color(0xFFFFFFFF),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `.scan-frame`: 260px, corner 28, a dark radial glow, four 44px white
/// corner marks 14px in, and a blue line sweeping down and up (still with
/// reduce motion, at its start).
class OrbitScanFrame extends StatefulWidget {
  const OrbitScanFrame({
    super.key,
    this.child,
    this.width = 260,
    this.height = 260,
  });

  final Widget? child;
  final double width;
  final double height;

  @override
  State<OrbitScanFrame> createState() => _OrbitScanFrameState();
}

class _OrbitScanFrameState extends State<OrbitScanFrame>
    with SingleTickerProviderStateMixin {
  late final _beam = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );

  @override
  void dispose() {
    _beam.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    if (still) {
      _beam.stop();
    } else if (!_beam.isAnimating) {
      _beam.repeat();
    }
    const white = BorderSide(color: Color(0xFFFFFFFF), width: 4);
    Widget corner({required bool top, required bool left}) => Positioned(
      top: top ? 14 : null,
      bottom: top ? null : 14,
      left: left ? 14 : null,
      right: left ? null : 14,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          border: Border(
            top: top ? white : BorderSide.none,
            bottom: top ? BorderSide.none : white,
            left: left ? white : BorderSide.none,
            right: left ? BorderSide.none : white,
          ),
          borderRadius: BorderRadius.only(
            topLeft: top && left ? const Radius.circular(14) : Radius.zero,
            topRight: top && !left ? const Radius.circular(14) : Radius.zero,
            bottomLeft: !top && left ? const Radius.circular(14) : Radius.zero,
            bottomRight: !top && !left
                ? const Radius.circular(14)
                : Radius.zero,
          ),
        ),
      ),
    );
    return Container(
      width: widget.width,
      height: widget.height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const RadialGradient(
          center: Alignment(-0.2, -0.3),
          radius: 1.1,
          colors: [Color(0xFF26304A), Color(0xFF0B0F1A)],
          stops: [0, 0.7],
        ),
      ),
      child: Stack(
        children: [
          if (widget.child != null) Positioned.fill(child: widget.child!),
          corner(top: true, left: true),
          corner(top: true, left: false),
          corner(top: false, left: true),
          corner(top: false, left: false),
          AnimatedBuilder(
            animation: _beam,
            builder: (context, _) {
              // `@keyframes beam`: 30px → 226px → 30px, eased.
              final p = _beam.value < 0.5
                  ? _beam.value * 2
                  : 2 - _beam.value * 2;
              final y = 30 + (226 - 30) * Curves.easeInOut.transform(p);
              return Positioned(
                left: 24,
                right: 24,
                top: still ? 0 : y,
                child: Container(
                  height: 2,
                  decoration: const BoxDecoration(
                    color: Color(0xFF6EA2FF),
                    boxShadow: [
                      BoxShadow(color: Color(0xFF6EA2FF), blurRadius: 12),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ people search

class PeopleSearchModel {
  const PeopleSearchModel({this.people = const [], this.panel});

  /// Everyone you know on Orbit, not blocked.
  final List<HelixPersonItem> people;

  /// The app's whole people panel (the people, the lookup, the contacts
  /// card and the groups, the same component as on Chats and Calls), drawn
  /// under the field in place of [people] (`contracts/home.md`).
  final PeoplePanelModel? panel;
}

class PeopleSearchActions {
  const PeopleSearchActions({this.onOpenPerson, this.panel});

  final ValueChanged<String>? onOpenPerson;

  /// The panel's actions; Enter in the field is its look-up.
  final PeoplePanelActions? panel;
}

/// `people`: search the people you know, from a contact link.
class PeopleSearchScreen extends StatefulWidget {
  const PeopleSearchScreen({
    super.key,
    required this.model,
    this.actions = const PeopleSearchActions(),
  });

  final PeopleSearchModel model;
  final PeopleSearchActions actions;

  @override
  State<PeopleSearchScreen> createState() => _PeopleSearchScreenState();
}

class _PeopleSearchScreenState extends State<PeopleSearchScreen> {
  var _q = '';

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final top = MediaQuery.paddingOf(context).top;
    final panel = widget.model.panel;
    final panelActions = widget.actions.panel ?? const PeoplePanelActions();
    final q = _q.toLowerCase();
    final found = [
      for (final p in widget.model.people)
        if (p.names.display.toLowerCase().contains(q)) p,
    ];
    return OrbitPageBackground(
      child: Padding(
        padding: EdgeInsets.only(top: top),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OrbitAppBar(
              onLead: () => Navigator.maybePop(context),
              titleWidget: SizedBox(
                height: 44,
                child: OrbitSearchField(
                  hint: 'Name, number or ~Orbit name',
                  // The app's page opens ready to type.
                  autofocus: panel != null,
                  onChanged: (v) {
                    setState(() => _q = v);
                    panelActions.onQueryChanged?.call(v);
                  },
                  onSubmitted: (_) => panelActions.onLookUp?.call(),
                ),
              ),
            ),
            if (panel != null)
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 30),
                  children: [PeoplePanel(model: panel, actions: panelActions)],
                ),
              )
            else
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 30),
                  children: [
                    OrbitListLabel(_q.isEmpty ? 'People on Orbit' : 'People'),
                    if (found.isEmpty)
                      OrbitEmptyState(
                        icon: OrbitIcons.magnifyingGlass,
                        title: 'No matches',
                        text: 'Nobody you know matches “$_q”.',
                      ),
                    for (final p in found)
                      InkWell(
                        onTap: () => widget.actions.onOpenPerson?.call(p.id),
                        hoverColor: t.hover,
                        splashFactory: NoSplash.splashFactory,
                        child: SizedBox(
                          height: orbitRowHeight,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: OrbitSpace.gutter,
                            ),
                            child: Row(
                              children: [
                                OrbitAvatar(avatar: p.avatar, size: 52),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      OrbitText(
                                        p.names.display,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: t.font.style(
                                          size: OrbitType.headline,
                                          weight: 600,
                                          color: t.ink,
                                          letterSpacingEm: -0.01,
                                        ),
                                      ),
                                      if ((p.names.secondary ?? '').isNotEmpty)
                                        const SizedBox(height: 3),
                                      if ((p.names.secondary ?? '').isNotEmpty)
                                        OrbitText(
                                          p.names.secondary!,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: t.mono.style(
                                            size: 12,
                                            color: t.ink3,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
