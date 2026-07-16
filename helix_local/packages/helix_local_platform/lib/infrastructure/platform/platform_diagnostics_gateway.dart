import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:helix_local_protocol/application/contracts/gateways.dart';

class PlatformDiagnosticsGateway implements DiagnosticsGateway {
  final NetworkInfo _info;
  final Connectivity _connectivity;

  PlatformDiagnosticsGateway({NetworkInfo? info, Connectivity? connectivity})
    : _info = info ?? NetworkInfo(),
      _connectivity = connectivity ?? Connectivity();

  @override
  Future<String?> getWifiIP() async {
    try {
      return await _info.getWifiIP();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String?> getWifiName() async {
    try {
      if (Platform.isAndroid) {
        var networkName = await _info.getWifiName();
        if (networkName != null &&
            networkName.startsWith('"') &&
            networkName.endsWith('"') &&
            networkName.length > 1) {
          networkName = networkName.substring(1, networkName.length - 1);
        }
        return networkName;
      }
    } catch (_) {}
    return null;
  }

  @override
  Future<String> getConnectivityType() async {
    try {
      final results = await _connectivity.checkConnectivity();
      final result = results.isNotEmpty
          ? results.first
          : ConnectivityResult.none;
      return _connectivityLabel(result);
    } catch (_) {
      return 'Other';
    }
  }

  String _connectivityLabel(ConnectivityResult result) {
    switch (result) {
      case ConnectivityResult.wifi:
        return 'Wi-Fi';
      case ConnectivityResult.ethernet:
        return 'Ethernet';
      case ConnectivityResult.mobile:
        return 'Mobile';
      case ConnectivityResult.bluetooth:
        return 'Bluetooth';
      case ConnectivityResult.vpn:
        return 'VPN';
      case ConnectivityResult.other:
        return 'Other';
      case ConnectivityResult.none:
        return 'None';
      default:
        return 'Other';
    }
  }
}
