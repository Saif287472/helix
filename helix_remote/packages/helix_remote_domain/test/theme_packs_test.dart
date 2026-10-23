import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:helix_remote_domain/models.dart';
import 'package:test/test.dart';

/// The theme document every pack in these tests carries: 109 bytes of the
/// format `orbit_ui` reads, small enough to keep in the file.
const theme =
    '{"id":"synthwave","effects":[{"kind":"wordmarkGlow"}],'
    '"tokens":{"pattern":{"chat-pattern":{"kind":"grain"}}}}';

const themePath = 'themes/synthwave.json';
const themeSize = 109;
const themeSha256 =
    '215b71602638020f7cfc18c10c6fa652642833f2c69729d80c4ff7251fd872cb';

const publisher = 'agiletechbd';
const packId = 'synthwave';

/// The signing vectors, pinned: the bytes a publisher signs, the key that
/// signs them, and the signature the app must accept. A change to the
/// canonical form, to what goes into the message, or to Ed25519 shows up here
/// instead of silently changing what every pack already in the field means.
const pinnedCanonical =
    '{"files":[{"bytes":109,"kind":"theme","path":"themes/synthwave.json",'
    '"sha256":"215b71602638020f7cfc18c10c6fa652642833f2c69729d80c4ff7251fd872cb"}],'
    '"formatVersion":1,"id":"synthwave","publisher":"agiletechbd","revision":1,'
    '"theme":"themes/synthwave.json"}';

const pinnedPublisherKey =
    '03a107bff3ce10be1d70dd18e74bc09967e4d6309ba50d5f1ddc8664125531b8';

const pinnedSignature =
    'woAAGLL8UU2ZyYhtqiGaAqNwaoCZHpyr8ADuGC0JtzTxz5QkuqtoZFBq6Eol3iN6l1BdOX'
    '+kBFDggpF9oE6BBw==';

final Uint8List themeBytes = Uint8List.fromList(utf8.encode(theme));
final Uint8List publisherSeed = Uint8List.fromList(
  List<int>.generate(32, (i) => i),
);
final List<int> publisherKey = _hexDecode(pinnedPublisherKey);
final Set<String> shippedEffects = {'wordmarkGlow'};
final Set<String> shippedPatterns = {'grain'};

