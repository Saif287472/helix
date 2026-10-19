import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:helix_remote/features/people/application/contact_info.dart';
import 'package:helix_remote/shared/navigation/people_paths.dart';
import 'package:orbit_ui/orbit_ui.dart' as orbit;

/// Connector: the safety number of a chat, sixty digits both of you can read
/// to each other and a QR code each of you can scan from the other's phone,
/// drawn by `orbit_ui`'s Safety number.
///
/// If the numbers match, nobody is sitting between the two of you, and the
/// chat can be marked verified. If a person's key changes, the verified mark
/// is cleared by the engine and this screen is where it is put back.
class SafetyNumberScreen extends ConsumerWidget {
  const SafetyNumberScreen({super.key, required this.accountId});

  final String accountId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final person = ref.watch(contactPersonProvider(accountId)).value;
    final number = ref.watch(safetyNumberProvider(accountId));
    final data = number.value;
    final name = (person ?? ContactPerson.unknown(accountId)).name.display;
    return orbit.SafetyNumberScreen(
      model: orbit.SafetyNumberModel(
        name: name,
        trust: switch (person?.trust ?? TrustState.noKey) {
          TrustState.noKey => orbit.TrustState.noKey,
          TrustState.unverified => orbit.TrustState.unverified,
          TrustState.verified => orbit.TrustState.verified,
          TrustState.keyChanged => orbit.TrustState.keyChanged,
        },
        // Null with a value: no key pinned yet, "No safety number yet".
        groups: data?.groups,
        qr: data?.qrMatrix,
        loading: number.isLoading && !number.hasValue,
        loadFailed: number.hasError && !number.hasValue,
      ),
      actions: orbit.SafetyNumberActions(
        onScan: () => context.push(PeoplePaths.scan(accountId)),
        onSetVerified: (verified) => ref
            .read(contactInfoActionsProvider)
            .setVerified(accountId, verified: verified),
        onRetry: () => ref.invalidate(safetyNumberProvider(accountId)),
      ),
    );
  }
}
