part of '../helix_remote_ui.dart';

/// A titled group of settings rows on one card.
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              HelixSpace.md,
              HelixSpace.md,
              HelixSpace.md,
              HelixSpace.xs,
            ),
            child: Semantics(
              header: true,
              child: Text(
                title!,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: scheme.primary,
                ),
              ),
            ),
          ),
        Material(
          color: scheme.surface,
          child: Column(children: children),
        ),
        if (footer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              HelixSpace.md,
              HelixSpace.xs,
              HelixSpace.md,
              HelixSpace.sm,
            ),
            child: Text(
              footer!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

/// One settings row: icon, title, optional subtitle and trailing widget.
/// At least 56 px tall and grows with text scale.
class HelixSettingsTile extends StatelessWidget {
  const HelixSettingsTile({
    super.key,
    required this.title,
    this.icon,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.destructive = false,
    this.showChevron = false,
  });

  final String title;
  final IconData? icon;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// Red title and icon (log out, delete account).
  final bool destructive;

  /// A forward chevron for rows that open a page.
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = destructive ? scheme.error : scheme.onSurface;
    return Semantics(
      button: onTap != null,
      container: true,
      label: subtitle == null ? title : '$title, $subtitle',
      onTap: onTap,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: HelixSpace.md,
                vertical: HelixSpace.xs,
              ),
              child: Row(
                children: [
                  if (icon != null) ...[
                    Icon(
                      icon,
                      color: destructive
                          ? scheme.error
                          : scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: HelixSpace.md),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(fontSize: 16, color: color),
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle!,
                            style: TextStyle(
                              fontSize: 14,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
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
    this.subtitle,
  });

  final String title;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final IconData? icon;
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
              padding: const EdgeInsets.symmetric(
                horizontal: HelixSpace.md,
                vertical: HelixSpace.xs,
              ),
              child: Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, color: scheme.onSurfaceVariant),
                    const SizedBox(width: HelixSpace.md),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: const TextStyle(fontSize: 16)),
                        if (subtitle != null)
                          Text(
                            subtitle!,
                            style: TextStyle(
                              fontSize: 14,
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

/// The profile row at the top of Settings: avatar, name, about line.
class HelixProfileHeaderTile extends StatelessWidget {
  const HelixProfileHeaderTile({
    super.key,
    required this.avatar,
    required this.name,
    this.about,
    this.onTap,
  });

  final HelixAvatarModel avatar;
  final String name;
  final String? about;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: onTap != null,
      container: true,
      label: about == null ? name : '$name, $about',
      onTap: onTap,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(HelixSpace.md),
            child: Row(
              children: [
                HelixAvatar(model: avatar, size: HelixAvatarSize.xl),
                const SizedBox(width: HelixSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      if (about != null)
                        Text(
                          about!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                    ],
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
