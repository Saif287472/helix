part of '../contact_info_screen.dart';

class _Section extends StatelessWidget {
  const _Section({required this.color, required this.children});

  final Color color;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      color: color,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i != children.length - 1)
              Divider(
                height: 1,
                indent: 92,
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
          ],
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.destructive = false,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final bool destructive;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final titleColor = destructive ? cs.error : cs.onSurface;
    final subtitleColor = destructive ? cs.error : cs.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(30, 17, 30, 17),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(icon, size: 24, color: destructive ? cs.error : subtitleColor),
            const SizedBox(width: 43),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontSize: 16,
                      color: titleColor,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: subtitleColor,
                        height: 1.18,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 12), trailing!],
          ],
        ),
      ),
    );
  }
}

class _CommonGroupsSection extends StatelessWidget {
  const _CommonGroupsSection({
    required this.color,
    required this.contactName,
    required this.groups,
    required this.memberSummary,
    required this.canManageGroups,
    required this.onCreateGroup,
    required this.onAddToGroup,
  });

  final Color color;
  final String contactName;
  final List<RemoteConversation> groups;
  final String Function(RemoteConversation group) memberSummary;
  final bool canManageGroups;
  final VoidCallback onCreateGroup;
  final VoidCallback onAddToGroup;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      color: color,
      padding: const EdgeInsets.only(top: 16, bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 30),
            child: Text(
              '${groups.length} ${groups.length == 1 ? 'Group' : 'Groups'} in common',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (canManageGroups) ...[
            _InfoRow(
              icon: Icons.group_outlined,
              title: 'Create group with $contactName',
              onTap: onCreateGroup,
            ),
            Divider(height: 1, indent: 92, color: cs.outlineVariant),
            _InfoRow(
              icon: Icons.group_add_outlined,
              title: 'Add to groups',
              subtitle: 'Add this contact to groups you are in.',
              onTap: onAddToGroup,
            ),
            Divider(height: 1, indent: 92, color: cs.outlineVariant),
          ],
          for (var i = 0; i < groups.length; i++) ...[
            _GroupRow(group: groups[i], summary: memberSummary(groups[i])),
            if (i != groups.length - 1)
              Divider(height: 1, indent: 92, color: cs.outlineVariant),
          ],
        ],
      ),
    );
  }
}

class _GroupRow extends StatelessWidget {
  const _GroupRow({required this.group, required this.summary});

  final RemoteConversation group;
  final String summary;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final title = group.title.isEmpty ? 'Group' : group.title;
    return Padding(
      padding: const EdgeInsets.fromLTRB(30, 14, 30, 14),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: cs.primary,
            child: Text(
              title.characters.first.toUpperCase(),
              style: TextStyle(
                color: cs.onPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 30),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  summary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricLine extends StatelessWidget {
  const _MetricLine(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
