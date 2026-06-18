import 'dart:typed_data';
import 'package:helix_domain/application/contracts/repositories.dart';
import 'package:helix_domain/core/constants.dart';

class InMemoryEphemeralMediaCache implements EphemeralMediaCache {
  final Map<String, Uint8List> _cache = {};
  final List<String> _insertOrder = [];

  @override
  Uint8List? getMedia(String mediaId) => _cache[mediaId];

  @override
  bool hasMedia(String mediaId) => _cache.containsKey(mediaId);

  @override
  void storeMedia(String mediaId, Uint8List bytes) {
    if (_cache.containsKey(mediaId)) return;
    _cache[mediaId] = bytes;
    _insertOrder.add(mediaId);
    _enforceBudget();
  }

  @override
  void clear() {
    _cache.clear();
    _insertOrder.clear();
  }

  void _enforceBudget() {
    int total = _cache.values.fold(0, (sum, b) => sum + b.length);
    while (total > kEphemeralCacheMaxBytes && _insertOrder.isNotEmpty) {
      final evicted = _insertOrder.removeAt(0);
      final removed = _cache.remove(evicted);
      total -= removed?.length ?? 0;
    }
  }
}
