import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/platform/app_storage.dart';
import 'package:path/path.dart' as p;

/// How much room Helix uses on this phone, split the way a person thinks of
/// it: the encrypted database (messages, keys), downloaded media, and the
/// theme packs that were got from the server.
final class StorageUsage {
  const StorageUsage({
    this.databaseBytes = 0,
    this.mediaBytes = 0,
    this.packBytes = 0,
  });

  final int databaseBytes;
  final int mediaBytes;

  /// What the packs in `packs/` take. Separate from [mediaBytes] because it is
  /// not chat content, and a person can delete it themselves on Appearance.
  final int packBytes;

  int get totalBytes => databaseBytes + mediaBytes + packBytes;
}

abstract interface class StorageUsageProbe {
  Future<StorageUsage> measure();
}

final class DeviceStorageUsageProbe implements StorageUsageProbe {
  const DeviceStorageUsageProbe();

  @override
  Future<StorageUsage> measure() async {
    try {
      final base = await AppPaths.appDirectory();
      final packs = await AppPaths.packsDirectory();
      var database = 0;
      var media = 0;
      var themes = 0;
      await for (final entity in base.list(recursive: true)) {
        if (entity is! File) continue;
        final size = await entity.length();
        final name = p.basename(entity.path);
        if (name.startsWith('helix_remote.db')) {
          database += size;
        } else if (p.isWithin(packs.path, entity.path)) {
          themes += size;
        } else if (name != 'profile_avatar.png') {
          media += size;
        }
      }
      return StorageUsage(
        databaseBytes: database,
        mediaBytes: media,
        packBytes: themes,
      );
    } on Object {
      return const StorageUsage();
    }
  }
}

final storageUsageProbeProvider = Provider<StorageUsageProbe>(
  (ref) => const DeviceStorageUsageProbe(),
);
