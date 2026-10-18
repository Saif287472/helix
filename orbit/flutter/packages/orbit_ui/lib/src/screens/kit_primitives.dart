import 'package:flutter/material.dart';

import 'package:orbit_ui/src/components/avatar.dart';
import 'package:orbit_ui/src/components/button.dart';
import 'package:orbit_ui/src/components/chip_tag.dart';
import 'package:orbit_ui/src/components/fab.dart';
import 'package:orbit_ui/src/components/icon_button.dart';
import 'package:orbit_ui/src/components/toggles.dart';
import 'package:orbit_ui/src/icons/orbit_glyph.dart';
import 'package:orbit_ui/src/icons/orbit_icons.dart';
import 'package:orbit_ui/src/models/view_models.dart';
import 'package:orbit_ui/src/screens/kit_sheet.dart';
import 'package:orbit_ui/src/theme/orbit_tokens.dart';
import 'package:orbit_ui/src/theme/pattern_painter.dart';

/// `kit-primitives` (`prototype/js/screens/states.js`): every primitive in
/// the states the prototype draws, for the compare tool. Section for section
/// the same as the prototype's sheet.
class KitPrimitivesScreen extends StatefulWidget {
  const KitPrimitivesScreen({super.key});

  @override
  State<KitPrimitivesScreen> createState() => _KitPrimitivesScreenState();
}

class _KitPrimitivesScreenState extends State<KitPrimitivesScreen> {
  var _switchA = false;
  var _switchB = true;
  var _checkA = false;
  var _checkB = true;
  var _chip = 0;

  // `Data.av(person)`: the display name, seeded by the person's id.
  static HelixAvatarModel _person(String name, String seed) => HelixAvatarModel(
    name: name,
    colorIndex: HelixAvatarModel.colorIndexFor(seed),
  );

  static final _nadia = _person('Nadia Rahman', 'nadia');
  static final _arif = _person('Arif Hossain', 'arif');
  static final _tanvir = _person('Tanvir Ahmed', 'tanvir');
  static final _family = HelixAvatarModel(
    name: 'Family',
    colorIndex: HelixAvatarModel.colorIndexFor('family'),
    isGroup: true,
  );

