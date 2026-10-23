import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/platform/app_storage.dart';
import 'package:helix_remote_domain/models.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart'
    show OrbitPackEntry;
import 'package:orbit_ui/orbit_ui.dart' show OrbitEffects, OrbitTokens;
import 'package:path/path.dart' as p;

/// Whose packs this build will draw with: the pack format's trust anchor
/// (`orbit/PORT_PLAN.md` Part C, ADR-033).
///
/// **Empty unless the build passes**
/// `--dart-define=HELIX_PACK_PUBLISHERS=slug:hex,slug:hex`, where `hex` is the
/// 32-byte Ed25519 public key `dart run tool/theme_pack_tool.dart keygen`
/// prints. With nothing defined, every pack is refused as
/// [OrbitPackFailure.unknownPublisher] - which is the state the app ships in
/// today, and the safe one: a pack folder on a server is an invitation, and
/// only the key says whose invitation to accept.
///
/// Build-time rather than a page where someone types a key, because that is
/// the only place a release app can get the anchor from. It mirrors TLS pinning
/// ([`TlsPinPolicy`]): a define that turns a security decision on, off by
/// default, and a malformed value is refused rather than half-read.
abstract final class PackTrust {
  /// The value of the `HELIX_PACK_PUBLISHERS` define, empty in a build that
  /// passed none.
  static const defined = String.fromEnvironment('HELIX_PACK_PUBLISHERS');

  /// The keys this build trusts: [defined] unless a test passes its own.
  static Map<String, List<int>> forThisBuild([String? source]) =>
      parse(source ?? defined);

  /// Reads `slug:hex,slug:hex` into publisher id to raw key bytes.
  ///
  /// Throws [FormatException] for an entry that is not a slug and 64 hex
  /// characters. A typo in the anchor is a build that cannot download anything,
  /// so it is an error and never a silently missing publisher.
  static Map<String, List<int>> parse(String source) {
    final publishers = <String, List<int>>{};
    for (final entry in source.split(',')) {
      final pair = entry.trim();
      if (pair.isEmpty) continue;
      final colon = pair.lastIndexOf(':');
      final slug = colon < 0 ? '' : pair.substring(0, colon);
      final hex = colon < 0 ? '' : pair.substring(colon + 1);
      if (!_isSlug(slug) || hex.length != 64 || !_isHex(hex)) {
        throw const FormatException(
          'HELIX_PACK_PUBLISHERS holds "slug:hex" pairs separated by commas, '
          'where hex is 64 hexadecimal characters',
        );
      }
      publishers[slug] = _fromHex(hex);
    }
    return publishers;
  }

  /// The parse, with a build's bad anchor read as "trusts nobody" - only for
  /// the read path, where a typo in a define must not stop the app starting or
  /// leave it with no theme at all: the packs on the device are then refused as
  /// [OrbitPackFailure.unknownPublisher] and Orbit is drawn. The pages that
  /// manage packs use [forThisBuild], which fails the action instead of quietly
  /// trusting nobody, so a build with a broken anchor is noticed.
  static Map<String, List<int>> forThisBuildOrNone([String? source]) {
    try {
      return parse(source ?? defined);
    } on FormatException {
      return const {};
    }
  }
}

/// Where the packs a person downloads are kept, and what the app will draw
/// with them.
///
/// The folder is the server's own layout: `manifest.json` in
/// `packs/<id>/r<revision>` beside a `files` folder of SHA-256 names, so a pack
/// is one folder a device can hold and re-check, and a file two revisions share
/// is stored once. Nothing here knows the format: `checkOrbitPack` in
/// `helix_remote_domain` is the one gate, and it runs over **every** pack on
/// **every** read, not only when one is downloaded. A pack folder that was
/// edited afterwards, or that a newer app no longer trusts the publisher of, is
/// therefore not a theme.
///
/// The store never opens a path a pack named: files are written and read by
/// their SHA-256, which is what [PackSource] asks the host for too.
final class ThemePackStore {
  const ThemePackStore({Map<String, List<int>>? trustedPublishers})
    : _publishers = trustedPublishers;

