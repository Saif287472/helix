import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/features/settings/application/about_providers.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// Settings > Help and about > Terms and Privacy Policy.
///
/// The documents come from the server with their version numbers, so what is
/// shown is what the server holds you to. When the server cannot be reached
/// the copy shipped with the app is shown, and says so.
class LegalPage extends ConsumerStatefulWidget {
  const LegalPage({super.key});

  @override
  ConsumerState<LegalPage> createState() => _LegalPageState();
}

class _LegalPageState extends ConsumerState<LegalPage> {
  var _privacy = false;

  @override
  Widget build(BuildContext context) {
    final legal = ref.watch(legalProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Terms and Privacy Policy')),
      body: switch (legal) {
        AsyncData(:final value) => ListView(
          padding: const EdgeInsets.all(HelixSpace.md),
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Terms')),
                ButtonSegment(value: true, label: Text('Privacy')),
              ],
              selected: {_privacy},
              onSelectionChanged: (v) => setState(() => _privacy = v.first),
            ),
            const SizedBox(height: HelixSpace.md),
            Text(
              _privacy ? value.privacyTitle : value.termsTitle,
              style: theme.textTheme.titleLarge,
            ),
            Text(
              'Version ${_privacy ? value.privacyVersion : value.termsVersion}'
              '${value.fromServer ? '' : ' (copy shipped with the app)'}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: HelixSpace.md),
            Text(_privacy ? value.privacy : value.terms),
          ],
        ),
        AsyncError() => HelixErrorState(
          message: 'The documents could not be loaded.',
          onRetry: () => ref.invalidate(legalProvider),
        ),
        _ => const Padding(
          padding: EdgeInsets.all(HelixSpace.lg),
          child: LinearProgressIndicator(),
        ),
      },
    );
  }
}
