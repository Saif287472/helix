/// Import-boundary rules for Helix Remote v2 (ADR-029).
///
/// Each v2 package and the v2 server has an `architecture_test.dart` that
/// scans its own sources with [scanDartSources] and checks them with
/// [checkAll] against the rules for its layer, usually [v2PackageRules] plus
/// layer-specific ones.
library;

export 'src/rules.dart';
export 'src/source_scanner.dart';
export 'src/v2_layers.dart';
