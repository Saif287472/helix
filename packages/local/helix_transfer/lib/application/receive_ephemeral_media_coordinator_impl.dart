import 'dart:async';
import 'dart:typed_data';
import 'package:helix_domain/application/contracts/repositories.dart';
import 'package:helix_protocol/application/contracts/use_cases.dart';
import 'package:helix_domain/core/constants.dart';
import 'package:helix_protocol/protocol/protocol_messages.dart';

class _Assembly {
  _Assembly({
    required this.chunkCount,
    required this.totalSize,
    required this.mimeType,
  }) : slots = List<Uint8List?>.filled(chunkCount, null);

  final int chunkCount;
  final int totalSize;
  final String mimeType;
  final List<Uint8List?> slots;
  int received = 0;
}

class ReceiveEphemeralMediaCoordinatorImpl
    implements ReceiveEphemeralMediaCoordinator {
  ReceiveEphemeralMediaCoordinatorImpl({required this._cache});

  final EphemeralMediaCache _cache;
  final Map<String, _Assembly> _assembling = {};
  final Map<String, Timer> _assemblyTimers = {};

  static const kMaxPendingMediaAssemblies = 16;
  static const kAssemblyTimeout = Duration(seconds: 30);

  int _getTotalPendingBytes() {
    int total = 0;
    for (final assembly in _assembling.values) {
      for (final slot in assembly.slots) {
        if (slot != null) total += slot.length;
      }
    }
    return total;
  }

  @override
  Uint8List? receiveChunk(EphemeralMediaFrame frame) {
    final validId = RegExp(r'^[a-zA-Z0-9_\-]{1,64}$');
    if (!validId.hasMatch(frame.mediaId)) {
      return null;
    }

    final maxBytes = frame.mimeType.startsWith('image/')
        ? kEphemeralImageMaxBytes
        : frame.mimeType.startsWith('audio/')
        ? kEphemeralVoiceMaxBytes
        : 0;
    final maxChunks =
        (maxBytes + kEphemeralMediaChunkSize - 1) ~/ kEphemeralMediaChunkSize;

    if (frame.totalSize <= 0 ||
        frame.totalSize > maxBytes ||
        frame.chunkCount <= 0 ||
        frame.chunkCount > maxChunks ||
        frame.chunkIndex < 0 ||
        frame.chunkIndex >= frame.chunkCount ||
        frame.chunkData.isEmpty ||
        frame.chunkData.length > kEphemeralMediaChunkSize) {
      cancelAssembly(frame.mediaId);
      return null;
    }

    var assembly = _assembling[frame.mediaId];
    if (assembly == null) {
      if (_assembling.length >= kMaxPendingMediaAssemblies) {
        return null;
      }
      if (_getTotalPendingBytes() + frame.totalSize > kEphemeralCacheMaxBytes) {
        return null;
      }
      assembly = _Assembly(
        chunkCount: frame.chunkCount,
        totalSize: frame.totalSize,
        mimeType: frame.mimeType,
      );
      _assembling[frame.mediaId] = assembly;
    } else {
      if (assembly.chunkCount != frame.chunkCount ||
          assembly.totalSize != frame.totalSize ||
          assembly.mimeType != frame.mimeType) {
        cancelAssembly(frame.mediaId);
        return null;
      }
    }

    _assemblyTimers[frame.mediaId]?.cancel();
    _assemblyTimers[frame.mediaId] = Timer(kAssemblyTimeout, () {
      cancelAssembly(frame.mediaId);
    });

    if (frame.chunkIndex < assembly.slots.length &&
        assembly.slots[frame.chunkIndex] == null) {
      assembly.slots[frame.chunkIndex] = frame.chunkData;
      assembly.received++;
    }

    if (assembly.received < frame.chunkCount) return null;
    cancelAssembly(frame.mediaId);

    // Reassemble in order.
    final builder = BytesBuilder(copy: false);
    for (final slot in assembly.slots) {
      if (slot != null) builder.add(slot);
    }
    final bytes = builder.toBytes();
    if (bytes.length != frame.totalSize) return null;
    _cache.storeMedia(frame.mediaId, bytes);
    return bytes;
  }

  @override
  void cancelAssembly(String mediaId) {
    _assembling.remove(mediaId);
    _assemblyTimers.remove(mediaId)?.cancel();
  }

  @override
  bool isAssembling(String mediaId) {
    return _assembling.containsKey(mediaId);
  }

  @override
  void dispose() {
    for (final timer in _assemblyTimers.values) {
      timer.cancel();
    }
    _assemblyTimers.clear();
    _assembling.clear();
  }
}