  /// null means this build's anchor ([PackTrust]).
  final Map<String, List<int>>? _publishers;

  static const limits = OrbitPackLimits.standard;

  // ------------------------------------------------------------------ reads

  /// Every pack on this device the app can draw with: one entry per id, the
  /// newest revision that passes the gate, in id order.
  ///
  /// A pack that fails is left on disk and simply not offered - a full-height
  /// read error, a theme document this build cannot parse, or a key a later app
  /// stopped trusting must not destroy what someone downloaded.
  Future<List<InstalledPack>> installed() async {
    final publishers = _publishers ?? PackTrust.forThisBuildOrNone();
    final root = await AppPaths.packsDirectory();
    if (!await root.exists()) return const [];
    final packs = <InstalledPack>[];
    for (final folder in root.listSync()) {
      if (folder is! Directory) continue;
      final id = p.basename(folder.path);
      if (!_isSlug(id)) continue;
      final pack = await _newestOf(folder.path, id: id, publishers: publishers);
      if (pack != null) packs.add(pack);
    }
    packs.sort((a, b) => a.id.compareTo(b.id));
    return packs;
  }

  /// The installed pack [id], or null when the device has none it can draw with.
  Future<InstalledPack?> load(String id) async {
    if (!_isSlug(id)) return null;
    final folder = Directory(
      p.join((await AppPaths.packsDirectory()).path, id),
    );
    if (!await folder.exists()) return null;
    return _newestOf(
      folder.path,
      id: id,
      publishers: _publishers ?? PackTrust.forThisBuildOrNone(),
    );
  }

  /// The themes packs add to the built-ins, by id. What [main] seeds the theme
  /// library with, so a downloaded theme is on screen from the first frame.
  Future<Map<String, OrbitTokens>> themeTokens() async => {
    for (final pack in await installed()) pack.id: pack.tokens,
  };

  // ---------------------------------------------------------------- changes

