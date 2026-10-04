import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/engine/local_settings.dart';
import 'package:helix_remote/core/platform/network_probe.dart';
import 'package:helix_remote/features/settings/application/settings_providers.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart'
    show MediaSettings;

/// The largest file fetched by itself when the policy allows it.
///
/// Only a ceiling: the policy decides *whether*, this decides *how big*. A
/// phone should not pull a 2 GB video unasked just because it is on Wi-Fi.
abstract final class MediaDownloadLimits {
  static const images = 10 * 1024 * 1024;
  static const audio = 10 * 1024 * 1024;
  static const video = 50 * 1024 * 1024;
  static const documents = 25 * 1024 * 1024;
}

/// The engine's limit (bytes, `0` = on request only) for [policy] on [network].
///
/// The engine's own settings are size limits that know nothing about Wi-Fi or
/// mobile data, so the person's choice ([MediaDownloadPolicy]) is turned into
/// a limit here, whenever the choice or the network changes.
int autoDownloadLimit({
  required MediaDownloadPolicy policy,
  required NetworkKind network,
  required int ceiling,
}) => switch (policy) {
  MediaDownloadPolicy.never => MediaSettings.never,
  MediaDownloadPolicy.always => ceiling,
  MediaDownloadPolicy.wifi =>
    network == NetworkKind.unmetered ? ceiling : MediaSettings.never,
};

/// Keeps the engine's auto-download limits in step with the person's choices
/// and the network. Read once at start-up (`ref.read(mediaPolicySyncProvider)`);
/// it rebuilds whenever a choice or the network changes, and writes only the
/// limits that differ from what the engine already has.
final mediaPolicySyncProvider = Provider<void>((ref) {
  final images = ref.watch(mediaImagesProvider).value;
  final audio = ref.watch(mediaAudioProvider).value;
  final video = ref.watch(mediaVideoProvider).value;
  final documents = ref.watch(mediaDocumentsProvider).value;
  final network = ref.watch(networkKindProvider).value ?? NetworkKind.unmetered;
  // Until every choice has been read, writing anything could overwrite one
  // the person made with a default.
  if (images == null || audio == null || video == null || documents == null) {
    return;
  }
  final store = ref.read(localSettingsProvider);
  final plan = [
    (MediaSettings.autoDownloadImages, images, MediaDownloadLimits.images),
    (MediaSettings.autoDownloadAudio, audio, MediaDownloadLimits.audio),
    (MediaSettings.autoDownloadVideo, video, MediaDownloadLimits.video),
    (
      MediaSettings.autoDownloadDocuments,
      documents,
      MediaDownloadLimits.documents,
    ),
  ];
  Future<void> apply() async {
    for (final (setting, policy, ceiling) in plan) {
      final limit = autoDownloadLimit(
        policy: policy,
        network: network,
        ceiling: ceiling,
      );
      if (await store.get(setting) != limit) await store.set(setting, limit);
    }
  }

  unawaited(apply());
});
