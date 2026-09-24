import 'package:flutter/material.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

class CodeEntryStep extends StatelessWidget {
  const CodeEntryStep({
    super.key,
    required this.codeString,
    required this.isLoading,
    this.errorMessage,
    required this.showInfoPopover,
    required this.onCodeChanged,
    required this.onToggleInfo,
    required this.onSubmit,
  });

  final String codeString;
  final bool isLoading;
  final String? errorMessage;
  final bool showInfoPopover;
  final ValueChanged<String> onCodeChanged;
  final VoidCallback onToggleInfo;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final upper = codeString.trim().toUpperCase();
    final isRecovery = upper.startsWith('HLX-REC-') ||
        upper.startsWith('REC-') ||
        upper.contains('RECOVERY');

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  "Enter invitation or recovery code",
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(
                  showInfoPopover ? Icons.cancel_outlined : Icons.info_outline,
                  color: theme.colorScheme.primary,
                ),
                tooltip: 'Code details',
                onPressed: onToggleInfo,
              ),
            ],
          ),
          const SizedBox(height: HelixSpace.xs),
          Text(
            "Paste the code your admin shared to join a private server or recover your account.",
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          // Info popover banner
          if (showInfoPopover) ...[
            const SizedBox(height: HelixSpace.md),
            Container(
              padding: HelixInsets.all(HelixSpace.md),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.help_outline, size: 18, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        "Code Details",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "• Invitation Codes (HLX-INV-… or link): Connects to a private server and verifies your device.",
                    style: theme.textTheme.bodySmall?.copyWith(height: 1.3),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "• Recovery Codes (HLX-REC-…): Instantly restores your existing Helix identity and chat keys.",
                    style: theme.textTheme.bodySmall?.copyWith(height: 1.3),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: HelixSpace.lg),
          TextFormField(
            initialValue: codeString,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Code or Link',
              hintText: 'e.g. HLX-INV-… or HLX-REC-…',
              prefixIcon: const Icon(Icons.qr_code),
              errorText: errorMessage,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onChanged: onCodeChanged,
            onFieldSubmitted: (_) => onSubmit(),
          ),
          if (upper.isNotEmpty) ...[
            const SizedBox(height: HelixSpace.sm),
            Container(
              padding: HelixInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isRecovery
                    ? theme.colorScheme.secondaryContainer.withValues(alpha: 0.6)
                    : theme.colorScheme.primaryContainer.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    isRecovery ? Icons.history : Icons.verified_outlined,
                    size: 18,
                    color: isRecovery
                        ? theme.colorScheme.onSecondaryContainer
                        : theme.colorScheme.onPrimaryContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isRecovery
                          ? "Detected: Account Recovery Code"
                          : "Detected: Server Invitation Code",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isRecovery
                            ? theme.colorScheme.onSecondaryContainer
                            : theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: HelixSpace.xl),
          FilledButton.icon(
            onPressed: isLoading ? null : onSubmit,
            style: FilledButton.styleFrom(
              padding: HelixInsets.all(HelixSpace.md),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: isLoading
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.link),
            label: Text(
              isLoading ? "Verifying…" : "Verify & Connect",
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }
}