void main() {
  group('the signing form', () {
    test('is these bytes, keys in code-unit order, no spaces', () {
      expect(utf8.decode(sampleManifest().signingBytes()), pinnedCanonical);
    });

    test('does not sign its own signature', () {
      expect(
        utf8.decode(sampleManifest(signature: pinnedSignature).signingBytes()),
        pinnedCanonical,
      );
    });

    test('is what the pinned signature signs', () async {
      expect(_hex(await _publicKeyOf(publisherSeed)), pinnedPublisherKey);
      expect(
        await Ed25519().verify(
          sampleManifest().signingBytes(),
          signature: Signature(
            base64Decode(pinnedSignature),
            publicKey: SimplePublicKey(publisherKey, type: KeyPairType.ed25519),
          ),
        ),
        isTrue,
      );
    });
  });

  test('a pack signed by a trusted publisher is allowed, and the app gets the '
      'manifest it can keep', () async {
    final check = await _check(
      sampleManifest(),
      signature: pinnedSignature,
      files: {themePath: themeBytes},
    );
    expect(check.isAllowed, isTrue, reason: check.detail);
    expect(check.manifest!.id, packId);
    expect(check.manifest!.publisher, publisher);
    expect(check.manifest!.revision, 1);
  });

  group('refused before anything of the pack is opened', () {
    test('nobody signed it', () async {
      await _expectRefusal(
        _check(
          sampleManifest(),
          unsigned: true,
          files: {themePath: themeBytes},
        ),
        OrbitPackFailure.unsigned,
      );
    });

    test('these are not the bytes that were signed', () async {
      // Revision 2 of the pack, still carrying revision 1's signature.
      await _expectRefusal(
        _check(
          sampleManifest(revision: 2),
          signature: pinnedSignature,
          files: {themePath: themeBytes},
        ),
        OrbitPackFailure.badSignature,
      );
    });

    test('the publisher is one this build does not trust', () async {
      await _expectRefusal(
        _check(
          sampleManifest(),
          signature: pinnedSignature,
          publishers: {'someone-else': publisherKey},
          files: {themePath: themeBytes},
        ),
        OrbitPackFailure.unknownPublisher,
      );
    });

    test("a trusted publisher's unusable key is no trust at all", () async {
      await _expectRefusal(
        _check(
          sampleManifest(),
          signature: pinnedSignature,
          publishers: {publisher: publisherKey.take(31).toList()},
          files: {themePath: themeBytes},
        ),
        OrbitPackFailure.unknownPublisher,
      );
    });

    test('a theme this build cannot draw is not opened first', () async {
      final pack = await _pack(
        files: {
          themePath: Uint8List.fromList(
            utf8.encode(theme.replaceFirst('wordmarkGlow', 'screenCurl')),
          ),
        },
      );
      // Honestly hashed and sized, but signed with the pinned signature, which
      // covers a different pack: the content is never reached.
      await _expectRefusal(
        _check(pack.manifest, signature: pinnedSignature, files: pack.files),
        OrbitPackFailure.badSignature,
      );
    });

    test(
      'a path this app will not open is refused before the signature',
      () async {
        final escaped = _packAt('../night.json');
        await _expectRefusal(
          _check(escaped.manifest, unsigned: true, files: escaped.files),
          OrbitPackFailure.badPath,
        );
      },
    );
  });

  group('the manifest', () {
    test('is another format version', () async {
      await _expectRefusal(
        _check(
          sampleManifest(formatVersion: 2),
          signature: pinnedSignature,
          files: {themePath: themeBytes},
        ),
        OrbitPackFailure.unknownFormat,
      );
    });

    test('is not JSON', () async {
      await _expectRefusal(
        _checkBytes(
          manifestBytes: utf8.encode('a pack, honest'),
          files: const {},
        ),
        OrbitPackFailure.badManifest,
      );
    });

    test('has a field of the wrong shape', () async {
      final json = {...sampleManifest().toJson()}..['id'] = 'Synth Wave';
      await _expectRefusal(
        _checkBytes(
          manifestBytes: Uint8List.fromList(utf8.encode(jsonEncode(json))),
          files: {themePath: themeBytes},
        ),
        OrbitPackFailure.badManifest,
      );
    });

    test('carries more files than a pack may', () async {
      final files = {
        themePath: themeBytes,
        for (var i = 0; i < 16; i++) 'themes/copy$i.png': Uint8List(1),
      };
      final pack = await _pack(files: files);
      await _expectRefusal(
        _check(pack.manifest, files: files),
        OrbitPackFailure.tooManyFiles,
      );
    });

    test('carries two theme documents', () async {
      final pack = await _pack(
        files: {themePath: themeBytes, 'themes/other.json': themeBytes},
      );
      await _expectRefusal(
        _check(pack.manifest, files: pack.files),
        OrbitPackFailure.badManifest,
      );
    });

    test('names a kind the format does not have', () async {
      await _expectRefusal(
        _check(
          sampleManifest(
            files: [
              const OrbitPackFile(
                path: themePath,
                kind: 'sound',
                bytes: themeSize,
                sha256: themeSha256,
              ),
            ],
          ),
          files: {themePath: themeBytes},
        ),
        OrbitPackFailure.badManifest,
      );
    });

    test('names a kind the file is not', () async {
      await _expectRefusal(
        _check(
          sampleManifest(
            theme: 'themes/synthwave.png',
            files: [
              const OrbitPackFile(
                path: 'themes/synthwave.png',
                kind: 'theme',
                bytes: themeSize,
                sha256: themeSha256,
              ),
            ],
          ),
          files: {'themes/synthwave.png': themeBytes},
        ),
        OrbitPackFailure.badManifest,
      );
    });

    test('lists one file twice', () async {
      await _expectRefusal(
        _check(
          sampleManifest(files: const [themeEntry, themeEntry]),
          files: {themePath: themeBytes},
        ),
        OrbitPackFailure.badManifest,
      );
    });

    test('points at a theme document it does not carry', () async {
      await _expectRefusal(
        _check(
          sampleManifest(theme: 'themes/absent.json'),
          files: {themePath: themeBytes},
        ),
        OrbitPackFailure.badManifest,
      );
    });

    test('is bigger than a manifest may be', () async {
      await _expectRefusal(
        _checkBytes(manifestBytes: Uint8List(65 * 1024), files: const {}),
        OrbitPackFailure.tooLarge,
      );
    });
  });

  group('the paths', () {
    final longName = 'a' * 96;
    for (final path in [
      '../somewhere-else.json',
      'themes/../evil.json',
      '/themes/synthwave.json',
      r'themes\synthwave.json',
      'themes//synthwave.json',
      'C:themes/synthwave.json',
      'themes/a b.json',
      'themes/$longName.json',
    ]) {
      test('refuses "$path"', () async {
        final escaped = _packAt(path);
        await _expectRefusal(
          _check(escaped.manifest, files: escaped.files),
          OrbitPackFailure.badPath,
        );
      });
    }

    test(
      'a folder below the pack root is the shape the format wants',
      () async {
        final pack = await _pack(
          files: {'themes/deep/synthwave.json': themeBytes},
          theme: 'themes/deep/synthwave.json',
        );
        final check = await _check(pack.manifest, files: pack.files);
        expect(check.isAllowed, isTrue, reason: check.detail);
      },
    );
  });

  group('the files, once the signature holds', () {
    test('one the manifest promised is not in the download', () async {
      final pack = await _pack();
      await _expectRefusal(
        _check(pack.manifest, files: const {}),
        OrbitPackFailure.missingFile,
      );
    });

    test('one the download carried that was never signed for', () async {
      final pack = await _pack();
      await _expectRefusal(
        _check(
          pack.manifest,
          files: {themePath: themeBytes, 'themes/extra.png': Uint8List(1)},
        ),
        OrbitPackFailure.changedFile,
      );
    });

    test('one byte changed', () async {
      final pack = await _pack();
      final tampered = [...themeBytes]..[80] = themeBytes[80] + 1;
      await _expectRefusal(
        _check(pack.manifest, files: {themePath: Uint8List.fromList(tampered)}),
        OrbitPackFailure.changedFile,
      );
    });

    test('whose declared size is a lie', () async {
      final pack = await _pack();
      await _expectRefusal(
        _check(
          sampleManifest(
            files: [
              const OrbitPackFile(
                path: themePath,
                kind: 'theme',
                bytes: themeSize + 1,
                sha256: themeSha256,
              ),
            ],
          ),
          files: pack.files,
        ),
        OrbitPackFailure.changedFile,
      );
    });

    test('bigger than a file may be', () async {
      final pack = await _pack();
      await _expectRefusal(
        _check(
          pack.manifest,
          files: pack.files,
          limits: const OrbitPackLimits(fileBytes: 64),
        ),
        OrbitPackFailure.tooLarge,
      );
    });

    test('and a pack bigger in total than it may be', () async {
      final pack = await _pack();
      await _expectRefusal(
        _check(
          pack.manifest,
          files: pack.files,
          limits: const OrbitPackLimits(totalBytes: 64),
        ),
        OrbitPackFailure.tooLarge,
      );
    });
  });

  group('the theme document', () {
    test('is not JSON', () async {
      final pack = await _pack(
        files: {
          themePath: Uint8List.fromList([1, 2, 3]),
        },
      );
      await _expectRefusal(
        _check(pack.manifest, files: pack.files),
        OrbitPackFailure.badTheme,
      );
    });

    test('is another theme than the pack claims', () async {
      final pack = await _pack(
        files: {
          themePath: Uint8List.fromList(
            utf8.encode(theme.replaceFirst('"synthwave"', '"papyrus"')),
          ),
        },
      );
      await _expectRefusal(
        _check(pack.manifest, files: pack.files),
        OrbitPackFailure.themeMismatch,
      );
    });

    test('switches on an effect this build does not ship', () async {
      final pack = await _pack();
      await _expectRefusal(
        _check(pack.manifest, files: pack.files, effects: {'bubbleGlow'}),
        OrbitPackFailure.unknownEffect,
      );
    });

    test('asks for a chat pattern this build does not draw', () async {
      final pack = await _pack();
      await _expectRefusal(
        _check(pack.manifest, files: pack.files, patterns: {'neonGrid'}),
        OrbitPackFailure.unknownPattern,
      );
    });

    test('and a refusal never quotes the pack back', () async {
      final pack = await _pack(
        files: {
          themePath: Uint8List.fromList(
            utf8.encode(
              theme.replaceFirst('wordmarkGlow', r'evil\nINFO forged line'),
            ),
          ),
        },
      );
      final check = await _check(pack.manifest, files: pack.files);
      expect(check.failure, OrbitPackFailure.unknownEffect);
      expect(check.detail, contains('(not an identifier)'));
      expect(check.detail, isNot(contains('\n')));
      expect(check.detail, isNot(contains('forged')));
    });
  });

  group('the slug a publisher builds from', () {
    // `tool/theme_pack_tool.dart build` turns a slug into a folder before any
    // manifest exists, so this predicate is the only thing between `--ids` and
    // a path. The manifest checks below prove the same rule on the wire.
    test('is a theme the format can name', () {
      for (final slug in ['bloom', 'jungle', 'a', 'a.b_c-d9']) {
        expect(isOrbitPackName(slug), isTrue, reason: slug);
      }
    });

    test('is never a path, a name or an empty string', () {
      for (final bad in [
        '',
        ' ',
        '..',
        '../orbit',
        'themes/bloom',
        'Bloom',
        'bloom ',
        '-bloom',
        '.bloom',
        'a' * 65,
      ]) {
        expect(isOrbitPackName(bad), isFalse, reason: '"$bad" was accepted');
      }
    });
  });
}