  /// Downloads pack [id] and puts it where the app can draw with it.
  ///
  /// [revision] asks for a specific one; without it the newest the host lists.
  /// Every byte is fetched and gate-checked **before** anything is moved into
  /// place, so a pack that turns out to be unsigned, tampered with or drawn in
  /// an effect this app does not ship leaves the theme on screen untouched.
  /// Revisiting an id replaces it, and the revisions older than the new one go:
  /// the app draws an id by its newest revision, so the others are only bytes.
  ///
  /// Returns [PackChange.alreadyCurrent] when this device already holds a
  /// revision at least as new, so the caller can say "up to date" rather than
  /// re-download the same bytes.
  ///
  /// Throws [PackNotHosted] when the host lists no such pack, and
  /// [PackRefused] when the pack fails the gate (with the format's own
  /// [OrbitPackFailure] and reason). Anything else the source throws - no
  /// network, a server that answers 404 - comes through as it is.
  Future<PackChange> install(
    PackSource source,
    String id, {
    int? revision,
  }) async {
    if (!_isSlug(id)) throw PackNotHosted(id);
    final hosted = await _hosted(source, id, revision);
    if (hosted == null) throw PackNotHosted(id);
    final current = await load(id);
    if (current != null && current.revision >= hosted.revision) {
      return PackChange.alreadyCurrent;
    }

    final manifestBytes = await source.manifest(hosted.id, hosted.revision);
    if (manifestBytes.length > limits.manifestBytes) {
      throw const PackRefused(
        OrbitPackFailure.tooLarge,
        'the manifest is bigger than a manifest may be',
      );
    }
    final OrbitPackManifest manifest;
    try {
      manifest = OrbitPackManifest.fromJson(
        jsonDecode(utf8.decode(manifestBytes)) as Map<String, Object?>,
      );
    } on FormatException catch (e) {
      throw PackRefused(OrbitPackFailure.badManifest, e.message);
    }
    // A manifest that is not the one the host listed for this name and number
    // is not the pack the person asked for, whatever else it may be.
    if (manifest.id != hosted.id || manifest.revision != hosted.revision) {
      throw const PackRefused(
        OrbitPackFailure.badManifest,
        'it is not the pack this name and revision are for',
      );
    }
    // And this store draws themes, so a pack that carries a sound stops here,
    // before its files are paid for in bandwidth. A host that serves both kinds
    // from one folder lists both, and nothing but this manifest says which one
    // this is.
    if (manifest.contents != 'theme') {
      throw const PackRefused(
        OrbitPackFailure.unknownContent,
        'this store draws themes, and this pack is not one',
      );
    }

    // The caps the gate enforces, checked against the manifest's own promises
    // first: a manifest that lists sixteen 8 MiB files must be refused before
    // they are paid for in bandwidth, not after.
    if (manifest.files.length > limits.fileCount) {
      throw PackRefused(
        OrbitPackFailure.tooManyFiles,
        '${manifest.files.length} files, a pack may carry ${limits.fileCount}',
      );
    }
    var promised = 0;
    for (final file in manifest.files) {
      if (file.bytes > limits.fileBytes) {
        throw const PackRefused(
          OrbitPackFailure.tooLarge,
          'a file promises more bytes than a file may have',
        );
      }
      promised += file.bytes;
      if (promised > limits.totalBytes) {
        throw const PackRefused(
          OrbitPackFailure.tooLarge,
          'the pack promises more bytes in total than a pack may have',
        );
      }
    }

    // Fetched by digest, so there is no path to sanitise and a server cannot
    // hand the app a file its signed manifest does not name.
    final files = <String, List<int>>{};
    for (final file in manifest.files) {
      files[file.path] = await source.file(
        manifest.id,
        manifest.revision,
        file.sha256,
      );
    }
    final check = await _check(
      manifestBytes: manifestBytes,
      files: files,
      publishers: _publishers ?? PackTrust.forThisBuild(),
    );
    if (!check.isAllowed) {
      throw PackRefused(check.failure!, check.detail);
    }

    final root = await AppPaths.packsDirectory();
    final staging = Directory(
      p.join(
        root.path,
        '.staging',
        '${manifest.id}-r${manifest.revision}'
            '-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}',
      ),
    );
    try {
      await staging.create(recursive: true);
      await File(
        p.join(staging.path, 'manifest.json'),
      ).writeAsBytes(manifestBytes, flush: true);
      final store = Directory(p.join(staging.path, 'files'))
        ..createSync(recursive: true);
      for (final file in manifest.files) {
        await File(
          p.join(store.path, file.sha256),
        ).writeAsBytes(files[file.path]!, flush: true);
      }
      final pack = Directory(
        p.join(root.path, manifest.id, 'r${manifest.revision}'),
      );
      if (await pack.exists()) {
        // Content-addressed, so this is the same revision the device holds
        // under the same name. Keeping what is already there is the only
        // answer that cannot change a theme a person is looking at.
        await staging.delete(recursive: true);
      } else {
        await pack.parent.create(recursive: true);
        await staging.rename(pack.path);
        await _forgetOlderRevisions(pack.parent, keeping: manifest.revision);
      }
    } finally {
      // Moved, deleted or never made it: the staging folder is not left behind.
      if (await staging.exists()) await staging.delete(recursive: true);
    }
    return PackChange.installed;
  }

  /// Deletes pack [id] and everything it downloaded. False when the device
  /// never had it. Throws what the file system throws.
  ///
  /// A pack that is on screen when its folder goes is not a problem: the theme
  /// library is re-read after this, the id is no longer in it, and
  /// [orbitTokensProvider] falls back to Orbit.
  Future<bool> remove(String id) async {
    if (!_isSlug(id)) return false;
    final folder = Directory(
      p.join((await AppPaths.packsDirectory()).path, id),
    );
    if (!await folder.exists()) return false;
    await folder.delete(recursive: true);
    return true;
  }

  // ----------------------------------------------------------------- parts

