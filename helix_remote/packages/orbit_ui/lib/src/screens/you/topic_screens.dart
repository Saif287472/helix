import 'dart:async';

import 'package:flutter/material.dart';

import 'package:orbit_ui/src/brand/orbit_mark.dart';
import 'package:orbit_ui/src/components/avatar.dart';
import 'package:orbit_ui/src/components/button.dart';
import 'package:orbit_ui/src/components/chat_rows.dart';
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
import 'package:orbit_ui/src/screens/you/ringtone_packs_screen.dart'
    show phoneRingtoneLabel;
import 'package:orbit_ui/src/theme/orbit_metrics.dart';
import 'package:orbit_ui/src/theme/orbit_text.dart';
import 'package:orbit_ui/src/theme/orbit_tokens.dart';

void _none() {}

// ------------------------------------------------------------ shared parts

/// `segRow` in `js/screens/topics.js` (`.segrow`): a setting whose few
/// choices sit inline under its title. 12px 14px in; the head (an optional
/// 36px icon tile, the title and sub) 10px over a small segmented control.
/// Its rules in a card run the full width.
class OrbitSegRow<T> extends StatelessWidget implements OrbitFullWidthRule {
  const OrbitSegRow({
    super.key,
    required this.title,
    required this.options,
    required this.value,
    required this.onChanged,
    this.sub = '',
    this.icon,
    this.iconColor = 0,
  });

