/// Downloadable Orbit theme packs: the manifest format, and the one gate every
/// pack passes before the app draws with it (`orbit/PORT_PLAN.md` Part C).
///
/// A pack is **data**. It carries a theme document in the same JSON the
/// built-in themes are written in, and it may only switch on effects this
/// build already ships - so a pack can never bring code, and a hacked server
/// can never make one. That is the whole design, and it is why [checkOrbitPack]
/// checks three things and nothing else: the publisher's signature, the size
/// limits, and the format.
///
/// What is *not* here: the effect registry (a design-system fact, so
/// `orbit_ui` owns it and the app hands it to [knownEffectKinds]), the trust
/// anchor (an app build fact, so the app owns it and hands it to
/// [trustedPublishers]), and the download itself.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// The only pack format this build reads.
///
/// A pack saying anything else is refused rather than guessed at: the envelope
/// is a dozen fields, so a new version means a new app release, and a
/// half-understood pack is the one that draws something its publisher never
/// signed.
const orbitPackFormatVersion = 1;

/// The file kinds a pack may carry, and the extensions each one takes.
///
/// `theme` is the theme document itself and the only kind the app draws with.
/// `audio` is a ringtone, which the app plays rather than draws. `font` and
/// `image` may sit in a pack ahead of the step that ships their loader: they
/// are checked like any other file (signed, hashed, size-limited) and simply
/// not read, which is why the format can name them now.
const orbitPackFileKinds = <String, List<String>>{
  'theme': ['.json'],
  'audio': ['.m4a', '.aac', '.mp3', '.ogg', '.wav'],
  'font': ['.ttf', '.otf', '.woff2'],
  'image': ['.png', '.webp'],
};

/// What a pack is, and the file kind its one body must be.
///
/// A theme pack's body is its theme document, named by the manifest's `theme`
/// path. A sound pack has no document at all: its one file *is* the pack, and
/// the app plays it (Part C step 5, on the owner's ruling that a ringtone
/// arrives as a signed pack rather than through a second download route).
///
/// A manifest without `contents` is a theme pack, which is every pack written
/// before sounds existed - and because an absent field is not signed, those
/// packs' bytes do not change here.
const orbitPackContents = <String, String>{'theme': 'theme', 'sound': 'audio'};

/// The `contents` a manifest has when it does not say.
const orbitPackDefaultContents = 'theme';

/// How many id and publisher characters a manifest may use.
const orbitPackNameMaxChars = 64;

/// Whether [value] is a slug a pack may be named by, as `id` or `publisher`.
///
/// A publisher building packs from a folder of theme documents needs this
/// before a slug becomes a file or folder name; the app never needs it, because
/// [checkOrbitPack] refuses a manifest that breaks it.
bool isOrbitPackName(String value) => _isName(value);

/// The caps a pack is refused against, in bytes and counts.
///
/// A built-in theme document is about 9 KiB, so a whole pack of one theme fits
/// in a fraction of these. They are deliberately far above what a real pack
/// needs and nowhere near what would hurt a phone: the point is that a pack
/// that cannot be drawn is refused before it is read, not that the limits
/// themselves are tight.
final class OrbitPackLimits {
  const OrbitPackLimits({
    this.manifestBytes = 64 * 1024,
    this.fileBytes = 8 * 1024 * 1024,
    this.totalBytes = 24 * 1024 * 1024,
    this.fileCount = 16,
    this.pathChars = 96,
  });

  static const standard = OrbitPackLimits();

  /// The manifest itself, which the app parses in memory.
  final int manifestBytes;

  /// One file's bytes.
  final int fileBytes;

  /// All of a pack's files together.
  final int totalBytes;

  /// How many files a pack lists.
  final int fileCount;

  /// How long a file path may be.
  final int pathChars;
}

/// Why a pack was refused, in one of the ways the app can say without quoting
/// the pack back.
enum OrbitPackFailure {
  /// The manifest names a format this build cannot read.
  unknownFormat('a format this version of the app does not understand'),

  /// The manifest is not a pack manifest: not JSON, or a field of the wrong
  /// shape, or over the file-count limit.
  badManifest('a manifest that is not well-formed'),

  /// The theme document inside the pack is not JSON in the shape a theme has.
  badTheme('a theme document that is not well-formed'),

