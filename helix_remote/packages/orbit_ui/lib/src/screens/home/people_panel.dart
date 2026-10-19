import 'package:flutter/material.dart';

import 'package:orbit_ui/src/components/avatar.dart';
import 'package:orbit_ui/src/components/chat_rows.dart';
import 'package:orbit_ui/src/components/icon_button.dart';
import 'package:orbit_ui/src/components/list_rows.dart';
import 'package:orbit_ui/src/components/page_parts.dart';
import 'package:orbit_ui/src/components/spinner.dart';
import 'package:orbit_ui/src/icons/orbit_glyph.dart';
import 'package:orbit_ui/src/icons/orbit_icons.dart';
import 'package:orbit_ui/src/models/view_models.dart';
import 'package:orbit_ui/src/screens/home/home_models.dart';
import 'package:orbit_ui/src/theme/orbit_metrics.dart';
import 'package:orbit_ui/src/theme/orbit_text.dart';
import 'package:orbit_ui/src/theme/orbit_tokens.dart';

/// `peoplePanel` (`prototype/js/screens/home.js`): the people part of the
/// Chats search, the Calls search and the People page.
///
/// With nothing typed: the contacts card (or the Refresh row), then everyone
/// you know under "People on Orbit". With a search: the lookup row or its
/// result, a hint for an incomplete number, then Groups and People that
/// match, or "No matches".
class PeoplePanel extends StatelessWidget {
  const PeoplePanel({
    super.key,
    required this.model,
    this.actions = const PeoplePanelActions(),
  });

