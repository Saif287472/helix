/// A theme's motion: how long a change takes, and the curve it takes on.
///
/// Motion is theme data like everything else, so a downloadable pack (Part C)
/// can ship its own timings. There is no per-theme constant in Dart: the
/// prototype keeps one global set - `--dur: 180ms`, `--dur-page: 260ms` and
/// `--ease: cubic-bezier(0.2, 0.7, 0.2, 1)` in `css/tokens.css` - and
/// `orbit/prototype/tools/themes.py` writes those values into every theme's
/// JSON. This reads them back.
///
/// It is deliberately **not** a group inside the theme's `tokens`. Those are
/// the custom properties `css/themes.css` defines, one flat value each with a
/// generated getter; motion is none of them. It sits beside `tokens` and
/// `effects` in the document instead, because it is a record with its own
/// Dart type rather than a value the generated extension can name.
///
/// Reduce motion is not data either. It is the platform's setting, so it
/// belongs to the app and not to a theme pack - see [OrbitMotion.allowed].
library;

import 'package:flutter/widgets.dart';

/// How long this theme's changes take, and the curve they ease on.
///
/// The prototype uses two durations and one curve, and every one of the eight
/// themes shares them, because that is the design as it stands. Two of the
/// three are per-*screen* decisions rather than per-theme ones - `--dur` for a
/// control or a colour, `--dur-page` for a page, a sheet or a pager - so a
/// theme that picked different timings would change how the product feels,
/// not how it looks. That is the owner's decision, not a default.
final class OrbitMotion {
  const OrbitMotion._({
    required this.short,
    required this.page,
    required this.curve,
    required this.controlPoints,
  });

  /// Reads the `motion` record of one theme JSON document - the same document
  /// `OrbitTokens.fromThemeJson` reads.
  ///
  /// Throws [FormatException] on a duration that is not a number of seconds or
  /// a curve that is not a `cubic-bezier`, rather than falling back to a
  /// default. A theme whose timing silently filled in would animate at a speed
  /// nobody chose, and every screenshot would still look fine.
  factory OrbitMotion.fromThemeJson(Map<String, Object?> json) {
    final raw = json['motion'];
    if (raw is! Map<Object?, Object?>) {
      throw FormatException('a theme has no "motion"', json.toString());
    }
    final durations = raw['duration'];
    if (durations is! Map<Object?, Object?>) {
      throw FormatException('motion has no "duration"', '$raw');
    }
    final curve = raw['curve'];
    if (curve is! List<Object?> || curve.length != 4) {
      throw FormatException('motion curve is not a cubic-bezier', '$curve');
    }

    final points = <double>[
      for (final p in curve)
        if (p is num)
          p.toDouble()
        else
          throw FormatException('a curve point is not a number', '$p'),
    ];
    // The first and third control points are the x coordinates, and a
    // `cubic-bezier` whose x leaves 0..1 is not a function of time. CSS
    // refuses such a curve; Flutter's `Cubic` asserts it in debug and draws
    // something else in release, so it is checked here where the message can
    // name the theme's number.
    for (final i in [0, 2]) {
      if (points[i] < 0 || points[i] > 1) {
        throw FormatException(
          'a curve x coordinate is outside 0..1, so it is not a cubic-bezier',
          '${points[i]} at point $i of $curve',
        );
      }
    }

    return OrbitMotion._(
      short: _seconds(durations['short'], 'motion.duration.short'),
      page: _seconds(durations['page'], 'motion.duration.page'),
      curve: Cubic(points[0], points[1], points[2], points[3]),
      controlPoints: List.unmodifiable(points),
    );
  }

  /// The prototype's `--dur`: a colour, a border, a switch or a control's own
  /// change. 180 ms in every built-in theme.
  final Duration short;

  /// The prototype's `--dur-page`: a page, a sheet, a dialog or a pager's
  /// movement. 260 ms in every built-in theme.
  final Duration page;

  /// The prototype's `--ease`, as Flutter's [Cubic] takes the same four
  /// control points in the same order.
  ///
  /// Hand it straight to a `CurvedAnimation`, an `AnimationController` or any
  /// implicit animation's `curve`.
  final Curve curve;

  /// The four control points behind [curve], in the JSON's own order.
  ///
  /// Kept beside the built [curve] for tests and for anything that has to
  /// describe the motion in numbers, the way `OrbitPattern` keeps its settings
  /// beside the `OrbitTile` it builds from them.
  final List<double> controlPoints;

  /// Whether motion may run right now, from the platform's own setting.
  ///
  /// This is `prefers-reduced-motion`, which the prototype answers in
  /// `css/pages.css` by switching animation **off**:
  /// `.phone-screen * { animation: none !important; transition: none
  /// !important; }`, under the note that a near-zero transition on every
  /// element would make each one transition every property, and a page that
  /// is not drawing frames would keep the old values.
  ///
  /// So the answer is yes or no, and the caller's job is to not start the
  /// animation - not to run it faster. A theme pack cannot override this: it is
  /// a person who has asked their platform for less movement, not a style
  /// choice.
  static bool allowed(BuildContext context) =>
      !MediaQuery.disableAnimationsOf(context);

  /// A number of seconds, as the theme JSON writes it, as a [Duration].
  ///
  /// Seconds rather than milliseconds because that is the unit CSS uses, so
  /// the number a pack author writes is the one they already know, and the
  /// conversion happens once, here.
  static Duration _seconds(Object? v, String key) {
    if (v is! num) {
      throw FormatException(
        'a duration is not a number of seconds',
        '$key: $v',
      );
    }
    if (v < 0) {
      throw FormatException('a duration is negative', '$key: $v');
    }
    return Duration(
      microseconds: (v * Duration.microsecondsPerSecond).round(),
    );
  }
}