  /// The manifest's id and the theme document's id differ.
  themeMismatch('a theme document that is not the one the manifest signs for'),

  /// A file path that would escape the pack's own folder.
  badPath('a file path this app will not open'),

  /// More files than [OrbitPackLimits.fileCount].
  tooManyFiles('more files than a pack may carry'),

  /// A pack, a file or a manifest over its limit.
  tooLarge('bigger than a pack is allowed to be'),

  /// A file the manifest signs for but the download did not deliver.
  missingFile('a file the manifest promised is not there'),

  /// A file whose bytes are not the bytes the manifest hashed.
  changedFile('a file that is not the one the publisher signed'),

  /// A theme switching on an effect this build does not ship.
  unknownEffect('an effect this app does not have'),

  /// A theme asking for a chat pattern this build does not draw.
  unknownPattern('a chat pattern this app does not have'),

  /// A `contents` this build has no loader for: it is neither a theme it can
  /// draw nor a sound it can play.
  unknownContent('a kind of pack this app does not know'),

  /// A manifest with no signature at all.
  unsigned('a pack nobody signed'),

  /// A signature that is not a valid Ed25519 signature by the pack's own
  /// publisher over the pack's own manifest.
  badSignature('a signature that does not match what the pack contains'),

  /// A publisher this build does not trust, or whose key is unusable.
  unknownPublisher('a publisher this app does not trust');

  const OrbitPackFailure(this.reason);

  /// One line saying why, for the settings page and the logs. Never includes
  /// anything from inside the pack.
  final String reason;
}

/// One file a pack carries, as the manifest describes it.
final class OrbitPackFile {
  const OrbitPackFile({
    required this.path,
    required this.kind,
    required this.bytes,
    required this.sha256,
  });

  factory OrbitPackFile.fromJson(Map<String, Object?> json) {
    final path = json['path'];
    final kind = json['kind'];
    final bytes = json['bytes'];
    final sha256 = json['sha256'];
    if (path is! String || kind is! String) {
      throw const FormatException('files[] needs a path and a kind');
    }
    if (bytes is! int || bytes < 0) {
      throw const FormatException('files[] needs a byte count');
    }
    if (sha256 is! String || !_isHexSha256(sha256)) {
      throw const FormatException('files[] needs a lowercase hex sha256');
    }
    return OrbitPackFile(path: path, kind: kind, bytes: bytes, sha256: sha256);
  }

  Map<String, Object?> toJson() => {
    'path': path,
    'kind': kind,
    'bytes': bytes,
    'sha256': sha256,
  };

  /// Relative to the pack's own folder, and checked before it is ever opened.
  final String path;

  /// One of [orbitPackFileKinds].
  final String kind;

  /// The size the manifest signs for, which must match the bytes delivered.
  final int bytes;

  /// Lowercase hex SHA-256 of the file's bytes.
  final String sha256;
}

/// A pack's manifest: what the pack is, who signed it, and which bytes they
/// signed.
final class OrbitPackManifest {
  const OrbitPackManifest({
    required this.formatVersion,
    required this.id,
    required this.publisher,
    required this.revision,
    this.contents = orbitPackDefaultContents,
    this.theme,
    required this.files,
    this.signature,
  });

  /// Reads a manifest, throwing [FormatException] for a field of the wrong
  /// shape. [checkOrbitPack] turns that into a refusal; nothing else should
  /// parse one directly.
  factory OrbitPackManifest.fromJson(Map<String, Object?> json) {
    final formatVersion = json['formatVersion'];
    final id = json['id'];
    final publisher = json['publisher'];
    final revision = json['revision'];
    final contents = json['contents'];
    final theme = json['theme'];
    final rawFiles = json['files'];
    final rawSignature = json['signature'];
    if (formatVersion is! int) {
      throw const FormatException('formatVersion must be a whole number');
    }
    if (id is! String || !_isName(id)) {
      throw const FormatException('id must be a lowercase slug');
    }
    if (publisher is! String || !_isName(publisher)) {
      throw const FormatException('publisher must be a lowercase slug');
    }
    if (revision is! int || revision < 1) {
      throw const FormatException('revision must be a whole number from 1');
    }
    if (contents != null && contents is! String) {
      throw const FormatException(
        'contents must be a lowercase word or absent',
      );
    }
    if (theme != null && theme is! String) {
      throw const FormatException('theme must be a path, or absent');
    }
    if (rawFiles is! List) throw const FormatException('files must be a list');
    String? signature;
    if (rawSignature != null) {
      if (rawSignature is! String) {
        throw const FormatException('signature must be base64 or absent');
      }
      signature = rawSignature;
    }
    final packFiles = <OrbitPackFile>[];
    for (final item in rawFiles) {
      if (item is! Map<String, Object?>) {
        throw const FormatException('files[] items must be objects');
      }
      packFiles.add(OrbitPackFile.fromJson(item));
    }
    return OrbitPackManifest(
      formatVersion: formatVersion,
      id: id,
      publisher: publisher,
      revision: revision,
      contents: contents as String? ?? orbitPackDefaultContents,
      theme: theme as String?,
      files: packFiles,
      signature: signature,
    );
  }

