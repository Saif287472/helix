import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:helix_remote/core/platform/app_storage.dart';
import 'package:helix_remote/core/theme/orbit_packs.dart';
import 'package:helix_remote_crypto/v2.dart'
    show Ed25519KeyPair, Sha256Accumulator;
import 'package:helix_remote_domain/models.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart'
    show OrbitPackEntry;

/// The pack fixtures every pack test shares: signed packs of both kinds, and the
/// host that serves them.
///
/// A theme pack and a sound pack are the same envelope with one different word,
/// so both stores' tests are built from these - and one set of signing fixtures
/// is the point. A pack signed some other way would let a store test pass on
/// bytes no publisher would ever serve.

/// The key the test packs are signed by, and the build's trust in it. Made once,
/// in `setUpAll`, because Ed25519 derivation is not free.
late final Ed25519KeyPair publisherKey;
late final Ed25519KeyPair otherKey;
late final Map<String, List<int>> trusted;

Future<void> makePublisherKeys() async {
  publisherKey = await Ed25519KeyPair.fromSeed(List<int>.filled(32, 3));
  otherKey = await Ed25519KeyPair.fromSeed(List<int>.filled(32, 9));
  trusted = {'helix': publisherKey.publicKey};
}

/// The theme a test pack carries, as bytes and as the file it is in.
final List<int> junk = utf8.encode('{"id": "synthwave", "tokens": {}}');

final List<int> keyBytes = List<int>.generate(32, (i) => i);
final String hexKey = keyBytes
    .map((b) => b.toRadixString(16).padLeft(2, '0'))
    .join();

Future<String> packsRoot() async => (await AppPaths.packsDirectory()).path;

/// The theme document of a pack: one of the app's own generated themes, with
/// its id and name moved to the pack's, so it is a real document and every
/// effect and pattern in it is one this build ships.
Map<String, Object?> themed({
  required String id,
  required String name,
  List<Object?> effects = const [],
}) {
  final doc =
      jsonDecode(
            File(
              '../packages/orbit_ui/assets/themes/night.json',
            ).readAsStringSync(),
          )
          as Map<String, Object?>;
  doc['id'] = id;
  doc['name'] = name;
  if (effects.isNotEmpty) doc['effects'] = effects;
  return doc;
}

/// One pack as its host has it: the manifest as published, and the bytes of
/// every file it names, by path.
final class HostedPack {
  HostedPack({required this.manifest, required this.files});

  final OrbitPackManifest manifest;
  final Map<String, List<int>> files;

  Uint8List get manifestBytes =>
      Uint8List.fromList(utf8.encode(jsonEncode(manifest.toJson())));

  Map<String, List<int>> get byDigest => {
    for (final entry in manifest.files) entry.sha256: files[entry.path]!,
  };

  OrbitPackEntry get listed => OrbitPackEntry(
    id: manifest.id,
    revision: manifest.revision,
    manifestBytes: manifestBytes.length,
    totalBytes: manifest.files.fold(0, (a, f) => a + f.bytes),
    updatedAt: DateTime.utc(2026, 10, 23),
  );

  /// The same manifest, serving other bytes: what a host that changed a
  /// published pack answers.
  HostedPack servedAs(List<int> bytes) => HostedPack(
    manifest: manifest,
    files: {for (final path in files.keys) path: bytes},
  );
}

/// A theme pack the publisher signed - or one they did not, with [signature]
/// false.
Future<HostedPack> signedPack({
  required Ed25519KeyPair by,
  String id = 'synthwave',
  int revision = 1,
  String publisher = 'helix',
  String name = 'Synthwave',
  Map<String, Object?>? theme,
  bool signature = true,
  int? fileBytes,
}) async {
  final doc = theme ?? themed(id: id, name: name);
  var bytes = Uint8List.fromList(utf8.encode(jsonEncode(doc)));
  if (fileBytes != null) {
    // Padded, so it is the manifest's promise being checked and not the size
    // of a real theme document.
    bytes = Uint8List.fromList([
      ...bytes,
      ...List<int>.filled(fileBytes - bytes.length, 0x20),
    ]);
  }
  final path = 'themes/$id.json';
  final digest = await sha256Hex(bytes);
  OrbitPackManifest build(String? signed) => OrbitPackManifest(
    formatVersion: orbitPackFormatVersion,
    id: id,
    publisher: publisher,
    revision: revision,
    theme: path,
    files: [
      OrbitPackFile(
        path: path,
        kind: 'theme',
        bytes: bytes.length,
        sha256: digest,
      ),
    ],
    signature: signed,
  );
  final signature64 = base64Encode(await by.sign(build(null).signingBytes()));
  return HostedPack(
    manifest: build(signature ? signature64 : null),
    files: {path: bytes},
  );
}

