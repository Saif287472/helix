import 'package:flutter/widgets.dart';
import 'package:orbit_ui/orbit_ui.dart';

/// The screen keys that have a Flutter screen, and how to build each on fake
/// data.
///
/// The keys are the prototype's (`prototype/screens.json`). A key not listed
/// here is not ported yet, and the preview says so rather than drawing a
/// stand-in.
final Map<String, WidgetBuilder> orbitPorted = <String, WidgetBuilder>{
  'startup': (context) => const OrbitStartup(),
};

/// The six pack themes' font families, which this app declares in its own
/// `pubspec.yaml` the way a downloaded theme pack will bring them.
const orbitPreviewPackFonts = <String>[
  'DM Sans',
  'DM Mono',
  'Fraunces',
  'Nunito',
  'EB Garamond',
  'Cinzel',
  'Rajdhani',
  'Exo 2',
  'Share Tech Mono',
  'JetBrains Mono',
  'Black Ops One',
  'Barlow',
];
