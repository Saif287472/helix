import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:helix_remote/features/people/application/contact_info.dart';
import 'package:helix_remote/features/people/presentation/widgets/key_changed_banner.dart';
import 'package:helix_remote/shared/navigation/people_paths.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// The safety number of a chat: sixty digits both of you can read to each
/// other, and a QR code each of you can scan from the other's phone.
///
/// If the numbers match, nobody is sitting between the two of you, and the
/// chat can be marked verified. If a person's key changes, the verified mark is
/// cleared by the engine and this screen is where it is put back.
class SafetyNumberScreen extends ConsumerWidget {
  const SafetyNumberScreen({super.key, required this.accountId});

  final String accountId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final person = ref.watch(contactPersonProvider(accountId)).value;
    final number = ref.watch(safetyNumberProvider(accountId));
    final name = (person ?? ContactPerson.unknown(accountId)).name.display;
    final trust = person?.trust ?? TrustState.noKey;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Safety number')),
      body: number.when(
        loading: () => const HelixAsyncPanel(loading: true, child: SizedBox()),
        error: (_, _) => const HelixErrorState(
          message: 'The safety number could not be worked out. Try again.',
        ),
        data: (data) {
          if (data == null) {
            return const HelixEmptyState(
              icon: Icons.verified_user_outlined,
              title: 'No safety number yet',
              message:
                  'Send a message first. A safety number needs both of your '
                  'keys.',
            );
          }
          return ListView(
            padding: const EdgeInsets.all(HelixSpace.md),
            children: [
              if (trust == TrustState.keyChanged) KeyChangedBanner(name: name),
              Center(
                child: HelixQrDisplay(
                  matrix: data.qrMatrix,
                  semanticLabel: 'QR code for the safety number with $name',
                ),
              ),
              const SizedBox(height: HelixSpace.md),
              HelixSafetyNumberView(
                groups: data.groups,
                verified: trust == TrustState.verified,
              ),
              const SizedBox(height: HelixSpace.md),
              Text(
                'To check that your chat with $name is private, compare this '
                'number with the one on their phone, or scan their QR code. '
                'If they match, nobody can be listening in.',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: HelixSpace.md),
              FilledButton.icon(
                onPressed: () => context.push(PeoplePaths.scan(accountId)),
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Scan their code'),
              ),
              const SizedBox(height: HelixSpace.xs),
              if (trust == TrustState.verified)
                OutlinedButton(
                  onPressed: () => ref
                      .read(contactInfoActionsProvider)
                      .setVerified(accountId, verified: false),
                  child: const Text('Mark as not verified'),
                )
              else
                OutlinedButton(
                  onPressed: () => ref
                      .read(contactInfoActionsProvider)
                      .setVerified(accountId, verified: true),
                  child: const Text('Mark as verified'),
                ),
            ],
          );
        },
      ),
    );
  }
}