  final PeoplePanelModel model;
  final PeoplePanelActions actions;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final m = model;
    final a = actions;
    final browsing = m.query.trim().isEmpty;
    final out = <Widget>[];
    if (browsing) {
      switch (m.contacts) {
        case ContactsCard.ask || ContactsCard.openSettings:
          final settings = m.contacts == ContactsCard.openSettings;
          out.add(
            OrbitBanner(
              kind: OrbitNoticeKind.info,
              icon: OrbitIcons.addressBook,
              title: 'Find your contacts on Orbit',
              text:
                  'Orbit compares scrambled versions of your contacts’ numbers '
                  'to find who is on Orbit. Your contacts never leave your '
                  'phone.',
              actions: [
                OrbitNoticeAction(
                  settings ? 'Open settings' : 'Allow contacts',
                  () => settings
                      ? a.onOpenContactsSettings?.call()
                      : a.onAllowContacts?.call(),
                ),
              ],
            ),
          );
        case ContactsCard.refresh:
          final sub = switch (m.refresh) {
            PhoneBookStatus.checking => 'Checking your contacts...',
            PhoneBookStatus.limit =>
              'Today’s limit for checking contacts is used up. Orbit will try '
                  'again tomorrow.',
            PhoneBookStatus.done =>
              '${m.found} contact${m.found == 1 ? ' is' : 's are'} on Orbit.',
            PhoneBookStatus.failed =>
              'Your contacts could not be checked. Orbit will try again '
                  'later.',
            PhoneBookStatus.idle =>
              'Check which of your contacts are on Orbit.',
          };
          out.add(
            OrbitCard(
              margin: const EdgeInsets.fromLTRB(
                OrbitSpace.gutter,
                8,
                OrbitSpace.gutter,
                0,
              ),
              children: [
                OrbitListRow(
                  icon: OrbitIcons.arrowsClockwise,
                  iconColor: 0,
                  title: 'Refresh contacts',
                  sub: sub,
                  onTap: m.refresh == PhoneBookStatus.checking
                      ? null
                      : () => a.onRefreshContacts?.call(),
                ),
              ],
            ),
          );
        case ContactsCard.hidden:
      }
      if (m.empty == PanelEmpty.nobodyYet) {
        out.add(
          const OrbitEmptyState(
            icon: OrbitIcons.userCircleDashed,
            title: 'Nobody yet',
            text: 'Type a phone number or a ~name to find someone.',
          ),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: out,
        );
      }
      out
        ..add(OrbitListLabel(m.peopleLabel, count: m.people.length))
        ..addAll(m.people.map((p) => _PersonRow(p, mode: m.mode, actions: a)));
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: out,
      );
    }

    if (m.lookup != LookupView.idle) {
      out.add(_LookupState(m.lookup));
    } else {
      switch (m.lookupPrompt) {
        case FindNumber(:final shown):
          out.add(
            _LookupRow(
              label: shown,
              icon: OrbitIcons.dotsNine,
              sub: 'Only a scrambled version of the number is sent.',
              onTap: a.onLookUp,
            ),
          );
        case FindName(:final name):
          out.add(
            _LookupRow(
              label: name,
              icon: OrbitIcons.at,
              sub: 'Looks up this ~Orbit name once.',
              onTap: a.onLookUp,
            ),
          );
        case NeedFullNumber():
          out.add(
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: OrbitSpace.gutter,
                vertical: 10,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: OrbitIcon(
                      OrbitIcons.info,
                      size: OrbitType.caption,
                      color: t.ink3,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OrbitText(
                      'Type the whole number. Without a country code it is '
                      'read as a Bangladesh number (+880).',
                      style: t.font.style(
                        size: OrbitType.caption,
                        color: t.ink3,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        case NoLookup():
      }
    }
    if (m.groups.isNotEmpty) {
      out.add(const OrbitListLabel('Groups'));
      for (final g in m.groups) {
        out.add(_GroupRow(g, onTap: () => a.onOpenGroup?.call(g.groupId)));
      }
    }
    if (m.people.isNotEmpty) {
      out.add(const OrbitListLabel('People'));
      out.addAll(m.people.map((p) => _PersonRow(p, mode: m.mode, actions: a)));
    }
    if (m.empty == PanelEmpty.noMatches) {
      out.add(
        OrbitEmptyState(
          icon: OrbitIcons.magnifyingGlass,
          title: 'No matches',
          text: 'Nobody you know matches “${m.query.trim()}”.',
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: out,
    );
  }
}

/// A chat-row-shaped line: a 52px leading part, a name line and a small
/// line under it, an optional end.
class _Line extends StatelessWidget {
  const _Line({
    required this.lead,
    required this.name,
    required this.sub,
    this.end = const [],
    this.onTap,
    this.onLongPress,
  });

  final Widget lead;
  final Widget name;
  final Widget sub;
  final List<Widget> end;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        hoverColor: t.hover,
        highlightColor: t.pressed,
        splashFactory: NoSplash.splashFactory,
        child: SizedBox(
          height: orbitRowHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: OrbitSpace.gutter),
            child: Row(
              children: [
                lead,
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [name, const SizedBox(height: 3), sub],
                  ),
                ),
                if (end.isNotEmpty) ...[const SizedBox(width: 14), ...end],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

TextStyle _nameStyle(OrbitTokens t) => t.font.style(
  size: OrbitType.headline,
  weight: 600,
  color: t.ink,
  letterSpacingEm: -0.01,
);

/// A person: their picture, name (with the seal when verified) and number
/// or ~name in mono 12px; "Blocked" in `--danger`. In the Calls search, a
/// voice and a video button at the end.
class _PersonRow extends StatelessWidget {
  const _PersonRow(this.p, {required this.mode, required this.actions});

  final HelixPersonItem p;
  final PeopleSearchMode mode;
  final PeoplePanelActions actions;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final name = p.names.display;
    final sub = p.blocked ? 'Blocked' : (p.names.secondary ?? p.about ?? '');
    return _Line(
      lead: OrbitAvatar(avatar: p.avatar, size: 52),
      name: Row(
        children: [
          Flexible(
            child: OrbitText(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _nameStyle(t),
            ),
          ),
          if (p.verified) ...[
            const SizedBox(width: 5),
            OrbitIcon(
              OrbitIcons.sealCheck,
              weight: OrbitIconWeight.fill,
              size: 15,
              color: t.accent,
            ),
          ],
        ],
      ),
      sub: OrbitText(
        sub,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: p.blocked
            ? t.font.style(size: 12, color: t.danger)
            : t.mono.style(size: 12, color: t.ink3, letterSpacingEm: 0.02),
      ),
      end: mode == PeopleSearchMode.calls
          ? [
              OrbitIconButton(
                icon: OrbitIcons.phone,
                tooltip: 'Voice call $name',
                tone: OrbitIconButtonTone.accent,
                onPressed: () => actions.onCallPerson?.call(p.id, video: false),
              ),
              OrbitIconButton(
                icon: OrbitIcons.videoCamera,
                tooltip: 'Video call $name',
                tone: OrbitIconButtonTone.accent,
                onPressed: () => actions.onCallPerson?.call(p.id, video: true),
              ),
            ]
          : const [],
      onTap: () => actions.onOpenPerson?.call(p.id),
      onLongPress: () => actions.onOpenContactInfo?.call(p.id),
    );
  }
}

class _GroupRow extends StatelessWidget {
  const _GroupRow(this.g, {required this.onTap});

  final PanelGroup g;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    return _Line(
      lead: OrbitAvatar(avatar: g.avatar, size: 52),
      name: OrbitText(
        g.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: _nameStyle(t),
      ),
      sub: OrbitText(
        'Group',
        style: t.font.style(size: OrbitType.small, color: t.ink3),
      ),
      onTap: onTap,
    );
  }
}

/// "Find … on Orbit": a 52px `--accent-soft` tile with a bold icon.
class _LookupRow extends StatelessWidget {
  const _LookupRow({
    required this.label,
    required this.icon,
    required this.sub,
    this.onTap,
  });

  final String label;
  final OrbitGlyph icon;
  final String sub;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    return _Line(
      lead: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: t.accentSoft,
          borderRadius: BorderRadius.circular(52 * t.avatarR / 100),
        ),
        child: Center(
          child: OrbitIcon(
            icon,
            weight: OrbitIconWeight.bold,
            size: 52 * 0.46,
            color: t.accent,
          ),
        ),
      ),
      name: OrbitText(
        'Find $label on Orbit',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: _nameStyle(t),
      ),
      sub: OrbitText(
        sub,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: t.font.style(size: OrbitType.small, color: t.ink3),
      ),
      onTap: onTap,
    );
  }
}

