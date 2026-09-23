import 'package:flutter/material.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';
import '../state/onboarding_state.dart';

class OthersHubStep extends StatelessWidget {
  const OthersHubStep({
    super.key,
    required this.onSelectOption,
  });

  final ValueChanged<OthersOption> onSelectOption;

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
                color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.4),
              ),
              child: Icon(
                Icons.hub_outlined,
                size: 36,
                color: theme.colorScheme.secondary,
              ),
            ),
          ),
          const SizedBox(height: HelixSpace.md),
          Text(
            "Custom Server Setup",
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: HelixSpace.xxs),
          Text(
            "Choose how you want to connect to a custom server network.",
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: HelixSpace.xl),
          _OptionCard(
            title: 'Join a personal server',
            subtitle:
                'Enter an invitation link or code (INV-xxxx) provided by your admin, or restore an account with a recovery code (REC-xxxx).',
            icon: Icons.vpn_key_outlined,
            badgeText: 'Instant Join',
            onTap: () => onSelectOption(OthersOption.join),
          ),
          const SizedBox(height: HelixSpace.md),
          _OptionCard(
            title: 'Host your own server',
            subtitle:
                'Run your own Helix Remote server on your PC or VPS using the free Helix Admin companion app.',
            icon: Icons.dns_outlined,
            badgeText: 'Self-Hosted',
            onTap: () => onSelectOption(OthersOption.host),
          ),
        ],
      ),
    );
  }
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.badgeText,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final String badgeText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: HelixInsets.all(HelixSpace.md),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: HelixInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 28, color: theme.colorScheme.primary),
            ),
            const SizedBox(width: HelixSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Container(
                        padding: HelixInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          badgeText,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: HelixSpace.xs),
            Icon(
              Icons.chevron_right,
              color: theme.colorScheme.outline,
            ),
          ],
        ),
      ),
    );
  }
}
