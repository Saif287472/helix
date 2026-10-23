import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// The pieces every console screen is built from: slate cards with a blue
/// accent, status dots and pills, and the segmented bar. Colours come from
/// [HelixConsoleColors]; nothing here knows about the server.

/// A white, bordered card.
class ConsoleCard extends StatelessWidget {
  const ConsoleCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.color = HelixConsoleColors.surface,
    this.borderColor = HelixConsoleColors.border,
    this.radius = 16,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final Color borderColor;
  final double radius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: BorderSide(color: borderColor),
    );
    return Material(
      color: color,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? Padding(padding: padding, child: child)
          : InkWell(
              onTap: onTap,
              customBorder: shape,
              child: Padding(padding: padding, child: child),
            ),
    );
  }
}

/// The big title at the top of a place ("Dashboard").
class ConsoleTitle extends StatelessWidget {
  const ConsoleTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontSize: 26,
        fontWeight: FontWeight.w800,
        color: HelixConsoleColors.text,
      ),
    ),
  );
}

/// A section heading between cards ("Service health").
class ConsoleHeading extends StatelessWidget {
  const ConsoleHeading(this.text, {super.key, this.subtitle});

  final String text;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Semantics(
        header: true,
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: HelixConsoleColors.text,
            letterSpacing: -0.2,
          ),
        ),
      ),
      if (subtitle != null) ...[
        const SizedBox(height: 4),
        Text(
          subtitle!,
          style: const TextStyle(
            fontSize: 12,
            color: HelixConsoleColors.textMuted,
          ),
        ),
      ],
    ],
  );
}

/// The small upper-case label that opens a card ("SERVER NODE IDENTITY").
class ConsoleCardLabel extends StatelessWidget {
  const ConsoleCardLabel(
    this.text, {
    super.key,
    this.color = HelixConsoleColors.textMuted,
  });

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.6,
        color: color,
      ),
    ),
  );
}

/// A small filled circle: green, amber, slate or red.
class ConsoleDot extends StatelessWidget {
  const ConsoleDot({super.key, required this.color, this.size = 8});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    ),
  );
}

/// The tones a pill or banner can have.
enum ConsoleTone {
  ok(
    HelixConsoleColors.onOk,
    HelixConsoleColors.okSurface,
    HelixConsoleColors.okBorder,
    HelixConsoleColors.ok,
  ),
  warn(
    HelixConsoleColors.onWarn,
    HelixConsoleColors.warnSurface,
    HelixConsoleColors.warnBorder,
    HelixConsoleColors.warn,
  ),
  danger(
    HelixConsoleColors.danger,
    HelixConsoleColors.dangerSurface,
    HelixConsoleColors.dangerBorder,
    HelixConsoleColors.danger,
  ),
  info(
    HelixConsoleColors.accent,
    HelixConsoleColors.accentSurface,
    HelixConsoleColors.accentBorder,
    HelixConsoleColors.accent,
  ),
  neutral(
    HelixConsoleColors.textMuted,
    HelixConsoleColors.sunken,
    HelixConsoleColors.border,
    HelixConsoleColors.off,
  );

  const ConsoleTone(this.text, this.surface, this.border, this.dot);

  final Color text;
  final Color surface;
  final Color border;
  final Color dot;
}

/// A rounded status pill, with an optional leading dot.
class ConsolePill extends StatelessWidget {
  const ConsolePill({
    super.key,
    required this.label,
    this.tone = ConsoleTone.neutral,
    this.dot = false,
    this.upper = false,
  });

  final String label;
  final ConsoleTone tone;
  final bool dot;
  final bool upper;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    excludeSemantics: true,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: tone.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: tone.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            ConsoleDot(color: tone.text, size: 6),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              upper ? label.toUpperCase() : label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: upper ? 10 : 11,
                fontWeight: FontWeight.w800,
                letterSpacing: upper ? 0.5 : 0,
                color: tone.text,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// One option in a [ConsoleSegmented].
class ConsoleSegment {
  const ConsoleSegment(this.label);

