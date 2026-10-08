part of '../helix_remote_ui.dart';

/// Colours of the settings pages: the tinted page, the cards on it and the
/// round icon of each row. All of them come from the colour scheme or from
/// named tokens, so a page never picks its own.
abstract final class HelixSettingsColors {
  /// The icon circles, in the order a row with no colour of its own picks
  /// from. Each reads on the white icon drawn in it.
  static const palette = <Color>[
    HelixColorTokens.cFF3B82F6,
    HelixColorTokens.cFF5B6EE1,
    HelixColorTokens.cFF2FA84F,
    HelixColorTokens.cFF7C3AED,
    HelixColorTokens.cFF4F46E5,
    HelixColorTokens.cFFF24E1E,
    HelixColorTokens.cFF14B8A6,
    HelixColorTokens.cFF0EA5E9,
    HelixColorTokens.cFFF97316,
    HelixColorTokens.cFF6D6AAE,
  ];

  /// Sign out, delete: the same red the rest of the app uses for danger.
  static const danger = HelixColorTokens.cFFDC2626;

  /// The circle of a row that gave no colour: one icon always gets the same
  /// one, so a page does not change colour between visits.
  static Color forIcon(IconData icon) =>
      palette[icon.codePoint % palette.length];

  /// The page behind the cards: the card colour with a breath of the brand.
  static Color page(ColorScheme scheme) => Color.alphaBlend(
    scheme.primary.withAlpha(5),
    scheme.surfaceContainerLowest,
  );

  static Color card(ColorScheme scheme) => scheme.surfaceContainerLowest;
}

/// A settings page: the tinted background and a flat app bar. Use it for every
/// page made of [HelixSettingsSection]s so they all sit on the same ground.
class HelixSettingsScaffold extends StatelessWidget {
  const HelixSettingsScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions = const [],
    this.floatingActionButton,
  });

  final String title;
  final Widget body;
  final List<Widget> actions;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    final page = HelixSettingsColors.page(Theme.of(context).colorScheme);
    return Scaffold(
      backgroundColor: page,
      appBar: AppBar(
        title: Text(title),
        backgroundColor: page,
        scrolledUnderElevation: 0,
        actions: actions,
      ),
      body: body,
      floatingActionButton: floatingActionButton,
    );
  }
}

/// A titled group of settings rows on one rounded card, with a hairline
/// between rows. [footer] explains the group under the card.
class HelixSettingsSection extends StatelessWidget {
  const HelixSettingsSection({
    super.key,
    required this.children,
    this.title,
    this.footer,
  });

  final String? title;
  final List<Widget> children;

