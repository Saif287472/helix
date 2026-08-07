part of '../settings_screen.dart';

class _SettingsSearchField extends StatelessWidget {
  const _SettingsSearchField({
    required this.controller,
    required this.query,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final String query;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return SizedBox(
      height: 52,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Search settings',
          prefixIcon: Icon(Icons.search, color: cs.onSurfaceVariant),
          suffixIcon: query.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear search',
                  onPressed: onClear,
                  icon: const Icon(Icons.close),
                ),
          filled: true,
          fillColor: _settingsCardColor(theme, cs),
          contentPadding: HelixInsets.zero,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(28),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.displayName,
    required this.accountId,
    required this.serverUri,
    required this.onTap,
    required this.onQrTap,
    required this.onEditTap,
  });

  final String displayName;
  final String accountId;
  final Uri serverUri;
  final VoidCallback onTap;
  final VoidCallback onQrTap;
  final VoidCallback onEditTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final accountLabel = accountId.isNotEmpty
        ? _shortId(accountId)
        : 'Helix account';
    final serverLabel = serverUri.host.isNotEmpty
        ? serverUri.host
        : serverUri.toString();

    return Material(
      color: _settingsCardColor(theme, cs),
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: HelixInsets.fromLTRB(16, 14, 12, 14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 31,
                backgroundColor: cs.primaryContainer,
                child: Text(
                  _initials(displayName),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: cs.onPrimaryContainer,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      accountLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Available on $serverLabel',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Show Helix code',
                onPressed: onQrTap,
                icon: const Icon(Icons.qr_code_2),
              ),
              IconButton(
                tooltip: 'Edit profile',
                onPressed: onEditTap,
                icon: const Icon(Icons.edit_outlined),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _initials(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 'H';
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length > 1) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return trimmed.substring(0, trimmed.length.clamp(1, 2)).toUpperCase();
  }

  static String _shortId(String accountId) {
    if (accountId.length <= 14) return accountId;
    return '${accountId.substring(0, 7)}...${accountId.substring(accountId.length - 4)}';
  }
}

class _OneUiSettingsCard extends StatelessWidget {
  const _OneUiSettingsCard({required this.group});

  final _SettingsGroup group;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Semantics(
      label: group.title,
      child: Material(
        color: _settingsCardColor(theme, cs),
        borderRadius: BorderRadius.circular(28),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (var i = 0; i < group.items.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  thickness: 1,
                  indent: 76,
                  endIndent: 28,
                  color: cs.outlineVariant.withAlpha(
                    theme.brightness == Brightness.dark ? 56 : 110,
                  ),
                ),
              _SettingsRow(item: group.items[i]),
            ],
          ],
        ),
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({required this.item});

  final _SettingsItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final titleColor = item.isDestructive ? cs.error : cs.onSurface;
    final subtitleColor = item.isDestructive
        ? cs.error.withAlpha(theme.brightness == Brightness.dark ? 210 : 190)
        : cs.onSurfaceVariant;

    return InkWell(
      onTap: item.onTap,
      child: Padding(
        padding: HelixInsets.fromLTRB(32, 16, 18, 16),
        child: Row(
          children: [
            _CategoryIcon(icon: item.icon, color: item.color),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontSize: 15,
                      height: 1.14,
                      fontWeight: FontWeight.w500,
                      color: titleColor,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontSize: 15.5,
                      height: 1.2,
                      color: subtitleColor,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            if (item.value != null)
              Flexible(
                flex: 0,
                child: Text(
                  item.value!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            if (item.trailingIcon != null) ...[
              const SizedBox(width: 6),
              Icon(item.trailingIcon, color: cs.onSurfaceVariant, size: 22),
            ] else ...[
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right,
                color: cs.onSurfaceVariant.withAlpha(180),
                size: 24,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CategoryIcon extends StatelessWidget {
  const _CategoryIcon({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      child: Icon(icon, color: HelixScrimColors.onBackdrop, size: 23),
    );
  }
}

class _EmptySearchState extends StatelessWidget {
  const _EmptySearchState({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: HelixInsets.symmetric(horizontal: 18, vertical: 28),
      decoration: BoxDecoration(
        color: _settingsCardColor(theme, cs),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        children: [
          Icon(Icons.search_off, size: 42, color: cs.onSurfaceVariant),
          const SizedBox(height: 10),
          Text(
            'No settings match "$query"',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            HelixLocalizations.of(context).tryDifferentTitleDescription,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsGroup {
  const _SettingsGroup({required this.title, required this.items});

  final String title;
  final List<_SettingsItem> items;
}

class _SettingsItem {
  const _SettingsItem({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.value,
    this.trailingIcon,
    this.isDestructive = false,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final String? value;
  final IconData? trailingIcon;
  final bool isDestructive;
}

Color _settingsPageColor(ThemeData theme, ColorScheme cs) {
  if (theme.brightness == Brightness.dark) {
    return Color.alphaBlend(cs.surfaceTint.withAlpha(8), cs.surface);
  }
  return Color.alphaBlend(cs.primary.withAlpha(5), cs.surfaceContainerLowest);
}

Color _settingsCardColor(ThemeData theme, ColorScheme cs) {
  if (theme.brightness == Brightness.dark) {
    return Color.alphaBlend(
      cs.surfaceTint.withAlpha(14),
      cs.surfaceContainerLow,
    );
  }
  return cs.surfaceContainerLowest;
}