/// The theme file entry the pinned manifest signs for.
const themeEntry = OrbitPackFile(
  path: themePath,
  kind: 'theme',
  bytes: themeSize,
  sha256: themeSha256,
);

/// A manifest, with the pinned pack's fields by default.
OrbitPackManifest sampleManifest({
  int formatVersion = orbitPackFormatVersion,
  String id = packId,
  String pub = publisher,
  int revision = 1,
  String theme = themePath,
  List<OrbitPackFile> files = const [themeEntry],
  String? signature,
}) => OrbitPackManifest(
  formatVersion: formatVersion,
  id: id,
  publisher: pub,
  revision: revision,
  theme: theme,
  files: files,
  signature: signature,
);

/// A pack of one theme document listed at [path] - a path the gate is expected
/// to refuse, so the bytes are never opened.
({OrbitPackManifest manifest, Map<String, List<int>> files}) _packAt(
  String path,
) => (
  manifest: sampleManifest(
    theme: path,
    files: [
      OrbitPackFile(
        path: path,
        kind: 'theme',
        bytes: themeSize,
        sha256: themeSha256,
      ),
    ],
  ),
  files: {path: themeBytes},
);

/// A pack built the way `tool/theme_pack_tool.dart` builds one: sizes and
/// hashes read from the bytes it was given, files sorted by path.
Future<({OrbitPackManifest manifest, Map<String, List<int>> files})> _pack({
  Map<String, List<int>>? files,
  String id = packId,
  String theme = themePath,
}) async {
  final delivered = files ?? {theme: themeBytes};
  final listed = <OrbitPackFile>[];
  for (final path in delivered.keys.toList()..sort()) {
    listed.add(
      OrbitPackFile(
        path: path,
        kind: _kindOf(path),
        bytes: delivered[path]!.length,
        sha256: await _sha256Hex(delivered[path]!),
      ),
    );
  }
  return (
    manifest: OrbitPackManifest(
      formatVersion: orbitPackFormatVersion,
      id: id,
      publisher: publisher,
      revision: 1,
      theme: theme,
      files: listed,
    ),
    files: delivered,
  );
}

