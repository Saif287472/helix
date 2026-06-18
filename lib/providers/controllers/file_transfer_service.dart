import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:helix_protocol/application/contracts/use_cases.dart';
import 'package:helix_protocol/protocol/protocol_messages.dart';
import 'package:helix_transport/services/transport/secure_channel.dart';

import 'package:helix_storage/infrastructure/storage/in_memory_transfer_repository.dart';
import 'package:helix_transfer/helix_transfer.dart';

class FileTransferService {
  FileTransferService({
    SendFileUseCase? sendFileUseCase,
    ReceiveFileCoordinator? receiveFileCoordinator,
  }) {
    final repo = InMemoryTransferRepository();

    _sendFileUseCase =
        sendFileUseCase ??
        SendFileUseCaseImpl(
          onProgressUpdate: (threadId, messageId, progress, {localFilePath}) {},
        );

    _receiveFileCoordinator =
        receiveFileCoordinator ??
        ReceiveFileCoordinatorImpl(
          repository: repo,
          onProgressUpdate: (threadId, messageId, progress, {localFilePath}) {},
          getCacheDirectory: () => getApplicationCacheDirectory(),
          // No getFinalDirectory here — this stub is used only in tests.
        );
  }

  late final SendFileUseCase _sendFileUseCase;
  late final ReceiveFileCoordinator _receiveFileCoordinator;

  Future<void> sendFile({
    required String threadId,
    required String messageId,
    required String fileId,
    required File file,
    required String mimeType,
    required SecureChannel channel,
  }) async {
    final gateway = TransferGatewayAdapter(() => channel);
    await _sendFileUseCase.sendFile(
      threadId: threadId,
      messageId: messageId,
      fileId: fileId,
      file: file,
      mimeType: mimeType,
      gateway: gateway,
    );
  }

  Future<File?> receiveChunk({
    required String threadId,
    required String messageId,
    required FileTransferFrame frame,
  }) async {
    return _receiveFileCoordinator.receiveChunk(
      threadId: threadId,
      messageId: messageId,
      frame: frame,
    );
  }

  Future<void> receiveProbe({
    required String threadId,
    required String messageId,
    required FileProbeFrame frame,
    required SecureChannel channel,
  }) async {
    final gateway = TransferGatewayAdapter(() => channel);
    await _receiveFileCoordinator.receiveProbe(
      threadId: threadId,
      messageId: messageId,
      frame: frame,
      gateway: gateway,
    );
  }

  Future<void> receiveComplete({
    required String threadId,
    required String messageId,
    required String fileId,
    required String expectedSha256,
  }) async {
    await _receiveFileCoordinator.receiveComplete(
      threadId: threadId,
      messageId: messageId,
      fileId: fileId,
      expectedSha256: expectedSha256,
    );
  }

  Future<void> cancelTransfer(String fileId) async {
    await _receiveFileCoordinator.cancelTransfer(fileId);
  }

  Future<void> cleanupOldFiles() async {
    if (_receiveFileCoordinator is ReceiveFileCoordinatorImpl) {
      await (_receiveFileCoordinator).cleanupOldFiles();
    }
  }
}
