import 'dart:convert';
import 'dart:typed_data';

/// A decoded JSON object.
typedef JsonMap = Map<String, Object?>;

/// The largest integer a wire message may carry (2^53 - 1, the largest
/// integer JavaScript reads exactly).
const maxWireInt = 9007199254740991;

/// The earliest wire timestamp: the epoch.
const minWireTime = 0;

/// The latest wire timestamp: 9999-12-31T23:59:59.999Z.
const maxWireTime = 253402300799999;

/// The backstop limit on a decoded string, for a field whose DTO names no
/// smaller one. Nothing legitimate needs more: the longest field on the wire
/// is a 32 KiB SDP blob (`CallSignal.maxSdpLength`), then a compiled-in legal
/// document and a crash stack, all well under this.
const maxWireStringLength = 65536;

/// The backstop limit on a base64url field, measured on the decoded bytes.
/// The largest payload the server accepts is 256 KiB
/// (`SendMessageRequest.maxPayloadBytes`); a field that legitimately carries
/// more names its own limit at the call site (a history backup does).
const maxWireBytes = 1024 * 1024;

/// The backstop limit on the length of a decoded list. The largest legitimate
/// list is a contact sync (`SetContactsRequest.maxContacts`, 5000), so this
/// leaves room without letting a peer build a list the body cap already paid
/// for.
const maxWireListItems = 20000;

/// Thrown when a wire message does not match the contract. [path] names the
/// offending field (`body.recipients[2].device_id`), never its value: wire
/// values can be secrets.
final class ProtocolFormatException extends FormatException {
  ProtocolFormatException(String message, {this.path = ''})
    : super(path.isEmpty ? message : '$message (at $path)');

  final String path;
}

