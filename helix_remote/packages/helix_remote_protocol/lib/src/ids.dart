import 'dart:math';

/// UUID helpers. Every v2 identifier on the wire (accounts, devices,
/// messages, groups, calls, media) is a lowercase canonical UUID, and ids
/// created in v2 are UUIDv7 (time-ordered, so they index well; ADR-025).
abstract final class Uuid {
  static final RegExp _canonical = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );

  static final Random _secure = Random.secure();

  /// A new UUIDv7 (RFC 9562): 48-bit Unix milliseconds, version 7, 74 random
  /// bits. Ids from one generator are ordered by creation millisecond; ids
  /// within the same millisecond are not ordered among themselves.
  static String v7({DateTime? now, Random? random}) {
    final rng = random ?? _secure;
    var ms = (now ?? DateTime.now()).toUtc().millisecondsSinceEpoch;
    final bytes = List<int>.filled(16, 0);
    for (var i = 5; i >= 0; i--) {
      bytes[i] = ms % 256;
      ms ~/= 256;
    }
    for (var i = 6; i < 16; i++) {
      bytes[i] = rng.nextInt(256);
    }
    bytes[6] = 0x70 | (bytes[6] & 0x0f); // version 7
    bytes[8] = 0x80 | (bytes[8] & 0x3f); // RFC 4122 variant
    return format(bytes);
  }

  /// Formats 16 bytes as a canonical lowercase UUID.
  static String format(List<int> bytes) {
    if (bytes.length != 16) {
      throw ArgumentError.value(bytes.length, 'bytes', 'must be 16 bytes');
    }
    final hex = [
      for (final b in bytes) b.toRadixString(16).padLeft(2, '0'),
    ].join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  /// Whether [value] is a canonical lowercase UUID of any version.
  static bool isValid(String value) => _canonical.hasMatch(value);

  /// Whether [value] is a canonical UUIDv7.
  static bool isV7(String value) =>
      isValid(value) &&
      value[14] == '7' &&
      const {'8', '9', 'a', 'b'}.contains(value[19]);

  /// The creation time encoded in a UUIDv7.
  static DateTime timeOfV7(String value) {
    if (!isV7(value)) {
      throw ArgumentError.value(value, 'value', 'is not a UUIDv7');
    }
    final hex = value.replaceAll('-', '').substring(0, 12);
    return DateTime.fromMillisecondsSinceEpoch(
      int.parse(hex, radix: 16),
      isUtc: true,
    );
  }
}
