import 'package:flutter/material.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

class HostGuideStep extends StatelessWidget {
  const HostGuideStep({
    super.key,
    required this.currentStep,
    required this.onStepChanged,
    required this.onBackToOptions,
    this.onProceedToJoin,
  });

  final int currentStep;
  final ValueChanged<int> onStepChanged;
  final VoidCallback onBackToOptions;
  final VoidCallback? onProceedToJoin;

  static const List<Map<String, String>> _guideSteps = [
    {
      'title': 'Install Helix Admin',
      'body':
          'Download and install the free Helix Admin companion app or Docker container on your PC or cloud VPS.',
      'icon': 'download',
    },
    {
      'title': 'Configure Server Node',
      'body':
          'Follow the setup wizard in Helix Admin to generate encryption keys, configure storage, and set public network ports.',
      'icon': 'settings',
    },
    {
      'title': 'Generate Invite Link',
      'body':
          'Once your server node is running, use Helix Admin to issue a shareable server invite link or code (INV-xxxx).',
      'icon': 'link',
    },
    {
      'title': 'Connect Mobile Client',
      'body':
          'Return to this app, select "Join a personal server", and paste your invite link or code.',
      'icon': 'devices',
    },
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stepInfo = _guideSteps[currentStep];

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
              ),
              child: Icon(
                Icons.computer,
                size: 32,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(height: HelixSpace.md),
          Text(
            "Run your own Helix Server",
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: HelixSpace.xxs),
          Text(
            'Step ${currentStep + 1} of 4',
            textAlign: TextAlign.center,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: HelixSpace.lg),
          // Active step highlight card
          Container(
            padding: HelixInsets.all(HelixSpace.md),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: theme.colorScheme.primary,
                      child: Text(
                        '${currentStep + 1}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        stepInfo['title']!,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: HelixSpace.sm),
                Text(
                  stepInfo['body']!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: HelixSpace.lg),
          // Guide Steps overview indicator dots / list
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(4, (i) {
              final active = i == currentStep;
              return GestureDetector(
                onTap: () => onStepChanged(i),
                child: Container(
                  width: active ? 28 : 8,
                  height: 8,
                  margin: HelixInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    color: active
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outlineVariant,
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: HelixSpace.xl),
          Row(
            children: [
              if (currentStep > 0) ...[
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => onStepChanged(currentStep - 1),
                    child: const Text("Previous"),
                  ),
                ),
                const SizedBox(width: HelixSpace.sm),
              ],
              Expanded(
                child: FilledButton(
                  onPressed: () {
                    if (currentStep < 3) {
                      onStepChanged(currentStep + 1);
                    } else if (onProceedToJoin != null) {
                      onProceedToJoin!();
                    } else {
                      onBackToOptions();
                    }
                  },
                  child: Text(
                    currentStep < 3 ? "Next Step" : "Ready to Join",
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: HelixSpace.sm),
          TextButton(
            onPressed: onBackToOptions,
            child: const Text("Back to server options"),
          ),
        ],
      ),
    );
  }
}
