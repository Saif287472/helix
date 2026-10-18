import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:orbit_ui/orbit_ui.dart';

/// The eight built-in themes, loaded from their JSON files.
///
/// This is the whole of Part A's theme loading: the app asks for a theme by id
/// and gets tokens back, and nothing anywhere knows what "Orbit" looks like.
/// A downloaded theme pack (Part C) will be loaded the same way, from a file
/// rather than the bundle.
///
/// The ids and the order are the theme table's (`themes.py`), written here
/// because a Dart const list is cheaper than reading a directory listing, and a
/// missing file must be a loud failure rather than a theme that silently
/// disappears.
final class OrbitThemeLibrary {
  OrbitThemeLibrary._(this._byId, this.themes);

  /// The ids `tools/gen_orbit_tokens.py`'s themes come from, Orbit first.
  static const ids = <String>[
    'orbit',
    'night',
    'bloom',
    'mochi',
    'papyrus',
    'arcade',
    'terminal',
    'field',
  ];

  /// Loads every theme, or throws naming the first that would not load.
  ///
  /// A theme that half-loads must not become a theme that looks deliberate.
  static Future<OrbitThemeLibrary> load() async {
    final themes = <OrbitTokens>[];
    for (final id in ids) {
      // The JSON is orbit_ui's asset, so from an app it is under the package.
      final raw = await rootBundle.loadString(
        'packages/orbit_ui/assets/themes/$id.json',
      );
      themes.add(
        OrbitTokens.fromThemeJson(jsonDecode(raw) as Map<String, Object?>),
      );
    }
    return OrbitThemeLibrary._({for (final t in themes) t.meta.id: t}, themes);
  }

  final Map<String, OrbitTokens> _byId;

  /// The themes, in [ids] order: Orbit first, then Night, Bloom, Mochi, Papyrus,
  /// Arcade, Terminal, Field.
  final List<OrbitTokens> themes;

  /// The theme [id], or throws listing the ids it does have.
  OrbitTokens byId(String id) {
    final found = _byId[id];
    if (found == null) {
      throw ArgumentError.value(
        id,
        'id',
        'not a built-in theme; have ${_byId.keys.toList()}',
      );
    }
    return found;
  }
}

/// The four colours a theme's chip is drawn from.
///
/// The same four the generator writes as `swatches` for the HTML viewer's theme
/// list: the background, the accent, this account's own bubble and the second
/// colour. They are read from the tokens rather than kept here, so a theme
/// pack brings its own.
extension OrbitThemePalette on OrbitTokens {
  List<Color> get palette => <Color>[
    value<Color>('bg'),
    value<Color>('accent'),
    value<Color>('out'),
    value<Color>('cyan'),
  ];
}