  final String label;
}

/// The segmented bar under a place's title: one selected segment, filled blue.
class ConsoleSegmented extends StatelessWidget {
  const ConsoleSegmented({
    super.key,
    required this.segments,
    required this.selected,
    required this.onSelected,
  });

  final List<ConsoleSegment> segments;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: HelixConsoleColors.surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: HelixConsoleColors.border),
    ),
    child: Row(
      children: [
        for (var i = 0; i < segments.length; i++)
          Expanded(
            child: _SegmentButton(
              segment: segments[i],
              selected: i == selected,
              onTap: () => onSelected(i),
            ),
          ),
      ],
    ),
  );
}

class _SegmentButton extends StatelessWidget {
  const _SegmentButton({
    required this.segment,
    required this.selected,
    required this.onTap,
  });

  final ConsoleSegment segment;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = selected
        ? HelixConsoleColors.surface
        : HelixConsoleColors.textMuted;
    return Semantics(
      button: true,
      selected: selected,
      label: segment.label,
      excludeSemantics: true,
      child: Material(
        color: selected ? HelixConsoleColors.accent : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Center(
              child: Text(
                segment.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: foreground,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A rounded filter chip ("Active (12)"). [tone] tints it when it matters
/// (pending reports are red).
class ConsoleChip extends StatelessWidget {
  const ConsoleChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.tone,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final ConsoleTone? tone;

  @override
  Widget build(BuildContext context) {
    final Color fill;
    final Color edge;
    final Color text;
    if (tone != null) {
      fill = selected ? tone!.text : tone!.surface;
      edge = selected ? tone!.text : tone!.border;
      text = selected ? HelixConsoleColors.surface : tone!.text;
    } else {
      fill = selected ? HelixConsoleColors.accent : HelixConsoleColors.surface;
      edge = selected ? HelixConsoleColors.accent : HelixConsoleColors.border;
      text = selected
          ? HelixConsoleColors.surface
          : HelixConsoleColors.textBody;
    }
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: fill,
        shape: StadiumBorder(side: BorderSide(color: edge)),
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                widthFactor: 1,
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: text,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A horizontal run of [ConsoleChip]s that scrolls on a narrow screen.
class ConsoleChipRow extends StatelessWidget {
  const ConsoleChipRow({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          children[i],
        ],
      ],
    ),
  );
}

/// One tab of a [ConsoleDock].
class ConsoleDockItem {
  const ConsoleDockItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.on,
    required this.onTap,
    this.tooltip,
    this.badge = 0,
    this.badgeMore = false,
  });

  /// The glyph while the place is not the one being looked at.
  final IconData icon;

  /// The glyph once it is - the open tab's icon is filled, like the other
  /// icons of the place.
  final IconData selectedIcon;

  /// The words beside the icon, and what a screen reader is told.
  final String label;

  final bool on;
  final VoidCallback onTap;

  /// What a long press says; [label] when not given.
  final String? tooltip;

  /// A red count in the tab's corner (open reports); zero shows nothing.
  final int badge;

  /// Whether [badge] is the whole count or the most the console has seen.
  final bool badgeMore;
}

/// The places of the console on a phone, in the shape the Orbit app uses for
/// its own tabs (`packages/orbit_ui/lib/src/components/bars.dart`): a 62 px
/// pill, 7 px in, its tabs 4 px apart. A tab is 50 px tall and at least 56 px
/// wide, and only the open one shows its name - the rest are an icon each.
/// The colours are the console's own slate and blue, not a theme pack's.
class ConsoleDock extends StatelessWidget {
  const ConsoleDock({super.key, required this.items});

  static const _height = 62.0;
  static const _tabHeight = 50.0;
  static const _edge = 1.0;

  final List<ConsoleDockItem> items;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: 'Places',
    // The pill is drawn behind the tabs rather than around them: its content
    // box is shorter than a 50 px tab.
    child: Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: HelixConsoleColors.surface,
              border: Border.all(
                color: HelixConsoleColors.border,
                width: _edge,
              ),
              borderRadius: BorderRadius.circular(_height / 2),
              boxShadow: [
                BoxShadow(
                  color: HelixConsoleColors.text.withValues(alpha: 0.07),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
          ),
        ),
        SizedBox(
          height: _height,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6 + _edge),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (i, item) in items.indexed) ...[
                  if (i > 0) const SizedBox(width: 4),
                  _tab(item),
                ],
              ],
            ),
          ),
        ),
      ],
    ),
  );

  Widget _tab(ConsoleDockItem item) {
    final ink = item.on
        ? HelixConsoleColors.surface
        : HelixConsoleColors.textMuted;
    final radius = BorderRadius.circular(_tabHeight / 2);
    return Tooltip(
      message: item.tooltip ?? item.label,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        selected: item.on,
        label: item.badge > 0
            ? '${item.label}, ${consoleCount(item.badge, more: item.badgeMore)} open'
            : item.label,
        excludeSemantics: true,
        child: Material(
          color: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: radius),
          child: InkWell(
            onTap: item.onTap,
            customBorder: RoundedRectangleBorder(borderRadius: radius),
            child: Container(
              height: _tabHeight,
              constraints: const BoxConstraints(minWidth: 56),
              padding: EdgeInsets.only(left: 16, right: item.on ? 18 : 16),
              decoration: BoxDecoration(
                color: item.on ? HelixConsoleColors.accent : null,
                borderRadius: radius,
                boxShadow: item.on
                    ? [
                        BoxShadow(
                          color: HelixConsoleColors.accent.withValues(
                            alpha: 0.32,
                          ),
                          blurRadius: 12,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(
                        item.on ? item.selectedIcon : item.icon,
                        size: 23,
                        color: ink,
                      ),
                      if (item.badge > 0)
                        Positioned(
                          right: -8,
                          top: -6,
                          child: ConsoleCount(item.badge, more: item.badgeMore),
                        ),
                    ],
                  ),
                  if (item.on) ...[
                    const SizedBox(width: 8),
                    Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: ink,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A count as the operator reads it: `7`, or `50+` when that is the most the
/// console has seen.
String consoleCount(int count, {bool more = false}) =>
    '$count${more ? '+' : ''}';

/// The red count a navigation item rides on when something waits (open
/// reports). Decorative: the item's own semantics carry the number in words.
class ConsoleCount extends StatelessWidget {
  const ConsoleCount(this.count, {super.key, this.more = false});

  final int count;
  final bool more;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: HelixConsoleColors.danger,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        consoleCount(count, more: more),
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          height: 1.2,
          color: HelixConsoleColors.surface,
        ),
      ),
    ),
  );
}

/// One labelled block of [ConsoleDrawerRow]s in a [ConsoleDrawer].
class ConsoleDrawerGroup extends StatelessWidget {
  const ConsoleDrawerGroup({
    super.key,
    required this.label,
    required this.rows,
  });

  final String label;
  final List<ConsoleDrawerRow> rows;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
        child: ConsoleCardLabel(label),
      ),
      for (final (i, row) in rows.indexed) ...[
        if (i > 0) const _DrawerHairline(),
        row,
      ],
    ],
  );
}

