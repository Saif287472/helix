// Transfer providers: file transfer and ephemeral media services.
import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:helix/providers/infrastructure_providers.dart';
import 'package:helix/providers/messaging_providers.dart'
    show messagingServiceProvider;
import 'package:helix/providers/controllers/file_transfer_service.dart';
import 'package:helix/providers/controllers/ephemeral_media_service.dart';
import 'package:helix_local_transfer/helix_transfer.dart';

final fileTransferServiceProvider = Provider<FileTransferService>((ref) {
  final messaging = ref.watch(messagingServiceProvider);
  final repo = ref.watch(transferRepositoryProvider);

  final sendFileUseCase = SendFileUseCaseImpl(
    onProgressUpdate: (threadId, messageId, progress, {localFilePath}) {
      messaging.updateTransferProgress(
        threadId,
        messageId,
        progress,
        localFilePath: localFilePath,
      );
    },
  );

  final receiveFileCoordinator = ReceiveFileCoordinatorImpl(
    repository: repo,
    onProgressUpdate: (threadId, messageId, progress, {localFilePath}) {
      messaging.updateTransferProgress(
        threadId,
        messageId,
        progress,
        localFilePath: localFilePath,
      );
    },
    getCacheDirectory: () => getApplicationCacheDirectory(),
    getFinalDirectory: _helixMediaDir,
  );
  ref.onDispose(() => unawaited(receiveFileCoordinator.dispose()));

  return FileTransferService(
    sendFileUseCase: sendFileUseCase,
    receiveFileCoordinator: receiveFileCoordinator,
  );
});

final ephemeralMediaServiceProvider = Provider<EphemeralMediaService>((ref) {
  final messaging = ref.watch(messagingServiceProvider);
  final cache = ref.watch(ephemeralMediaCacheProvider);

  final sendEphemeralMediaUseCase = SendEphemeralMediaUseCaseImpl(
    cache: cache,
    onProgressUpdate: (threadId, messageId, progress, {localFilePath}) {
      messaging.updateTransferProgress(
        threadId,
        messageId,
        progress,
        localFilePath: localFilePath,
      );
    },
  );

  final receiveEphemeralMediaCoordinator = ReceiveEphemeralMediaCoordinatorImpl(
    cache: cache,
  );
  ref.onDispose(receiveEphemeralMediaCoordinator.dispose);

  return EphemeralMediaService(
    cache: cache,
    sendEphemeralMediaUseCase: sendEphemeralMediaUseCase,
    receiveEphemeralMediaCoordinator: receiveEphemeralMediaCoordinator,
  );
});

// ---------------------------------------------------------------------------
// Media directory helpers
// ---------------------------------------------------------------------------

String _mediaCategoryForMime(String mimeType) {
  if (mimeType.startsWith('image/')) return 'Images';
  if (mimeType.startsWith('audio/')) return 'Audio';
  if (mimeType.startsWith('video/')) return 'Video';
  return 'Others';
}

Future<Directory> _helixMediaDir(String mimeType) async {
  Directory? base;
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    base = await getDownloadsDirectory();
  }
  base ??= await getExternalStorageDirectory();
  base ??= await getApplicationDocumentsDirectory();

  final dir = Directory(
    p.join(base.path, 'Helix', 'Media', _mediaCategoryForMime(mimeType)),
  );
  await dir.create(recursive: true);
  return dir;
}
