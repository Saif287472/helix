/// The fixed registry of theme effects.
///
/// A theme switches an effect on **by name** with settings; the app ships the
/// effect *types*. That split is deliberate and is what makes downloadable
/// theme packs safe (Part C): a pack is data, so it can turn on effects that
/// already exist and nothing else. A pack cannot bring an effect the app has
/// never heard of, because a release Flutter build could not load new code
/// anyway - so a name that is not here is refused at load time rather than
/// quietly ignored.
///
/// The names and their parameters are the ones the theme table records
/// (`orbit/prototype/tools/themes.py` writes them into each theme's JSON).
/// Which parts of a screen each one paints is Phase 3, when the components
/// exist to paint on.
library;

/// What each effect does, and where the prototype draws it.
///
/// The wording is the prototype's: `orbit/prototype/css/themes.css` is where
/// every one of these was a raw rule before it became a record.
enum OrbitEffectKind {
  /// A drop shadow on the "Orbit" wordmark. Arcade, Terminal.
  wordmarkGlow('a drop shadow on the wordmark'),

  /// A shadow on each kind of message bubble. Arcade.
  bubbleGlow('a shadow on incoming and outgoing bubbles'),

  /// A coloured stripe down the edge of a bubble. Field.
  bubbleStripe('a stripe down the edge of a bubble'),

  /// A blinking glyph after the wordmark. Terminal.
  cursor('a blinking glyph after the wordmark'),

  /// A glyph beside a date or a group title. Mochi, Papyrus, Terminal, Field.
  ornament('a glyph beside a date or a group title'),

  /// An inset double rule around a card. Papyrus.
  cardRing('an inset double rule on a card'),

  /// A notched corner, and square radii with it. Arcade.
  cornerClip('a notched corner'),

  /// An italic wordmark. Bloom.
  wordmarkItalic('an italic wordmark'),

  /// A different face and size for the date separators. Bloom.
  dayLabel('another face and size for the dates'),

  /// A bolder bubble. Mochi.
  bubbleWeight('a bolder bubble'),

  /// A border on the dock. Mochi.
  dockBorder('a border on the dock'),

  /// The chat pattern behind a page, not only the timeline. Papyrus.
  pagePattern('the chat pattern behind a page'),

  /// The theme's own root size, which its CSS sets on the phone screen. Papyrus.
  baseFontSize('the theme root size'),

  /// The colour of eyebrows and dates. Arcade.
  eyebrowColour('the colour of eyebrows and dates');

  const OrbitEffectKind(this.paints);

  /// One line saying what it draws, for the docs and the gallery.
  final String paints;
}

/// The chat patterns a theme can choose, and what each one draws.
///
/// This is deliberately **not** every pattern the viewer can show: "Dot grid"
/// and "Orbit lines" are preview affordances (`body.bg-dots` in the prototype),
/// not theme data, so no theme and no pack can select them.
enum OrbitPatternKind {
  /// The chat background is plain: `--chat-bg`.
  none('a plain chat background'),

  /// Tiled fractal noise. Bloom and Papyrus.
  grain('tiled grain'),

  /// Tiled marks. Mochi.
  hearts('tiled hearts and sparkles'),

  /// One hairline each way per cell. Arcade.
  neonGrid('a neon grid'),

  /// A repeating line, period built in, no tile. Terminal.
  scanlines('scanlines'),

  /// Five stroked curves. Field.
  contours('contour lines');

  const OrbitPatternKind(this.looks);

  /// One line saying what it looks like, for the gallery.
  final String looks;

  bool get isNone => this == OrbitPatternKind.none;
}

/// The registry itself: the names a theme may use.
abstract final class OrbitEffects {
  /// Every effect the app ships.
  static const kinds = OrbitEffectKind.values;

  /// Every chat pattern the app ships.
  static const patterns = OrbitPatternKind.values;

  static final _byName = {for (final k in kinds) k.name: k};
  static final _patternByName = {for (final p in patterns) p.name: p};

  /// The effect [name], or null when the app has no such effect.
  ///
  /// A theme naming something else is not a theme this app can draw: the pack
  /// format carries data, and the effect types live in the app.
  static OrbitEffectKind? byName(String? name) => _byName[name];

  static OrbitPatternKind? patternByName(String? name) =>
      _patternByName[name];

  /// Throws when the theme asks for an effect or pattern this build has not
  /// got, naming both, so the failure says which pack or generator is wrong.
  static void validate(String theme, Iterable<String> effectNames,
      String? pattern) {
    for (final name in effectNames) {
      if (_byName[name] == null) {
        throw FormatException(
          'theme "$theme" switches on effect "$name", which this build does '
          'not ship. Only data is ever downloaded, so a theme cannot bring an '
          'effect type.',
        );
      }
    }
    if (pattern != null && _patternByName[pattern] == null) {
      throw FormatException(
        'theme "$theme" asks for chat pattern "$pattern", which this build '
        'does not ship.',
      );
    }
  }
}