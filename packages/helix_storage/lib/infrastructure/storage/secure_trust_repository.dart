import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:helix_domain/core/constants.dart';
import 'package:helix_domain/domain/models.dart';
import 'package:helix_domain/application/contracts/repositories.dart';

class SecureTrustRepository implements TrustRepository {
  final FlutterSecureStorage _storage;

  const SecureTrustRepository({this._storage = const FlutterSecureStorage()});

  @override
  Future<List<KnownPeer>> loadKnownPeers() async {
    try {
      final raw = await _storage.read(key: kKeyKnownPeers);
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List<dynamic>;
        return list
            .map((e) => KnownPeer.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {
      // Corrupt data or not found — return empty list
    }
    return [];
  }

  @override
  Future<void> saveKnownPeers(List<KnownPeer> peers) async {
    final json = jsonEncode(peers.map((p) => p.toJson()).toList());
    await _storage.write(key: kKeyKnownPeers, value: json);
  }
}