  Map<String, Object?> toJson() => {
    'formatVersion': formatVersion,
    'id': id,
    'publisher': publisher,
    'revision': revision,
    // Absent means a theme pack, and an absent field is not signed: every theme
    // pack written before sounds existed keeps signing exactly the bytes it did.
    if (contents != orbitPackDefaultContents) 'contents': contents,
    if (theme != null) 'theme': theme,
    'files': [for (final f in files) f.toJson()],
    if (signature != null) 'signature': signature,
  };

  /// The exact bytes the publisher signs: this manifest without its
  /// `signature` field, as JSON with object keys in code-unit order and no
  /// whitespace, UTF-8.
  ///
  /// This is the only thing the signature covers, so it is what `pack` and
  /// `sign` in `tool/theme_pack_tool.dart` write and [checkOrbitPack] rebuilds.
  /// A pack whose downloaded manifest re-serialises differently is a pack whose
  /// signature will not verify - which is the safe direction for a format that
  /// is only ever written by this repo's own tool.
  Uint8List signingBytes() {
    final unsigned = toJson()..remove('signature');
    return Uint8List.fromList(utf8.encode(_canonicalJson(unsigned)));
  }

  /// Which format this pack is written for.
  final int formatVersion;

  /// The pack's id, and the slug the app knows this theme or sound by.
  final String id;

  /// Which trusted publisher's key must sign this manifest; see
  /// [OrbitPackCheck] and the app's trust anchor.
  final String publisher;

  /// What the publisher says this version of the pack is. The app keeps the
  /// highest revision it has for [id], so a re-download is an upgrade.
  final int revision;

  /// What is inside: one of [orbitPackContents]'s keys, defaulting to
  /// [orbitPackDefaultContents] when the manifest does not say. An unknown
  /// word is not guessed at; the gate refuses it as
  /// [OrbitPackFailure.unknownContent].
  final String contents;

  /// The path of the theme document, which must be one of [files]. Null for a
  /// pack that is not a theme: a sound pack's one file is the pack itself, so
  /// there is nothing to name.
  final String? theme;

  final List<OrbitPackFile> files;

  /// Base64 of the 64-byte Ed25519 signature over [signingBytes], or null when
  /// the pack has not been signed yet - which a release build never accepts.
  final String? signature;
}

/// What [checkOrbitPack] decided: the parsed manifest, or why not.
final class OrbitPackCheck {
  const OrbitPackCheck.allowed(this.manifest) : failure = null, detail = null;

  const OrbitPackCheck.refused(this.failure, this.detail) : manifest = null;

  bool get isAllowed => failure == null;

  /// The manifest, when the pack passed. Null when it was refused, so a
  /// caller cannot draw with a pack it forgot to check.
  final OrbitPackManifest? manifest;

  final OrbitPackFailure? failure;

  /// Which field or path was wrong, for the settings page and the logs. Names
  /// only the identifiers the format constrains (a slug, a checked path, a
  /// registry name); anything a pack wrote about itself is left out, and no
  /// theme text or file content ever is.
  final String? detail;

  @override
  String toString() => isAllowed
      ? 'OrbitPackCheck.allowed(${manifest!.id} r${manifest!.revision})'
      : 'OrbitPackCheck.refused(${failure!.name}: $detail)';
}

