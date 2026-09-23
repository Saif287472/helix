import 'package:flutter/material.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

class GlobalNameStep extends StatelessWidget {
  const GlobalNameStep({
    super.key,
    required this.displayName,
    required this.isLoading,
    this.errorMessage,
    required this.onNameChanged,
    required this.onSubmit,
    required this.onSkip,
  });

  final String displayName;
  final bool isLoading;
  final String? errorMessage;
  final ValueChanged<String> onNameChanged;
  final VoidCallback onSubmit;
  final VoidCallback onSkip;

  bool get _isValid => displayName.trim().length >= 3;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initial = displayName.trim().isEmpty
        ? '?'
        : displayName.trim().characters.first.toUpperCase();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Banner
          Container(
            padding: HelixInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: HelixColorTokens.success.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: HelixColorTokens.success.withValues(alpha: 0.3),
              ),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.check_circle_outline,
                  size: 16,
                  color: HelixColorTokens.success,
                ),
                SizedBox(width: 8),
                Flexible(
                  child: Text(
                    "Phone Number Verified",
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: HelixColorTokens.success,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: HelixSpace.lg),
          Center(
            child: CircleAvatar(
              radius: 40,
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Text(
                initial,
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          ),
          const SizedBox(height: HelixSpace.md),
          Text(
            "Please enter your name",
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: HelixSpace.xxs),
          Text(
            "Choose how you'd like to appear to your contacts.",
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: HelixSpace.lg),
          TextFormField(
            initialValue: displayName,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Display Name',
              hintText: 'e.g. Alex Vance',
              prefixIcon: const Icon(Icons.person_outline),
              helperText: 'Must be at least 3 characters',
              errorText: errorMessage,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onChanged: onNameChanged,
            onFieldSubmitted: (_) {
              if (_isValid && !isLoading) onSubmit();
            },
          ),
          const SizedBox(height: HelixSpace.xl),
          FilledButton(
            onPressed: (_isValid && !isLoading) ? onSubmit : null,
            style: FilledButton.styleFrom(
              padding: HelixInsets.all(HelixSpace.md),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              isLoading ? 'Creating Profile…' : 'Proceed to Helix',
              style: const TextStyle(fontSize: 16),
            ),
          ),
          const SizedBox(height: HelixSpace.sm),
          OutlinedButton(
            onPressed: isLoading ? null : onSkip,
            style: OutlinedButton.styleFrom(
              padding: HelixInsets.symmetric(vertical: 12, horizontal: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "Skip for now",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                Text(
                  "Your phone number will be used as your default name",
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