/// A sound pack the publisher signed: one audio file, and no theme document,
/// because a ringtone is the pack (Part C step 5). The bytes are a count up in
/// octet - the gate hashes a sound and never opens it, which is the point.
Future<HostedPack> signedSoundPack({
  required Ed25519KeyPair by,
  String id = 'chime',
  int revision = 1,
  String publisher = 'helix',
  bool signature = true,
  int? fileBytes,
}) async {
  var bytes = Uint8List.fromList(List<int>.generate(512, (i) => i % 256));
  if (fileBytes != null) {
    bytes = Uint8List.fromList([
      ...bytes,
      ...List<int>.filled(fileBytes - bytes.length, 0x20),
    ]);
  }
  final path = 'sounds/$id.m4a';
  final digest = await sha256Hex(bytes);
  OrbitPackManifest build(String? signed) => OrbitPackManifest(
    formatVersion: orbitPackFormatVersion,
    id: id,
    publisher: publisher,
    revision: revision,
    contents: 'sound',
    files: [
      OrbitPackFile(
        path: path,
        kind: 'audio',
        bytes: bytes.length,
        sha256: digest,
      ),
    ],
    signature: signed,
  );
  final signature64 = base64Encode(await by.sign(build(null).signingBytes()));
  return HostedPack(
    manifest: build(signature ? signature64 : null),
    files: {path: bytes},
  );
}

/// The host: answers the three pack routes from [packs], and remembers every
/// file digest it was asked for.
final class FakePackSource implements PackSource {
  FakePackSource(this.packs);

  final List<HostedPack> packs;
  final List<String> fetched = [];

  /// Every manifest read, as `id@revision`, in the order the reads began.
  final List<String> manifests = [];

  /// How long each manifest read takes; the probe's scheduling is measured
  /// against it.
  Duration manifestDelay = Duration.zero;

  /// Manifest reads in flight, and the most that ever were at once.
  int inFlight = 0;
  int peakInFlight = 0;

  /// Ids whose manifest read throws instead of answering.
  Set<String> failing = const {};

  HostedPack _one(String id, int revision) => packs.firstWhere(
    (p) => p.manifest.id == id && p.manifest.revision == revision,
    orElse: () => throw StateError('the host holds no $id r$revision'),
  );

  @override
  Future<List<OrbitPackEntry>> list() async => [
    for (final pack in packs) pack.listed,
  ];

  @override
  Future<List<int>> manifest(String id, int revision) async {
    manifests.add('$id@$revision');
    inFlight++;
    if (inFlight > peakInFlight) peakInFlight = inFlight;
    try {
      if (manifestDelay > Duration.zero) {
        await Future<void>.delayed(manifestDelay);
      }
      if (failing.contains(id)) throw StateError('no answer for $id');
      return _one(id, revision).manifestBytes;
    } finally {
      inFlight--;
    }
  }

  @override
  Future<List<int>> file(String id, int revision, String digest) async {
    fetched.add(digest);
    final bytes = _one(id, revision).byDigest[digest];
    if (bytes == null) throw StateError('the host has no file $digest');
    return bytes;
  }
}

/// A host that holds a pack's file bytes back until the test opens it: what a
/// download in flight looks like from the page. The list and manifest routes
/// answer at once, because a page reads those to decide what to offer before
/// anything is downloaded.
final class GatedPackSource implements PackSource {
  GatedPackSource(this.pack);

  final HostedPack pack;
  final Completer<void> _gate = Completer<void>();

  void open() => _gate.complete();

  @override
  Future<List<OrbitPackEntry>> list() async => [pack.listed];

  @override
  Future<List<int>> manifest(String id, int revision) async =>
      pack.manifestBytes;

  @override
  Future<List<int>> file(String id, int revision, String digest) async {
    await _gate.future;
    return pack.byDigest[digest]!;
  }
}

/// A host that never answers the list route: offline, or a server built before
/// the pack routes went live.
final class OfflinePackSource implements PackSource {
  int listCalls = 0;

  @override
  Future<List<OrbitPackEntry>> list() async {
    listCalls++;
    throw StateError('the host is not there');
  }

  @override
  Future<List<int>> manifest(String id, int revision) async => const [];

  @override
  Future<List<int>> file(String id, int revision, String digest) async =>
      const [];
}

Future<String> sha256Hex(List<int> bytes) async {
  final digest = Sha256Accumulator()..add(bytes);
  return digest.close().map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
