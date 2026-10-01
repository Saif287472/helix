import 'package:helix_remote_architecture_rules/src/source_scanner.dart';

/// One broken rule: a directive in [file] at [line] that points at [uri].
final class Violation {
  const Violation({
    required this.rule,
    required this.file,
    required this.line,
    required this.uri,
    required this.message,
  });

  final String rule;
  final String file;
  final int line;
  final String uri;
  final String message;

  @override
  String toString() => '[$rule] $file:$line -> $uri: $message';
}

/// A boundary check over a set of scanned files.
abstract interface class ArchitectureRule {
  String get name;

  Iterable<Violation> check(List<SourceFile> files);
}

/// Runs every rule over [files] and returns all violations.
List<Violation> checkAll(List<SourceFile> files, List<ArchitectureRule> rules) {
  return [for (final rule in rules) ...rule.check(files)];
}

/// A readable report for a test failure message.
String describeViolations(List<Violation> violations) {
  if (violations.isEmpty) return 'No architecture violations.';
  return [
    '${violations.length} architecture violation(s):',
    for (final v in violations) '  $v',
  ].join('\n');
}

/// Matches URIs that point into any of [packages] (`package:<name>/...`).
bool Function(String uri) anyPackage(Iterable<String> packages) {
  final names = packages.toSet();
  return (uri) {
    final package = packageOfUri(uri);
    return package != null && names.contains(package);
  };
}

/// Files matching [appliesTo] (all files when null) must not refer to a URI
/// for which [forbidden] returns true.
final class ForbiddenDirectiveRule implements ArchitectureRule {
  ForbiddenDirectiveRule({
    required this.name,
    required this.reason,
    required this.forbidden,
    this.appliesTo,
  });

  @override
  final String name;

  /// Shown with each violation; say what to do instead.
  final String reason;
  final bool Function(String uri) forbidden;
  final bool Function(String path)? appliesTo;

  @override
  Iterable<Violation> check(List<SourceFile> files) sync* {
    for (final file in files) {
      if (!(appliesTo?.call(file.path) ?? true)) continue;
      for (final directive in file.directives) {
        if (!forbidden(directive.uri)) continue;
        yield Violation(
          rule: name,
          file: file.path,
          line: directive.line,
          uri: directive.uri,
          message: reason,
        );
      }
    }
  }
}

/// Internal packages that exist only to test other packages. They may be
/// imported from `test/`, never from `lib/` or `bin/`.
const Set<String> testOnlyPackages = {'helix_remote_architecture_rules'};

/// Dependency direction between workspace packages.
///
/// Code in [selfPackage] may refer to another *internal* package (one for
/// which [isInternal] is true) only if it is in [allowed], or if it is in
/// [testOnly] and the importing file is under `test/`. Third-party packages
/// and `dart:` libraries are not governed here; pubspec review covers them.
final class InternalDependencyRule implements ArchitectureRule {
  InternalDependencyRule({
    required this.selfPackage,
    required this.allowed,
    this.testOnly = testOnlyPackages,
    bool Function(String package)? isInternal,
  }) : isInternal = isInternal ?? isHelixRemotePackage;

  final String selfPackage;
  final Set<String> allowed;
  final Set<String> testOnly;
  final bool Function(String package) isInternal;

  @override
  String get name => 'dependency-direction:$selfPackage';

  @override
  Iterable<Violation> check(List<SourceFile> files) sync* {
    for (final file in files) {
      for (final directive in file.directives) {
        final package = packageOfUri(directive.uri);
        if (package == null || package == 'dart' || package == selfPackage) {
          continue;
        }
        if (!isInternal(package) || allowed.contains(package)) continue;
        if (testOnly.contains(package) && file.path.startsWith('test/')) {
          continue;
        }
        yield Violation(
          rule: name,
          file: file.path,
          line: directive.line,
          uri: directive.uri,
          message:
              '$selfPackage may depend on ${_list(allowed)} only '
              '(ARCHITECTURE_V2_PLAN.md §6.1).',
        );
      }
    }
  }

  static String _list(Set<String> names) => names.isEmpty
      ? 'no internal packages'
      : (names.toList()..sort()).join(', ');
}

/// True for Helix Remote workspace packages (`helix_remote_*`).
bool isHelixRemotePackage(String package) =>
    package.startsWith('helix_remote_');

/// Server module boundary (ADR-026).
///
/// A file inside `<modulesDir>/<module>/` may refer to another module only
/// through that module's `api.dart`. Files outside any module (platform,
/// kernel, the composition in `server.dart`) are not restricted by this
/// rule.
final class ModuleBoundaryRule implements ArchitectureRule {
  ModuleBoundaryRule({
    required this.packageName,
    this.modulesDir = 'lib/src/modules',
  });

  final String packageName;
  final String modulesDir;

  @override
  String get name => 'module-boundary';

  String? _moduleOf(String path) {
    final prefix = '$modulesDir/';
    if (!path.startsWith(prefix)) return null;
    final rest = path.substring(prefix.length);
    final slash = rest.indexOf('/');
    return slash < 0 ? null : rest.substring(0, slash);
  }

  @override
  Iterable<Violation> check(List<SourceFile> files) sync* {
    for (final file in files) {
      final from = _moduleOf(file.path);
      if (from == null) continue;
      for (final directive in file.directives) {
        final target = file.resolveInPackage(
          directive.uri,
          packageName: packageName,
        );
        if (target == null) continue;
        final to = _moduleOf(target);
        if (to == null || to == from) continue;
        if (target == '$modulesDir/$to/api.dart') continue;
        yield Violation(
          rule: name,
          file: file.path,
          line: directive.line,
          uri: directive.uri,
          message:
              'module "$from" may use module "$to" only through '
              '$modulesDir/$to/api.dart (ADR-026).',
        );
      }
    }
  }
}