/// The gate run on a manifest alone: every check [checkOrbitPack] makes before
/// it opens a file, and nothing after them.
///
/// A page that lists what a host offers cannot take a pack's word for what kind
/// it is, because `contents` lives inside the signed manifest and only the
/// signature makes it the publisher's own word - so such a page asks for the
/// manifest and decides from this. The answer is not "usable": only
/// [checkOrbitPack], with the files in hand, says that. It is "this id and
/// revision is a pack of `manifest.contents`, by a publisher this build trusts",
/// which is all an offer row is worth, and it is decided without paying for a
/// file's bytes.
Future<OrbitPackCheck> checkOrbitPackManifest({
  required List<int> manifestBytes,
  required Map<String, List<int>> trustedPublishers,
  OrbitPackLimits limits = OrbitPackLimits.standard,
}) async {
  if (manifestBytes.length > limits.manifestBytes) {
    return const OrbitPackCheck.refused(
      OrbitPackFailure.tooLarge,
      'the manifest is bigger than a manifest may be',
    );
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(Uint8List.fromList(manifestBytes)));
  } on FormatException catch (e) {
    return OrbitPackCheck.refused(
      OrbitPackFailure.badManifest,
      'the manifest is not readable: ${e.message}',
    );
  }
  if (decoded is! Map<String, Object?>) {
    return const OrbitPackCheck.refused(
      OrbitPackFailure.badManifest,
      'the manifest is not an object',
    );
  }
  if (decoded['formatVersion'] != orbitPackFormatVersion) {
    return OrbitPackCheck.refused(
      OrbitPackFailure.unknownFormat,
      'it asks for format ${decoded['formatVersion']}, this app reads '
      '$orbitPackFormatVersion',
    );
  }
  final OrbitPackManifest manifest;
  try {
    manifest = OrbitPackManifest.fromJson(decoded);
  } on FormatException catch (e) {
    return OrbitPackCheck.refused(
      OrbitPackFailure.badManifest,
      'the manifest is not well-formed: ${e.message}',
    );
  }

  final shape = _checkShape(manifest, limits);
  if (shape != null) return shape;

  final signed = _publisherRoot(manifest, trustedPublishers);
  if (signed.refused != null) return signed.refused!;
  final verified = await _signatureVerifies(
    root: signed.root!,
    message: manifest.signingBytes(),
    signature: manifest.signature!,
  );
  if (!verified) {
    return OrbitPackCheck.refused(
      OrbitPackFailure.badSignature,
      'signed by "${manifest.publisher}" for pack "${manifest.id}", '
      'which this pack is not',
    );
  }
  return OrbitPackCheck.allowed(manifest);
}

/// The gate every downloaded pack passes before the app reads a byte of it.
///
/// [manifestBytes] is the manifest exactly as downloaded - the bytes are what
/// the signature is checked against, so a pack re-serialised on the way is
/// refused rather than repaired. [files] is every file by path.
/// [knownEffectKinds] and [knownPatternKinds] are this build's registries
/// (`orbit_ui`'s `OrbitEffects`), and [trustedPublishers] maps publisher id to
/// the raw 32-byte Ed25519 key the app ships.
///
/// Nothing in a pack is opened until its signature has verified: the checks
/// before it touch only the manifest's own shape and its declared sizes, and
/// they are [checkOrbitPackManifest]'s answer to a page that asked.
Future<OrbitPackCheck> checkOrbitPack({
  required List<int> manifestBytes,
  required Map<String, List<int>> files,
  required Set<String> knownEffectKinds,
  required Set<String> knownPatternKinds,
  required Map<String, List<int>> trustedPublishers,
  OrbitPackLimits limits = OrbitPackLimits.standard,
}) async {
  final manifest = await checkOrbitPackManifest(
    manifestBytes: manifestBytes,
    trustedPublishers: trustedPublishers,
    limits: limits,
  );
  if (!manifest.isAllowed) return manifest;
  final pack = manifest.manifest!;

  final delivered = await _checkFiles(pack, files, limits);
  if (delivered != null) return delivered;
  final theme = pack.contents == 'theme'
      ? _checkTheme(pack, files, knownEffectKinds, knownPatternKinds)
      : null;
  if (theme != null) return theme;
  return manifest;
}