  /// The host's entry for [id] - [revision], or the newest it lists.
  Future<OrbitPackEntry?> _hosted(
    PackSource source,
    String id,
    int? revision,
  ) async {
    OrbitPackEntry? best;
    for (final entry in await source.list()) {
      if (entry.id != id) continue;
      if (revision == null) {
        if (best == null || entry.revision > best.revision) best = entry;
      } else if (entry.revision == revision) {
        return entry;
      }
    }
    return best;
  }

  /// The newest revision in one pack's folder that this device can draw with.
  Future<InstalledPack?> _newestOf(
    String folder, {
    required String id,
    required Map<String, List<int>> publishers,
  }) async {
    InstalledPack? newest;
    for (final revision in Directory(folder).listSync()) {
      if (revision is! Directory) continue;
      final number = _revisionOf(p.basename(revision.path));
      if (number == null) continue;
      final pack = await _read(
        revision.path,
        id: id,
        revision: number,
        publishers: publishers,
      );
      if (pack == null) continue;
      if (newest == null || pack.revision > newest.revision) newest = pack;
    }
    return newest;
  }

  /// One pack folder, gate-checked. Null when it is not a theme this device can
  /// draw with, for any of the reasons [installed] documents.
  Future<InstalledPack?> _read(
    String folder, {
    required String id,
    required int revision,
    required Map<String, List<int>> publishers,
  }) async {
    try {
      final manifestFile = File(p.join(folder, 'manifest.json'));
      if (!await manifestFile.exists()) return null;
      final manifestBytes = await _readCapped(
        manifestFile,
        limits.manifestBytes,
      );
      if (manifestBytes == null) return null;
      final OrbitPackManifest manifest;
      try {
        manifest = OrbitPackManifest.fromJson(
          jsonDecode(utf8.decode(manifestBytes)) as Map<String, Object?>,
        );
      } on FormatException {
        return null;
      }
      // The folder is how the app finds a theme and the revision it offers is
      // the number in its name, so a hand-edited folder that claims another
      // pack's manifest, or another revision, is not a pack.
      if (manifest.id != id || manifest.revision != revision) return null;
      // A sound pack is a perfectly good pack that this class has no way to
      // draw: its one file is audio, so `manifest.theme` is null and there are
      // no tokens to read. The gate would allow it; the theme list must not.
      if (manifest.contents != 'theme') return null;
      final files = <String, List<int>>{};
      var bytes = manifestBytes.length;
      for (final file in manifest.files) {
        final stored = File(p.join(folder, 'files', file.sha256));
        if (!await stored.exists()) return null;
        final content = await _readCapped(stored, limits.fileBytes);
        if (content == null) return null;
        bytes += content.length;
        files[file.path] = content;
      }
      final check = await _check(
        manifestBytes: manifestBytes,
        files: files,
        publishers: publishers,
      );
      if (!check.isAllowed) return null;
      final OrbitTokens tokens;
      try {
        // The gate reads the theme document for its id, its effects and its
        // pattern; drawing with it needs every one of its 111 tokens, which is
        // this parse's job. A document half-right is a theme nobody designed.
        tokens = OrbitTokens.fromThemeJson(
          jsonDecode(utf8.decode(files[manifest.theme]!))
              as Map<String, Object?>,
        );
      } on FormatException {
        return null;
      }
      return InstalledPack(
        id: id,
        revision: revision,
        tokens: tokens,
        bytes: bytes,
      );
    } on FileSystemException {
      return null; // A file that cannot be read is not a theme today.
    }
  }

  Future<Uint8List?> _readCapped(File file, int cap) async {
    final length = await file.length();
    if (length > cap) return null;
    return file.readAsBytes();
  }

  Future<OrbitPackCheck> _check({
    required List<int> manifestBytes,
    required Map<String, List<int>> files,
    required Map<String, List<int>> publishers,
  }) => checkOrbitPack(
    manifestBytes: manifestBytes,
    files: files,
    knownEffectKinds: {for (final kind in OrbitEffects.kinds) kind.name},
    knownPatternKinds: {for (final kind in OrbitEffects.patterns) kind.name},
    trustedPublishers: publishers,
    limits: limits,
  );

