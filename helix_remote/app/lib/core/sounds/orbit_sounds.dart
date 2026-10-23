import 'dart:io';

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/theme/orbit_packs.dart';

/// The ringtones this device has downloaded.
///
/// Same folder, same gate, same rules as a theme pack - because a downloadable
/// ringtone arrives as a signed pack too (`orbit/PORT_PLAN.md` Part C step 5,
/// the owner's ruling). What differs is only what the app makes of a pack once
/// the gate has passed: a theme becomes [OrbitTokens] to draw with, a sound
/// becomes the one file a phone can ring with, and neither store reads the
/// other's packs. A server folder that holds both kinds therefore lists both,
/// and a device shows each on its own page.
///
/// The sounds that ship with the build are not packs and never come through
/// here: [BuiltInRingtones] in `orbit_ringtones.dart` is where those live.
///
/// Nothing here plays a sound. The ringer that does is
/// `features/calls/application/platform/notification_call_ringer.dart`, and
/// Android decides which sound a call rings with when it makes the
/// notification channel, so a channel is per ringtone, not per call.
final class SoundPackStore {
  SoundPackStore({Map<String, List<int>>? trustedPublishers})
    : _packs = PackFolder(
        contents: 'sound',
        decode: _sound,
        trustedPublishers: trustedPublishers,
      );

  final PackFolder<InstalledSound> _packs;

  /// Every sound on this device the app can ring with: one entry per id, the
  /// newest revision that passes the gate, in id order.
  Future<List<InstalledSound>> installed() async => [
    for (final pack in await _packs.stored()) pack.value,
  ];

  /// The installed sound [id], or null when the device has no pack it can ring
  /// with under that name.
  Future<InstalledSound?> load(String id) async =>
      (await _packs.load(id))?.value;

  /// Downloads sound [id]. The rules - the newest revision on offer, the caps
  /// paid for before a byte is fetched, the staging a refusal never leaves - are
  /// [PackFolder.install]'s.
  Future<PackChange> install(PackSource source, String id, {int? revision}) =>
      _packs.install(source, id, revision: revision);

  /// Deletes sound [id] and the bytes it downloaded.
  Future<bool> remove(String id) => _packs.remove(id);

  /// A sound pack is exactly one audio file and no theme document, so the pack
  /// is that file: named by its digest, which is how it is stored, and never by
  /// a path the manifest wrote.
  static InstalledSound? _sound(PackBytes pack) {
    final file = pack.manifest.files.where((f) => f.kind == 'audio').single;
    return InstalledSound(
      id: pack.id,
      revision: pack.revision,
      bytes: pack.bytes,
      file: pack.fileAt(file),
      suffix: _suffixOf(file.path),
    );
  }
}

/// One sound this device holds, as far as the app is concerned.
@immutable
final class InstalledSound {
  const InstalledSound({
    required this.id,
    required this.revision,
    required this.bytes,
    required this.file,
    required this.suffix,
  });

  final String id;

  /// The revision this folder holds, which is the newest the app found for [id].
  final int revision;

  /// Its manifest and its file together.
  final int bytes;

  /// The audio itself, in the pack's own folder. Read-only to the app: it is
  /// what a notification channel's sound is pointed at.
  final File file;

  /// The suffix the pack's file name ended with (`.m4a`, `.mp3`, ...), which the
  /// platform copy keeps so the system can tell what kind of audio it is being
  /// handed. The pack's own file is stored by its digest and has no suffix.
  final String suffix;
}

/// The publisher keys this build downloads sounds from - the same anchor the
/// themes use, because it is one format and one publisher.
final soundPackStoreProvider = Provider<SoundPackStore>(
  (ref) => SoundPackStore(trustedPublishers: ref.watch(packPublishersProvider)),
);

/// The lower-case suffix of a pack file path, or an empty string for a path the
/// format would have refused anyway.
String _suffixOf(String path) {
  final dot = path.lastIndexOf('.');
  return dot < 0 ? '' : path.substring(dot).toLowerCase();
}
