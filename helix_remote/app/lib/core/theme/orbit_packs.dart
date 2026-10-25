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

/// Where the packs a person downloads are kept, whatever they turn out to be.
///
/// [T] is what this app makes of one: [OrbitTokens] for a theme, a sound file
/// for a ringtone. The two kinds share this class because they share every rule
/// that matters - the folder layout, the size caps, the staging a download goes
/// through before it may replace anything, the gate that runs on **every** read
/// and not only on download - and a second copy of those would be a second place
/// for the security-relevant part to drift. What differs is two arguments:
/// [contents], the word a pack's manifest must carry for this folder to keep it,
/// and [decode], what this app makes of a pack the gate has already passed.
///
/// The folder is the server's own layout: `manifest.json` in
/// `packs/<id>/r<revision>` beside a `files` folder of SHA-256 names, so a pack
/// is one folder a device can hold and re-check, and a file two revisions share
/// is stored once. Nothing here knows the format: `checkOrbitPack` in
/// `helix_remote_domain` is the one gate. A pack folder that was edited
/// afterwards, or that a newer app no longer trusts the publisher of, is
/// therefore not a pack - and a pack of the other [contents] is not this app's
/// business either, so one folder can hold both kinds.
///
/// The store never opens a path a pack named: files are written and read by
/// their SHA-256, which is what [PackSource] asks the host for too.
final class PackFolder<T> {
  PackFolder({
    required this.contents,
    required this.decode,
    Map<String, List<int>>? trustedPublishers,
  }) : _publishers = trustedPublishers;

  /// The `contents` a pack must declare to live in this store's folder:
  /// `theme` or `sound`, the two words [orbitPackContents] knows.
  final String contents;

  /// What this app makes of a pack that passed the gate. Null for one that
  /// passed every check and is still no use here - a theme document whose
  /// tokens this build cannot parse, for instance - which is read as "this
  /// device holds no such pack" and leaves its bytes alone.
  final T? Function(PackBytes pack) decode;

  /// null means this build's anchor ([PackTrust]).
  final Map<String, List<int>>? _publishers;

  static const limits = OrbitPackLimits.standard;

  // ------------------------------------------------------------------ reads

