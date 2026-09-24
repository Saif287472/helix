import 'package:flutter/material.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';
import 'package:helix_remote/screens/setup/state/onboarding_state.dart';

class ServerSelectionStep extends StatelessWidget {
  const ServerSelectionStep({
    super.key,
    required this.selectedType,
    required this.onSelectType,
    required this.onProceed,
    required this.onContinueOffline,
  });

  final ServerType selectedType;
  final ValueChanged<ServerType> onSelectType;
  final VoidCallback onProceed;
  final VoidCallback onContinueOffline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
              ),
              child: Icon(
                Icons.shield_outlined,
                size: 36,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(height: HelixSpace.md),
          Text(
            "Helix",
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: HelixSpace.xxs),
          Text(
            "The privacy you deserve",
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: HelixSpace.lg),
          Text(
            "How do you want to proceed?",
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: HelixSpace.md),
          // Segmented Tabs
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _SegmentTile(
                    label: 'Helix Global Server',
                    icon: Icons.public,
                    isSelected: selectedType == ServerType.global,
                    onTap: () => onSelectType(ServerType.global),
                  ),
                ),
                Expanded(
                  child: _SegmentTile(
                    label: 'Others',
                    icon: Icons.dns_outlined,
                    isSelected: selectedType == ServerType.others,
                    onTap: () => onSelectType(ServerType.others),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: HelixSpace.lg),
          // Info banner / card
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            crossFadeState: selectedType == ServerType.global
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: const _ServerInfoCard(
              title: 'Connected to Helix Global Server',
              description:
                  'Connect directly to official Helix secure nodes. Free, encrypted messaging with zero server configuration needed.',
              badgeColor: HelixColorTokens.success,
              icon: Icons.check_circle_outline,
            ),
            secondChild: _ServerInfoCard(
              title: 'Custom & Self-Hosted Servers',
              description:
                  'Join a private server code, connect with an admin invite link, or self-host your own server node via Helix Admin.',
              badgeColor: theme.colorScheme.primary,
              icon: Icons.hub_outlined,
            ),
          ),
          const SizedBox(height: HelixSpace.xl),
          FilledButton(
            onPressed: onProceed,
            style: FilledButton.styleFrom(
              padding: HelixInsets.all(HelixSpace.md),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text("Continue", style: TextStyle(fontSize: 16)),
          ),
          const SizedBox(height: HelixSpace.xs),
          TextButton(
            onPressed: onContinueOffline,
            child: const Text("Continue offline for now"),
          ),
        ],
      ),
    );
  }
}

class _SegmentTile extends StatelessWidget {
  const _SegmentTile({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        constraints: const BoxConstraints(minHeight: 48),
        padding: HelixInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.surface
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: isSelected
              ? [
                  const BoxShadow(
                    color: HelixScrimColors.shadowSoft,
                    blurRadius: 4,
                    offset: Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServerInfoCard extends StatelessWidget {
  const _ServerInfoCard({
    required this.title,
    required this.description,
    required this.badgeColor,
    required this.icon,
  });

  final String title;
  final String description;
  final Color badgeColor;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: HelixInsets.all(HelixSpace.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: badgeColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: badgeColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
