/// The Orbit theme-pack tool: make a publisher key, build packs from the theme
/// table or a folder, sign them, check one the way the app does, and publish it
/// (`orbit/PORT_PLAN.md` Part C steps 1 and 8, ADR-033,
/// `docs/product/THEME_PACK_FORMAT.md`).
///
/// A publisher - today only Helix itself - runs this from `helix_remote/`:
///
/// ```
/// dart run tool/theme_pack_tool.dart keygen  --seed-file keys/orbit.hex
/// dart run tool/theme_pack_tool.dart build   --themes packages/orbit_ui/assets/themes
///                                            --ids bloom,mochi,papyrus \
///                                            --publisher agiletechbd --revision 1 \
///                                            --seed-file keys/orbit.hex
/// dart run tool/theme_pack_tool.dart pack    --in build/synthwave --id synthwave \
///                                            --publisher agiletechbd --revision 1 \
///                                            --seed-file keys/orbit.hex
/// dart run tool/theme_pack_tool.dart sign    --manifest build/synthwave/manifest.json \
///                                            --seed-file keys/orbit.hex
/// dart run tool/theme_pack_tool.dart verify  --in build/synthwave \
///                                            --key <the publisher key printed by keygen>
/// dart run tool/theme_pack_tool.dart publish --in build/synthwave \
///                                            --out /srv/helix/packs
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
    case 'build':
      await _build(options);
    case 'sign':
      await _sign(options);
    case 'verify':
      await _verify(options);
    case 'publish':
      await _publish(options);
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

  build --themes DIR --ids SLUG,SLUG --out DIR
        --publisher SLUG --revision N [--seed-file PATH]
      The same step for a whole theme table: for each slug it copies
      DIR/<slug>.json into OUT/<slug>/themes/<slug>.json and writes that
      folder's manifest, so one command stages and builds every theme a
      publisher means to offer. The document's own "id" must still be the
      slug, and a staged file that is a different generation of the same theme
      is refused rather than overwritten - the folder it writes is staging, and
      publish is the step that decides what a server offers.

  sign --manifest FILE --seed-file PATH
      Signs a manifest that was built unsigned.

  verify --in DIR [--manifest FILE] [--key HEX]
       [--effects a,b,c] [--patterns a,b,c]
      Runs the app's own gate over the folder. --key is the publisher key the
      build trusts; without a registry, --effects and --patterns are not
      checked and the tool says so.

  publish --in DIR --out DIR [--manifest FILE]
      Copies a signed pack into the server's pack folder (HELIX_PACKS_DIR) the
      way the server serves it: OUT/<id>/r<revision>/manifest.json plus
      OUT/<id>/r<revision>/files/<sha256>, one copy of each file by its hash,
      so a file in two revisions is stored once. The manifest must be signed,
      and every file it names must be in DIR and hash to the bytes it claims.
      The files go in before the manifest, because a revision folder without
      one is a revision the server does not list, so an interrupted publish
      leaves nothing half-advertised. A revision that is already published with
      other bytes is refused - a revision is immutable, so build --revision
      one higher instead.

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
  await _manifest(
    folder,
    outputPath,
    id: id,
    publisher: publisher,
    revision: revision,
    seedPath: o['seed-file'],
  );
}

/// Part C step 8: the theme table itself becomes pack folders, so a publisher's
/// command is one line for as many themes as they mean to offer instead of one
/// folder built by hand per theme.
///
/// What it writes is staging, not an offer: `publish` is still the step that
/// decides what a server serves, and a revision already published there is
/// still never rewritten.
Future<void> _build(Map<String, String> o) async {
  final themes = o['themes'];
  final out = o['out'];
  final publisher = o['publisher'];
  final revision = int.tryParse(o['revision'] ?? '');
  final ids = _slugs(o['ids']);
  if (themes == null) _die('build needs --themes DIR');
  if (out == null) _die('build needs --out DIR');
  if (publisher == null) _die('build needs --publisher SLUG');
  if (revision == null || revision < 1) {
    _die('build needs --revision N, from 1');
  }
  if (ids.isEmpty) _die('build needs --ids SLUG,SLUG');
  final source = _folder(themes);
  final root = Directory(out)..createSync(recursive: true);
  for (final id in ids) {
    // A slug is about to become a folder name, so the format's own rule checks
    // it first: `--ids ../orbit` names no theme anyone could ever download.
    if (!isOrbitPackName(id)) {
      _die('"$id" is not a slug a pack may be named by');
    }
    final document = File('${source.path}/$id.json');
    if (!document.existsSync()) {
      _die(
        '${source.path} has no $id.json - build packs the theme documents '
        'that exist, it does not invent one',
      );
    }
    final bytes = document.readAsBytesSync();
    final folder = Directory('${root.path}/$id');
    final staged = File('${folder.path}/themes/$id.json');
    if (staged.existsSync() && !_sameBytes(staged.readAsBytesSync(), bytes)) {
      _die(
        '${staged.path} is another generation of $id; stage into a fresh '
        '--out, or delete it, rather than mix two',
      );
    }
    staged.parent.createSync(recursive: true);
    staged.writeAsBytesSync(bytes);
    await _manifest(
      folder,
      '${folder.path}/manifest.json',
      id: id,
      publisher: publisher,
      revision: revision,
      seedPath: o['seed-file'],
    );
  }
  stdout.writeln('');
  stdout.writeln('built ${ids.length} packs in ${root.path}');
  stdout.writeln('then: verify --in <that folder> --key <publisher key>');
  stdout.writeln('and:  publish --in <that folder> --out the pack folder');
}

