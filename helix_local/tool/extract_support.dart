import 'dart:io';

class ExtractionContext {
  ExtractionContext._({
    required this.repoRoot,
    required this.helixRoot,
    required this.outputRoot,
  });

  final String repoRoot;
  final String helixRoot;
  final String outputRoot;

  factory ExtractionContext.fromScript() {
    final toolDir = File.fromUri(Platform.script).parent.path;
    final repoRoot = Directory(toolDir).parent.path;
    final helixRoot = Directory(repoRoot).parent.path;
    return ExtractionContext._(
      repoRoot: repoRoot,
      helixRoot: helixRoot,
      outputRoot: joinPath(helixRoot, ['docs', 'codebase']),
    );
  }

  String repoPath(String relativePath) =>
      joinPath(repoRoot, relativePath.split('/'));
}

class ExtractSpec {
  const ExtractSpec({
    required this.id,
    required this.outputPath,
    required this.title,
    required this.subtitle,
    required this.collectFiles,
  });

  final String id;
  final String outputPath;
  final String title;
  final String subtitle;
  final List<String> Function(ExtractionContext context) collectFiles;
}

class ExtractResult {
  ExtractResult({
    required this.spec,
    required this.path,
    required this.fileCount,
    required this.bytes,
  });

  final ExtractSpec spec;
  final String path;
  final int fileCount;
  final int bytes;
}

class ExtractionException implements Exception {
  ExtractionException(this.message);

  final String message;

  @override
  String toString() => message;
}

void addFile(
  List<String> out,
  ExtractionContext context,
  String relativePath, {
  bool required = true,
}) {
  final file = File(context.repoPath(relativePath));
  if (file.existsSync()) {
    out.add(file.path);
    return;
  }
  if (required) {
    throw ExtractionException('Required file is missing: $relativePath');
  }
}

List<String> collectDir(
  ExtractionContext context,
  String relativePath, {
  List<String> exts = const ['.dart'],
  List<String> exclude = const [],
  bool required = true,
}) {
  final dir = Directory(context.repoPath(relativePath));
  if (!dir.existsSync()) {
    if (required) {
      throw ExtractionException('Required directory is missing: $relativePath');
    }
    return [];
  }

  final results = <String>[];
  for (final entity in dir.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final normalized = normalizePath(entity.path);
    if (!exts.any(normalized.endsWith)) continue;
    if (exclude.any(normalized.contains)) continue;
    results.add(entity.path);
  }
  results.sort(
    (a, b) => normalizePath(
      a,
    ).toLowerCase().compareTo(normalizePath(b).toLowerCase()),
  );
  return results;
}

List<String> directChildren(
  ExtractionContext context,
  String relativePath, {
  bool directories = true,
  bool files = true,
}) {
  final dir = Directory(context.repoPath(relativePath));
  if (!dir.existsSync()) return [];

  final results = <String>[];
  for (final entity in dir.listSync(followLinks: false)) {
    if (directories && entity is Directory) {
      results.add(relativeTo(entity.path, context.repoRoot));
    } else if (files && entity is File) {
      results.add(relativeTo(entity.path, context.repoRoot));
    }
  }
  results.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return results;
}

Future<ExtractResult> writeExtract(
  ExtractionContext context,
  ExtractSpec spec,
) async {
  final files = dedupeAndValidate(context, spec.collectFiles(context));
  if (files.isEmpty) {
    throw ExtractionException('Extractor produced no files: ${spec.id}');
  }

  const separator =
      '================================================================================';
  final generatedAt = DateTime.now().toIso8601String();
  final buffer = StringBuffer()
    ..writeln(separator)
    ..writeln(spec.title)
    ..writeln(spec.subtitle)
    ..writeln('Generated: $generatedAt')
    ..writeln('Repository: ${normalizePath(context.repoRoot)}')
    ..writeln('Files: ${files.length}')
    ..writeln(separator)
    ..writeln()
    ..writeln('INDEX:');

  String? currentBucket;
  for (var i = 0; i < files.length; i++) {
    final rel = relativeTo(files[i], context.repoRoot);
    final bucket = indexBucket(rel);
    if (bucket != currentBucket) {
      currentBucket = bucket;
      buffer.writeln();
      buffer.writeln('  $bucket');
    }
    buffer.writeln('    [${number(i)}] $rel');
  }

  for (var i = 0; i < files.length; i++) {
    final rel = relativeTo(files[i], context.repoRoot);
    buffer
      ..writeln()
      ..writeln(separator)
      ..writeln('FILE [${number(i)}]: $rel')
      ..writeln(separator);
    final content = File(files[i]).readAsStringSync();
    buffer.write(content);
    if (!content.endsWith('\n')) buffer.writeln();
  }

  final out = File(joinPath(context.outputRoot, spec.outputPath.split('/')));
  await out.parent.create(recursive: true);
  await out.writeAsString(buffer.toString());
  return ExtractResult(
    spec: spec,
    path: out.path,
    fileCount: files.length,
    bytes: await out.length(),
  );
}