/// Encodes bytes as unpadded base64url, the only binary encoding on the wire.
String encodeBytes(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

/// Decodes unpadded (or padded) base64url.
Uint8List decodeBytes(String value, {String path = ''}) {
  try {
    return base64Url.decode(base64Url.normalize(value));
  } on FormatException {
    throw ProtocolFormatException('expected base64url bytes', path: path);
  }
}

/// Strict, path-tracking reader over a JSON object.
///
/// Every DTO decodes through one of these so a malformed message fails with
/// a [ProtocolFormatException] naming the field, instead of a `TypeError`
/// somewhere inside the server or app. Unknown fields are ignored (forward
/// compatibility, `remote_compatibility_policy.md`).
///
/// Every string, byte field and list is bounded: [string], [bytes] and the
/// list readers take a limit and default it to the backstops above, so a
/// field nobody thought about is still capped. Where the contract knows the
/// real size of a field, the call site names it.
final class JsonReader {
  JsonReader(this.json, {this.path = ''});

  /// Wraps [value], which must be a JSON object.
  factory JsonReader.of(Object? value, {String path = ''}) {
    if (value is Map<String, Object?>) return JsonReader(value, path: path);
    if (value is Map) {
      return JsonReader(value.cast<String, Object?>(), path: path);
    }
    throw ProtocolFormatException('expected an object', path: path);
  }

  /// Decodes [source] as a JSON object.
  factory JsonReader.decode(String source) {
    final Object? value;
    try {
      value = jsonDecode(source);
    } on FormatException {
      throw ProtocolFormatException('invalid JSON');
    }
    return JsonReader.of(value);
  }

  final JsonMap json;
  final String path;

  String _at(String key) => path.isEmpty ? key : '$path.$key';

  bool has(String key) => json[key] != null;

  Never _type(String key, String expected) =>
      throw ProtocolFormatException('expected $expected', path: _at(key));

  Object _required(String key) {
    final value = json[key];
    if (value == null) {
      throw ProtocolFormatException('missing field', path: _at(key));
    }
    return value;
  }

  String string(String key, {int maxLength = maxWireStringLength}) {
    final value = _required(key);
    if (value is! String) return _type(key, 'a string');
    if (value.length > maxLength) {
      throw ProtocolFormatException('too long', path: _at(key));
    }
    return value;
  }

  String? optString(String key, {int maxLength = maxWireStringLength}) =>
      has(key) ? string(key, maxLength: maxLength) : null;

  /// A non-empty string, trimmed of nothing: the wire value must already be
  /// canonical.
  String nonEmpty(String key, {int maxLength = maxWireStringLength}) {
    final value = string(key, maxLength: maxLength);
    if (value.isEmpty) {
      throw ProtocolFormatException('must not be empty', path: _at(key));
    }
    return value;
  }

  /// An integer in the range every JSON implementation reads exactly
  /// (|v| <= 2^53 - 1, [maxWireInt]). A hostile peer's larger value, an
  /// infinite or fractional number is a [ProtocolFormatException], never an
  /// arithmetic overflow further on.
  int integer(String key) {
    final value = _required(key);
    final int result;
    if (value is int) {
      result = value;
    } else if (value is double &&
        value.isFinite &&
        value == value.truncateToDouble() &&
        value.abs() <= maxWireInt) {
      result = value.toInt();
    } else {
      return _type(key, 'an integer');
    }
    if (result > maxWireInt || result < -maxWireInt) {
      throw ProtocolFormatException('integer out of range', path: _at(key));
    }
    return result;
  }

  int? optInt(String key) => has(key) ? integer(key) : null;

  /// An integer within [min] .. [max]; anything else is a
  /// [ProtocolFormatException] (sizes, counts, coordinates and durations of
  /// untrusted content are checked where they are read).
  int intIn(String key, int min, int max) {
    final value = integer(key);
    if (value < min || value > max) {
      throw ProtocolFormatException('value out of range', path: _at(key));
    }
    return value;
  }

  int? optIntIn(String key, int min, int max) =>
      has(key) ? intIn(key, min, max) : null;

  bool boolean(String key) {
    final value = _required(key);
    return value is bool ? value : _type(key, 'a boolean');
  }

  bool flag(String key, {bool orElse = false}) =>
      has(key) ? boolean(key) : orElse;

  /// Base64url bytes, capped on the decoded length ([maxLength]). The text is
  /// checked first, at its four-chars-per-three-bytes size, so an oversize
  /// field is refused before it is decoded into memory.
  Uint8List bytes(String key, {int maxLength = maxWireBytes}) {
    final value = string(key, maxLength: maxLength * 4 ~/ 3 + 4);
    final decoded = decodeBytes(value, path: _at(key));
    if (decoded.length > maxLength) {
      throw ProtocolFormatException('too long', path: _at(key));
    }
    return decoded;
  }

  Uint8List? optBytes(String key, {int maxLength = maxWireBytes}) =>
      has(key) ? bytes(key, maxLength: maxLength) : null;

  /// [bytes] where the contract fixes the length (a key, a digest, a
  /// signature): a wrong length is a protocol error here, not a crypto
  /// failure somewhere later.
  Uint8List bytesOf(String key, int length) {
    final value = bytes(key, maxLength: length);
    if (value.length != length) {
      throw ProtocolFormatException('expected $length bytes', path: _at(key));
    }
    return value;
  }

  Uint8List? optBytesOf(String key, int length) =>
      has(key) ? bytesOf(key, length) : null;

  /// Epoch milliseconds (UTC). All wire timestamps use this form, within
  /// [minWireTime] .. [maxWireTime] (1970 to the end of year 9999): a value
  /// outside it is a [ProtocolFormatException], not the `RangeError` that
  /// `DateTime` would throw (and not a date that breaks arithmetic later).
  DateTime time(String key) {
    final ms = integer(key);
    if (ms < minWireTime || ms > maxWireTime) {
      throw ProtocolFormatException('time out of range', path: _at(key));
    }
    return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  }

  DateTime? optTime(String key) => has(key) ? time(key) : null;

  JsonReader object(String key) =>
      JsonReader.of(_required(key), path: _at(key));

  JsonReader? optObject(String key) => has(key) ? object(key) : null;

  List<Object?> _list(String key, {int maxItems = maxWireListItems}) {
    final value = _required(key);
    if (value is! List) return _type(key, 'a list');
    if (value.length > maxItems) {
      throw ProtocolFormatException(
        'over the $maxItems item limit',
        path: _at(key),
      );
    }
    return value.cast<Object?>();
  }

  /// A list of objects, each decoded by [decode].
  List<T> objects<T>(
    String key,
    T Function(JsonReader item) decode, {
    int maxItems = maxWireListItems,
  }) {
    final items = _list(key, maxItems: maxItems);
    return [
      for (var i = 0; i < items.length; i++)
        decode(JsonReader.of(items[i], path: '${_at(key)}[$i]')),
    ];
  }

  /// Like [objects], but a missing field is an empty list.
  List<T> optObjects<T>(
    String key,
    T Function(JsonReader item) decode, {
    int maxItems = maxWireListItems,
  }) => has(key) ? objects(key, decode, maxItems: maxItems) : <T>[];

  List<String> strings(
    String key, {
    int maxItems = maxWireListItems,
    int maxLength = maxWireStringLength,
  }) {
    final items = _list(key, maxItems: maxItems);
    return [
      for (var i = 0; i < items.length; i++)
        items[i] is String && (items[i]! as String).length <= maxLength
            ? items[i]! as String
            : throw ProtocolFormatException(
                'expected a string of at most $maxLength characters',
                path: '${_at(key)}[$i]',
              ),
    ];
  }

  List<String> optStrings(
    String key, {
    int maxItems = maxWireListItems,
    int maxLength = maxWireStringLength,
  }) => has(key)
      ? strings(key, maxItems: maxItems, maxLength: maxLength)
      : <String>[];

  /// A wire enum value. Unknown values throw unless [orElse] is given, which
  /// is how forward-compatible enums decode values from newer peers.
  T enumValue<T extends WireEnum>(String key, List<T> values, {T? orElse}) {
    final wire = string(key);
    for (final value in values) {
      if (value.wire == wire) return value;
    }
    if (orElse != null) return orElse;
    throw ProtocolFormatException('unknown value', path: _at(key));
  }

  T? optEnum<T extends WireEnum>(String key, List<T> values, {T? orElse}) =>
      has(key) ? enumValue(key, values, orElse: orElse) : null;

  /// The raw JSON value of [key], for payloads this layer does not interpret.
  Object? raw(String key) => json[key];
}

/// An enum with a stable wire spelling.
abstract interface class WireEnum {
  String get wire;
}

/// Something that encodes to a JSON object.
abstract interface class JsonEncodable {
  JsonMap toJson();
}

/// Drops `null` values so optional fields are omitted rather than sent as
/// `null` (the contract treats both the same; omitting is smaller).
JsonMap compact(JsonMap map) => {
  for (final entry in map.entries)
    if (entry.value != null) entry.key: entry.value,
};

int toWireTime(DateTime time) => time.toUtc().millisecondsSinceEpoch;