/// The manifest of the pack in [folder]: every file it holds hashed, its one
/// theme document checked against [id], signed when a seed is given, written to
/// [outputPath].
Future<void> _manifest(
  Directory folder,
  String outputPath, {
  required String id,
  required String publisher,
  required int revision,
  String? seedPath,
}) async {
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
  final signed = await _withSignature(manifest, seedPath);
  File(outputPath).writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(signed)}\n',
  );
  stdout.writeln(
    'pack: ${manifest.id} r${manifest.revision}, '
    '${manifest.files.length} files, '
    '${manifest.files.map((f) => f.bytes).fold(0, (a, b) => a + b)} bytes',
  );
  stdout.writeln('manifest: $outputPath');
  if (seedPath == null) {
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

/// Copies a built pack into the folder the server reads (`HELIX_PACKS_DIR`), in
/// the layout `server/lib/src/modules/ops/pack_host.dart` serves and
/// `docs/product/THEME_PACK_FORMAT.md` describes.
Future<void> _publish(Map<String, String> o) async {
  final dir = o['in'];
  final dest = o['out'];
  if (dir == null) {
    _die('publish needs --in DIR, the folder the pack was built in');
  }
  if (dest == null) {
    _die("publish needs --out DIR, the server's HELIX_PACKS_DIR");
  }
  final folder = _folder(dir);
  final source = File(o['manifest'] ?? '${folder.path}/manifest.json');
  if (!source.existsSync()) _die('${source.path} does not exist');
  final manifestBytes = source.readAsBytesSync();
  final manifest = _readManifest(utf8.decode(manifestBytes));
  if (manifest.signature == null) {
    _die(
      '${source.path} holds no signature; sign it, or every device that '
      'downloads it will refuse it',
    );
  }
  final delivered = await _filesIn(folder);
  for (final entry in manifest.files) {
    final bytes = delivered[entry.path];
    if (bytes == null) {
      _die('the manifest names ${entry.path}, which $dir does not hold');
    }
    if (bytes.length != entry.bytes) {
      _die(
        '${entry.path} is ${bytes.length} bytes, not the ${entry.bytes} '
        'the manifest says',
      );
    }
    final hex = await _sha256Hex(bytes);
    if (hex != entry.sha256) {
      _die(
        '${entry.path} hashes to $hex, not to the ${entry.sha256} the '
        'manifest says',
      );
    }
  }

  final pack = '$dest/${manifest.id}/r${manifest.revision}';
  final published = File('$pack/manifest.json');
  if (published.existsSync()) {
    if (!_sameBytes(published.readAsBytesSync(), manifestBytes)) {
      _die(
        '$pack already holds a different manifest. A revision is the bytes a '
        'device already cached, so it is never rewritten: pack again with '
        '--revision ${manifest.revision + 1}',
      );
    }
    stdout.writeln('$pack/manifest.json is already published, unchanged');
  }
  final files = Directory('$pack/files')..createSync(recursive: true);
  var copied = 0;
  for (final entry in manifest.files) {
    final at = File('${files.path}/${entry.sha256}');
    if (at.existsSync()) continue;
    at.writeAsBytesSync(delivered[entry.path]!, flush: true);
    copied++;
  }
  if (!published.existsSync()) {
    published.writeAsBytesSync(manifestBytes, flush: true);
  }
  stdout.writeln(
    'published: ${manifest.id} r${manifest.revision}, '
    '${manifest.files.length} files ($copied copied, '
    '${manifest.files.length - copied} already there)',
  );
  stdout.writeln('at: $pack');
}

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
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

/// `--ids`, as slugs in order, with blanks dropped.
List<String> _slugs(String? value) => [
  for (final part in (value ?? '').split(','))
    if (part.trim().isNotEmpty) part.trim(),
];

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
