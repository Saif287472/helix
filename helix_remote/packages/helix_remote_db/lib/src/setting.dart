import 'dart:convert';

import 'package:meta/meta.dart';

/// A typed setting: its key, its type and its default. Values are stored as
/// JSON in `settings.value`. Features declare their settings as constants:
///
/// ```dart
/// const readReceipts = Setting<bool>('privacy.read_receipts', true);
/// const theme = Setting.enumeration('ui.text_size', TextSize.values, TextSize.normal);
/// ```
@immutable
final class Setting<T> {
  /// A setting whose value is a JSON scalar: `bool`, `int`, `String`, or a
  /// nullable one of those.
  const Setting(this.key, this.defaultValue) : _values = null;

  /// An enum setting, stored by name.
  const Setting.enumeration(this.key, List<T> values, this.defaultValue)
    : _values = values;

  final String key;
  final T defaultValue;
  final List<T>? _values;

  /// Decodes a stored value. A value of the wrong shape, or an enum name
  /// this version does not know, reads as the default instead of failing.
  T decode(String stored) {
    final Object? json;
    try {
      json = jsonDecode(stored);
    } on FormatException {
      return defaultValue;
    }
    final values = _values;
    if (values != null) {
      for (final value in values) {
        if ((value as Enum).name == json) return value;
      }
      return defaultValue;
    }
    return json is T ? json : defaultValue;
  }

  String encode(T value) {
    if (_values != null) return jsonEncode((value as Enum).name);
    return jsonEncode(value);
  }

  @override
  bool operator ==(Object other) => other is Setting && other.key == key;

  @override
  int get hashCode => key.hashCode;

  @override
  String toString() => 'Setting($key)';
}
