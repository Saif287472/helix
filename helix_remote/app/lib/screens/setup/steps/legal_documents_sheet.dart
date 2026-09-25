import 'package:flutter/material.dart';
import 'package:helix_remote/l10n/helix_localizations.dart';
import 'package:helix_remote_domain/models.dart';

/// Opens the versioned legal documents used by the Global registration flow.
Future<void> showLegalDocumentsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const LegalDocumentsSheet(),
  );
}

class LegalDocumentsSheet extends StatefulWidget {
  const LegalDocumentsSheet({super.key});

  @override
  State<LegalDocumentsSheet> createState() => _LegalDocumentsSheetState();
}

class _LegalDocumentsSheetState extends State<LegalDocumentsSheet> {
  bool _showPrivacy = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = HelixLocalizations.of(context);
    final title = _showPrivacy
        ? HelixLegalDocuments.privacyTitle
        : HelixLegalDocuments.termsTitle;
    final version = _showPrivacy
        ? HelixLegalDocuments.privacyVersion
        : HelixLegalDocuments.termsVersion;
    final text = _showPrivacy
        ? HelixLegalDocuments.privacyPolicy
        : HelixLegalDocuments.termsOfService;

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.88,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: l10n.close,
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Text(
              '${l10n.legalVersionLabel} $version · '
              '${l10n.legalEffectiveLabel} ${HelixLegalDocuments.effectiveDate}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            SegmentedButton<bool>(
              segments: [
                ButtonSegment<bool>(
                  value: false,
                  label: Text(l10n.terms),
                  icon: const Icon(Icons.description_outlined),
                ),
                ButtonSegment<bool>(
                  value: true,
                  label: Text(l10n.privacy),
                  icon: const Icon(Icons.privacy_tip_outlined),
                ),
              ],
              selected: {_showPrivacy},
              onSelectionChanged: (selection) {
                setState(() => _showPrivacy = selection.first);
              },
            ),
            const SizedBox(height: 12),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: SelectableText(
                    text,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
