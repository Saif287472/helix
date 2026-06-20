import 'package:helix_remote_backend/src/repositories.dart';

final class PostgreSqlBackendAdapter {
  const PostgreSqlBackendAdapter({
    required this.connectionString,
    required this.repositories,
  });

  final String connectionString;
  final SqliteBackendRepositories repositories;

  Never open() {
    throw UnsupportedError(
      'PostgreSQL production adapter is gated behind repository parity tests. '
      'Use SqliteBackendRepositories for development and tests until parity is green.',
    );
  }
}
