import 'dart:io';

import 'package:path/path.dart' as p;

/// The folder of theme packs a server hosts, read-only (ADR-033).
///
/// This is a file host, not a judge. It never opens a manifest and holds no
/// copy of the pack format: it lists what its own folder holds and streams
/// those bytes unchanged. That is deliberate. The one place the format is
/// understood is `checkOrbitPack` in `helix_remote_domain`, which the app runs
/// on what it downloaded - so a broken or hostile host has nothing it can
/// reach before that check, and a second implementation here could only drift
/// from the first.
///
/// The layout the operator's `tool/theme_pack_tool.dart publish` writes:
///
/// ```
/// <root>/<id>/r<revision>/manifest.json
/// <root>/<id>/r<revision>/files/<sha256 of that file>
/// ```
///
/// Files are named by hash, not by path, so a URL can only ever be a slug, a
/// number and 64 hex characters: there is no path to escape, and a client asks
/// for exactly the bytes the manifest promised.
final class PackHost {
  const PackHost(this.root);

  /// The pack folder, or null when this server hosts no packs. Every answer
  /// then is the same as an empty folder, so a server without the setting is
  /// healthy and simply has nothing to offer.
  final String? root;

  /// The same caps as the pack format (`OrbitPackLimits` in
  /// `helix_remote_domain`, `docs/product/THEME_PACK_FORMAT.md`). Nothing
  /// larger than the format can describe leaves this server, so a mistaken
  /// file in the folder cannot turn a gallery browse into a large download.
  static const maxManifestBytes = 64 * 1024;
  static const maxFileBytes = 8 * 1024 * 1024;

  /// A pack slug, as the format defines it. The first character is a letter or
  /// a digit, so `..` and `.` are never a slug and no folder name can point
  /// outside the root.
  static final _id = RegExp(r'^[a-z0-9][a-z0-9._-]{0,63}$');

  static final _digest = RegExp(r'^[0-9a-f]{64}$');

  static final _revision = RegExp(r'^r([1-9][0-9]{0,8})$');

  /// Every pack in the folder, sorted by id then revision, so two nodes answer
  /// the same and the list does not move under a client.
  Future<List<HostedPack>> list() async {
    final directory = root;
    if (directory == null) return const [];
    final folder = Directory(directory);
    if (!await folder.exists()) return const [];
    final packs = <HostedPack>[];
    await for (final id in folder.list(followLinks: false)) {
      if (id is! Directory) continue;
      final slug = p.basename(id.path);
      if (!_id.hasMatch(slug)) continue;
      await for (final revision in id.list(followLinks: false)) {
        if (revision is! Directory) continue;
        final number = revisionOf(p.basename(revision.path));
        if (number == null) continue;
        final pack = await _measure(slug, number, revision.path);
        if (pack != null) packs.add(pack);
      }
    }
    packs.sort((a, b) {
      final byId = a.id.compareTo(b.id);
      return byId != 0 ? byId : a.revision.compareTo(b.revision);
    });
    return packs;
  }

  /// One pack as its folder shows it, or null when the folder holds no
  /// manifest - a half-published directory is not a pack.
  Future<HostedPack?> _measure(
    String id,
    int revision,
    String directory,
  ) async {
    final manifest = File(p.join(directory, 'manifest.json'));
    if (!await manifest.exists()) return null;
    final manifestBytes = await manifest.length();
    var totalBytes = manifestBytes;
    var updated = (await manifest.lastModified()).toUtc();
    final files = Directory(p.join(directory, 'files'));
    if (await files.exists()) {
      await for (final entry in files.list(followLinks: false)) {
        if (entry is! File) continue;
        totalBytes += await entry.length();
        final at = (await entry.lastModified()).toUtc();
        if (at.isAfter(updated)) updated = at;
      }
    }
    return HostedPack(
      id: id,
      revision: revision,
      manifestBytes: manifestBytes,
      totalBytes: totalBytes,
      updatedAt: updated,
    );
  }

  /// `GET /v1/packs/{id}/revisions/{revision}/manifest`.
  Future<PackRead> manifest(String id, int revision) =>
      _read(id, revision, 'manifest.json', maxManifestBytes);

  /// One file of a pack, by the SHA-256 the manifest names for it.
  Future<PackRead> file(String id, int revision, String digest) {
    if (!_digest.hasMatch(digest)) return Future.value(const PackMiss());
    return _read(id, revision, 'files/$digest', maxFileBytes);
  }

  Future<PackRead> _read(
    String id,
    int revision,
    String relative,
    int cap,
  ) async {
    final directory = root;
    if (directory == null) return const PackMiss();
    // Every piece is checked against its own rule before any of them is
    // joined, and the result is checked to stay inside the folder. A slug and
    // a hex digest cannot hold a separator, so this is belt and braces - both
    // are kept, because escaping a pack folder is worth the redundancy.
    if (!_id.hasMatch(id)) return const PackMiss();
    if (revision < 1 || revision > maxRevision) return const PackMiss();
    final base = p.normalize(p.absolute(directory));
    final path = p.normalize(p.join(base, id, 'r$revision', relative));
    if (!p.isWithin(base, path)) return const PackMiss();
    final file = File(path);
    if (!await file.exists()) return const PackMiss();
    final length = await file.length();
    if (length > cap) return PackTooBig(length: length, cap: cap);
    return PackHit(length: length, open: () => file.openRead());
  }

  static const maxRevision = 999999999;

  /// The number in a `r7` folder name, or null when the folder is not a
  /// published revision.
  static int? revisionOf(String name) {
    final match = _revision.firstMatch(name);
    return match == null ? null : int.parse(match.group(1)!);
  }
}

/// What the host found for one read.
sealed class PackRead {
  const PackRead();
}

/// A file to serve: [length] bytes, and a fresh stream each time [open] is
/// called.
final class PackHit extends PackRead {
  const PackHit({required this.length, required this.open});

  final int length;
  final Stream<List<int>> Function() open;
}

/// Not in the folder - which is also the answer for anything the folder rules
/// cannot name, so a probe cannot tell a missing pack from an illegal name.
final class PackMiss extends PackRead {
  const PackMiss();
}

/// On disk but larger than the pack format allows, so it is the operator's
/// mistake, and the answer says so rather than hiding it.
final class PackTooBig extends PackRead {
  const PackTooBig({required this.length, required this.cap});

  final int length;
  final int cap;
}

/// One pack in the host's folder, as the folder shows it: names, sizes and a
/// time, and nothing about what the pack *is*. The signed manifest answers
/// that, and the device checks it.
final class HostedPack {
  const HostedPack({
    required this.id,
    required this.revision,
    required this.manifestBytes,
    required this.totalBytes,
    required this.updatedAt,
  });

  final String id;
  final int revision;
  final int manifestBytes;

  /// The manifest plus the pack's files: what downloading this pack costs.
  final int totalBytes;

  final DateTime updatedAt;
}
