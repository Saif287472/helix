import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// A titled, rounded card grouping related settings rows - the same
/// group-of-rows language the main Helix Remote app's settings screen uses.
/// Keeps a settings surface scannable instead of one long form, which
/// matters most for the server-connection controls: they're the part most
/// likely to overwhelm a first-time self-hoster if dumped onto one screen.
class SettingsSectionCard extends StatelessWidget {
  const SettingsSectionCard({super.key, this.title, required this.rows});

  final String? title;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null) ...[
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              title!.toUpperCase(),
              style: TextStyle(
                color: context.textFaint,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
          ),
        ],
        Material(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    thickness: 1,
                    indent: 68,
                    endIndent: 16,
                    color: Theme.of(context).dividerColor,
                  ),
                rows[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// A single row inside a [SettingsSectionCard]: colored icon, title,
/// optional subtitle, and an optional trailing widget (switch, value text)
/// or a chevron when [onTap] is set with no explicit [trailing].
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.isDestructive = false,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final titleColor = isDestructive
        ? Theme.of(context).colorScheme.error
        : context.textPrimary;
    // trailing (typically a Switch) sits as a sibling of the tappable
    // InkWell, not nested inside it - a Switch nested inside another
    // tappable region would leave a tap on its thumb ambiguous between the
    // Switch's own onChanged and the row's onTap.
    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: iconColor,
                    ),
                    child: Icon(icon, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: titleColor,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle!,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: context.textTertiary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (trailing == null && onTap != null) ...[
                    const SizedBox(width: 4),
                    Icon(
                      Icons.chevron_right,
                      color: context.textFaint,
                      size: 22,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: trailing!,
          ),
        ],
      ],
    );
  }
}
