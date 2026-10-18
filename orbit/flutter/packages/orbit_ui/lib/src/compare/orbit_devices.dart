/// The device sizes and file names the two halves of the compare tool agree on.
///
/// `shoot_html.py` photographs the prototype at `phone` 412x866, `window-m`
/// 960x720 and `window-l` 1280x800, and names every file
/// `<key>[.scroll<n>].<device>.<theme>.png`. This file is the Flutter half of
/// that agreement. It is one list, in one place, so a device cannot be added on
/// one side only: the render writes that name, and the report looks the HTML
/// side's manifest up by that name.
library;

/// One device the compare tool renders at.
enum OrbitDevice {
  /// The prototype's phone frame, and the size every screen is ported at.
  phone('phone', 412, 866),

  /// The medium Windows layout: list on the left, screen on the right.
  windowM('window-m', 960, 720),

  /// The wide Windows layout.
  windowL('window-l', 1280, 800);

  const OrbitDevice(this.wireName, this.width, this.height);

  /// The name that appears in a file name and in the compare page's JSON.
  /// `windowM` is `window-m`, not `window_m`, because that is what the HTML
  /// half writes.
  final String wireName;

  /// Logical pixels. The render sets the surface to this at a device pixel
  /// ratio of exactly 1.0, so one Flutter pixel is one image pixel and one
  /// CSS pixel.
  final int width;
  final int height;

  /// The device with this [wireName].
  ///
  /// Throws [ArgumentError] on an unknown name: a typo in a device name must
  /// not quietly fall back to the phone, because that would compare a window
  /// layout against a phone shot and score it as if the whole screen were
  /// wrong.
  static OrbitDevice byWireName(String name) {
    for (final device in values) {
      if (device.wireName == name) return device;
    }
    throw ArgumentError.value(
      name,
      'name',
      'not a device the compare tool renders at ('
          '${values.map((d) => d.wireName).join(', ')})',
    );
  }
}

/// The file name both halves use for one screen state.
///
/// A key shot at two scroll offsets keeps both files, exactly as
/// `shoot_html.py` names them, so the two directories can be walked together.
String orbitShotFileName(
  String key, {
  required OrbitDevice device,
  required String theme,
  int scroll = 0,
}) {
  if (key.isEmpty) {
    throw ArgumentError.value(key, 'key', 'a screen key is never empty');
  }
  if (theme.isEmpty) {
    throw ArgumentError.value(theme, 'theme', 'a theme id is never empty');
  }
  if (scroll < 0) {
    throw ArgumentError.value(scroll, 'scroll', 'scroll offsets are >= 0');
  }
  final suffix = scroll == 0 ? '' : '.scroll$scroll';
  return '$key$suffix.${device.wireName}.$theme.png';
}

/// Reads a file name the [orbitShotFileName] rules produce back into a spec.
///
/// This is how the two halves find each other: the report reads the HTML
/// half's `manifest.json`, takes each shot's `file` name, and parses it into
/// the spec the Flutter render wrote under. Parsing from the right is what
/// makes a key containing a dot safe - only the theme and the device are fixed
/// positions.
OrbitShotSpec orbitParseShotFileName(String fileName) {
  final bare = fileName.endsWith('.png')
      ? fileName.substring(0, fileName.length - 4)
      : fileName;
  final parts = bare.split('.');
  if (parts.length < 3) {
    throw FormatException(
      "'$fileName' is not <key>[.scroll<n>].<device>.<theme>.png",
    );
  }
  final theme = parts.last;
  final device = OrbitDevice.byWireName(parts[parts.length - 2]);
  final head = parts.sublist(0, parts.length - 2);
  var key = head.join('.');
  var scroll = 0;
  if (head.isNotEmpty) {
    final tail = head.last;
    final offset = tail.startsWith('scroll')
        ? int.tryParse(tail.substring('scroll'.length))
        : null;
    if (offset != null && offset != 0) {
      scroll = offset;
      key = head.sublist(0, head.length - 1).join('.');
    }
  }
  return OrbitShotSpec(key, device: device, theme: theme, scroll: scroll);
}

/// One screen state, on one side of the comparison.
///
/// [scroll] is the page offset both halves were shot at. It is part of the
/// identity of the comparison, so `settings` at the top and `settings` 760px
/// down are two different comparisons and never one.
final class OrbitShotSpec {
  const OrbitShotSpec(
    this.key, {
    required this.device,
    required this.theme,
    this.scroll = 0,
  });

  /// The prototype's screen key, from `prototype/screens.json` and the same
  /// key the preview app uses.
  final String key;

  final OrbitDevice device;

  /// The theme id, the same string `shoot_html.py --theme` takes.
  final String theme;

  final int scroll;

  /// `<key>[.scroll<n>].<device>.<theme>.png`
  String get fileName =>
      orbitShotFileName(key, device: device, theme: theme, scroll: scroll);

  /// A short name for a report line, for example `group.phone.orbit` or
  /// `settings.scroll760.phone.orbit`.
  String get shortName => fileName.substring(0, fileName.length - 4);

  @override
  String toString() => shortName;

  @override
  bool operator ==(Object other) =>
      other is OrbitShotSpec &&
      other.key == key &&
      other.device == device &&
      other.theme == theme &&
      other.scroll == scroll;

  @override
  int get hashCode => Object.hash(key, device, theme, scroll);
}