Future<void> writeManifest({
  required ExtractionContext context,
  required String scope,
}) async {
  final uploadDir = Directory(joinPath(context.outputRoot, [scope]));
  await uploadDir.create(recursive: true);
  final manifest = File(joinPath(uploadDir.path, ['00_UPLOAD_INDEX.md']));
  final generatedAt = DateTime.now().toIso8601String();
  final uploadFiles =
      uploadDir
          .listSync(followLinks: false)
          .whereType<File>()
          .where(
            (file) => file.path
                .replaceAll('\\', '/')
                .split('/')
                .last
                .endsWith('.txt'),
          )
          .toList()
        ..sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));
  final uploadCount = uploadFiles.length + 1;
  if (uploadCount > 15) {
    throw ExtractionException(
      'Upload folder contains $uploadCount files; the limit is 15. Remove stale files from ${normalizePath(uploadDir.path)}.',
    );
  }

  final buffer = StringBuffer()
    ..writeln('# Helix Agent Upload Extracts')
    ..writeln()
    ..writeln('Generated: $generatedAt')
    ..writeln('Folder: ${normalizePath(uploadDir.path)}')
    ..writeln('Upload files: $uploadCount including this index')
    ..writeln()
    ..writeln('| File | Size |')
    ..writeln('| --- | ---: |')
    ..writeln('| 00_UPLOAD_INDEX.md | index |');

  for (final file in uploadFiles) {
    final name = file.path.replaceAll('\\', '/').split('/').last;
    buffer.writeln('| $name | ${formatBytes(file.lengthSync())} |');
  }

  buffer
    ..writeln()
    ..writeln('Compact codebase tree:')
    ..writeln()
    ..writeln('```text');
  writeWorkspaceTree(buffer, context.helixRoot);
  buffer
    ..writeln('```')
    ..writeln()
    ..writeln('Commands:')
    ..writeln()
    ..writeln('- `dart run tool/extract_all.dart` regenerates every segment.')
    ..writeln('- `dart run tool/extract_all.dart --list` lists segment ids.')
    ..writeln(
      '- `dart run tool/extract_all.dart --only <segment_id>` regenerates one segment.',
    );

  await manifest.writeAsString(buffer.toString());
}

void writeWorkspaceTree(StringBuffer buffer, String helixRoot) {
  for (final project in ['helix_local', 'helix_remote']) {
    final root = Directory(joinPath(helixRoot, [project]));
    if (!root.existsSync()) continue;

    buffer.writeln('$project/');
    writeExistingFiles(buffer, root, ['pubspec.yaml', 'analysis_options.yaml']);
    writeTreeSection(buffer, root, 'app/lib');
    writeTreeSection(buffer, root, 'admin/lib');
    writeTreeSection(buffer, root, 'backend/bin');
    writeTreeSection(buffer, root, 'backend/lib/src');
    writeTreeSection(buffer, root, 'backend/lib/src/modules');
    writeTreeSection(buffer, root, 'contracts');
    writeTreeSection(buffer, root, 'packages');
    buffer.writeln();
  }
}

void writeExistingFiles(
  StringBuffer buffer,
  Directory root,
  List<String> files,
) {
  for (final file in files) {
    if (File(joinPath(root.path, file.split('/'))).existsSync()) {
      buffer.writeln('  $file');
    }
  }
}

void writeTreeSection(
  StringBuffer buffer,
  Directory root,
  String relativePath,
) {
  final dir = Directory(joinPath(root.path, relativePath.split('/')));
  if (!dir.existsSync()) return;

  buffer.writeln('  $relativePath/');
  final children =
      dir
          .listSync(followLinks: false)
          .where(
            (entity) => !entity.path
                .replaceAll('\\', '/')
                .split('/')
                .last
                .startsWith('.'),
          )
          .toList()
        ..sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));

  for (final child in children) {
    final name = child.path.replaceAll('\\', '/').split('/').last;
    if (child is Directory) {
      buffer.writeln('    $name/');
    } else if (child is File && isTreeFile(name)) {
      buffer.writeln('    $name');
    }
  }
}

