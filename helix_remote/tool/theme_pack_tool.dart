/// The Orbit theme-pack tool: make a publisher key, build a pack, sign it, and
/// check one the way the app does (`orbit/PORT_PLAN.md` Part C step 1,
/// ADR-033, `docs/product/THEME_PACK_FORMAT.md`).
///
/// A publisher - today only Helix itself - runs this from `helix_remote/`:
///
/// ```
/// dart run tool/theme_pack_tool.dart keygen  --seed-file keys/orbit.hex
/// dart run tool/theme_pack_tool.dart pack    --in build/synthwave --id synthwave \
///                                            --publisher agiletechbd --revision 1 \
///                                            --seed-file keys/orbit.hex
/// dart run tool/theme_pack_tool.dart sign    --manifest build/synthwave/manifest.json \
///                                            --seed-file keys/orbit.hex
/// dart run tool/theme_pack_tool.dart verify  --in build/synthwave \
///                                            --key <the publisher key printed by keygen>
/// ```
///
/// The app never signs and never holds a private key, which is why the private
/// half lives only in the file `--seed-file` names, and why this tool prints a
/// seed's public key and never the seed itself.
///
/// `verify` checks a pack with [checkOrbitPack] - the same code the app runs -
/// but it is a publisher's dry run, not the thing a user relies on: the effect
/// registry comes from `orbit_ui`, which a Dart script cannot import, so
/// `--effects` and `--patterns` are whatever the publisher lists, and without
/// them those two checks are reported as not run.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:helix_remote_domain/models.dart';

final _ed25519 = Ed25519();
final _sha256 = Sha256();

Future<void> main(List<String> args) async {
  final command = args.isEmpty ? 'help' : args.first;
  final options = _options(args.skip(1).toList());
  switch (command) {
    case 'keygen':
      await _keygen(options);
    case 'pack':
      await _pack(options);
    case 'sign':
      await _sign(options);
    case 'verify':
      await _verify(options);
    case 'help':
    case '--help':
    case '-h':
      stdout.write(_usage);
    default:
      _die('unknown command "$command"; run it with no arguments for usage');
  }
}

const _usage = '''
Orbit theme packs (orbit/PORT_PLAN.md Part C)

  keygen --seed-file PATH
      Writes a new Ed25519 private key (hex) to PATH, which must not exist yet,
      and prints the publisher key to paste into the app's trust anchor. The
      private key is never printed.

  pack --in DIR --id SLUG --publisher SLUG --revision N
       [--seed-file PATH] [--out FILE]
      Lists every file under DIR except manifest.json, hashes each one, and
      writes DIR/manifest.json (or --out). The folder must hold exactly one
      .json theme document whose own "id" is --id. With --seed-file the
      manifest is signed in the same step.

  sign --manifest FILE --seed-file PATH
      Signs a manifest that was built unsigned.

  verify --in DIR [--manifest FILE] [--key HEX]
       [--effects a,b,c] [--patterns a,b,c]
      Runs the app's own gate over the folder. --key is the publisher key the
      build trusts; without a registry, --effects and --patterns are not
      checked and the tool says so.

Exit code is 0 when the pack is usable and 1 when it is not.
''';

Map<String, String> _options(List<String> args) {
  final out = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (!arg.startsWith('--')) {
      _die('"$arg" is not an option; every argument is --name value');
    }
    final name = arg.substring(2);
    if (i + 1 >= args.length || args[i + 1].startsWith('--')) {
      _die('--$name needs a value');
    }
    out[name] = args[++i];
  }
  return out;
}

Never _die(String why) {
  stderr.writeln('theme_pack_tool: $why');
  stderr.writeln('Run with no arguments for usage.');
  exit(1);
}

Future<void> _keygen(Map<String, String> o) async {
  final path = o['seed-file'];
  if (path == null) _die('keygen needs --seed-file PATH');
  final file = File(path);
  if (file.existsSync()) {
    _die('$path already holds a key; nothing was overwritten');
  }
  final pair = await _ed25519.newKeyPair();
  final seed = await pair.extractPrivateKeyBytes();
  final public = await pair.extractPublicKey();
  file.writeAsStringSync('${_hex(seed)}\n', flush: true);
  stdout.writeln('publisher key: ${_hex(public.bytes)}');
  stdout.writeln('private key:   $path (not printed, and not in the pack)');
}