/// One destination in a [ConsoleDrawer]: a glyph, its words, and what waits
/// there. At least 56 px tall, so it clears the 48 px rule with room left.
class ConsoleDrawerRow extends StatelessWidget {
  const ConsoleDrawerRow({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.selected = false,
    this.badge = 0,
    this.badgeMore = false,
    this.tone,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;
  final bool selected;

  /// Open reports waiting behind this row; zero shows nothing.
  final int badge;
  final bool badgeMore;

  /// The colour of the glyph and the words, for a row that is not a plain
  /// destination - signing out is red.
  final ConsoleTone? tone;

  @override
  Widget build(BuildContext context) {
    final ink =
        tone?.text ??
        (selected ? HelixConsoleColors.accent : HelixConsoleColors.textBody);
    return Semantics(
      button: true,
      selected: selected,
      label: badge > 0
          ? '$label, ${consoleCount(badge, more: badgeMore)} open'
          : label,
      hint: subtitle,
      excludeSemantics: true,
      child: Material(
        color: selected ? HelixConsoleColors.accentSurface : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(icon, size: 22, color: ink),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: ink,
                          ),
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle!,
                            style: const TextStyle(
                              fontSize: 12,
                              height: 1.3,
                              color: HelixConsoleColors.textMuted,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (badge > 0) ...[
                    const SizedBox(width: 8),
                    ConsoleCount(badge, more: badgeMore),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The phone's system drawer: the places an operator reaches for rarely, with
/// the session at the top and the way out at the bottom. It slides in from the
/// right (`Scaffold.endDrawer`), 85% of the window wide and no wider than
/// 420 px, and holds flat hairline rows rather than cards.
class ConsoleDrawer extends StatelessWidget {
  const ConsoleDrawer({
    super.key,
    required this.title,
    required this.subtitle,
    required this.groups,
    this.onSignOut,
  });

  /// The server this console is signed in to.
  final String title;

  /// The session, in words: when it ends.
  final String subtitle;

  final List<ConsoleDrawerGroup> groups;
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    final wanted = MediaQuery.sizeOf(context).width * 0.85;
    return Drawer(
      width: wanted > 420 ? 420.0 : wanted,
      backgroundColor: HelixConsoleColors.surface,
      semanticLabel: 'System and configuration',
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: HelixConsoleColors.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: HelixConsoleColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const _DrawerHairline(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 12),
                children: groups,
              ),
            ),
            if (onSignOut != null) ...[
              const _DrawerHairline(),
              ConsoleDrawerRow(
                icon: Icons.logout,
                label: 'Sign out',
                subtitle: 'Ends every admin session on this server',
                tone: ConsoleTone.danger,
                onTap: onSignOut!,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The 1 px line between drawer rows and blocks: a hairline, not a card.
class _DrawerHairline extends StatelessWidget {
  const _DrawerHairline();

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(height: 1, color: HelixConsoleColors.border),
  );
}

/// A number with its label: one tile in the dashboard grid.
class ConsoleMetricTile extends StatelessWidget {
  const ConsoleMetricTile({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.accent,
    this.subtitle,
    this.subtitleColor = HelixConsoleColors.onOk,
    this.valueColor = HelixConsoleColors.text,
  });

  final String title;
  final String value;
  final String? subtitle;
  final IconData icon;
  final Color accent;
  final Color subtitleColor;
  final Color valueColor;

  @override
  Widget build(BuildContext context) => Semantics(
    label: [title, value, ?subtitle].join(': '),
    excludeSemantics: true,
    child: ConsoleCard(
      radius: 12,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: HelixConsoleColors.textMuted,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: accent, size: 16),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: valueColor,
                  ),
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: subtitleColor,
                  ),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

/// One service on the health list: a status dot, a name and what is known.
class ConsoleHealthRow extends StatelessWidget {
  const ConsoleHealthRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.note,
    required this.dot,
  });

  final String title;
  final String subtitle;
  final String note;
  final Color dot;

  @override
  Widget build(BuildContext context) => ConsoleCard(
    radius: 12,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    child: Row(
      children: [
        ConsoleDot(color: dot),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: HelixConsoleColors.text,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12,
                  color: HelixConsoleColors.textMuted,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                note,
                style: const TextStyle(
                  fontSize: 11,
                  color: HelixConsoleColors.textMuted,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// A title with a line under it and a control on the right: one setting.
class ConsoleSettingRow extends StatelessWidget {
  const ConsoleSettingRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.titleColor = HelixConsoleColors.text,
    this.subtitleColor = HelixConsoleColors.textMuted,
  });

  final String title;
  final String subtitle;
  final Widget trailing;
  final Color titleColor;
  final Color subtitleColor;

  @override
  Widget build(BuildContext context) {
    final row = Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: titleColor,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  color: subtitleColor,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        trailing,
      ],
    );
    // A switch is announced with the words beside it.
    return trailing is Switch ? MergeSemantics(child: row) : row;
  }
}

/// A labelled value in a boxed well, with an optional copy button.
class ConsoleProperty extends StatelessWidget {
  const ConsoleProperty({
    super.key,
    required this.label,
    required this.value,
    this.copyable = false,
    this.mono = true,
  });

  final String label;
  final String value;
  final bool copyable;
  final bool mono;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
    decoration: BoxDecoration(
      color: HelixConsoleColors.sunken,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: HelixConsoleColors.border),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  color: HelixConsoleColors.textMuted,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(
                  fontSize: 13,
                  fontFamily: mono ? 'monospace' : null,
                  fontWeight: FontWeight.w600,
                  color: HelixConsoleColors.text,
                ),
              ),
            ],
          ),
        ),
        if (copyable)
          IconButton(
            tooltip: 'Copy $label',
            icon: const Icon(
              Icons.copy,
              size: 18,
              color: HelixConsoleColors.textMuted,
            ),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              await Clipboard.setData(ClipboardData(text: value));
              messenger
                ..hideCurrentSnackBar()
                ..showSnackBar(SnackBar(content: Text('$label copied.')));
            },
          )
        else
          const SizedBox(width: 8),
      ],
    ),
  );
}