bool isTreeFile(String name) {
  return name.endsWith('.dart') ||
      name.endsWith('.md') ||
      name.endsWith('.yaml') ||
      name.endsWith('.json');
}

Future<void> runExtractionCli({
  required List<String> args,
  required String scope,
  required List<ExtractSpec> specs,
}) async {
  if (args.contains('--list') || args.contains('-l')) {
    stdout.writeln('Available $scope extract segments:');
    for (final spec in specs) {
      stdout.writeln('  ${spec.id.padRight(32)} ${spec.outputPath}');
    }
    return;
  }

  final filters = <String>[];
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '--only' || arg == '--segment') {
      if (i + 1 >= args.length) {
        throw ExtractionException('$arg requires a segment id');
      }
      filters.addAll(
        args[++i]
            .split(',')
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty),
      );
    } else if (arg.startsWith('-')) {
      throw ExtractionException('Unknown option: $arg');
    } else {
      filters.add(arg);
    }
  }

  final selected = filters.isEmpty
      ? specs
      : specs
            .where((spec) => filters.any((filter) => matchesSpec(spec, filter)))
            .toList();
  if (selected.isEmpty) {
    throw ExtractionException(
      'No extract segments matched: ${filters.join(', ')}',
    );
  }

  final context = ExtractionContext.fromScript();
  for (final spec in selected) {
    stdout.writeln('');
    stdout.writeln('== ${spec.id} ==');
    final result = await writeExtract(context, spec);
    stdout.writeln(
      'OK  ${spec.outputPath} (${formatBytes(result.bytes)}, ${result.fileCount} files)',
    );
  }

  await writeManifest(context: context, scope: scope);
  stdout.writeln('');
  stdout.writeln(
    'Done. Extracts written under ${joinPath(context.outputRoot, [scope])}',
  );
}

bool matchesSpec(ExtractSpec spec, String filter) {
  final normalized = filter.toLowerCase();
  return spec.id.toLowerCase() == normalized ||
      spec.outputPath.toLowerCase() == normalized ||
      spec.outputPath.toLowerCase().replaceAll('.txt', '') == normalized;
}

List<String> dedupeAndValidate(ExtractionContext context, List<String> files) {
  final root = normalizePath(context.repoRoot).toLowerCase();
  final seen = <String>{};
  final results = <String>[];
  for (final file in files) {
    final normalized = normalizePath(File(file).absolute.path);
    final lower = normalized.toLowerCase();
    if (!lower.startsWith('$root/')) {
      throw ExtractionException(
        'Refusing to extract file outside repo root: $normalized',
      );
    }
    if (seen.add(lower)) results.add(file);
  }
  return results;
}

String relativeTo(String path, String root) {
  final normalizedPath = normalizePath(File(path).absolute.path);
  final normalizedRoot = normalizePath(Directory(root).absolute.path);
  final prefix = '$normalizedRoot/';
  if (normalizedPath.toLowerCase().startsWith(prefix.toLowerCase())) {
    return normalizedPath.substring(prefix.length);
  }
  return normalizedPath;
}

String indexBucket(String relativePath) {
  final parts = relativePath.split('/');
  if (parts.length >= 2 && parts[0] == 'packages') {
    return 'packages/${parts[1]}';
  }
  if (parts.length >= 5 && parts[0] == 'backend' && parts[3] == 'modules') {
    final module = parts[4].endsWith('.dart')
        ? parts[4].replaceAll('.dart', '')
        : parts[4];
    return 'backend/lib/src/modules/$module';
  }
  if (parts.length >= 3 &&
      (parts[0] == 'app' || parts[0] == 'admin') &&
      parts[1] == 'lib') {
    return '${parts[0]}/lib/${parts[2]}';
  }
  return parts.first;
}

String joinPath(String base, Iterable<String> parts) {
  var current = base;
  for (final part in parts) {
    if (part.isEmpty) continue;
    current = '$current${Platform.pathSeparator}$part';
  }
  return current;
}

String normalizePath(String path) => path.replaceAll('\\', '/');

String number(int i) => (i + 1).toString().padLeft(3, '0');

String formatBytes(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '$bytes B';
}
