import 'package:meta/meta.dart';

@immutable
abstract class ProductDescriptor {
  const ProductDescriptor();

  String get productId;
  String get displayName;
  String get packageId;
  String get appDataFolder;
  String get databaseFilename;
  String get secureStoragePrefix;
  String get notificationNamespace;
  String get urlScheme;
  String get methodChannelNamespace;
  String get logNamespace;
  String get exportPrefix;
  String get protocolLabel;
  String get windowsNotificationGuid;
}

class LocalProductDescriptor extends ProductDescriptor {
  const LocalProductDescriptor();

  @override
  String get productId => 'local';

  @override
  String get displayName => 'Helix Local';

  @override
  String get packageId => 'com.helix.local';

  @override
  String get appDataFolder => 'com.helix/helix';

  @override
  String get databaseFilename => 'helix_local.db';

  @override
  String get secureStoragePrefix => 'helix_local_v1_';

  @override
  String get notificationNamespace => 'com.helix.local.notification';

  @override
  String get urlScheme => 'helixlocal';

  @override
  String get methodChannelNamespace => 'com.helix.local';

  @override
  String get logNamespace => 'helix_local';

  @override
  String get exportPrefix => 'helix_local_export';

  @override
  String get protocolLabel => 'helix-local-protocol';

  @override
  String get windowsNotificationGuid => '17b09742-cd2c-45d4-b0fe-52814bfd70ae';
}

class RemoteProductDescriptor extends ProductDescriptor {
  const RemoteProductDescriptor();

  @override
  String get productId => 'remote';

  @override
  String get displayName => 'Helix Remote';

  @override
  String get packageId => 'com.helix.remote';

  @override
  String get appDataFolder => 'com.helix/helix_remote';

  @override
  String get databaseFilename => 'helix_remote.db';

  @override
  String get secureStoragePrefix => 'helix_remote_v1_';

  @override
  String get notificationNamespace => 'com.helix.remote.notification';

  @override
  String get urlScheme => 'helixremote';

  @override
  String get methodChannelNamespace => 'com.helix.remote';

  @override
  String get logNamespace => 'helix_remote';

  @override
  String get exportPrefix => 'helix_remote_export';

  @override
  String get protocolLabel => 'helix-remote-protocol';

  @override
  String get windowsNotificationGuid => '27b09742-cd2c-45d4-b0fe-52814bfd70af';
}

/// Returns true only when [path] is a descendant of [descriptor]'s appDataFolder,
/// using proper directory-component matching after normalizing separators and
/// resolving `..` segments.
///
/// Design rationale:
/// - Substring checks (e.g. `contains('helix_local')`) incorrectly accept paths
///   like `Documents/helix_local_anomaly_log.txt` that share a prefix with the
///   product namespace but live outside the approved root.
/// - We require the appDataFolder to appear as a complete path component bounded
///   by `/` separators, preventing sibling-directory or prefix collisions.
/// - `..` segments are resolved before matching so traversal tricks cannot escape
///   the approved root and re-enter via a different route.
/// - Relative paths are rejected outright; only absolute paths are permitted.
///
/// Platform limitation: this function works on the string representation of the
/// path only.  Symlinks and Windows reparse points are not followed; callers that
/// operate on real files should additionally use dart:io `File.resolveSymbolicLinksSync`
/// before passing the path here.
bool isPathInScopeForDestructiveOperation(
  String path,
  ProductDescriptor descriptor,
) {
  final candidate = _normalizeScopePath(path);

  // Reject relative paths — a traversal attack outside the approved root would
  // resolve to a path that no longer starts with a drive letter or '/'.
  final isAbsolute =
      candidate.startsWith('/') || RegExp(r'^[a-z]:').hasMatch(candidate);
  if (!isAbsolute) return false;

  final approvedFolder = descriptor.appDataFolder
      .replaceAll('\\', '/')
      .toLowerCase();

  // The appDataFolder must appear as a complete directory component — bounded by
  // '/' on both sides, or by '/' on the left and end-of-string on the right.
  // This prevents "helix_remote" from matching "helix", etc.
  final insideFolder = candidate.contains('/$approvedFolder/');
  final atFolderEnd = candidate.endsWith('/$approvedFolder');

  if (!insideFolder && !atFolderEnd) return false;

  // Reject paths that also contain the other product's appDataFolder — a crafted
  // path that visits both products' directories must never be approved.
  final otherFolder =
      (descriptor.productId == 'local'
              ? const RemoteProductDescriptor()
              : const LocalProductDescriptor())
          .appDataFolder
          .replaceAll('\\', '/')
          .toLowerCase();

  if (candidate.contains('/$otherFolder/') ||
      candidate.endsWith('/$otherFolder')) {
    return false;
  }

  return true;
}

/// Normalizes a filesystem path for scope comparison:
/// - Converts backslashes to forward slashes.
/// - Lowercases all characters (case-insensitive comparison).
/// - Resolves `.` and `..` segments.
/// - Preserves a leading `/` for Unix absolute paths.
String _normalizeScopePath(String path) {
  final withSlashes = path.replaceAll('\\', '/').toLowerCase();
  final startsWithSlash = withSlashes.startsWith('/');

  final parts = <String>[];
  for (final segment in withSlashes.split('/')) {
    if (segment.isEmpty || segment == '.') continue;
    if (segment == '..') {
      if (parts.isNotEmpty) parts.removeLast();
      continue;
    }
    parts.add(segment);
  }

  final joined = parts.join('/');
  return startsWithSlash ? '/$joined' : joined;
}
