import 'package:flutter/material.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// Building blocks for the settings sub-pages, matching the look of the main
/// settings list: rounded cards on a tinted page, a coloured circle per row.

Color settingsPageColor(ColorScheme cs) =>
    Color.alphaBlend(cs.primary.withAlpha(5), cs.surfaceContainerLowest);

/// A settings sub-page: app bar plus a scrollable column of sections.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: settingsPageColor(cs),
      appBar: AppBar(
        title: Text(title),
        backgroundColor: settingsPageColor(cs),
        scrolledUnderElevation: 0,
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: HelixInsets.fromLTRB(16, 4, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    );
  }
}

/// A titled group of rows. [footer] explains the group in small print.
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    this.title,
    required this.children,
    this.footer,
  });

  final String? title;
  final List<Widget> children;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text(
                title!,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: cs.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          Material(
            color: cs.surfaceContainerLowest,
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
                      color: cs.outlineVariant.withAlpha(110),
                    ),
                  children[i],
                ],
              ],
            ),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Text(
                footer!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RowIcon extends StatelessWidget {
  const _RowIcon({required this.icon, required this.color});

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

/// A row that opens something: another page, a picker, a dialog.
class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    this.subtitle,
    this.value,
    this.onTap,
    this.trailing,
    this.destructive = false,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;

  /// The current choice, shown on the right (e.g. "Contacts").
  final String? value;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.fromLTRB(20, 6, 16, 6),
      leading: _RowIcon(icon: icon, color: color),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w500,
          color: destructive ? cs.error : null,
        ),
      ),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing:
          trailing ??
          (value != null
              ? Text(
                  value!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.primary,
                    fontWeight: FontWeight.w600,
                  ),
                )
              : (onTap != null
                    ? Icon(Icons.chevron_right, color: cs.onSurfaceVariant)
                    : null)),
      onTap: onTap,
    );
  }
}

/// A row with an on/off switch.
class SettingsSwitchTile extends StatelessWidget {
  const SettingsSwitchTile({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile(
    contentPadding: const EdgeInsets.fromLTRB(20, 6, 16, 6),
    secondary: _RowIcon(icon: icon, color: color),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
    subtitle: subtitle == null ? null : Text(subtitle!),
    value: value,
    onChanged: onChanged,
  );
}

/// One option in [pickSettingsOption].
class SettingsOption<T> {
  const SettingsOption(this.value, this.label, {this.description});

  final T value;
  final String label;
  final String? description;
}

/// A bottom sheet of radio options. Returns the chosen value, or null when
/// dismissed.
Future<T?> pickSettingsOption<T>(
  BuildContext context, {
  required String title,
  required T current,
  required List<SettingsOption<T>> options,
}) {
  return showModalBottomSheet<T>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: RadioGroup<T>(
          groupValue: current,
          onChanged: (value) => Navigator.pop(ctx, value),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Text(title, style: Theme.of(ctx).textTheme.titleMedium),
              ),
              for (final option in options)
                RadioListTile<T>(
                  value: option.value,
                  title: Text(option.label),
                  subtitle: option.description == null
                      ? null
                      : Text(option.description!),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
