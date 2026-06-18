// lib/ui/widgets/connectivity_banner.dart
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Streams the current connectivity results from `connectivity_plus`.
final _connectivityProvider = StreamProvider<List<ConnectivityResult>>((ref) {
  return Connectivity().onConnectivityChanged;
});

/// A banner that warns the user when the device is on cellular data only.
///
/// Peer discovery relies on local-network broadcasts, which are unavailable
/// over mobile data.  When Wi-Fi / Ethernet are absent this banner is shown;
/// otherwise it renders [SizedBox.shrink].
class ConnectivityBanner extends ConsumerWidget {
  const ConnectivityBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectivity = ref.watch(_connectivityProvider);

    return connectivity.when(
      data: (results) {
        final hasLocal = results.any(
          (r) =>
              r == ConnectivityResult.wifi || r == ConnectivityResult.ethernet,
        );
        final hasCellular = results.contains(ConnectivityResult.mobile);

        if (hasLocal || !hasCellular) return const SizedBox.shrink();

        return const _CellularWarningBanner();
      },
      loading: () => const SizedBox.shrink(),
      error: (error, stackTrace) => const SizedBox.shrink(),
    );
  }
}

class _CellularWarningBanner extends StatelessWidget {
  const _CellularWarningBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber.shade300),
      ),
      child: Row(
        children: [
          Icon(
            Icons.signal_cellular_alt,
            size: 18,
            color: Colors.orange.shade700,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'On mobile data \u2014 peer discovery requires Wi-Fi or Ethernet.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.orange.shade900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
