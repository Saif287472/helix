import 'dart:convert';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orbit_ui/orbit_ui.dart';

/// The Orbit theme the app draws with (orbit/PORT_PLAN.md, Part B).
///
/// The default Orbit theme only, for now: the other built-in themes come in
/// a later app upgrade. [main] loads it before the first frame and overrides
/// this provider, so every screen gets its tokens synchronously.
final orbitTokensProvider = Provider<OrbitTokens>(
  (ref) => throw StateError(
    'The Orbit theme is loaded in main() and passed as an override.',
  ),
);

/// Reads a built-in theme from `orbit_ui`'s assets.
Future<OrbitTokens> loadOrbitTokens({
  AssetBundle? bundle,
  String id = 'orbit',
}) async {
  final raw = await (bundle ?? rootBundle).loadString(
    'packages/orbit_ui/assets/themes/$id.json',
  );
  return OrbitTokens.fromThemeJson(jsonDecode(raw) as Map<String, Object?>);
}