String _kindOf(String path) {
  final lower = path.toLowerCase();
  for (final entry in orbitPackFileKinds.entries) {
    if (entry.value.any((suffix) => lower.endsWith(suffix))) return entry.key;
  }
  throw ArgumentError.value(path, 'path', 'has no kind in the format');
}

/// Signs with the pinned test key. Signing here is not what makes the format
/// trustworthy - [pinnedCanonical] is, because it pins the message itself.
Future<String> _signature(OrbitPackManifest manifest) async {
  final signature = await Ed25519().sign(
    manifest.signingBytes(),
    keyPair: SimpleKeyPairData(
      publisherSeed,
      publicKey: SimplePublicKey(
        await _publicKeyOf(publisherSeed),
        type: KeyPairType.ed25519,
      ),
      type: KeyPairType.ed25519,
    ),
  );
  return base64Encode(signature.bytes);
}

Future<List<int>> _publicKeyOf(Uint8List seed) async {
  final pair = await Ed25519().newKeyPairFromSeed(seed);
  return (await pair.extractPublicKey()).bytes;
}

Uint8List _manifestBytes(OrbitPackManifest manifest, {String? signature}) {
  final json = manifest.toJson();
  if (signature != null) json['signature'] = signature;
  return Uint8List.fromList(utf8.encode(jsonEncode(json)));
}

