import 'dart:io';

import 'package:helix_remote/core/platform/app_storage.dart';
import 'package:helix_remote/core/sounds/orbit_sounds.dart';
import 'package:helix_remote/core/theme/orbit_app_theme.dart'
    show FileDeviceSettingsStore;
import 'package:helix_remote/core/theme/orbit_packs.dart' show PackTrust;
import 'package:path/path.dart' as p;

/// The sound an incoming call rings with, in the form Android's notification
/// system needs it: one channel per ringtone (a channel's sound cannot change
/// once it is created) and a `content://` address for the file.
final class CallRingtone {
  const CallRingtone({
    required this.id,
    required this.channelId,
    required this.uri,
  });

  /// The pack's signed id, which is also the name the ringtone has on screen.
  final String id;

  /// The channel that rings this ringtone. Android fixes a channel's sound when
  /// the channel is created, so the id carries the pack id and the audio kind;
  /// a ringtone whose bytes change keeps its channel and plays the new file.
  final String channelId;

  /// The `content://` address of the copy, served by the provider declared in
  /// `AndroidManifest.xml`.
  final String uri;
}

/// The ringtone chosen on this device, made reachable to the phone.
///
/// The pack folder is the app's private data, which Android's notification
/// service cannot open, so choosing a ringtone writes one copy into the app's
/// external files folder and the system reads it through a provider scoped to
/// that folder alone (`AndroidManifest.xml`, `res/xml/helix_remote_ringtones.xml`).
/// The copy is made when the choice is made, never when a call arrives: a call
/// cannot wait for a download.
///
/// Provider-free on purpose: the FCM isolate (`push_background.dart`) has no
/// Riverpod container, and it is the path a call rings through when the app is
/// not running.
abstract final class Ringtones {
  /// The provider authority in `AndroidManifest.xml`. Kept here as well so the
  /// URI is built in one place; a test reads the manifest and compares.
  static const authority = 'com.helix.remote.ringtones';

  /// The channels a ringtone may ring on, before the pack id and audio kind.
  static const channelPrefix = 'helix_incoming_calls_ringtone.';

  /// The channel that rings pack [id] at [suffix] (`.m4a`, `.mp3`, ...).
  static String channelId(String id, String suffix) =>
      '$channelPrefix$id$suffix';

  /// Where Android's system reads the copy of [id] at [suffix].
  static String uri(String id, String suffix) =>
      'content://$authority/ringtones/$id$suffix';

  /// Writes the copy of [sound] the system rings with, replacing the previous
  /// choice's copy (a copy only exists while its ringtone is the choice).
  /// [sound] must have come from [SoundPackStore], which is what puts it
  /// through the gate.
  ///
  /// True when there is nothing left to do: off Android (where nothing rings
  /// through a channel) or once the copy is in place. False is a device whose
  /// external storage cannot be written; the page then keeps the phone's own
  /// ringtone, so what a call rings with is what the page says.
  static Future<bool> publish(InstalledSound sound) async {
    if (!AppPaths.isAndroid()) return true;
    try {
      final dir = await AppPaths.ringtoneDirectory();
      if (dir == null) return false;
      final name = '${sound.id}${sound.suffix}';
      final target = File(p.join(dir.path, name));
      final temp = File('${target.path}.part');
      try {
        await sound.file.copy(temp.path);
        // A rename in one folder is atomic, so a call never reads half a file.
        await temp.rename(target.path);
      } on Object {
        try {
          if (await temp.exists()) await temp.delete();
        } on Object {
          // Left for the next publish to overwrite.
        }
        return false;
      }
      await _removeCopies(dir, keep: target.path);
      return true;
    } on Object {
      return false;
    }
  }

  /// Deletes the copy of pack [id], or every copy when [id] is null.
  ///
  /// Called when the ringtone is deleted and when the phone's own sound is
  /// chosen again, so the only file outside the pack folder is one a call can
  /// actually ring with.
  static Future<void> forget({String? id}) async {
    if (!AppPaths.isAndroid()) return;
    try {
      final dir = await AppPaths.ringtoneDirectory(create: false);
      if (dir == null || !await dir.exists()) return;
      await _removeCopies(dir, id: id, keep: '');
    } on Object {
      // A copy that cannot be deleted stays until the next clean-up; the pack
      // it came from is gone either way, so nothing can ring it.
    }
  }

  /// What the next call rings with: null for the phone's own ringtone (no
  /// choice, or a chosen pack this device no longer holds or cannot have
  /// copied).
  ///
  /// The pack is gate-checked again here, on every call, exactly as every other
  /// read of the folder is: a manifest edited after its download is not a
  /// ringtone. [publishers] is the build's anchor; a test passes its own.
  static Future<CallRingtone?> chosen({
    Map<String, List<int>>? publishers,
  }) async {
    if (!AppPaths.isAndroid()) return null;
    try {
      final id = await const FileDeviceSettingsStore().readRingtone();
      if (id == null) return null;
      final sound = await SoundPackStore(
        trustedPublishers: publishers ?? PackTrust.forThisBuildOrNone(),
      ).load(id);
      if (sound == null) return null;
      final dir = await AppPaths.ringtoneDirectory(create: false);
      if (dir == null) return null;
      final copy = File(p.join(dir.path, '${sound.id}${sound.suffix}'));
      if (!await copy.exists()) return null;
      return CallRingtone(
        id: sound.id,
        channelId: channelId(sound.id, sound.suffix),
        uri: uri(sound.id, sound.suffix),
      );
    } on Object {
      // A file the app cannot read is a call that rings with the phone's own
      // sound, never one that cannot ring at all.
      return null;
    }
  }

  /// Deletes the copies of [id] (or all of them for [id] null), except [keep].
  static Future<void> _removeCopies(
    Directory dir, {
    String? id,
    required String keep,
  }) async {
    final List<FileSystemEntity> entries;
    try {
      entries = dir.listSync();
    } on Object {
      // The folder this would clean is not there any more: nothing left to do.
      return;
    }
    final prefix = id == null ? '' : '$id.';
    for (final entry in entries) {
      if (entry is! File) continue;
      if (entry.path == keep) continue;
      if (prefix.isNotEmpty && !p.basename(entry.path).startsWith(prefix)) {
        continue;
      }
      try {
        await entry.delete();
      } on Object {
        // One stuck file must not stop the others.
      }
    }
  }
}
