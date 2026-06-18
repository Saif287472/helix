import 'dart:typed_data';

import 'package:uuid/uuid.dart';
import 'package:helix_local_domain/application/contracts/repositories.dart';
import 'package:helix_local_protocol/application/contracts/use_cases.dart';
import 'package:helix_local_protocol/protocol/protocol_messages.dart';
import 'package:helix_local_transport/services/transport/secure_channel.dart';

import 'package:helix_local_storage/infrastructure/storage/in_memory_ephemeral_media_cache.dart';
import 'package:helix_local_transfer/helix_transfer.dart';

class EphemeralMediaService {
  EphemeralMediaService({
    EphemeralMediaCache? cache,
    SendEphemeralMediaUseCase? sendEphemeralMediaUseCase,
    ReceiveEphemeralMediaCoordinator? receiveEphemeralMediaCoordinator,
  }) {
    _cache = cache ?? InMemoryEphemeralMediaCache();

    _sendEphemeralMediaUseCase =
        sendEphemeralMediaUseCase ??
        SendEphemeralMediaUseCaseImpl(
          cache: _cache,
          onProgressUpdate: (threadId, messageId, progress, {localFilePath}) {},
        );

    _receiveEphemeralMediaCoordinator =
        receiveEphemeralMediaCoordinator ??
        ReceiveEphemeralMediaCoordinatorImpl(cache: _cache);
  }

  late final EphemeralMediaCache _cache;
  late final SendEphemeralMediaUseCase _sendEphemeralMediaUseCase;
  late final ReceiveEphemeralMediaCoordinator _receiveEphemeralMediaCoordinator;

  Uint8List? getMedia(String mediaId) => _cache.getMedia(mediaId);

  bool hasMedia(String mediaId) => _cache.hasMedia(mediaId);

  Future<Uint8List> prepareImage(Uint8List bytes) async {
    return _sendEphemeralMediaUseCase.prepareImage(bytes);
  }

  Uint8List prepareVoice(Uint8List bytes) {
    return _sendEphemeralMediaUseCase.prepareVoice(bytes);
  }

  Future<void> sendMedia({
    required String mediaId,
    required String mimeType,
    required Uint8List prepared,
    required SecureChannel channel,
    required String threadId,
    required String messageId,
  }) async {
    final gateway = EphemeralMediaGatewayAdapter(() => channel);
    await _sendEphemeralMediaUseCase.sendMedia(
      mediaId: mediaId,
      mimeType: mimeType,
      prepared: prepared,
      threadId: threadId,
      messageId: messageId,
      gateway: gateway,
    );
  }

  Uint8List? receiveChunk(EphemeralMediaFrame frame) {
    return _receiveEphemeralMediaCoordinator.receiveChunk(frame);
  }

  void cancelAssembly(String mediaId) {
    _receiveEphemeralMediaCoordinator.cancelAssembly(mediaId);
  }

  bool isAssembling(String mediaId) {
    return _receiveEphemeralMediaCoordinator.isAssembling(mediaId);
  }

  static const _uuid = Uuid();
  static String generateMediaId() => _uuid.v4();
}