  Future<void> _forgetOlderRevisions(
    Directory folder, {
    required int keeping,
  }) async {
    for (final entry in folder.listSync()) {
      if (entry is! Directory) continue;
      final revision = _revisionOf(p.basename(entry.path));
      if (revision == null || revision >= keeping) continue;
      try {
        await entry.delete(recursive: true);
      } on FileSystemException {
        // One stuck folder costs bytes, not the upgrade. It goes next time.
      }
    }
  }
}

/// The publisher keys this build draws packs from: [PackTrust]'s define, or
/// whatever a test says it trusts.
final packPublishersProvider = Provider<Map<String, List<int>>>(
  (ref) => PackTrust.forThisBuild(),
);

/// This device's pack folder, read with this build's anchor.
final themePackStoreProvider = Provider<ThemePackStore>(
  (ref) => ThemePackStore(trustedPublishers: ref.watch(packPublishersProvider)),
);

/// What [ThemePackStore.install] did.
enum PackChange {
  /// The pack is on this device now, and the app can draw with it.
  installed,

  /// This device already held a revision at least as new, so nothing was
  /// downloaded.
  alreadyCurrent,
}

/// The host the app asks for a pack's bytes: Helix Global, or the personal
/// server this account runs on. `helix_remote_api`'s ops client is the one
/// implementation that talks; a fake answers it in tests.
abstract interface class PackSource {
  /// Every pack the host serves: one entry for every revision it publishes, so
  /// the newest revision of an id is the largest number under that id.
  Future<List<OrbitPackEntry>> list();

  /// [id]'s manifest at [revision], exactly as published: the gate checks the
  /// signature over these bytes, so they are never re-written on the way.
  Future<List<int>> manifest(String id, int revision);

  /// One file of [id] at [revision], named by the lowercase hex SHA-256 its
  /// manifest gives it.
  Future<List<int>> file(String id, int revision, String digest);
}

/// One pack this device holds, as far as the app is concerned: its name, the
/// tokens it draws with, and the bytes it costs.
@immutable
final class InstalledPack {
  const InstalledPack({
    required this.id,
    required this.revision,
    required this.tokens,
    required this.bytes,
  });

  final String id;

  /// The revision this folder holds, which is the newest the app found for [id].
  final int revision;

  final OrbitTokens tokens;

  /// Its manifest and its files together.
  final int bytes;

  /// The theme's own name, from the signed theme document. Not the folder or
  /// the manifest's id - that is what a person reads on Appearance.
  String get name => tokens.meta.name;
}

/// The host lists no pack with this id (or no such revision).
final class PackNotHosted implements Exception {
  const PackNotHosted(this.id);

  final String id;

  @override
  String toString() => 'no pack named "$id" is on offer';
}

/// A pack that failed the gate. The failure is the format's own, so the page
/// can say what was wrong without opening the pack again.
final class PackRefused implements Exception {
  const PackRefused(this.failure, [this.detail]);

  final OrbitPackFailure failure;

  /// Which field or path was wrong, as the gate worded it. Never theme text.
  final String? detail;

  @override
  String toString() => 'the pack is refused: ${failure.reason}';
}

final _slug = RegExp(r'^[a-z0-9][a-z0-9._-]{0,63}$');
final _hex = RegExp(r'^[0-9a-f]+$');
final _revisionFolder = RegExp(r'^r([0-9]{1,9})$');

/// Whether [value] is a theme id - the slug a pack is named by, which is also
/// what `device_settings.json` may hold as the chosen theme.
bool isThemeId(String value) => _slug.hasMatch(value);

bool _isSlug(String value) => _slug.hasMatch(value);

bool _isHex(String value) => _hex.hasMatch(value);

int? _revisionOf(String folderName) =>
    int.tryParse(_revisionFolder.firstMatch(folderName)?.group(1) ?? '');

Uint8List _fromHex(String hex) => Uint8List.fromList([
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
]);