  /// Every pack of [contents] on this device that this app can use: one entry
  /// per id, the newest revision that passes the gate, in id order.
  ///
  /// A pack that fails is left on disk and simply not offered - a full-height
  /// read error, a file that no longer hashes, or a key a later app stopped
  /// trusting must not destroy what someone downloaded.
  Future<List<PackOf<T>>> stored() async {
    final publishers = _publishers ?? PackTrust.forThisBuildOrNone();
    final root = await AppPaths.packsDirectory();
    if (!await root.exists()) return const [];
    final packs = <PackOf<T>>[];
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

  /// The installed pack [id], or null when the device has none this app can use.
  Future<PackOf<T>?> load(String id) async {
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

  // ---------------------------------------------------------------- changes

  /// Downloads pack [id] and puts it where this app can use it.
  ///
  /// [revision] asks for a specific one; without it the newest the host lists.
  /// Every byte is fetched and gate-checked **before** anything is moved into
  /// place, so a pack that turns out to be unsigned, tampered with, or of the
  /// other [contents] leaves what is on screen untouched. Revisiting an id
  /// replaces it, and the revisions older than the new one go: an app uses an id
  /// by its newest revision, so the others are only bytes.
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
    // And this folder is one kind's, so the other kind stops here, before its
    // files are paid for in bandwidth. A host that serves both kinds from one
    // folder lists both, and nothing but this manifest says which one this is.
    if (manifest.contents != contents) {
      throw PackRefused(
        OrbitPackFailure.unknownContent,
        'this keeps $contents packs, and this pack is not one',
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
    // Nothing is moved into place until the app has proved it can use it: a
    // decode that failed after the rename would leave bytes no page can offer,
    // and no page can delete either. The folder named here is the one the pack
    // would have; nothing is written to it.
    final probe = PackBytes(
      id: manifest.id,
      revision: manifest.revision,
      manifest: manifest,
      folder: p.join(root.path, manifest.id, 'r${manifest.revision}'),
      files: files,
      bytes:
          manifestBytes.length +
          files.values.fold<int>(0, (sum, bytes) => sum + bytes.length),
    );
    if (_decode(probe) == null) {
      throw const PackRefused(
        OrbitPackFailure.badTheme,
        'this app cannot read what it carries, so it could not be offered',
      );
    }

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

  /// The newest revision in one pack's folder that this app can use.
  Future<PackOf<T>?> _newestOf(
    String folder, {
    required String id,
    required Map<String, List<int>> publishers,
  }) async {
    PackOf<T>? newest;
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

  /// One pack folder, gate-checked. Null when it is not a pack this app can use,
  /// for any of the reasons [stored] documents.
  Future<PackOf<T>?> _read(
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
      } on Object {
        // Not JSON, not an object, or not a manifest: none of these is a pack,
        // and none may take the folder read down with it.
        return null;
      }
      // The folder is how the app finds a pack and the revision it offers is
      // the number in its name, so a hand-edited folder that claims another
      // pack's manifest, or another revision, is not a pack.
      if (manifest.id != id || manifest.revision != revision) return null;
      // One folder, two kinds: the themes store is not the one that plays a
      // ringtone and the ringtones store is not the one that draws a theme. The
      // gate would allow either; this list must not.
      if (manifest.contents != contents) return null;
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
      final pack = PackBytes(
        id: id,
        revision: revision,
        manifest: manifest,
        folder: folder,
        files: files,
        bytes: bytes,
      );
      final value = _decode(pack);
      // A pack the gate allowed but this app cannot use is not a pack on screen
      // today: the theme document is not the 111 tokens the gate read, or the
      // sound is not a file this platform can point a ringtone at.
      if (value == null) return null;
      return PackOf(pack: pack, value: value);
    } on FileSystemException {
      return null; // A file that cannot be read is not a pack today.
    }
  }

  /// [decode], with anything it throws read as "not a pack today".
  ///
  /// This is the folder's contract and not the decoder's promise: one stored
  /// theme a build cannot parse must not take every other pack's read down
  /// with it, and a later decoder is free to raise something other than
  /// `FormatException`. Nothing else in a read is allowed to throw for a bad
  /// pack either; a decoded value that cannot be made is simply absent.
  T? _decode(PackBytes pack) {
    try {
      return decode(pack);
    } on Object {
      return null;
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

/// One pack this device holds, as its folder and the bytes the gate hashed.
@immutable
final class PackBytes {
  const PackBytes({
    required this.id,
    required this.revision,
    required this.manifest,
    required this.folder,
    required this.files,
    required this.bytes,
  });

  final String id;
  final int revision;

  /// The manifest that passed the gate, so its paths, kinds and digests are the
  /// publisher's own words and not a folder's guess at them.
  final OrbitPackManifest manifest;

  /// `packs/<id>/r<revision>`, which is where [stored] read it from.
  final String folder;

  /// Every file's bytes, under the path its manifest names it by.
  final Map<String, List<int>> files;

  /// The manifest and the files together.
  final int bytes;

  /// Where one of this pack's files is kept: by its digest, never by the path
  /// the pack wrote, which is the one thing a pack must not be trusted with.
  File fileAt(OrbitPackFile file) => File(p.join(folder, 'files', file.sha256));
}

/// A pack this app can use: [pack] is what the folder held, [value] what
/// [PackFolder.decode] made of it.
@immutable
final class PackOf<T> {
  const PackOf({required this.pack, required this.value});

  final PackBytes pack;
  final T value;

  String get id => pack.id;

  int get revision => pack.revision;

  int get bytes => pack.bytes;
}

/// The themes a person downloads, in the device's pack folder, and what the app
/// draws with them.
///
/// The rules are [PackFolder]'s and `checkOrbitPack`'s; what is here is the one
/// thing that is a theme's own: a pack's document has to be readable as this
/// build's tokens before the app offers it on Appearance.
final class ThemePackStore {
  ThemePackStore({Map<String, List<int>>? trustedPublishers})
    : _packs = PackFolder(
        contents: 'theme',
        decode: _pack,
        trustedPublishers: trustedPublishers,
      );

  final PackFolder<InstalledPack> _packs;

  /// The themes packs add to the built-ins, by id. What [main] seeds the theme
  /// library with, so a downloaded theme is on screen from the first frame.
  Future<Map<String, OrbitTokens>> themeTokens() async => {
    for (final pack in await installed()) pack.id: pack.tokens,
  };

  /// Every pack on this device the app can draw with: one entry per id, the
  /// newest revision that passes the gate, in id order.
  Future<List<InstalledPack>> installed() async => [
    for (final pack in await _packs.stored()) pack.value,
  ];

  /// The installed pack [id], or null when the device has none it can draw with.
  Future<InstalledPack?> load(String id) async =>
      (await _packs.load(id))?.value;

  Future<PackChange> install(PackSource source, String id, {int? revision}) =>
      _packs.install(source, id, revision: revision);

  Future<bool> remove(String id) => _packs.remove(id);

  /// The gate read this document for its id, its effects and its pattern;
  /// drawing with it needs every one of its 111 tokens, which is this parse's
  /// job. A document half-right is a theme nobody designed, so it is no theme
  /// at all here, and null is how a folder says so.
  static InstalledPack? _pack(PackBytes pack) {
    final OrbitTokens tokens;
    try {
      tokens = OrbitTokens.fromThemeJson(
        jsonDecode(utf8.decode(pack.files[pack.manifest.theme!]!))
            as Map<String, Object?>,
      );
    } on FormatException {
      return null;
    }
    return InstalledPack(
      id: pack.id,
      revision: pack.revision,
      tokens: tokens,
      bytes: pack.bytes,
    );
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

/// What [PackFolder.install] did.
enum PackChange {
  /// The pack is on this device now, and this app can use it.
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

/// One pack the host offers, as its list entry and the kind **its own signed
/// manifest** says it is.
@immutable
final class PackOffer {
  const PackOffer({required this.entry, required this.contents});

  final OrbitPackEntry entry;

  /// `theme` or `sound`, from the manifest the publisher signed.
  final String contents;

  String get id => entry.id;

  int get revision => entry.revision;
}

/// What [hostedPacks] found: the offers this app can vouch for, and how many
/// rows it could not.
@immutable
final class PackOffers {
  const PackOffers({required this.rows, required this.unverified});

  /// One per pack id, newest revision, in id order.
  final List<PackOffer> rows;

  /// Rows the host listed that this build would not download: the other kind,
  /// a signature that does not hold, a publisher it does not trust, a manifest
  /// it could not read. A page says so when [rows] is empty and this is not,
  /// because "nothing is on offer" would be the wrong sentence for a host that
  /// lists ten packs nobody signed.
  final int unverified;
}

/// How many offers [hostedPacks] will read manifests for.
///
/// A cap, not a design: one small request per pack id is what telling the kinds
/// apart costs, and a folder a server has filled past this is not this app's
/// market. What is past it is simply not offered.
const hostedPackProbe = 64;

/// How many manifest reads [hostedPacks] has in flight at once.
///
/// Parallel enough that a folder is not walked one server round trip at a time,
/// small enough that opening More themes is not a burst of 64 requests at a
/// phone's link.
const hostedPackProbeConcurrency = 6;

/// The kinds this session has verified, by `id@revision` - [hostedPacks]'
/// `verified` map.
///
/// A manifest is signed and a revision is immutable, so the answer cannot
/// change while the app runs. Kept outside the pages' `autoDispose` providers
/// on purpose: leaving More themes and coming back asks only about revisions
/// this session has not seen, not the whole folder again.
final verifiedPackKindsProvider = Provider<Map<String, String>>((ref) => {});

/// Every pack [source] offers that this app could use, of the [contents] kind.
///
/// The list route says nothing about what a row *is* - `contents` lives inside
/// the signed manifest, and the endpoint never opens it (that is its whole
/// design) - so a page that lists one kind reads each offer's manifest and asks
/// [checkOrbitPackManifest]. That is the only honest way to name a row a sound:
/// the word comes from the publisher's signature, not from a server's guess, and
/// a row that cannot be verified is not offered at all rather than offered and
/// refused after a tap. Nothing here downloads a file, so the cost is one small
/// read per pack id, a few at a time.
///
/// [publishers] is this build's anchor; [hostedPackProbe] bounds the reads and
/// [hostedPackProbeConcurrency] how many run at once. [verified] is the
/// session's memory of manifests already checked: a hit for the same
/// `id@revision` answers without a request. Only a manifest that fully verified
/// is remembered - a timeout or a refusal is asked again next visit, because an
/// outage is not a fact about the pack.
Future<PackOffers> hostedPacks(
  PackSource source,
  String contents,
  Map<String, List<int>> publishers, {
  Map<String, String>? verified,
}) async {
  final newest = <String, OrbitPackEntry>{};
  for (final entry in await source.list()) {
    final best = newest[entry.id];
    if (best == null || best.revision < entry.revision) {
      newest[entry.id] = entry;
    }
  }
  final ids = newest.values.map((e) => e.id).toList()..sort();
  final probed = ids.take(hostedPackProbe).toList();
  final kinds = List<String?>.filled(probed.length, null);
  var cursor = 0;

  Future<void> probe() async {
    while (cursor < probed.length) {
      final index = cursor++;
      final entry = newest[probed[index]]!;
      final key = '${entry.id}@${entry.revision}';
      final known = verified?[key];
      if (known != null) {
        kinds[index] = known;
        continue;
      }
      try {
        final check = await checkOrbitPackManifest(
          manifestBytes: await source.manifest(entry.id, entry.revision),
          trustedPublishers: publishers,
        );
        final manifest = check.manifest;
        if (manifest == null) continue;
        kinds[index] = manifest.contents;
        verified?[key] = manifest.contents;
      } on Object {
        // One pack the host will not answer for is not an offer, and an
        // outage is asked again next visit.
      }
    }
  }

  await Future.wait([
    for (var i = 0; i < hostedPackProbeConcurrency && i < probed.length; i++)
      probe(),
  ]);

  final rows = <PackOffer>[];
  var unverified = ids.length - probed.length;
  for (var i = 0; i < probed.length; i++) {
    final entry = newest[probed[i]]!;
    if (kinds[i] == contents) {
      rows.add(PackOffer(entry: entry, contents: contents));
    } else {
      unverified++;
    }
  }
  return PackOffers(rows: rows, unverified: unverified);
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

/// Whether [value] is a pack id - the slug a pack is named by, which is also
/// what `device_settings.json` may hold as the chosen theme or ringtone. A
/// sound pack has no other name a person could be shown, so its id is what the
/// Ringtones page reads.
bool isPackId(String value) => _slug.hasMatch(value);

bool _isSlug(String value) => _slug.hasMatch(value);

bool _isHex(String value) => _hex.hasMatch(value);

int? _revisionOf(String folderName) =>
    int.tryParse(_revisionFolder.firstMatch(folderName)?.group(1) ?? '');

Uint8List _fromHex(String hex) => Uint8List.fromList([
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
]);
