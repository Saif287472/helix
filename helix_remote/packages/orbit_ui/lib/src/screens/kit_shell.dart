import 'package:flutter/material.dart';

import 'package:orbit_ui/src/components/bars.dart';
import 'package:orbit_ui/src/components/button.dart';
import 'package:orbit_ui/src/components/codes.dart';
import 'package:orbit_ui/src/components/fab.dart';
import 'package:orbit_ui/src/components/fields.dart';
import 'package:orbit_ui/src/components/icon_button.dart';
import 'package:orbit_ui/src/components/list_rows.dart';
import 'package:orbit_ui/src/components/page_parts.dart';
import 'package:orbit_ui/src/icons/orbit_glyph.dart';
import 'package:orbit_ui/src/icons/orbit_icons.dart';
import 'package:orbit_ui/src/models/view_models.dart';
import 'package:orbit_ui/src/screens/kit_sheet.dart';
import 'package:orbit_ui/src/theme/orbit_metrics.dart';
import 'package:orbit_ui/src/theme/orbit_tokens.dart';

/// `kit-shell` (`prototype/js/screens/states.js`): the parts pages are built
/// from, section for section as the prototype's sheet draws them.
class KitShellScreen extends StatefulWidget {
  const KitShellScreen({super.key});

  @override
  State<KitShellScreen> createState() => _KitShellScreenState();
}

class _KitShellScreenState extends State<KitShellScreen> {
  var _seg1 = 'create';
  var _seg2 = 'privacy';
  var _crash = true;
  var _tab1 = 'chats';
  var _tab2 = 'calls';

  static const _me = HelixAvatarModel(name: 'Hasan', colorIndex: 0);