  /// Explanatory text under the card.
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 4, 20, 8),
              child: Semantics(
                header: true,
                child: Text(
                  title!,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          Material(
            color: HelixSettingsColors.card(scheme),
            borderRadius: BorderRadius.circular(24),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      indent: 72,
                      endIndent: 20,
                      color: scheme.outlineVariant.withAlpha(110),
                    ),
                  children[i],
                ],
              ],
            ),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 8, 20, 0),
              child: Text(
                footer!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The white icon in its coloured circle at the start of a settings row.
class _SettingsRowIcon extends StatelessWidget {
  const _SettingsRowIcon({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 36,
    height: 36,
    decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    child: Icon(icon, color: HelixScrimColors.onBackdrop, size: 20),
  );
}

/// One settings row: a coloured icon, title, optional subtitle and a trailing
/// value, widget or chevron. At least 56 px tall and grows with text scale.
class HelixSettingsTile extends StatelessWidget {
  const HelixSettingsTile({
    super.key,
    required this.title,
    this.icon,
    this.iconColor,
    this.subtitle,
    this.value,
    this.trailing,
    this.onTap,
    this.destructive = false,
    this.showChevron = false,
  });

  final String title;
  final IconData? icon;

  /// The circle's colour; a row that gives none gets one from
  /// [HelixSettingsColors.forIcon].
  final Color? iconColor;
  final String? subtitle;

  /// The current choice, shown in the brand colour before the chevron.
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// Red title and icon (log out, delete account).
  final bool destructive;

  /// A forward chevron for rows that open a page.
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final titleColor = destructive ? scheme.error : scheme.onSurface;
    final circle = destructive
        ? HelixSettingsColors.danger
        : (iconColor ??
              (icon == null ? null : HelixSettingsColors.forIcon(icon!)));
    return Semantics(
      button: onTap != null,
      container: true,
      label: subtitle == null ? title : '$title, $subtitle',
      value: value,
      onTap: onTap,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 8, 16, 8),
              child: Row(
                children: [
                  if (icon != null) ...[
                    _SettingsRowIcon(icon: icon!, color: circle!),
                    const SizedBox(width: 16),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: titleColor,
                          ),
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle!,
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.25,
                              color: destructive
                                  ? scheme.error.withAlpha(190)
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (value != null) ...[
                    const SizedBox(width: 8),
                    Flexible(
                      flex: 0,
                      child: Text(
                        value!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                  ?trailing,
                  if (showChevron)
                    Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A settings row with a switch. The whole row toggles.
class HelixSettingsSwitchTile extends StatelessWidget {
  const HelixSettingsSwitchTile({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.icon,
    this.iconColor,
    this.subtitle,
  });

  final String title;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final IconData? icon;
  final Color? iconColor;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      toggled: value,
      container: true,
      label: subtitle == null ? title : '$title, $subtitle',
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onChanged == null ? null : () => onChanged!(!value),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 8, 16, 8),
              child: Row(
                children: [
                  if (icon != null) ...[
                    _SettingsRowIcon(
                      icon: icon!,
                      color: iconColor ?? HelixSettingsColors.forIcon(icon!),
                    ),
                    const SizedBox(width: 16),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle!,
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.25,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Switch(value: value, onChanged: onChanged),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The profile card at the top of Settings: avatar, name, about line, an
/// optional detail line and an edit button.
class HelixProfileHeaderTile extends StatelessWidget {
  const HelixProfileHeaderTile({
    super.key,
    required this.avatar,
    required this.name,
    this.about,
    this.detail,
    this.onTap,
    this.onEdit,
  });

  final HelixAvatarModel avatar;
  final String name;
  final String? about;

  /// A quieter line under [about] (the server this phone is on).
  final String? detail;
  final VoidCallback? onTap;

  /// Shows an edit button when given.
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
      child: Material(
        color: HelixSettingsColors.card(scheme),
        borderRadius: BorderRadius.circular(28),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                button: onTap != null,
                container: true,
                label: [name, ?about, ?detail].join(', '),
                onTap: onTap,
                child: ExcludeSemantics(
                  child: InkWell(
                    onTap: onTap,
                    child: Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                        16,
                        14,
                        8,
                        14,
                      ),
                      child: Row(
                        children: [
                          HelixAvatar(model: avatar, size: HelixAvatarSize.xl),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (about != null) ...[
                                  const SizedBox(height: 3),
                                  Text(
                                    about!,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                                if (detail != null) ...[
                                  const SizedBox(height: 3),
                                  Text(
                                    detail!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (onEdit != null)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: IconButton(
                  tooltip: 'Edit profile',
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A full-width status strip: offline, connecting, update available, info.
/// Announced politely when it appears.
class HelixBanner extends StatelessWidget {
  const HelixBanner({
    super.key,
    required this.kind,
    this.message,
    this.actionLabel,
    this.onAction,
  });

  final HelixBannerKind kind;

  /// Overrides the kind's default text.
  final String? message;

  /// "Update" / "Retry"; omit for none.
  final String? actionLabel;
  final VoidCallback? onAction;

  static String defaultMessage(HelixBannerKind kind) => switch (kind) {
    HelixBannerKind.offline =>
      'No connection. Messages will send when you are back online.',
    HelixBannerKind.connecting => 'Connecting...',
    HelixBannerKind.updateAvailable => 'A new version of Helix is available.',
    HelixBannerKind.info => '',
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (bg, iconColor, icon) = switch (kind) {
      HelixBannerKind.offline => (
        HelixStatusColors.cautionContainer,
        HelixStatusColors.onCautionContainer,
        Icons.cloud_off,
      ),
      HelixBannerKind.connecting => (
        HelixStatusColors.cautionContainer,
        HelixStatusColors.onCautionContainer,
        Icons.sync,
      ),
      HelixBannerKind.updateAvailable => (
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
        Icons.system_update_alt,
      ),
      HelixBannerKind.info => (
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
        Icons.info_outline,
      ),
    };
    final text = message ?? defaultMessage(kind);
    return Semantics(
      liveRegion: true,
      container: true,
      label: text,
      child: Material(
        color: bg,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: HelixChatMetrics.minTarget,
          ),
          child: Padding(
            padding: const EdgeInsetsDirectional.only(
              start: HelixSpace.md,
              top: HelixSpace.xxs,
              bottom: HelixSpace.xxs,
              end: HelixSpace.xs,
            ),
            child: Row(
              children: [
                ExcludeSemantics(
                  child: kind == HelixBannerKind.connecting
                      ? SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: iconColor,
                          ),
                        )
                      : Icon(icon, size: 20, color: iconColor),
                ),
                const SizedBox(width: HelixSpace.sm),
                Expanded(
                  child: ExcludeSemantics(
                    child: Text(
                      text,
                      style: TextStyle(fontSize: 14, color: scheme.onSurface),
                    ),
                  ),
                ),
                if (actionLabel != null)
                  TextButton(onPressed: onAction, child: Text(actionLabel!)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
