import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/features/settings/application/about_providers.dart';
import 'package:orbit_ui/orbit_ui.dart' as orbit;

/// Connector: the Terms and the Privacy Policy, from the server (or the copy
/// shipped with the app), drawn by `orbit_ui`'s [orbit.LegalScreen].
class LegalPage extends ConsumerWidget {
  const LegalPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final legal = ref.watch(legalProvider);
    final value = legal.value;
    if (value == null) {
      return orbit.OrbitYouPage(
        title: 'Terms and Privacy Policy',
        children: [
          if (legal.hasError)
            orbit.OrbitLoadFailed(
              title: 'The documents could not be loaded.',
              onRetry: () => ref.invalidate(legalProvider),
            )
          else
            const orbit.OrbitPageLoading(),
        ],
      );
    }
    final shipped = value.fromServer ? '' : ' (copy shipped with the app)';
    return orbit.LegalScreen(
      model: orbit.LegalModel(
        terms: orbit.LegalDocument(
          title: value.termsTitle,
          version: '${value.termsVersion}$shipped',
          body: value.terms,
        ),
        privacy: orbit.LegalDocument(
          title: value.privacyTitle,
          version: '${value.privacyVersion}$shipped',
          body: value.privacy,
        ),
      ),
    );
  }
}