  void _tap() {}

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    Widget row(List<Widget> items, double gap) => Wrap(
      spacing: gap,
      runSpacing: gap,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: items,
    );
    return OrbitKitPage(
      title: 'Primitives',
      intro:
          'Core primitive components: buttons, avatars, chips, tags, switches '
          "and checkboxes, and the theme's chat pattern.",
      children: [
        const OrbitKitLabel('Icon buttons'),
        OrbitKitFrame(
          padding: const EdgeInsets.all(12),
          child: row([
            OrbitIconButton(
              icon: OrbitIcons.bell,
              tooltip: 'Mute',
              onPressed: _tap,
            ),
            OrbitIconButton(
              icon: OrbitIcons.magnifyingGlass,
              tooltip: 'Search',
              tone: OrbitIconButtonTone.accent,
              onPressed: _tap,
            ),
            OrbitIconButton(
              icon: OrbitIcons.trash,
              tooltip: 'Delete',
              tone: OrbitIconButtonTone.danger,
              onPressed: _tap,
            ),
            OrbitIconButton(
              icon: OrbitIcons.eye,
              tooltip: 'Show',
              small: true,
              onPressed: _tap,
            ),
          ], 12),
        ),
        const OrbitKitLabel('Buttons'),
        OrbitKitFrame(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              row([
                OrbitButton(label: 'Primary', onPressed: _tap),
                OrbitButton(
                  label: 'Ink',
                  kind: OrbitButtonKind.ink,
                  onPressed: _tap,
                ),
                OrbitButton(
                  label: 'Secondary',
                  kind: OrbitButtonKind.secondary,
                  onPressed: _tap,
                ),
                OrbitButton(
                  label: 'Ghost',
                  kind: OrbitButtonKind.ghost,
                  onPressed: _tap,
                ),
                OrbitButton(
                  label: 'Danger',
                  kind: OrbitButtonKind.danger,
                  onPressed: _tap,
                ),
              ], 8),
              const SizedBox(height: 10),
              row([
                OrbitButton(label: 'Sending', busy: true, onPressed: _tap),
                const OrbitButton(
                  label: 'Disabled',
                  kind: OrbitButtonKind.secondary,
                  onPressed: null,
                ),
                OrbitButton(
                  label: 'With icon',
                  kind: OrbitButtonKind.secondary,
                  icon: OrbitIcons.plus,
                  iconWeight: OrbitIconWeight.regular,
                  onPressed: _tap,
                ),
              ], 8),
            ],
          ),
        ),
        const OrbitKitLabel('Floating action button'),
        OrbitKitFrame(
          padding: const EdgeInsets.all(14),
          child: Align(
            alignment: Alignment.centerLeft,
            child: OrbitFab(
              icon: OrbitIcons.pencilSimpleLine,
              iconWeight: OrbitIconWeight.regular,
              tooltip: 'New chat',
              onPressed: _tap,
            ),
          ),
        ),
        const OrbitKitLabel('Avatars'),
        OrbitKitFrame(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              row([
                // The sheet asks for the online dot, but Data.av carries no
                // online state, so the prototype draws none either.
                OrbitAvatar(avatar: _nadia),
                OrbitAvatar(avatar: _arif),
                OrbitAvatar(avatar: _family),
                OrbitAvatar(avatar: _tanvir, check: true),
              ], 10),
              const SizedBox(height: 12),
              row([
                for (final size in const [32.0, 40.0, 48.0, 56.0])
                  OrbitAvatar(avatar: _nadia, size: size),
              ], 10),
            ],
          ),
        ),
        const OrbitKitLabel('Chips and tags'),
        OrbitKitFrame(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              row([
                OrbitChip(
                  label: 'All',
                  on: _chip == 0,
                  onTap: () => setState(() => _chip = 0),
                ),
                OrbitChip(
                  label: 'Unread',
                  count: 3,
                  on: _chip == 1,
                  onTap: () => setState(() => _chip = 1),
                ),
                OrbitChip(
                  label: 'Groups',
                  on: _chip == 2,
                  onTap: () => setState(() => _chip = 2),
                ),
              ], 8),
              const SizedBox(height: 12),
              row(const [
                OrbitTag(label: 'Default'),
                OrbitTag(label: 'E2E', tone: OrbitTagTone.accent),
                OrbitTag(label: 'Verified', tone: OrbitTagTone.success),
                OrbitTag(label: 'Expiring', tone: OrbitTagTone.warning),
                OrbitTag(label: 'Revoked', tone: OrbitTagTone.danger),
              ], 8),
            ],
          ),
        ),
        const OrbitKitLabel('Switches and checkboxes'),
        OrbitKitFrame(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              row([
                OrbitSwitch(
                  on: _switchA,
                  label: 'Off',
                  onChanged: (v) => setState(() => _switchA = v),
                ),
                OrbitSwitch(
                  on: _switchB,
                  label: 'On',
                  onChanged: (v) => setState(() => _switchB = v),
                ),
              ], 10),
              const SizedBox(height: 6),
              OrbitCheckbox(
                label: 'Keep me signed in on this computer',
                on: _checkA,
                onChanged: (v) => setState(() => _checkA = v),
              ),
              const SizedBox(height: 6),
              OrbitCheckbox(
                label: 'I have read the Terms',
                on: _checkB,
                onChanged: (v) => setState(() => _checkB = v),
              ),
            ],
          ),
        ),
        const OrbitKitLabel('Chat pattern'),
        // `.timeline` at 140px: --chat-bg with the theme's pattern.
        OrbitKitFrame(
          padding: EdgeInsets.zero,
          background: t.bg,
          child: SizedBox(
            height: 140,
            child: OrbitPatternBackground(
              pattern: t.chatPattern,
              color: t.chatBg,
            ),
          ),
        ),
      ],
    );
  }
}