/// The manifest's own limits and path rules - the checks that run before any
/// file is looked at. Returns a refusal, or null when the shape holds.
OrbitPackCheck? _checkShape(
  OrbitPackManifest manifest,
  OrbitPackLimits limits,
) {
  // What the pack claims to be decides which file is its body, so it is
  // settled first: nothing about a pack this build cannot use is worth checking
  // file by file.
  final body = orbitPackContents[manifest.contents];
  if (body == null) {
    return OrbitPackCheck.refused(
      OrbitPackFailure.unknownContent,
      'it calls itself a "${_printable(manifest.contents)}" pack, and this app '
      'draws themes and plays sounds',
    );
  }
  if (manifest.contents == 'theme') {
    final path = manifest.theme;
    if (path == null) {
      return const OrbitPackCheck.refused(
        OrbitPackFailure.badManifest,
        'a theme pack names its theme document',
      );
    }
    if (!_isPath(path, limits.pathChars)) {
      return const OrbitPackCheck.refused(
        OrbitPackFailure.badPath,
        'its theme document is named by a path this app will not open',
      );
    }
  } else if (manifest.theme != null) {
    return const OrbitPackCheck.refused(
      OrbitPackFailure.badManifest,
      'a sound pack has no theme document to name',
    );
  }
  if (manifest.files.length > limits.fileCount) {
    return OrbitPackCheck.refused(
      OrbitPackFailure.tooManyFiles,
      '${manifest.files.length} files, a pack may carry ${limits.fileCount}',
    );
  }
  final seen = <String>{};
  var total = 0;
  var bodies = 0;
  OrbitPackFile? listedTheme;
  for (final f in manifest.files) {
    if (!_isPath(f.path, limits.pathChars)) {
      return OrbitPackCheck.refused(
        OrbitPackFailure.badPath,
        'path "${f.path}" is not one this app will open',
      );
    }
    if (!seen.add(f.path)) {
      return OrbitPackCheck.refused(
        OrbitPackFailure.badManifest,
        'path "${f.path}" is listed twice',
      );
    }
    final suffixes = orbitPackFileKinds[f.kind];
    if (suffixes == null) {
      return OrbitPackCheck.refused(
        OrbitPackFailure.badManifest,
        'file "${f.path}" has an unknown kind "${f.kind}"',
      );
    }
    if (!suffixes.any((s) => f.path.toLowerCase().endsWith(s))) {
      return OrbitPackCheck.refused(
        OrbitPackFailure.badManifest,
        'file "${f.path}" is kind "${f.kind}" but not named for one',
      );
    }
    if (f.kind == body) bodies++;
    if (f.path == manifest.theme) listedTheme = f;
    if (f.bytes > limits.fileBytes) {
      return OrbitPackCheck.refused(
        OrbitPackFailure.tooLarge,
        'file "${f.path}" promises more bytes than a file may have',
      );
    }
    total += f.bytes;
    if (total > limits.totalBytes) {
      return const OrbitPackCheck.refused(
        OrbitPackFailure.tooLarge,
        'the pack promises more bytes in total than a pack may have',
      );
    }
  }
  if (bodies != 1) {
    return OrbitPackCheck.refused(
      OrbitPackFailure.badManifest,
      'a ${manifest.contents} pack carries exactly one $body file, this lists '
      '$bodies',
    );
  }
  // A sound pack is its one file, so anything beside it - a theme, a font, a
  // second sound - is not that shape, even inside the file limit.
  if (manifest.contents == 'sound' && manifest.files.length != 1) {
    return OrbitPackCheck.refused(
      OrbitPackFailure.badManifest,
      'a sound pack is one file, this lists ${manifest.files.length}',
    );
  }
  if (manifest.contents == 'theme') {
    if (listedTheme == null) {
      return OrbitPackCheck.refused(
        OrbitPackFailure.badManifest,
        'theme "${manifest.theme}" is not one of the files',
      );
    }
    if (listedTheme.kind != 'theme') {
      return OrbitPackCheck.refused(
        OrbitPackFailure.badManifest,
        'theme "${manifest.theme}" is listed as kind "${listedTheme.kind}"',
      );
    }
  }
  return null;
}

