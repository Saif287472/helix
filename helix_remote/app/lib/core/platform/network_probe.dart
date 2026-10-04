import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What kind of network the device is on, for the two places that care:
/// automatic media download and backup over mobile data.
enum NetworkKind {
  /// Wi-Fi, Ethernet or anything else that is not metered mobile data.
  unmetered,

  /// Mobile data.
  mobile,

  /// No network at all.
  none,
}

abstract interface class NetworkProbe {
  Future<NetworkKind> current();

  Stream<NetworkKind> get changes;
}

final class DeviceNetworkProbe implements NetworkProbe {
  const DeviceNetworkProbe();

  static NetworkKind classify(List<ConnectivityResult> results) {
    if (results.isEmpty || results.every((r) => r == ConnectivityResult.none)) {
      return NetworkKind.none;
    }
    // Wi-Fi wins over mobile when both are up: traffic prefers it.
    final unmetered = results.any(
      (r) =>
          r == ConnectivityResult.wifi ||
          r == ConnectivityResult.ethernet ||
          r == ConnectivityResult.vpn ||
          r == ConnectivityResult.other,
    );
    if (unmetered) return NetworkKind.unmetered;
    return NetworkKind.mobile;
  }

  @override
  Future<NetworkKind> current() async {
    try {
      return classify(await Connectivity().checkConnectivity());
    } on Object {
      // A platform without the plugin: assume the best.
      return NetworkKind.unmetered;
    }
  }

  @override
  Stream<NetworkKind> get changes =>
      Connectivity().onConnectivityChanged.map(classify);
}

final networkProbeProvider = Provider<NetworkProbe>(
  (ref) => const DeviceNetworkProbe(),
);

/// The network now, and whenever it changes.
final networkKindProvider = StreamProvider<NetworkKind>((ref) async* {
  final probe = ref.watch(networkProbeProvider);
  yield await probe.current();
  yield* probe.changes;
});
