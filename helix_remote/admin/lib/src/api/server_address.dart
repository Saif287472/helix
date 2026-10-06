/// A server address typed by the operator, checked before anything is sent.
///
/// The admin password goes to this address, so a plain `http://` URL is
/// refused unless it points at the operator's own machine (development).
final class ServerAddress {
  const ServerAddress._(this.uri);

  /// The base URL: scheme, host, port and an optional path prefix, with no
  /// credentials, query, fragment or trailing slash.
  final Uri uri;

  /// The text to show and to store.
  String get text => uri.toString();

  /// Parses [raw]; a missing scheme means `https://`. Throws
  /// [ServerAddressException] with a message for the operator.
  factory ServerAddress.parse(String raw) {
    var text = raw.trim();
    if (text.isEmpty) {
      throw const ServerAddressException('Enter the server address.');
    }
    if (!text.contains('://')) text = 'https://$text';
    final Uri parsed;
    try {
      parsed = Uri.parse(text);
    } on FormatException {
      throw const ServerAddressException('That is not a valid address.');
    }
    if (parsed.scheme != 'https' && parsed.scheme != 'http') {
      throw const ServerAddressException(
        'The address must start with https://.',
      );
    }
    if (parsed.host.isEmpty) {
      throw const ServerAddressException('That is not a valid address.');
    }
    if (parsed.userInfo.isNotEmpty) {
      throw const ServerAddressException(
        'Leave the user name and password out of the address.',
      );
    }
    if (parsed.scheme == 'http' && !_isLocalHost(parsed.host)) {
      throw const ServerAddressException(
        'Use https://. The admin password must not cross the network '
        'unencrypted.',
      );
    }
    var path = parsed.path;
    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    return ServerAddress._(
      Uri(
        scheme: parsed.scheme,
        host: parsed.host,
        port: parsed.hasPort ? parsed.port : null,
        path: path,
      ),
    );
  }

  /// Machines where plain HTTP never leaves the device: loopback and the
  /// Android emulator's alias for the host.
  static bool _isLocalHost(String host) {
    final h = host.toLowerCase();
    return h == 'localhost' ||
        h.endsWith('.localhost') ||
        h.startsWith('127.') ||
        h == '::1' ||
        h == '[::1]' ||
        h == '10.0.2.2';
  }

  @override
  bool operator ==(Object other) => other is ServerAddress && other.uri == uri;

  @override
  int get hashCode => uri.hashCode;

  @override
  String toString() => text;
}

final class ServerAddressException implements Exception {
  const ServerAddressException(this.message);

  final String message;

  @override
  String toString() => message;
}