/// Every file the manifest signs for, byte for byte. Null when they all hold.
Future<OrbitPackCheck?> _checkFiles(
  OrbitPackManifest manifest,
  Map<String, List<int>> files,
  OrbitPackLimits limits,
) async {
  for (final path in files.keys) {
    if (!manifest.files.any((f) => f.path == path)) {
      return OrbitPackCheck.refused(
        OrbitPackFailure.changedFile,
        'the download carried "${_printable(path)}", which this pack does '
        'not list',
      );
    }
  }
  for (final f in manifest.files) {
    final bytes = files[f.path];
    if (bytes == null) {
      return OrbitPackCheck.refused(
        OrbitPackFailure.missingFile,
        'the download did not carry "${f.path}"',
      );
    }
    if (bytes.length > limits.fileBytes) {
      return OrbitPackCheck.refused(
        OrbitPackFailure.tooLarge,
        '"${f.path}" is bigger than a file may be',
      );
    }
    if (bytes.length != f.bytes) {
      return OrbitPackCheck.refused(
        OrbitPackFailure.changedFile,
        '"${f.path}" is ${bytes.length} bytes, the manifest says ${f.bytes}',
      );
    }
    final digest = await _sha256.hash(bytes);
    if (_hex(digest.bytes) != f.sha256) {
      return OrbitPackCheck.refused(
        OrbitPackFailure.changedFile,
        '"${f.path}" is not the file the publisher hashed',
      );
    }
  }
  return null;
}

/// The theme document, which is what the app is about to draw with. Null when
/// the pack is usable. Only a theme pack reaches this: a sound pack's one file
/// is checked by [_checkFiles] and played by the app.
OrbitPackCheck? _checkTheme(
  OrbitPackManifest manifest,
  Map<String, List<int>> files,
  Set<String> knownEffectKinds,
  Set<String> knownPatternKinds,
) {
  final Object? doc;
  try {
    doc = jsonDecode(utf8.decode(files[manifest.theme!]!));
  } on FormatException catch (e) {
    return OrbitPackCheck.refused(
      OrbitPackFailure.badTheme,
      'the theme document is not readable: ${e.message}',
    );
  }
  if (doc is! Map<String, Object?>) {
    return const OrbitPackCheck.refused(
      OrbitPackFailure.badTheme,
      'the theme document is not an object',
    );
  }
  if (doc['id'] != manifest.id) {
    return OrbitPackCheck.refused(
      OrbitPackFailure.themeMismatch,
      'the manifest is for "${manifest.id}" and its theme document calls '
      'itself something else',
    );
  }
  final effects = doc['effects'];
  if (effects != null) {
    if (effects is! List) {
      return const OrbitPackCheck.refused(
        OrbitPackFailure.badTheme,
        'effects is not a list',
      );
    }
    for (final e in effects) {
      if (e is! Map<String, Object?> || e['kind'] is! String) {
        return const OrbitPackCheck.refused(
          OrbitPackFailure.badTheme,
          'every effect needs a kind',
        );
      }
      final kind = e['kind']! as String;
      if (!knownEffectKinds.contains(kind)) {
        return OrbitPackCheck.refused(
          OrbitPackFailure.unknownEffect,
          'it switches on "${_printable(kind)}", an effect this build does '
          'not ship',
        );
      }
    }
  }
  final tokens = doc['tokens'];
  final group = tokens is Map<String, Object?> ? tokens['pattern'] : null;
  final pattern = group is Map<String, Object?> ? group['chat-pattern'] : null;
  final patternKind = pattern is Map<String, Object?> ? pattern['kind'] : null;
  if (patternKind is String && !knownPatternKinds.contains(patternKind)) {
    return OrbitPackCheck.refused(
      OrbitPackFailure.unknownPattern,
      'it asks for chat pattern "${_printable(patternKind)}", which this '
      'build does not ship',
    );
  }
  return null;
}

/// A name from outside this app, made safe to put in a log line: an identifier
/// is echoed as it is, anything else becomes a fixed word, so a pack cannot
/// quote itself into the client's logs.
String _printable(String name) =>
    _printableNamePattern.hasMatch(name) ? name : '(not an identifier)';

