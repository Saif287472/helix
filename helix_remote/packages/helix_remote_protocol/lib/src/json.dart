import 'dart:convert';
import 'dart:typed_data';

/// A decoded JSON object.
typedef JsonMap = Map<String, Object?>;

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

  String string(String key) {
    final value = _required(key);
    return value is String ? value : _type(key, 'a string');
  }

  String? optString(String key) => has(key) ? string(key) : null;

  /// A non-empty string, trimmed of nothing: the wire value must already be
  /// canonical.
  String nonEmpty(String key) {
    final value = string(key);
    if (value.isEmpty) {
      throw ProtocolFormatException('must not be empty', path: _at(key));
    }
    return value;
  }

  int integer(String key) {
    final value = _required(key);
    if (value is int) return value;
    if (value is double && value == value.truncateToDouble()) {
      return value.toInt();
    }
    return _type(key, 'an integer');
  }

  int? optInt(String key) => has(key) ? integer(key) : null;

  bool boolean(String key) {
    final value = _required(key);
    return value is bool ? value : _type(key, 'a boolean');
  }

  bool flag(String key, {bool orElse = false}) =>
      has(key) ? boolean(key) : orElse;

  Uint8List bytes(String key) => decodeBytes(string(key), path: _at(key));

  Uint8List? optBytes(String key) => has(key) ? bytes(key) : null;

  /// Epoch milliseconds (UTC). All wire timestamps use this form.
  DateTime time(String key) =>
      DateTime.fromMillisecondsSinceEpoch(integer(key), isUtc: true);

  DateTime? optTime(String key) => has(key) ? time(key) : null;

  JsonReader object(String key) =>
      JsonReader.of(_required(key), path: _at(key));

  JsonReader? optObject(String key) => has(key) ? object(key) : null;

  List<Object?> _list(String key) {
    final value = _required(key);
    return value is List ? value.cast<Object?>() : _type(key, 'a list');
  }

  /// A list of objects, each decoded by [decode].
  List<T> objects<T>(String key, T Function(JsonReader item) decode) {
    final items = _list(key);
    return [
      for (var i = 0; i < items.length; i++)
        decode(JsonReader.of(items[i], path: '${_at(key)}[$i]')),
    ];
  }

  /// Like [objects], but a missing field is an empty list.
  List<T> optObjects<T>(String key, T Function(JsonReader item) decode) =>
      has(key) ? objects(key, decode) : <T>[];

  List<String> strings(String key) {
    final items = _list(key);
    return [
      for (var i = 0; i < items.length; i++)
        items[i] is String
            ? items[i]! as String
            : throw ProtocolFormatException(
                'expected a string',
                path: '${_at(key)}[$i]',
              ),
    ];
  }

  List<String> optStrings(String key) => has(key) ? strings(key) : <String>[];

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