Future<OrbitPackCheck> _checkBytes({
  required List<int> manifestBytes,
  required Map<String, List<int>> files,
  Set<String>? effects,
  Set<String>? patterns,
  Map<String, List<int>>? publishers,
  OrbitPackLimits limits = OrbitPackLimits.standard,
}) => checkOrbitPack(
  manifestBytes: manifestBytes,
  files: files,
  knownEffectKinds: effects ?? shippedEffects,
  knownPatternKinds: patterns ?? shippedPatterns,
  trustedPublishers: publishers ?? {publisher: publisherKey},
  limits: limits,
);

/// Runs the gate over [manifest], signing it when no other signature is given,
/// which is how a refusal is reached by the check under test and not by an
/// earlier one.
Future<OrbitPackCheck> _check(
  OrbitPackManifest manifest, {
  required Map<String, List<int>> files,
  String? signature,
  bool unsigned = false,
  Set<String>? effects,
  Set<String>? patterns,
  Map<String, List<int>>? publishers,
  OrbitPackLimits limits = OrbitPackLimits.standard,
}) async {
  final bytes = unsigned
      ? _manifestBytes(manifest)
      : _manifestBytes(
          manifest,
          signature: signature ?? await _signature(manifest),
        );
  return _checkBytes(
    manifestBytes: bytes,
    files: files,
    effects: effects,
    patterns: patterns,
    publishers: publishers,
    limits: limits,
  );
}

Future<void> _expectRefusal(
  Future<OrbitPackCheck> check,
  OrbitPackFailure failure,
) async {
  final result = await check;
  expect(
    result.failure,
    failure,
    reason: '${result.failure}: ${result.detail}',
  );
  expect(result.manifest, isNull);
  expect(result.detail, isNotNull);
  expect(result.isAllowed, isFalse);
}

Future<String> _sha256Hex(List<int> bytes) async =>
    _hex((await Sha256().hash(bytes)).bytes);

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

List<int> _hexDecode(String text) => [
  for (var i = 0; i < text.length; i += 2)
    int.parse(text.substring(i, i + 2), radix: 16),
];