  final String title;
  final String sub;
  final OrbitGlyph? icon;
  final int iconColor;
  final List<OrbitSegment<T>> options;
  final T value;
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final (bg, ink) = OrbitAvatar.palette(t, iconColor);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Center(child: OrbitIcon(icon!, size: 19, color: ink)),
                ),
                const SizedBox(width: 14),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    OrbitText(
                      title,
                      style: t.font.style(
                        size: OrbitType.body,
                        weight: 520,
                        color: t.ink,
                      ),
                    ),
                    if (sub.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: OrbitText(
                          sub,
                          style: t.font.style(
                            size: OrbitType.caption,
                            color: t.ink3,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          OrbitSegmented<T>(
            small: true,
            options: options,
            value: value,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

List<OrbitSegment<String>> _segs(List<String> labels) => [
  for (final l in labels) OrbitSegment(l, l),
];

/// `.preview-box`: a framed sample on the chat background, with its mono
/// label.
class _PreviewBox extends StatelessWidget {
  const _PreviewBox({required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.chatBg,
        border: Border.all(color: t.line2),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OrbitText(
            label.toUpperCase(),
            style: t.mono.style(
              size: 10.5,
              color: t.ink3,
              letterSpacingEm: 0.1,
            ),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

/// `.pv-bubble`: a sample message, at most 85% wide, its time in mono.
class _PvBubble extends StatelessWidget {
  const _PvBubble(
    this.text, {
    required this.out,
    required this.time,
    this.scale = 1,
    this.read,
  });

  final String text;
  final bool out;
  final String time;
  final double scale;

  /// Ticks after the time: blue when read, grey when not, none for null.
  final bool? read;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final meta = out ? t.outMeta : t.inMeta;
    final r = read;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Align(
        alignment: out ? Alignment.centerRight : Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: 0.85,
          alignment: out ? Alignment.centerRight : Alignment.centerLeft,
          child: Align(
            alignment: out ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.fromLTRB(11, 8, 11, 7),
              decoration: BoxDecoration(
                color: out ? t.out : t.inBubble,
                border: Border.all(color: out ? t.outLine : t.inLine),
                borderRadius: out
                    ? const BorderRadius.only(
                        topLeft: Radius.circular(14),
                        topRight: Radius.circular(4),
                        bottomLeft: Radius.circular(14),
                        bottomRight: Radius.circular(14),
                      )
                    : const BorderRadius.only(
                        topLeft: Radius.circular(4),
                        topRight: Radius.circular(14),
                        bottomLeft: Radius.circular(14),
                        bottomRight: Radius.circular(14),
                      ),
              ),
              child: OrbitText.rich(
                TextSpan(
                  children: [
                    TextSpan(text: text),
                    WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              time,
                              style: t.mono.style(size: 10, color: meta),
                            ),
                            if (r != null) ...[
                              const SizedBox(width: 4),
                              OrbitIcon(
                                OrbitIcons.checks,
                                weight: r ? OrbitIconWeight.bold : null,
                                size: 13,
                                color: r ? t.readTick : meta,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                style: t.font.style(
                  size: 14 * scale,
                  color: out ? t.outInk : t.inInk,
                  height: 1.4,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `.sec-foot` without a section.
Widget _foot(String text) => OrbitSectionFoot(text);

// ================================================================= Privacy

/// Whether the server's privacy choices have come.
enum PrivacyServerStatus { loading, failed, ready }

class PrivacyModel {
  const PrivacyModel({
    required this.meName,
    required this.meAvatar,
    this.server = PrivacyServerStatus.ready,
    this.saving = false,
    this.error,
    this.contacts = const {},
    this.viewerName = 'Nadia',
    this.lastSeenEveryone = true,
    this.onlineEveryone = true,
    this.groupsEveryone = true,
    this.receipts = true,
    this.typing = true,
    this.timerLabel = 'Off',
    this.byNumber = true,
    this.byName = true,
    this.lockOn = false,
    this.lockAfter = '1 min',
    this.lockSub = 'Fingerprint, face or phone PIN to open Orbit',
    this.blockedCount = 0,
    this.blockedAvatar,
    this.askNumber = false,
    this.silenceUnknownCalls,
  });

  final String meName;
  final HelixAvatarModel meAvatar;

  /// "Silence unknown callers" is on; null when the app does not offer it.
  final bool? silenceUnknownCalls;

  /// "Who can see" and "Being found" are the server's: hidden until they
  /// come, with Try again when they could not be read.
  final PrivacyServerStatus server;

  /// A server choice is being sent: those controls wait.
  final bool saving;

  /// Why the last change, or the load, did not work.
  final String? error;

  /// The "Who can see" keys whose choice is "My contacts" (set by another
  /// app): they get a third segment.
  final Set<String> contacts;

  /// "What Nadia sees": your most recent chat's name, or "Someone".
  final String viewerName;
  final bool lastSeenEveryone;
  final bool onlineEveryone;
  final bool groupsEveryone;
  final bool receipts;
  final bool typing;

  /// "Off", "24 h", "7 d" or "90 d".
  final String timerLabel;
  final bool byNumber;
  final bool byName;
  final bool lockOn;

  /// "Now", "1 min", "5 min" or "30 min".
  final String lockAfter;

  /// "Windows Hello to open Orbit" on a window.
  final String lockSub;
  final int blockedCount;
  final HelixAvatarModel? blockedAvatar;

  /// Turning "By phone number" back on from a linked device asks for it.
  final bool askNumber;
}

class PrivacyActions {
  const PrivacyActions({
    this.onChanged,
    this.onOpenBlocked,
    this.onPhoneNumber,
    this.onCancelNumber,
    this.onRetry,
  });

  /// One setting changed: its key ("lastSeen", "receipts", …) and value.
  /// Answers a sentence when it could not be changed (the app lock without
  /// a screen lock), which the page toasts.
  final Future<String?> Function(String key, Object value)? onChanged;
  final VoidCallback? onOpenBlocked;

  /// The number typed in "Your phone number"; false when it is not a number
  /// with its country code (the dialog opens again).
  final Future<bool> Function(String number)? onPhoneNumber;
  final VoidCallback? onCancelNumber;
  final VoidCallback? onRetry;
}

/// `privacy`: who sees your status, receipts and typing, being found, app
/// lock and blocked people, with a live "What Nadia sees" preview.
class PrivacyScreen extends StatefulWidget {
  const PrivacyScreen({
    super.key,
    required this.model,
    this.actions = const PrivacyActions(),
  });

  final PrivacyModel model;
  final PrivacyActions actions;

  @override
  State<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends State<PrivacyScreen> {
  late Map<String, Object> _v = _from(widget.model);

  static Map<String, Object> _from(PrivacyModel m) => {
    'lastSeen': m.lastSeenEveryone,
    'online': m.onlineEveryone,
    'groups': m.groupsEveryone,
    'receipts': m.receipts,
    'typing': m.typing,
    'timer': m.timerLabel,
    'byNumber': m.byNumber,
    'byName': m.byName,
    'lock': m.lockOn,
    'lockAfter': m.lockAfter,
    'silenceCalls': m.silenceUnknownCalls ?? false,
  };

  @override
  void initState() {
    super.initState();
    if (widget.model.askNumber) _askLater();
  }

  @override
  void didUpdateWidget(PrivacyScreen old) {
    super.didUpdateWidget(old);
    if (old.model != widget.model) _v = _from(widget.model);
    if (widget.model.askNumber && !old.model.askNumber) _askLater();
  }

  void _askLater() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) _askNumber();
  });

  /// "Your phone number", again until it is one or the person cancels.
  Future<void> _askNumber() async {
    final a = widget.actions;
    while (mounted) {
      // The dialog runs Turn on a beat after it has closed, so its answer
      // is waited for; closed without one (Cancel) is null.
      final answer = Completer<String?>();
      unawaited(
        showOrbitInputDialog(
          context,
          title: 'Your phone number',
          label: 'With its country code, like +88017XXXXXXXX',
          value: '+880 ',
          maxLength: 20,
          confirmLabel: 'Turn on',
          onConfirm: answer.complete,
        ).then(
          (_) => Timer(const Duration(milliseconds: 120), () {
            if (!answer.isCompleted) answer.complete(null);
          }),
        ),
      );
      final number = await answer.future;
      if (!mounted) return;
      if (number == null) {
        a.onCancelNumber?.call();
        return;
      }
      final submit = a.onPhoneNumber;
      if (submit == null || await submit(number) || !mounted) return;
      showOrbitToast(
        context,
        'Enter the number with its country code, like +88017XXXXXXXX.',
        error: true,
      );
    }
  }

  Future<void> _set(String key, Object value) async {
    setState(() => _v[key] = value);
    final refused = await widget.actions.onChanged?.call(key, value);
    if (refused == null || !mounted) return;
    // Not changed: back to what holds, and why.
    setState(() => _v = _from(widget.model));
    showOrbitToast(context, refused, error: true);
  }

  bool _b(String k) => _v[k]! as bool;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final m = widget.model;
    final hidden = [!_b('lastSeen'), !_b('online')].where((x) => x).length;
    final waiting = m.saving;
    OrbitSegRow<String> who(String key, String title, OrbitGlyph icon, int c) {
      final contacts = m.contacts.contains(key);
      return OrbitSegRow<String>(
        title: title,
        icon: icon,
        iconColor: c,
        options: _segs(['Everyone', if (contacts) 'My contacts', 'Nobody']),
        value: contacts
            ? 'My contacts'
            : _b(key)
            ? 'Everyone'
            : 'Nobody',
        onChanged: waiting
            ? null
            : (v) {
                if (v != 'My contacts') _set(key, v == 'Everyone');
              },
      );
    }

    OrbitListRow sw(
      String key,
      String title,
      String sub,
      OrbitGlyph i,
      int c, {
      bool server = false,
    }) => OrbitListRow(
      icon: i,
      iconColor: c,
      title: title,
      sub: sub,
      end: OrbitRowEnd.toggle,
      on: _b(key),
      onChanged: server && waiting ? null : (v) => _set(key, v),
    );
    final ready = m.server == PrivacyServerStatus.ready;
    // The server's sections while its choices have not come.
    List<Widget> notYet() => [
      if (m.server == PrivacyServerStatus.loading)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 18),
          child: OrbitPageLoading(),
        )
      else
        OrbitLoadFailed(
          title: 'Your privacy choices could not be loaded.',
          onRetry: widget.actions.onRetry,
        ),
    ];
    final status = _b('online')
        ? 'online'
        : _b('lastSeen')
        ? 'last seen today at 08:12'
        : '';
    final preview = _PreviewBox(
      label: 'What ${m.viewerName} sees',
      children: [
        Container(
          padding: const EdgeInsets.only(bottom: 10),
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: t.line)),
          ),
          child: Row(
            children: [
              OrbitAvatar(avatar: m.meAvatar, size: 32),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  OrbitText(
                    m.meName,
                    style: t.font.style(size: 14, weight: 600, color: t.ink),
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 14),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: OrbitText(
                        status.isEmpty ? 'no status shown' : status,
                        style: t.mono.style(
                          size: 11,
                          color: status.isEmpty
                              ? t.ink3.withValues(alpha: t.ink3.a * 0.6)
                              : t.ink3,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        _PvBubble(
          'Did you get the photos?',
          out: true,
          time: '09:41',
          read: _b('receipts'),
        ),
        // Its 4px top margin collapses into the bubble's 6px bottom one.
        if (_b('typing'))
          Padding(
            padding: EdgeInsets.zero,
            child: Row(
              children: [
                OrbitText(
                  '${m.meName} is typing',
                  style: t.font
                      .style(size: 12, color: t.accentInk)
                      .copyWith(fontStyle: FontStyle.italic),
                ),
                const SizedBox(width: 6),
                for (var i = 0; i < 3; i++)
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(right: 4),
                    decoration: BoxDecoration(
                      color: t.ink4,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
    final lock = _b('lock');
    return OrbitYouPage(
      title: 'Privacy',
      children: [
        if (m.error != null && ready)
          OrbitInlineNotice(kind: OrbitNoticeKind.error, text: m.error!),
        OrbitHeroCard(
          icon: OrbitIcons.shieldCheck,
          title: 'Your privacy',
          sub: hidden > 0
              ? '$hidden of 2 statuses hidden'
              : 'Everyone can see your status',
          slot: preview,
          pills: [
            OrbitHeroPill(
              icon: OrbitIcons.checks,
              text: 'Receipts ${_b('receipts') ? 'on' : 'off'}',
              tone: _b('receipts') ? null : OrbitPillTone.accent,
            ),
            OrbitHeroPill(
              icon: OrbitIcons.lockSimple,
              text: 'App lock ${lock ? 'on' : 'off'}',
              tone: lock ? OrbitPillTone.ok : OrbitPillTone.warn,
            ),
            if (m.blockedCount > 0)
              OrbitHeroPill(
                icon: OrbitIcons.prohibit,
                text: '${m.blockedCount} blocked',
              ),
          ],
        ),
        if (ready)
          OrbitSection(
            title: 'Who can see',
            footer: 'Orbit applies these on its server, to everyone else.',
            rows: [
              who('lastSeen', 'Last seen', OrbitIcons.clock, 0),
              who('online', 'Online status', OrbitIcons.circle, 3),
              who(
                'groups',
                'Who can add me to groups',
                OrbitIcons.usersThree,
                2,
              ),
            ],
          )
        else ...[
          const OrbitGroupTitle('Who can see'),
          ...notYet(),
        ],
        OrbitSection(
          title: 'Messages',
          footer:
              'Turning receipts or typing off also hides other people’s '
              'from you.',
          rows: [
            sw(
              'receipts',
              'Read receipts',
              'Blue ticks when you have read a message',
              OrbitIcons.checks,
              1,
            ),
            sw(
              'typing',
              'Typing indicator',
              'Show people when you are typing',
              OrbitIcons.chatDots,
              4,
            ),
            OrbitSegRow<String>(
              title: 'Disappearing messages for new chats',
              icon: OrbitIcons.timer,
              iconColor: 5,
              options: _segs(const ['Off', '24 h', '7 d', '90 d']),
              value: _v['timer']! as String,
              onChanged: (v) => _set('timer', v),
            ),
          ],
        ),
        if (ready)
          OrbitSection(
            title: 'Being found',
            rows: [
              sw(
                'byNumber',
                'By phone number',
                'People who have your number can find you',
                OrbitIcons.phone,
                3,
                server: true,
              ),
              sw(
                'byName',
                'By ~Orbit name',
                'People who know your ~name can find you',
                OrbitIcons.at,
                1,
                server: true,
              ),
            ],
          ),
        if (m.silenceUnknownCalls != null)
          OrbitSection(
            title: 'Calls',
            footer:
                'A person is unknown when they are not in your phone\u2019s '
                'contacts, you have not renamed them, and you have never '
                'written to them.',
            rows: [
              sw(
                'silenceCalls',
                'Silence unknown callers',
                'Their calls do not ring. They show in your call history.',
                OrbitIcons.phoneX,
                4,
              ),
            ],
          ),
        OrbitSection(
          title: 'App lock',
          footer: lock ? 'Calls still ring while Orbit is locked.' : '',
          rows: [
            OrbitListRow(
              icon: OrbitIcons.fingerprint,
              iconColor: 0,
              title: 'Lock Orbit',
              sub: m.lockSub,
              end: OrbitRowEnd.toggle,
              on: lock,
              onChanged: (v) => _set('lock', v),
            ),
            if (lock)
              OrbitSegRow<String>(
                title: 'Lock again',
                sub: 'After Orbit has been in the background for',
                options: _segs(const ['Now', '1 min', '5 min', '30 min']),
                value: _v['lockAfter']! as String,
                onChanged: (v) => _set('lockAfter', v),
              ),
          ],
        ),
        OrbitSection(
          title: 'Blocked',
          rows: [
            OrbitListRow(
              leading: SizedBox(
                width: 36,
                child: Center(
                  child: m.blockedAvatar == null
                      ? OrbitIcon(OrbitIcons.prohibit, size: 19, color: t.ink3)
                      : OrbitAvatar(avatar: m.blockedAvatar!, size: 32),
                ),
              ),
              title: m.blockedCount == 1
                  ? '1 blocked person'
                  : '${m.blockedCount} blocked people',
              sub: 'They cannot message or call you',
              end: OrbitRowEnd.chevron,
              onTap: widget.actions.onOpenBlocked ?? _none,
            ),
          ],
        ),
      ],
    );
  }
}

// =========================================================== Notifications

class MutedChatItem {
  const MutedChatItem({
    required this.id,
    required this.title,
    required this.avatar,
    required this.label,
  });

  final String id;
  final String title;
  final HelixAvatarModel avatar;

  /// "Muted for 8 hours" / "Muted".
  final String label;
}

class NotificationsModel {
  const NotificationsModel({
    this.osOff = false,
    this.mutedLoading = false,
    this.mutedFailed = false,
    this.showRingtone = true,
    this.showWakeUps = false,
    this.wakeUps = true,
    this.messages = true,
    this.groups = true,
    this.calls = true,
    this.sound = true,
    this.vibrate = true,
    this.previews = false,
    this.ringtone = phoneRingtoneLabel,
    this.muted = const [],
    this.previewName = 'Nadia Rahman',
    this.previewText = 'Sent the photos from Cox’s Bazar 🌊',
    this.dateLabel = 'Friday, 16 October',
  });

  /// Notifications are off for Orbit in the phone's settings.
  final bool osOff;

  /// The muted chats are still being read, or could not be.
  final bool mutedLoading;
  final bool mutedFailed;

  /// The ringtone row; hidden where a call cannot ring with a chosen sound.
  final bool showRingtone;

  /// The "wake this phone" row; hidden where the server cannot wake the
  /// device at all.
  final bool showWakeUps;
  final bool wakeUps;
  final bool messages;
  final bool groups;
  final bool calls;
  final bool sound;
  final bool vibrate;
  final bool previews;

  /// What a call rings with, in the words the Ringtones page uses for it: the
  /// phone's own ringtone, or the sound pack chosen.
  final String ringtone;
  final List<MutedChatItem> muted;
  final String previewName;
  final String previewText;
  final String dateLabel;
}

class NotificationsActions {
  const NotificationsActions({
    this.onChanged,
    this.onOpenSystemSettings,
    this.onUnmute,
    this.onOpenRingtones,
  });

  /// "messages", "groups", "calls", "sound", "vibrate" or "previews", and its
  /// new value.
  final void Function(String key, bool value)? onChanged;
  final VoidCallback? onOpenSystemSettings;

  /// Unmutes the chat; the page then says "Unmuted".
  final Future<void> Function(String chatId)? onUnmute;

  /// Opens the Ringtones page, which is where the sound is chosen.
  final VoidCallback? onOpenRingtones;
}

/// `notifications`: the alerts, sound and lock screen (with a preview of
/// your lock screen), the ringtone, and muted chats.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({
    super.key,
    required this.model,
    this.actions = const NotificationsActions(),
  });

  final NotificationsModel model;
  final NotificationsActions actions;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late Map<String, bool> _v = _from(widget.model);

  static Map<String, bool> _from(NotificationsModel m) => {
    'wakeups': m.wakeUps,
    'messages': m.messages,
    'groups': m.groups,
    'calls': m.calls,
    'sound': m.sound,
    'vibrate': m.vibrate,
    'previews': m.previews,
  };

  @override
  void didUpdateWidget(NotificationsScreen old) {
    super.didUpdateWidget(old);
    if (old.model != widget.model) _v = _from(widget.model);
  }

  void _set(String key, bool value) {
    setState(() => _v[key] = value);
    widget.actions.onChanged?.call(key, value);
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.model;
    final on = [
      _v['messages']!,
      _v['groups']!,
      _v['calls']!,
    ].where((x) => x).length;
    OrbitListRow sw(
      String key,
      String title,
      String sub,
      OrbitGlyph i,
      int c,
    ) => OrbitListRow(
      icon: i,
      iconColor: c,
      title: title,
      sub: sub,
      end: OrbitRowEnd.toggle,
      on: _v[key]!,
      onChanged: (v) => _set(key, v),
    );
    return OrbitYouPage(
      title: 'Notifications',
      children: [
        if (m.osOff)
          OrbitInlineNotice(
            kind: OrbitNoticeKind.error,
            text:
                'Notifications are turned off for Orbit in your phone’s '
                'settings, so nothing here will make a sound.',
            action: OrbitNoticeAction(
              'Allow notifications',
              widget.actions.onOpenSystemSettings ?? _none,
            ),
          ),
        OrbitHeroCard(
          icon: OrbitIcons.bellRinging,
          title: 'Notifications',
          sub:
              '$on of 3 alerts on · previews '
              '${_v['previews']! ? 'shown' : 'hidden'}',
          // A picture of a lock screen, white on the brand gradient: read
          // out as one line rather than as text to be checked for contrast.
          slot: Semantics(
            container: true,
            label:
                'Your lock screen: '
                '${_v['previews']! ? '${m.previewName}, ${m.previewText}' : 'Orbit, New message'}',
            child: ExcludeSemantics(
              child: _LockPreview(
                title: _v['previews']! ? m.previewName : 'Orbit',
                body: _v['previews']! ? m.previewText : 'New message',
                date: m.dateLabel,
                sound: _v['sound']!,
                vibrate: _v['vibrate']!,
              ),
            ),
          ),
        ),
        const OrbitGroupTitle('Alerts'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: OrbitSpace.gutter),
          child: Row(
            children: [
              for (final (i, (k, icon, label)) in const [
                ('messages', OrbitIcons.chatCircle, 'Messages'),
                ('groups', OrbitIcons.usersThree, 'Groups'),
                ('calls', OrbitIcons.phone, 'Calls'),
              ].indexed) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: _AlertTile(
                    icon: icon,
                    label: label,
                    on: _v[k]!,
                    onTap: () => _set(k, !_v[k]!),
                  ),
                ),
              ],
            ],
          ),
        ),
        _foot(
          'Turning an alert off still delivers the message. It only stays '
          'quiet until you open Orbit.',
        ),
        if (m.showWakeUps)
          OrbitSection(
            title: 'Wake-ups',
            footer:
                'Off, Orbit’s servers do not wake this phone, so nothing '
                'arrives until you open Orbit. It applies to every account '
                'signed in on this phone.',
            rows: [
              sw(
                'wakeups',
                'Wake this phone for new messages',
                'Lets the server wake Orbit when something arrives',
                OrbitIcons.bellRinging,
                3,
              ),
            ],
          ),
        OrbitSection(
          title: 'Sound and lock screen',
          footer:
              'With previews off, a notification only says “New message”. '
              'Orbit’s servers and the push service never see message text '
              'either way.',
          rows: [
            sw(
              'sound',
              'Sound',
              'Your phone’s default notification sound',
              OrbitIcons.speakerHigh,
              4,
            ),
            sw('vibrate', 'Vibrate', '', OrbitIcons.vibrate, 2),
            sw(
              'previews',
              'Show message previews',
              'Who wrote and what they said, on the lock screen',
              OrbitIcons.eye,
              1,
            ),
            if (m.showRingtone)
              OrbitListRow(
                icon: OrbitIcons.phoneCall,
                iconColor: 0,
                title: 'Ringtone',
                sub: 'For incoming calls',
                value: m.ringtone,
                end: OrbitRowEnd.chevron,
                onTap: widget.actions.onOpenRingtones,
              ),
          ],
        ),
        if (m.mutedLoading) ...const [
          OrbitGroupTitle('Muted chats'),
          Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: OrbitPageLoading(),
          ),
        ] else if (m.mutedFailed) ...const [
          OrbitGroupTitle('Muted chats'),
          OrbitInlineNotice(
            kind: OrbitNoticeKind.error,
            text: 'Muted chats could not be loaded.',
          ),
        ] else if (m.muted.isEmpty) ...[
          const OrbitGroupTitle('Muted chats'),
          _foot('No muted chats. Mute a chat from the chat itself.'),
        ] else
          OrbitSection(
            title: 'Muted chats · ${m.muted.length}',
            footer: 'Mute a chat from the chat itself.',
            rows: [
              for (final c in m.muted)
                OrbitListRow(
                  leading: OrbitAvatar(avatar: c.avatar, size: 40),
                  title: c.title,
                  sub: c.label,
                  trailing: OrbitButton(
                    label: 'Unmute',
                    kind: OrbitButtonKind.ghost,
                    onPressed: () async {
                      final unmute = widget.actions.onUnmute;
                      if (unmute == null) return;
                      await unmute(c.id);
                      if (context.mounted) showOrbitToast(context, 'Unmuted');
                    },
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

/// `.alert-tile`: a square (at least 92px) with the icon, the label and
/// On or Off; on, it is `--accent-soft` in `--accent-ink`.
class _AlertTile extends StatelessWidget {
  const _AlertTile({
    required this.icon,
    required this.label,
    required this.on,
    required this.onTap,
  });

  final OrbitGlyph icon;
  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final ink = on ? t.accentInk : t.ink3;
    return Semantics(
      button: true,
      toggled: on,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 92),
          decoration: BoxDecoration(
            color: on ? t.accentSoft : t.surface,
            border: Border.all(color: on ? t.accentLine : t.line),
            borderRadius: BorderRadius.circular(t.rLg),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OrbitIcon(
                icon,
                weight: on ? OrbitIconWeight.fill : null,
                size: 24,
                color: ink,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: t.font.style(size: 13, weight: 600, color: ink),
              ),
              const SizedBox(height: 4),
              Text(
                on ? 'On' : 'Off',
                style: t.mono.style(size: 10.5, weight: 500, color: ink),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// `.lockprev`: your lock screen on the brand gradient: the time, the date,
/// one notification and what it will do.
class _LockPreview extends StatelessWidget {
  const _LockPreview({
    required this.title,
    required this.body,
    required this.date,
    required this.sound,
    required this.vibrate,
  });

  final String title;
  final String body;
  final String date;
  final bool sound;
  final bool vibrate;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final ink = t.onBrand;
    return Container(
      margin: const EdgeInsets.only(top: 14),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: t.brandGradient,
        borderRadius: BorderRadius.circular(18),
      ),
      child: CustomPaint(
        painter: const _Dots(),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
          child: Column(
            children: [
              Text(
                '9:41',
                style: t.font.style(
                  size: 38,
                  weight: 300,
                  color: ink,
                  height: 1,
                  letterSpacingEm: -0.02,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                date,
                style: t.font.style(
                  size: 12,
                  color: ink.withValues(alpha: 0.85),
                ),
              ),
              Container(
                margin: const EdgeInsets.only(top: 14),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: t.glassBg,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: const SizedBox.square(
                        dimension: 28,
                        child: OrbitMark(size: 28),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: OrbitText(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: t.font.style(
                                    size: 13,
                                    weight: 700,
                                    color: t.glassInk,
                                  ),
                                ),
                              ),
                              Text(
                                'now',
                                style: t.font.style(size: 11, color: t.ink3),
                              ),
                            ],
                          ),
                          const SizedBox(height: 1),
                          OrbitText(
                            body,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.font.style(size: 13, color: t.ink2),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Opacity(
                opacity: 0.9,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OrbitIcon(
                      sound ? OrbitIcons.speakerHigh : OrbitIcons.speakerSlash,
                      size: 10.5,
                      color: ink,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '${sound ? 'Sound' : 'Silent'} · ',
                      style: t.mono.style(size: 10.5, color: ink),
                    ),
                    const SizedBox(width: 5),
                    OrbitIcon(
                      vibrate ? OrbitIcons.vibrate : OrbitIcons.deviceMobile,
                      size: 10.5,
                      color: ink,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      vibrate ? 'Vibrate' : 'No vibration',
                      style: t.mono.style(size: 10.5, color: ink),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A 14px grid of faint white dots (the lock preview's backdrop).
class _Dots extends CustomPainter {
  const _Dots();

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = const Color(0x1AFFFFFF);
    for (var y = 7.0; y < size.height; y += 14) {
      for (var x = 7.0; x < size.width; x += 14) {
        canvas.drawCircle(Offset(x, y), 1.1, p);
      }
    }
  }

  @override
  bool shouldRepaint(_Dots old) => false;
}

// =================================================================== Chats

enum TextSizeChoice {
  small('Small', 0.9),
  normal('Default', 1),
  large('Large', 1.15),
  extraLarge('Extra large', 1.3);

  const TextSizeChoice(this.label, this.scale);
  final String label;
  final double scale;
}

enum DownloadWhen {
  never('Never'),
  wifi('Wi-Fi'),
  always('Always');

  const DownloadWhen(this.label);
  final String label;
}

class ChatsSettingsModel {
  const ChatsSettingsModel({
    this.textSize = TextSizeChoice.normal,
    this.enterSends = false,
    this.photos = DownloadWhen.wifi,
    this.voice = DownloadWhen.always,
    this.videos = DownloadWhen.never,
    this.documents = DownloadWhen.never,
    this.linkPreviews,
  });

  final TextSizeChoice textSize;
  final bool enterSends;

  /// Link previews are on; null when the app does not offer them.
  final bool? linkPreviews;
  final DownloadWhen photos;
  final DownloadWhen voice;
  final DownloadWhen videos;
  final DownloadWhen documents;
}

class ChatsSettingsActions {
  const ChatsSettingsActions({
    this.onTextSize,
    this.onEnterSends,
    this.onLinkPreviews,
    this.onDownload,
  });

  final ValueChanged<TextSizeChoice>? onTextSize;
  final ValueChanged<bool>? onEnterSends;
  final ValueChanged<bool>? onLinkPreviews;

  /// "photos", "voice", "videos" or "documents".
  final void Function(String kind, DownloadWhen when)? onDownload;
}

/// `chats-settings`: text size (with a preview), Enter sends, and what
/// downloads by itself.
class ChatsSettingsScreen extends StatefulWidget {
  const ChatsSettingsScreen({
    super.key,
    required this.model,
    this.actions = const ChatsSettingsActions(),
  });

  final ChatsSettingsModel model;
  final ChatsSettingsActions actions;

  @override
  State<ChatsSettingsScreen> createState() => _ChatsSettingsScreenState();
}

class _ChatsSettingsScreenState extends State<ChatsSettingsScreen> {
  late var _size = widget.model.textSize;
  late var _enter = widget.model.enterSends;
  late var _previews = widget.model.linkPreviews ?? false;
  late final Map<String, DownloadWhen> _dl = _downloads(widget.model);

  static Map<String, DownloadWhen> _downloads(ChatsSettingsModel m) => {
    'photos': m.photos,
    'voice': m.voice,
    'videos': m.videos,
    'documents': m.documents,
  };

  @override
  void didUpdateWidget(ChatsSettingsScreen old) {
    super.didUpdateWidget(old);
    // What is saved wins once it has come (the settings load after the
    // first frame).
    final m = widget.model;
    if (old.model != m) {
      _size = m.textSize;
      _enter = m.enterSends;
      _previews = m.linkPreviews ?? false;
      _dl.addAll(_downloads(m));
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.actions;
    OrbitSegRow<DownloadWhen> dl(
      String k,
      OrbitGlyph icon,
      int c,
      String label,
    ) => OrbitSegRow<DownloadWhen>(
      title: label,
      icon: icon,
      iconColor: c,
      options: [for (final w in DownloadWhen.values) OrbitSegment(w, w.label)],
      value: _dl[k]!,
      onChanged: (w) {
        setState(() => _dl[k] = w);
        a.onDownload?.call(k, w);
      },
    );
    return OrbitYouPage(
      title: 'Chats',
      children: [
        OrbitHeroCard(
          icon: OrbitIcons.chatCenteredText,
          title: 'Chats',
          sub:
              'Text ${_size.label.toLowerCase()} · Enter '
              '${_enter ? 'sends' : 'adds a line'}',
          slot: _PreviewBox(
            label: 'Preview',
            children: [
              _PvBubble(
                'Are you still coming to the launch on Friday?',
                out: false,
                time: '21:04',
                scale: _size.scale,
              ),
              _PvBubble(
                'Yes! Wouldn’t miss it.',
                out: true,
                time: '21:06',
                scale: _size.scale,
                read: true,
              ),
            ],
          ),
        ),
        const OrbitGroupTitle('Text size'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: OrbitSpace.gutter),
          child: Row(
            children: [
              for (final (i, s) in TextSizeChoice.values.indexed) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: _SizeButton(
                    choice: s,
                    index: i,
                    on: s == _size,
                    onTap: () {
                      setState(() => _size = s);
                      a.onTextSize?.call(s);
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
        _foot('Multiplies with your phone’s own text size.'),
        OrbitSection(
          title: 'Typing',
          footer: 'On by default on a computer, off on a phone.',
          rows: [
            OrbitListRow(
              icon: OrbitIcons.keyboard,
              iconColor: 7,
              title: 'Enter key sends',
              sub: 'With a keyboard. Otherwise Enter adds a new line',
              end: OrbitRowEnd.toggle,
              on: _enter,
              onChanged: (v) {
                setState(() => _enter = v);
                a.onEnterSends?.call(v);
              },
            ),
          ],
        ),
        if (widget.model.linkPreviews != null)
          OrbitSection(
            title: 'Links',
            footer:
                'Your phone asks the website for its title and description '
                'when you send a link, so the site sees your phone\u2019s '
                'address. Nothing is fetched when you receive a link.',
            rows: [
              OrbitListRow(
                icon: OrbitIcons.linkSimple,
                iconColor: 1,
                title: 'Link previews',
                sub:
                    'Show a card with the page\u2019s title under a link you send',
                end: OrbitRowEnd.toggle,
                on: _previews,
                onChanged: (v) {
                  setState(() => _previews = v);
                  a.onLinkPreviews?.call(v);
                },
              ),
            ],
          ),
        OrbitSection(
          title: 'Download automatically',
          footer:
              'Anything not downloaded automatically downloads when you tap '
              'it. Wi-Fi means Wi-Fi only; Always includes mobile data, up to '
              '10 MB for photos and voice, 25 MB for documents and 50 MB for '
              'videos. Small previews always load, so a chat is never blank.',
          rows: [
            dl('photos', OrbitIcons.image, 2, 'Photos'),
            dl('voice', OrbitIcons.microphone, 4, 'Voice messages'),
            dl('videos', OrbitIcons.videoCamera, 5, 'Videos'),
            dl('documents', OrbitIcons.fileText, 3, 'Documents'),
          ],
        ),
      ],
    );
  }
}

/// `.size-btn`: "Aa" at its size over the name; the chosen one is
/// `--accent-soft` with an `--accent` ring.
class _SizeButton extends StatelessWidget {
  const _SizeButton({
    required this.choice,
    required this.index,
    required this.on,
    required this.onTap,
  });

  final TextSizeChoice choice;
  final int index;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    return Tooltip(
      message: choice.label,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        selected: on,
        label: choice.label,
        excludeSemantics: true,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 74),
            decoration: BoxDecoration(
              color: on ? t.accentSoft : t.surface,
              border: Border.all(color: on ? t.accent : t.line),
              borderRadius: BorderRadius.circular(t.rLg),
              boxShadow: on
                  ? [BoxShadow(color: t.accent, spreadRadius: 1)]
                  : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Aa',
                  style: t.font.style(
                    size: 13 + index * 4.0,
                    weight: 650,
                    color: on ? t.accentInk : t.ink2,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  choice.label,
                  style: t.font.style(
                    size: 10.5,
                    color: on ? t.accentInk : t.ink3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ================================================================= Storage

class StorageChatItem {
  const StorageChatItem({
    required this.id,
    required this.title,
    required this.avatar,
    required this.sizeLabel,
    required this.share,
    required this.mediaLabel,
    required this.documentsLabel,
  });

  final String id;
  final String title;
  final HelixAvatarModel avatar;

  /// "412 MB".
  final String sizeLabel;

  /// Its size against the biggest chat, 0 to 1.
  final double share;
  final String mediaLabel;
  final String documentsLabel;
}

/// Whether the storage figures have been read.
enum StorageStatus { loading, failed, ready }

class StorageModel {
  const StorageModel({
    this.status = StorageStatus.ready,
    required this.totalLabel,
    required this.splitLabel,
    this.messagesShare = 0.15,
    this.mediaShare = 0.62,
    this.filesShare = 0.23,
    this.chats = const [],
    this.downloadSummary = '',
    this.backupOverMobile = false,
  });

  final StorageStatus status;

  /// "1.2 GB on this phone".
  final String totalLabel;

  /// "184 MB messages and keys · 1.0 GB media".
  final String splitLabel;
  final double messagesShare;
  final double mediaShare;
  final double filesShare;
  final List<StorageChatItem> chats;
  final String downloadSummary;
  final bool backupOverMobile;
}

class StorageActions {
  const StorageActions({
    this.onFreeMedia,
    this.onFreeDocuments,
    this.onOpenChatsSettings,
    this.onOpenBackup,
    this.onRetry,
  });

  /// Removes the chat's photos and videos, or documents, keeping its
  /// messages; answers what to say ("412 MB freed", a failure).
  final Future<String?> Function(String chatId)? onFreeMedia;
  final Future<String?> Function(String chatId)? onFreeDocuments;
  final VoidCallback? onOpenChatsSettings;
  final VoidCallback? onOpenBackup;
  final VoidCallback? onRetry;
}

/// `storage`: what Orbit keeps on this phone, the biggest chats, and data
/// use.
class StorageScreen extends StatelessWidget {
  const StorageScreen({
    super.key,
    required this.model,
    this.actions = const StorageActions(),
  });

  final StorageModel model;
  final StorageActions actions;

  // The prototype's own #7C3AED for files, in every theme.
  static const _files = Color(0xFF7C3AED);

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final m = model;
    final a = actions;
    Widget legend(Color c, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: c,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: t.font.style(size: 12, color: t.ink2)),
      ],
    );
    final slot = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label:
              'Storage: ${(m.messagesShare * 100).round()} percent messages, '
              '${((m.mediaShare + m.filesShare) * 100).round()} percent media',
          child: Container(
            height: 12,
            margin: const EdgeInsets.only(top: 16),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(6)),
            child: Row(
              children: [
                Expanded(
                  flex: (m.messagesShare * 1000).round(),
                  child: ColoredBox(color: t.accent),
                ),
                const SizedBox(width: 2),
                Expanded(
                  flex: (m.mediaShare * 1000).round(),
                  child: ColoredBox(color: t.cyan),
                ),
                const SizedBox(width: 2),
                Expanded(
                  flex: (m.filesShare * 1000).round(),
                  child: const ColoredBox(color: _files),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 14,
          runSpacing: 6,
          children: [
            legend(t.accent, 'Messages and keys'),
            legend(t.cyan, 'Photos and videos'),
            legend(_files, 'Files'),
          ],
        ),
      ],
    );
    Future<void> free(Future<String?> Function(String)? run, String id) async {
      final said = run == null ? null : await run(id);
      if (said != null && context.mounted) showOrbitToast(context, said);
    }

    return OrbitYouPage(
      title: 'Storage and data',
      children: [
        if (m.status == StorageStatus.loading) ...const [
          SizedBox(height: 120),
          OrbitPageLoading(),
        ] else if (m.status == StorageStatus.failed)
          OrbitLoadFailed(
            title: 'The storage figures could not be read.',
            onRetry: a.onRetry,
          )
        else
          OrbitHeroCard(
            icon: OrbitIcons.hardDrives,
            title: m.totalLabel,
            sub: m.splitLabel,
            slot: slot,
          ),
        if (m.chats.isNotEmpty) ...[
          const OrbitGroupTitle('Biggest chats'),
          OrbitCard(
            children: [
              for (final c in m.chats)
                OrbitListRow(
                  leading: OrbitAvatar(avatar: c.avatar, size: 40),
                  title: c.title,
                  titleWidget: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      OrbitText(
                        c.title,
                        style: t.font.style(
                          size: OrbitType.body,
                          weight: 520,
                          color: t.ink,
                        ),
                      ),
                      Container(
                        height: 4,
                        margin: const EdgeInsets.only(top: 7),
                        decoration: BoxDecoration(
                          color: t.line,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: c.share.clamp(0, 1),
                          child: Container(
                            decoration: BoxDecoration(
                              color: t.cyan,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  trailing: Text(
                    c.sizeLabel,
                    style: t.mono.style(size: OrbitType.small, color: t.ink3),
                  ),
                  onTap: () => showOrbitSheet(
                    context,
                    title: 'Free up space in ${c.title}',
                    text:
                        'Messages stay. Removed files can be downloaded again '
                        'while the sender’s copy is on the server.',
                    items: [
                      OrbitMenuItem(
                        icon: OrbitIcons.images,
                        label: 'Remove photos and videos · ${c.mediaLabel}',
                        onTap: () => free(a.onFreeMedia, c.id),
                      ),
                      OrbitMenuItem(
                        icon: OrbitIcons.fileText,
                        label: 'Remove documents · ${c.documentsLabel}',
                        onTap: () => free(a.onFreeDocuments, c.id),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          _foot('Tap a chat to free space without deleting its messages.'),
        ],
        OrbitSection(
          title: 'Data use',
          rows: [
            OrbitListRow(
              icon: OrbitIcons.downloadSimple,
              iconColor: 1,
              title: 'Download automatically',
              sub: m.downloadSummary,
              end: OrbitRowEnd.chevron,
              onTap: a.onOpenChatsSettings,
            ),
            OrbitListRow(
              icon: OrbitIcons.cloudArrowUp,
              iconColor: 2,
              title: 'Backup over mobile data',
              sub: m.backupOverMobile ? 'Allowed' : 'Wi-Fi only',
              end: OrbitRowEnd.chevron,
              onTap: a.onOpenBackup,
            ),
          ],
        ),
      ],
    );
  }
}

// ================================================================= Account

class AccountModel {
  const AccountModel({
    required this.name,
    required this.avatar,
    this.loadFailed = false,
    this.busy = false,
    this.notice,
    this.phoneMasked = '',
    this.helixName,
    this.hasPassword = true,
    this.passwordChangedLabel = '',
    this.deviceCount = 1,
    this.sinceLabel = '',
  });

  final String name;
  final HelixAvatarModel avatar;

  /// The account's details could not be read (offline): the hero shows the
  /// name only, with Try again.
  final bool loadFailed;

  /// Exporting or signing out.
  final bool busy;

  /// What the last action said ("The export was ready but could not be
  /// shared from this device.").
  final String? notice;
  final String phoneMasked;
  final String? helixName;
  final bool hasPassword;

  /// "Changed 3 weeks ago".
  final String passwordChangedLabel;
  final int deviceCount;

  /// "Since Sep 2026".
  final String sinceLabel;
}

class AccountActions {
  const AccountActions({
    this.onPassword,
    this.onActivity,
    this.onExport,
    this.onSignOut,
    this.onSwitchAccount,
    this.onExportFirst,
    this.onDelete,
    this.onRetry,
  });

  final VoidCallback? onPassword;
  final VoidCallback? onActivity;

  /// Shares the export; answers what to say when it did not work.
  final Future<String?> Function()? onExport;
  final VoidCallback? onSignOut;

  /// "Switch account" in the sign-out dialog: this account stays on the
  /// phone. Null hides the choice.
  final VoidCallback? onSwitchAccount;

  /// "Export first" in the delete dialog: the export only.
  final Future<String?> Function()? onExportFirst;

  /// Continue to the delete page.
  final VoidCallback? onDelete;
  final VoidCallback? onRetry;
}

/// `account`: who you are, sign-in, your data, and sign out or delete.
class AccountScreen extends StatelessWidget {
  const AccountScreen({
    super.key,
    required this.model,
    this.actions = const AccountActions(),
  });

  final AccountModel model;
  final AccountActions actions;

  @override
  Widget build(BuildContext context) {
    final m = model;
    final a = actions;
    final pass = m.hasPassword;
    final switchHint = a.onSwitchAccount == null
        ? ''
        : ' To keep it here and use another account, switch instead.';
    Future<void> say(Future<String?> Function()? run) async {
      final said = run == null ? null : await run();
      if (said != null && context.mounted) {
        showOrbitToast(context, said, error: true);
      }
    }

    return OrbitYouPage(
      title: 'Account',
      children: [
        if (m.loadFailed)
          OrbitInlineNotice(
            kind: OrbitNoticeKind.error,
            text:
                'Your account details could not be loaded. You may be '
                'offline.',
            action: OrbitNoticeAction('Try again', a.onRetry ?? _none),
          ),
        if (m.notice != null)
          OrbitInlineNotice(kind: OrbitNoticeKind.info, text: m.notice!),
        OrbitHeroCard(
          art: OrbitAvatar(avatar: m.avatar, size: 48),
          title: m.name,
          sub: [
            if (m.phoneMasked.isNotEmpty) m.phoneMasked,
            if ((m.helixName ?? '').isNotEmpty) '~${m.helixName}',
          ].join(' · '),
          pills: [
            if (!m.loadFailed)
              OrbitHeroPill(
                icon: pass ? OrbitIcons.checkCircle : OrbitIcons.warningCircle,
                text: pass ? 'Password set' : 'No password',
                tone: pass ? OrbitPillTone.ok : OrbitPillTone.warn,
              ),
            OrbitHeroPill(
              icon: OrbitIcons.devices,
              text: m.deviceCount == 1
                  ? '1 device'
                  : '${m.deviceCount} devices',
            ),
            if (m.sinceLabel.isNotEmpty)
              OrbitHeroPill(icon: OrbitIcons.calendarBlank, text: m.sinceLabel),
          ],
        ),
        OrbitSection(
          title: 'Sign-in',
          footer:
              'Your password never leaves this phone. Orbit only receives a '
              'key made from it.',
          rows: [
            OrbitListRow(
              icon: OrbitIcons.password,
              iconColor: 0,
              title: pass ? 'Change password' : 'Set a password',
              sub: pass
                  ? m.passwordChangedLabel
                  : 'Sign in on a new phone without another device',
              end: OrbitRowEnd.chevron,
              onTap: a.onPassword,
            ),
            OrbitListRow(
              icon: OrbitIcons.clockCounterClockwise,
              iconColor: 7,
              title: 'Security activity',
              sub: 'Sign-ins, new devices and key changes',
              end: OrbitRowEnd.chevron,
              onTap: a.onActivity,
            ),
          ],
        ),
        OrbitSection(
          title: 'Your data',
          rows: [
            OrbitListRow(
              icon: OrbitIcons.export,
              iconColor: 2,
              title: 'Export my data',
              sub:
                  'Account details, devices and settings. No messages: the '
                  'server never had them readable.',
              end: OrbitRowEnd.chevron,
              onTap: m.busy ? null : () => say(a.onExport),
            ),
          ],
        ),
        OrbitDangerZone(
          rows: [
            OrbitListRow(
              icon: OrbitIcons.signOut,
              title: 'Sign out',
              sub: 'Removes this account and its messages from this phone',
              danger: true,
              onTap: () => showOrbitDialog(
                context,
                title: 'Sign out?',
                text:
                    'Signing out removes this account from this phone and '
                    'deletes its messages, keys and history here. Your other '
                    'devices stay signed in.$switchHint',
                actions: [
                  const OrbitDialogAction('Cancel'),
                  if (a.onSwitchAccount != null)
                    OrbitDialogAction(
                      'Switch account',
                      onPressed: a.onSwitchAccount,
                    ),
                  OrbitDialogAction(
                    'Sign out and remove',
                    kind: OrbitButtonKind.danger,
                    onPressed: a.onSignOut,
                  ),
                ],
              ),
            ),
            OrbitListRow(
              icon: OrbitIcons.trash,
              title: 'Delete my account',
              sub: 'Permanent, for every device',
              danger: true,
              onTap: () => showOrbitDialog(
                context,
                title: 'Delete your account?',
                text:
                    'Your account, devices and server data are deleted for '
                    'good. Want a copy of your account data first?',
                actions: [
                  const OrbitDialogAction('Cancel'),
                  OrbitDialogAction(
                    'Export first',
                    onPressed: () => say(a.onExportFirst),
                  ),
                  OrbitDialogAction(
                    'Continue',
                    kind: OrbitButtonKind.danger,
                    onPressed: a.onDelete,
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

// ================================================================ Accounts

/// One account signed in on this phone.
class AccountsEntry {
  const AccountsEntry({
    required this.id,
    required this.title,
    required this.avatar,
    this.detail = '',
    this.current = false,
    this.unread = 0,
  });

  final String id;

  /// The name, or the masked number.
  final String title;

  /// The masked number under a name, or the server.
  final String detail;
  final HelixAvatarModel avatar;

  /// The account on screen.
  final bool current;

  /// The messages waiting in this account: only the account on screen is
  /// notified, so a number here is how the others say they have something.
  /// Zero shows nothing.
  final int unread;
}

class AccountsModel {
  const AccountsModel({
    this.accounts = const [],
    this.busy = false,
    this.notice,
  });

  /// The account on screen first, then the others, most recent first.
  final List<AccountsEntry> accounts;

  /// Switching or removing: nothing else can start.
  final bool busy;

  /// What the last action said ("The account could not be removed...").
  final String? notice;
}

class AccountsActions {
  const AccountsActions({this.onOpen, this.onAdd, this.onRemove});

  /// Opens another account in place of the one on screen.
  final ValueChanged<String>? onOpen;

  /// Sign-in for one more account; the others stay.
  final VoidCallback? onAdd;

  /// After "Remove ...?": signs that account out of this phone.
  final ValueChanged<String>? onRemove;
}

/// `accounts`: the accounts signed in on this phone. Tapping one opens it;
/// the minus removes it (signs it out here, after asking); Add account
/// signs in one more.
class AccountsScreen extends StatelessWidget {
  const AccountsScreen({
    super.key,
    required this.model,
    this.actions = const AccountsActions(),
  });

  final AccountsModel model;
  final AccountsActions actions;

  @override
  Widget build(BuildContext context) {
    final m = model;
    final a = actions;
    void remove(AccountsEntry e) => showOrbitDialog(
      context,
      title: 'Remove ${e.title}?',
      text:
          'This signs the account out of this phone and deletes its '
          'messages, keys and history here. Its other devices stay signed '
          'in, and you can sign in here again later.',
      actions: [
        const OrbitDialogAction('Cancel'),
        OrbitDialogAction(
          'Remove',
          kind: OrbitButtonKind.danger,
          onPressed: () => a.onRemove?.call(e.id),
        ),
      ],
    );

    return OrbitYouPage(
      title: 'Accounts',
      children: [
        if (m.notice != null)
          OrbitInlineNotice(kind: OrbitNoticeKind.error, text: m.notice!),
        OrbitSection(
          title: 'On this phone',
          footer:
              'Each account keeps its own messages and keys. Only the account '
              'in use is notified of new messages; the others show how many '
              'are waiting, and a call rings whoever it comes for. The app '
              'lock covers all of them.',
          rows: [
            for (final e in m.accounts)
              OrbitListRow(
                leading: OrbitAvatar(avatar: e.avatar, size: 40),
                title: e.title,
                sub: e.detail,
                value: e.current ? 'In use' : '',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (e.unread > 0) ...[
                      OrbitBadge(count: e.unread),
                      const SizedBox(width: 6),
                    ],
                    OrbitIconButton(
                      icon: OrbitIcons.userMinus,
                      tooltip: 'Remove ${e.title}',
                      onPressed: m.busy ? null : () => remove(e),
                    ),
                  ],
                ),
                onTap: e.current || m.busy ? null : () => a.onOpen?.call(e.id),
              ),
            OrbitListRow(
              icon: OrbitIcons.userCirclePlus,
              iconColor: 2,
              title: 'Add account',
              sub: 'Sign in with another number',
              accent: true,
              onTap: m.busy ? null : a.onAdd,
            ),
          ],
        ),
      ],
    );
  }
}