  void _tap() {}

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    Widget frame(Widget child, {double top = 0}) => Padding(
      padding: EdgeInsets.only(top: top),
      child: OrbitKitFrame(
        padding: EdgeInsets.zero,
        background: t.bg,
        child: child,
      ),
    );
    Widget search(String value, String hint) => OrbitAppBar(
      leadTooltip: 'Close search',
      onLead: _tap,
      background: t.bg,
      rule: false,
      titleWidget: OrbitSearchField(hint: hint, initialValue: value),
    );
    Widget dock(String tab, ValueChanged<String> pick) => SizedBox(
      height: 120,
      child: OrbitDockArea(
        dock: OrbitDock(
          items: [
            OrbitDockItem(
              icon: OrbitIcons.chatsCircle,
              label: 'Chats',
              on: tab == 'chats',
              onTap: () => pick('chats'),
            ),
            OrbitDockItem(
              icon: OrbitIcons.phone,
              label: 'Calls',
              on: tab == 'calls',
              onTap: () => pick('calls'),
            ),
          ],
        ),
        fab: OrbitFab(
          icon: tab == 'chats'
              ? OrbitIcons.chatCircleDots
              : OrbitIcons.phonePlus,
          iconWeight: OrbitIconWeight.bold,
          tooltip: tab == 'chats' ? 'New chat' : 'New call',
          size: 62,
          onPressed: _tap,
        ),
      ),
    );
    return OrbitKitPage(
      title: 'Shell',
      intro:
          'What pages are built from: fields, choices, notices, codes, cards '
          'of rows, the bars at the top and the dock at the bottom.',
      children: [
        const OrbitKitLabel('Search field'),
        frame(
          Column(
            children: [
              search('', 'Search chats, messages and people'),
              search('Nadia', 'Search people'),
            ],
          ),
        ),
        const OrbitKitLabel('Text fields'),
        OrbitCard(
          dividers: false,
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 2),
          children: [
            const OrbitTextField(
              label: 'Name',
              initialValue: 'Hasan',
              maxLength: 50,
              counter: true,
              hint: 'How people see you',
            ),
            const OrbitTextField(
              label: 'Phone number',
              prefix: '+880',
              hint: '1711 000001',
              keyboardType: TextInputType.phone,
              helper: 'With its country code',
            ),
            const OrbitTextField(
              label: 'Password',
              initialValue: 'secret',
              obscure: true,
              eye: true,
            ),
            OrbitTextField(
              label: 'Invite or recovery code',
              hint: 'HLX-INV-… or HLX-REC-…',
              mono: true,
              onPaste: _tap,
            ),
            const OrbitTextField(
              label: 'Description',
              initialValue: 'Family news and plans.',
              maxLength: 500,
              rows: 3,
            ),
            const OrbitTextField(
              label: 'Group name',
              error: 'Enter a group name of 1 to 100 characters.',
              maxLength: 100,
            ),
          ],
        ),
        const OrbitKitLabel('Segmented control'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: OrbitSpace.gutter),
          child: OrbitSegmented(
            options: const [
              OrbitSegment('create', 'Create'),
              OrbitSegment('restore', 'Restore'),
            ],
            value: _seg1,
            onChanged: (v) => setState(() => _seg1 = v),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            OrbitSpace.gutter,
            10,
            OrbitSpace.gutter,
            0,
          ),
          child: OrbitSegmented(
            options: const [
              OrbitSegment('terms', 'Terms', icon: OrbitIcons.fileText),
              OrbitSegment('privacy', 'Privacy', icon: OrbitIcons.shieldCheck),
            ],
            value: _seg2,
            onChanged: (v) => setState(() => _seg2 = v),
          ),
        ),
        const OrbitKitLabel('Notices'),
        const OrbitInlineNotice(
          kind: OrbitNoticeKind.info,
          text:
              'Saved on this device. Your phone did not let Orbit change your '
              'contacts.',
        ),
        const OrbitInlineNotice(
          kind: OrbitNoticeKind.success,
          text: 'Recovery backup created.',
        ),
        const OrbitInlineNotice(
          kind: OrbitNoticeKind.warning,
          text:
              'Check that the new device shows the same number. Do not approve '
              'a device you are not holding.',
        ),
        OrbitInlineNotice(
          kind: OrbitNoticeKind.error,
          text: 'That was not saved. Check your connection and try again.',
          action: OrbitNoticeAction('Try again', _tap),
        ),
        const OrbitKitLabel('Banners'),
        OrbitBanner(
          kind: OrbitNoticeKind.info,
          icon: OrbitIcons.addressBook,
          title: 'Find your contacts on Orbit',
          text:
              'Orbit compares scrambled versions of your contacts’ numbers to '
              'find who is on Orbit. Your contacts never leave your phone.',
          actions: [OrbitNoticeAction('Allow contacts', _tap)],
        ),
        // Two banners' 8px margins meet and collapse to one 8px gap.
        const OrbitBanner(
          margin: EdgeInsets.fromLTRB(
            OrbitSpace.gutter,
            0,
            OrbitSpace.gutter,
            8,
          ),
          kind: OrbitNoticeKind.warning,
          icon: OrbitIcons.shieldWarning,
          title: 'Safety number changed',
          text:
              'Your safety number with Nadia Rahman changed. That usually '
              'means they got a new phone or reinstalled Orbit. It can also '
              'mean someone is interfering. Compare safety numbers with them '
              'to be sure.',
        ),
        const OrbitKitLabel('Page intro and empty state'),
        frame(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const OrbitPageIntro(
                title: 'Is this your account?',
                text:
                    'Your other device approved this one. Check that this is '
                    'your account before Orbit gives this phone its keys.',
              ),
              OrbitEmptyState(
                icon: OrbitIcons.archive,
                title: 'All your chats are archived',
                text: 'They are kept in Archived chats, out of the way.',
                action: OrbitButton(
                  label: 'Open archived chats',
                  kind: OrbitButtonKind.secondary,
                  icon: OrbitIcons.archive,
                  onPressed: _tap,
                ),
              ),
            ],
          ),
        ),
        const OrbitKitLabel('Codes'),
        const OrbitCodeBox(
          label: 'Check number',
          code: '72 914',
          size: OrbitCodeSize.huge,
        ),
        OrbitCard(
          dividers: false,
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
          children: [
            const OrbitCodeBox(
              label: 'Shown only now',
              code: 'K7QD-M2XP-9RWA-H4TF-B8NC-3ZLE',
              size: OrbitCodeSize.secret,
              margin: EdgeInsets.only(top: 10),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                children: [
                  Expanded(
                    child: OrbitButton(
                      label: 'Copy',
                      kind: OrbitButtonKind.secondary,
                      icon: OrbitIcons.copy,
                      block: true,
                      onPressed: _tap,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OrbitButton(
                      label: 'Share',
                      kind: OrbitButtonKind.secondary,
                      icon: OrbitIcons.shareNetwork,
                      block: true,
                      onPressed: _tap,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const OrbitKitLabel('QR code'),
        const Padding(
          padding: EdgeInsets.only(top: 18, bottom: 6),
          child: Center(
            child: OrbitQrCard(child: OrbitQr(seed: 'safety-nadia')),
          ),
        ),
        const OrbitKitLabel('Progress'),
        const OrbitProgress(value: 0.4),
        const OrbitProgress(),
        const OrbitKitLabel('Section of rows'),
        OrbitSection(
          rows: [
            OrbitListRow(
              icon: OrbitIcons.usersThree,
              iconColor: 0,
              title: 'Group info',
              sub: 'Members, invite links and group settings',
              end: OrbitRowEnd.chevron,
              onTap: _tap,
            ),
            OrbitListRow(
              icon: OrbitIcons.images,
              iconColor: 2,
              title: 'Media, links and docs',
              end: OrbitRowEnd.chevron,
              onTap: _tap,
            ),
            OrbitListRow(
              icon: OrbitIcons.timer,
              iconColor: 5,
              title: 'Disappearing messages',
              value: 'Off',
              end: OrbitRowEnd.chevron,
              onTap: _tap,
            ),
            OrbitListRow(
              icon: OrbitIcons.eraser,
              title: 'Clear chat',
              danger: true,
              onTap: _tap,
            ),
          ],
        ),
        OrbitSection(
          title: 'Diagnostics',
          rows: [
            OrbitListRow(
              title: 'Send crash reports',
              sub: 'Only the error’s type, the app version and the platform',
              end: OrbitRowEnd.toggle,
              on: _crash,
              onChanged: (v) => setState(() => _crash = v),
            ),
          ],
          footer:
              'A crash report never contains messages, names, numbers or keys.',
        ),
        OrbitDangerZone(
          rows: [
            OrbitListRow(
              icon: OrbitIcons.signOut,
              title: 'Sign out all other devices',
              danger: true,
              onTap: _tap,
            ),
          ],
        ),
        const OrbitKitLabel('App bars'),
        frame(OrbitAppBar(title: 'Message info', onLead: _tap)),
        frame(
          OrbitAppBar(
            title: 'Join requests',
            onLead: _tap,
            actions: [
              OrbitIconButton(
                icon: OrbitIcons.dotsThreeVertical,
                tooltip: 'More options',
                onPressed: _tap,
              ),
            ],
          ),
          top: 10,
        ),
        frame(
          OrbitAppBar(
            title: '2 selected',
            selection: true,
            lead: OrbitAppBarLead.close,
            leadTooltip: 'Cancel selection',
            onLead: _tap,
            actions: [
              for (final (icon, tip) in const [
                (OrbitIcons.archive, 'Archive chats'),
                (OrbitIcons.trash, 'Delete chats'),
                (OrbitIcons.dotsThreeVertical, 'More options'),
              ])
                OrbitIconButton(
                  icon: icon,
                  tooltip: tip,
                  color: t.onInverse,
                  onPressed: _tap,
                ),
            ],
          ),
          top: 10,
        ),
        const OrbitKitLabel('Tab header'),
        frame(
          OrbitTabHeader(
            actions: [
              OrbitIconButton(
                icon: OrbitIcons.magnifyingGlass,
                tooltip: 'Search',
                onPressed: _tap,
              ),
              OrbitIconButton(
                icon: OrbitIcons.dotsThreeVertical,
                tooltip: 'More options',
                onPressed: _tap,
              ),
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: OrbitMePicture(
                  avatar: _me,
                  attention: true,
                  onPressed: _tap,
                ),
              ),
            ],
          ),
        ),
        const OrbitKitLabel('Dock'),
        frame(dock(_tab1, (v) => setState(() => _tab1 = v))),
        frame(dock(_tab2, (v) => setState(() => _tab2 = v)), top: 10),
      ],
    );
  }
}
