/// Maps module names to Postgres schema names.
///
/// Production uses the module names themselves (`identity`, `messaging`).
/// Tests use a random [prefix] per test file (`t3k9x2_identity`), so suites
/// can share one database, run in parallel and clean up by dropping every
/// schema with the prefix. Because SQL interpolates these names, they are
/// validated identifiers and never come from request data.
final class SchemaNames {
  SchemaNames({this.prefix = ''}) {
    if (prefix.isNotEmpty && !_identifier.hasMatch(prefix)) {
      throw ArgumentError.value(prefix, 'prefix', 'must be [a-z0-9_]');
    }
  }

  static final RegExp _identifier = RegExp(r'^[a-z][a-z0-9_]*$');

  final String prefix;

  /// The schema of [module] (also validated).
  String of(String module) {
    if (!_identifier.hasMatch(module)) {
      throw ArgumentError.value(module, 'module', 'must be [a-z0-9_]');
    }
    return '$prefix$module';
  }

  /// The platform's own schema (migrations, outbox, rate limits, ...).
  String get platform => of('platform');
}
