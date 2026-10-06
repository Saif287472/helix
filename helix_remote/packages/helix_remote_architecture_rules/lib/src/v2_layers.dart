import 'package:helix_remote_architecture_rules/src/rules.dart';

/// Allowed dependencies between v2 workspace packages
/// (ARCHITECTURE_V2_PLAN.md §6.1). A package may import only the internal
/// packages listed for it. Third-party dependencies are reviewed through
/// pubspec changes and the dependency risk register, not here.
///
/// A package joins this map in the phase that creates it. The app is not
/// listed: it may use every v2 package, and its presentation layer has its
/// own, stricter rule.
const Map<String, Set<String>> v2PackageDependencies = {
  'helix_remote_domain': {},
  'helix_remote_protocol': {'helix_remote_domain'},
  'helix_remote_crypto': {'helix_remote_domain', 'helix_remote_protocol'},
  'helix_remote_api': {'helix_remote_domain', 'helix_remote_protocol'},
  'helix_remote_db': {'helix_remote_domain', 'helix_remote_protocol'},
  'helix_remote_engine': {
    'helix_remote_domain',
    'helix_remote_protocol',
    'helix_remote_crypto',
    'helix_remote_api',
    'helix_remote_db',
  },
  'helix_remote_calls': {'helix_remote_domain', 'helix_remote_protocol'},
  'helix_remote_ui': {},
  'helix_remote_server': {'helix_remote_protocol'},
};

/// v1 packages that no v2 code may import. They were deleted at Phase X; the
/// rule keeps them from coming back.
const Set<String> v1RetiredPackages = {
  'helix_remote_backend',
  'helix_remote_storage',
  'helix_remote_sync',
  'helix_remote_groups',
};

/// The rules every v2 package applies to itself: dependency direction from
/// [v2PackageDependencies] and no imports of [v1RetiredPackages].
List<ArchitectureRule> v2PackageRules(String selfPackage) {
  final allowed = v2PackageDependencies[selfPackage];
  if (allowed == null) {
    throw ArgumentError.value(
      selfPackage,
      'selfPackage',
      'is not a v2 package; add it to v2PackageDependencies first',
    );
  }
  return [
    InternalDependencyRule(selfPackage: selfPackage, allowed: allowed),
    ForbiddenDirectiveRule(
      name: 'no-v1-packages',
      reason:
          'v1 packages were retired at Phase X; v2 code must not depend on '
          'them (ADR-029).',
      forbidden: anyPackage(v1RetiredPackages),
    ),
  ];
}