/// `.lookup-state`: what a lookup came back with. A 52px `--field` tile with
/// the icon at 22px in `--ink-3`, 14px before the title (weight 600) and its
/// explanation at `--t-caption` in `--ink-3`; 10px 16px in.
class _LookupState extends StatelessWidget {
  const _LookupState(this.view);

  final LookupView view;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final (icon, title, sub) = switch (view) {
      LookupView.searching => (
        OrbitIcons.spinnerGap,
        'Looking on Orbit...',
        '',
      ),
      LookupView.notFound => (
        OrbitIcons.userCircleDashed,
        'Not on Orbit',
        'Nobody on Orbit matches that, or they do not let people find them '
            'this way.',
      ),
      LookupView.self => (
        OrbitIcons.userCircle,
        'That is you',
        'This is your own account.',
      ),
      LookupView.rateLimited => (
        OrbitIcons.hourglassMedium,
        'Too many lookups',
        'You have looked up as many numbers as Orbit allows today. Try again '
            'tomorrow.',
      ),
      LookupView.offline => (
        OrbitIcons.wifiSlash,
        'No connection',
        'Check your connection and try again.',
      ),
      _ => (
        OrbitIcons.warningCircle,
        'Could not look this up',
        'Something went wrong. Try again in a moment.',
      ),
    };
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: OrbitSpace.gutter,
          vertical: 10,
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: t.field,
                borderRadius: BorderRadius.circular(52 * t.avatarR / 100),
              ),
              child: Center(
                child: view == LookupView.searching
                    ? OrbitSpinner(size: 22, color: t.ink3)
                    : OrbitIcon(icon, size: 22, color: t.ink3),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  OrbitText(
                    title,
                    style: t.font.style(
                      size: OrbitType.body,
                      weight: 600,
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
      ),
    );
  }
}