Future<void> _pack(Map<String, String> o) async {
  final dir = o['in'];
  final id = o['id'];
  final publisher = o['publisher'];
  final revision = int.tryParse(o['revision'] ?? '');
  if (dir == null) _die('pack needs --in DIR');
  if (id == null) _die('pack needs --id SLUG');
  if (publisher == null) _die('pack needs --publisher SLUG');
  if (revision == null || revision < 1) _die('pack needs --revision N, from 1');
  final folder = _folder(dir);
  final outputPath = o['out'] == null
      ? '${folder.path}/manifest.json'
      : File(o['out']!).path;
  final delivered = await _filesIn(folder);
  if (delivered.isEmpty) _die('${folder.path} holds no pack files');

  final themePath = _onlyTheme(delivered, id);
  final manifest = OrbitPackManifest(
    formatVersion: orbitPackFormatVersion,
    id: id,
    publisher: publisher,
    revision: revision,
    theme: themePath,
    files: [
      for (final entry in delivered.entries)
        OrbitPackFile(
          path: entry.key,
          kind: _kindOf(entry.key),
          bytes: entry.value.length,
          sha256: await _sha256Hex(entry.value),
        ),
    ],
  );
  final signed = await _withSignature(manifest, o['seed-file']);
  File(outputPath).writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(signed)}\n',
  );
  stdout.writeln(
    'pack: ${manifest.id} r${manifest.revision}, '
    '${manifest.files.length} files, '
    '${manifest.files.map((f) => f.bytes).fold(0, (a, b) => a + b)} bytes',
  );
  stdout.writeln('manifest: $outputPath');
  if (o['seed-file'] == null) {
    stdout.writeln(
      'unsigned: run sign --manifest $outputPath --seed-file PATH',
    );
  }
}

Future<void> _sign(Map<String, String> o) async {
  final path = o['manifest'];
  final seedPath = o['seed-file'];
  if (path == null) _die('sign needs --manifest FILE');
  if (seedPath == null) _die('sign needs --seed-file PATH');
  final file = File(path);
  if (!file.existsSync()) _die('$path does not exist');
  final manifest = _readManifest(file.readAsStringSync());
  if (manifest.signature != null) {
    stdout.writeln('this manifest already carries a signature; it is replaced');
  }
  final signed = await _withSignature(_unsigned(manifest), seedPath);
  file.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(signed)}\n',
  );
  stdout.writeln(
    'signed ${manifest.id} r${manifest.revision} for '
    '${manifest.publisher}',
  );
}

Future<void> _verify(Map<String, String> o) async {
  final dir = o['in'];
  if (dir == null) _die('verify needs --in DIR');
  final folder = _folder(dir);
  final manifestFile = File(o['manifest'] ?? '${folder.path}/manifest.json');
  if (!manifestFile.existsSync()) _die('${manifestFile.path} does not exist');
  final manifestBytes = manifestFile.readAsBytesSync();
  final delivered = await _filesIn(folder);
  final manifest = _readManifest(utf8.decode(manifestBytes));

  final effects = _csv(o['effects']);
  final patterns = _csv(o['patterns']);
  final check = await checkOrbitPack(
    manifestBytes: manifestBytes,
    files: delivered,
    knownEffectKinds:
        effects ??
        {
          for (final kind in _effectKindsIn(
            delivered[manifest.theme] ?? Uint8List(0),
          ))
            kind,
        },
    knownPatternKinds:
        patterns ??
        {
          for (final kind in _patternKindsIn(
            delivered[manifest.theme] ?? Uint8List(0),
          ))
            kind,
        },
    trustedPublishers: {
      if (o['key'] != null) manifest.publisher: _unhex(o['key']!),
    },
  );
  if (check.isAllowed) {
    stdout.writeln(
      'usable: ${check.manifest!.id} r${check.manifest!.revision}',
    );
  } else {
    stdout.writeln('refused: ${check.failure!.name} - ${check.detail}');
    stdout.writeln(check.failure!.reason);
  }
  if (effects == null || patterns == null) {
    stdout.writeln(
      'note: the effect and pattern registries come from orbit_ui, which a '
      'Dart script cannot import, so this run took them from the theme '
      'document itself and checked nothing against them. The app always '
      'checks.',
    );
  }
  if (!check.isAllowed) exit(1);
}

/// Signs [manifest]'s bytes with the seed in [seedPath] and returns its JSON
/// with the `signature` field set. The seed is read and forgotten.
Future<Map<String, Object?>> _withSignature(
  OrbitPackManifest manifest,
  String? seedPath,
) async {
  final json = manifest.toJson();
  if (seedPath == null) return json;
  final seed = _unhex(
    File(seedPath).readAsStringSync().trim(),
    what: 'the seed file',
  );
  if (seed.length != 32) _die('the seed file must hold 32 bytes in hex');
  final pair = await _ed25519.newKeyPairFromSeed(seed);
  final public = await pair.extractPublicKey();
  final signature = await _ed25519.sign(
    manifest.signingBytes(),
    keyPair: SimpleKeyPairData(
      seed,
      publicKey: public,
      type: KeyPairType.ed25519,
    ),
  );
  return json..['signature'] = base64Encode(signature.bytes);
}