/// The publisher's key, or the refusal that there is no usable one.
({List<int>? root, OrbitPackCheck? refused}) _publisherRoot(
  OrbitPackManifest manifest,
  Map<String, List<int>> trustedPublishers,
) {
  final signature = manifest.signature;
  if (signature == null || signature.isEmpty) {
    return (
      root: null,
      refused: const OrbitPackCheck.refused(
        OrbitPackFailure.unsigned,
        'nothing signed this pack',
      ),
    );
  }
  final root = trustedPublishers[manifest.publisher];
  if (root == null || root.length != 32) {
    return (
      root: null,
      refused: OrbitPackCheck.refused(
        OrbitPackFailure.unknownPublisher,
        'this app has no key for publisher "${manifest.publisher}"',
      ),
    );
  }
  return (root: root, refused: null);
}

Future<bool> _signatureVerifies({
  required List<int> root,
  required List<int> message,
  required String signature,
}) async {
  final List<int> raw;
  try {
    raw = base64Decode(signature);
  } on FormatException {
    return false;
  }
  if (raw.length != 64) return false;
  try {
    return await _ed25519.verify(
      message,
      signature: Signature(
        _bytes(raw),
        publicKey: SimplePublicKey(_bytes(root), type: KeyPairType.ed25519),
      ),
    );
  } on Object {
    return false;
  }
}

final _ed25519 = Ed25519();
final _sha256 = Sha256();

/// `cryptography` keeps the bytes it was handed unless they are copied into a
/// fresh `Uint8List`; every list that reaches it here is the caller's.
Uint8List _bytes(List<int> b) => Uint8List.fromList(b);

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// JSON with every object's keys in code-unit order, no whitespace, and no
/// duplicate keys ([_canonical] refuses them rather than dropping one, since a
/// manifest with the same field twice has no single meaning).
String _canonicalJson(Object? value) {
  final out = StringBuffer();
  _write(out, value);
  return out.toString();
}

void _write(StringBuffer out, Object? value) {
  switch (value) {
    case null:
      out.write('null');
    case final bool b:
      out.write(b ? 'true' : 'false');
    case final num n:
      out.write('$n');
    case final String s:
      _writeString(out, s);
    case final List<Object?> items:
      out.write('[');
      for (var i = 0; i < items.length; i++) {
        if (i > 0) out.write(',');
        _write(out, items[i]);
      }
      out.write(']');
    case final Map<String, Object?> map:
      final keys = map.keys.toList()..sort();
      out.write('{');
      for (var i = 0; i < keys.length; i++) {
        if (i > 0) out.write(',');
        _writeString(out, keys[i]);
        out.write(':');
        _write(out, map[keys[i]]);
      }
      out.write('}');
    default:
      throw FormatException('cannot be signed', value);
  }
}

void _writeString(StringBuffer out, String s) {
  out.write('"');
  for (final unit in s.codeUnits) {
    switch (unit) {
      case 0x08:
        out.write(r'\b');
      case 0x09:
        out.write(r'\t');
      case 0x0A:
        out.write(r'\n');
      case 0x0C:
        out.write(r'\f');
      case 0x0D:
        out.write(r'\r');
      case 0x22:
        out.write(r'\"');
      case 0x5C:
        out.write(r'\\');
      case < 0x20:
        out.write('\\u${unit.toRadixString(16).padLeft(4, "0")}');
      default:
        out.writeCharCode(unit);
    }
  }
  out.write('"');
}

final RegExp _namePattern = RegExp(r'^[a-z0-9][a-z0-9._-]{0,63}$');
final RegExp _pathSegmentPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$');
final RegExp _printableNamePattern = RegExp(r'^[A-Za-z0-9._-]{1,64}$');

bool _isName(String s) =>
    s.length <= orbitPackNameMaxChars && _namePattern.hasMatch(s);

bool _isPath(String path, int maxChars) {
  if (path.isEmpty || path.length > maxChars) return false;
  if (path.startsWith('/') || path.endsWith('/')) return false;
  for (final segment in path.split('/')) {
    if (segment == '.' || segment == '..') return false;
    if (!_pathSegmentPattern.hasMatch(segment)) return false;
  }
  return true;
}

bool _isHexSha256(String s) {
  if (s.length != 64) return false;
  for (final unit in s.codeUnits) {
    final isDigit = unit >= 0x30 && unit <= 0x39;
    final isLowerHex = unit >= 0x61 && unit <= 0x66;
    if (!isDigit && !isLowerHex) return false;
  }
  return true;
}