/// A banner for a problem or a note, in a tone.
class ConsoleBanner extends StatelessWidget {
  const ConsoleBanner({
    super.key,
    required this.message,
    this.tone = ConsoleTone.danger,
    this.title,
    this.onRetry,
  });

  final String message;
  final String? title;
  final ConsoleTone tone;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: tone == ConsoleTone.danger,
    child: ConsoleCard(
      radius: 12,
      padding: const EdgeInsets.all(14),
      color: tone.surface,
      borderColor: tone.border,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            tone == ConsoleTone.danger
                ? Icons.error_outline
                : Icons.info_outline,
            size: 20,
            color: tone.text,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null)
                  Text(
                    title!,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: tone.text,
                    ),
                  ),
                Text(
                  message,
                  style: TextStyle(fontSize: 12, height: 1.4, color: tone.text),
                ),
                if (onRetry != null)
                  TextButton(
                    onPressed: onRetry,
                    style: TextButton.styleFrom(foregroundColor: tone.text),
                    child: const Text('Try again'),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// An empty list: an icon, a line and a hint, in a card.
class ConsoleEmpty extends StatelessWidget {
  const ConsoleEmpty({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => ConsoleCard(
    padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
    child: SizedBox(
      width: double.infinity,
      child: Column(
        children: [
          ExcludeSemantics(
            child: Icon(icon, size: 34, color: HelixConsoleColors.textFaint),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: HelixConsoleColors.text,
            ),
          ),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                height: 1.5,
                color: HelixConsoleColors.textMuted,
              ),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 10), action!],
        ],
      ),
    ),
  );
}

/// The three button looks the console uses, so a screen never restyles one.
abstract final class ConsoleButtons {
  static final ButtonStyle outlined = OutlinedButton.styleFrom(
    foregroundColor: HelixConsoleColors.textBody,
    side: const BorderSide(color: HelixConsoleColors.borderStrong),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
  );

  static final ButtonStyle filled = FilledButton.styleFrom(
    backgroundColor: HelixConsoleColors.accent,
    foregroundColor: HelixConsoleColors.surface,
    elevation: 0,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
  );

  static ButtonStyle outlinedTone(Color color, Color edge) =>
      OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: edge),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      );

  static ButtonStyle filledTone(Color color) => FilledButton.styleFrom(
    backgroundColor: color,
    foregroundColor: HelixConsoleColors.surface,
    elevation: 0,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
  );
}

/// The skeleton shown while the console starts or a page loads.
class ConsoleLoading extends StatelessWidget {
  const ConsoleLoading({super.key, this.label = 'Loading'});

  final String label;

  @override
  Widget build(BuildContext context) => Center(
    child: Semantics(
      label: label,
      liveRegion: true,
      child: const HelixSkeleton(width: 192, height: 24),
    ),
  );
}