OrbitPackManifest _readManifest(String text) {
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    _die('the manifest is not JSON');
  }
  if (decoded is! Map<String, Object?>) _die('the manifest is not an object');
  try {
    return OrbitPackManifest.fromJson(decoded);
  } on FormatException catch (e) {
    _die('the manifest is not well-formed: ${e.message}');
  }
}

/// The manifest with its signature dropped, which is what gets signed again.
OrbitPackManifest _unsigned(OrbitPackManifest manifest) => OrbitPackManifest(
  formatVersion: manifest.formatVersion,
  id: manifest.id,
  publisher: manifest.publisher,
  revision: manifest.revision,
  theme: manifest.theme,
  files: manifest.files,
);

/// Every file under [folder] except the tool's own `manifest.json`, by
/// pack-relative path.
Future<Map<String, Uint8List>> _filesIn(Directory folder) async {
  final out = <String, Uint8List>{};
  for (final entity in folder.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final relative = _relative(folder, entity.path);
    if (relative == null) continue;
    if (relative.split('/').last == 'manifest.json') continue;
    out[relative] = entity.readAsBytesSync();
  }
  return {for (final key in out.keys.toList()..sort()) key: out[key]!};
}

/// The one `.json` document a pack is allowed to hold, by path. Its own `id`
/// must be the pack's, which is the check that stops a pack claiming to be one
/// theme and shipping another.
String _onlyTheme(Map<String, Uint8List> files, String id) {
  final documents = files.entries
      .where((entry) => entry.key.toLowerCase().endsWith('.json'))
      .toList();
  if (documents.length != 1) {
    _die(
      'a pack carries exactly one theme document; '
      '${documents.map((d) => d.key).join(', ')} are JSON',
    );
  }
  final Object? doc;
  try {
    doc = jsonDecode(utf8.decode(documents.single.value));
  } on FormatException {
    _die('${documents.single.key} is not readable JSON');
  }
  if (doc is! Map<String, Object?>) {
    _die('${documents.single.key} is not an object');
  }
  if (doc['id'] != id) {
    _die(
      '${documents.single.key} calls itself "${doc['id']}", '
      'and the pack is --id $id',
    );
  }
  return documents.single.key;
}

String _kindOf(String path) {
  final lower = path.toLowerCase();
  for (final entry in orbitPackFileKinds.entries) {
    if (entry.value.any((suffix) => lower.endsWith(suffix))) return entry.key;
  }
  _die('$path has no extension a pack knows; a theme is .json');
}

Iterable<String> _effectKindsIn(List<int> themeBytes) {
  final Object? doc;
  try {
    doc = jsonDecode(utf8.decode(themeBytes));
  } on FormatException {
    return const [];
  }
  final effects = doc is Map<String, Object?> ? doc['effects'] : null;
  if (effects is! List) return const [];
  return [
    for (final e in effects)
      if (e is Map<String, Object?> && e['kind'] is String)
        e['kind']! as String,
  ];
}

Iterable<String> _patternKindsIn(List<int> themeBytes) {
  final Object? doc;
  try {
    doc = jsonDecode(utf8.decode(themeBytes));
  } on FormatException {
    return const [];
  }
  final tokens = doc is Map<String, Object?> ? doc['tokens'] : null;
  final group = tokens is Map<String, Object?> ? tokens['pattern'] : null;
  final pattern = group is Map<String, Object?> ? group['chat-pattern'] : null;
  final kind = pattern is Map<String, Object?> ? pattern['kind'] : null;
  return kind is String ? [kind] : const [];
}

Set<String>? _csv(String? value) =>
    value == null ? null : {for (final part in value.split(',')) part.trim()};

Directory _folder(String path) {
  final folder = Directory(path);
  if (!folder.existsSync()) _die('$path is not a folder');
  return folder;
}

/// [entityPath] relative to [folder], with forward slashes, or null when it is
/// outside it (which `listSync` does not produce).
String? _relative(Directory folder, String entityPath) {
  final root = folder.path.replaceAll(r'\', '/');
  final path = entityPath.replaceAll(r'\', '/');
  final prefix = root.endsWith('/') ? root : '$root/';
  if (!path.startsWith(prefix)) return null;
  return path.substring(prefix.length);
}

Future<String> _sha256Hex(List<int> bytes) async =>
    _hex((await _sha256.hash(bytes)).bytes);

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Uint8List _unhex(String text, {String what = '--key'}) {
  final clean = text.trim();
  if (clean.isEmpty || clean.length.isOdd) _die('$what must be hex bytes');
  return Uint8List.fromList([
    for (var i = 0; i < clean.length; i += 2)
      int.tryParse(clean.substring(i, i + 2), radix: 16) ??
          _die('$what is not hex'),
  ]);
}
