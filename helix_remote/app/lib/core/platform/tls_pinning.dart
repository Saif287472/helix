import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:helix_remote_api/v2.dart'
    as api
    show RealtimeSocketFactory, defaultSocketFactory;
import 'package:helix_remote_crypto/v2.dart' show Sha256Accumulator;

/// Certificate pinning for Helix Global, in Dart.
///
/// Android's `network_security_config` (and its `pin-set`) only governs the
/// platform's own HTTP stack. Dart opens its own sockets with its own trust
/// store, so that file does not protect a single request the app makes, and
/// `HttpClient` offers no post-handshake hook that runs before the request is
/// written. This is the mechanism that does protect them.
///
/// **How.** A client built under [run] gets a `SecurityContext` that trusts no
/// certificate authority at all. Every server certificate therefore "fails"
/// the platform's validation and reaches `badCertificateCallback`, which is
/// where the decision is made: the connection is accepted only when the host
/// is one of [hosts] **and** the SHA-256 of the certificate's
/// SubjectPublicKeyInfo (the same value Android's `pin` element holds, base64)
/// is one of [pins]. Anything else - another host, another key, a certificate
/// that cannot be parsed - is refused before a byte of the request is sent.
/// Failing closed is the point, so there is no "trust the system store as a
/// fallback".
///
/// **Which traffic.** Only a runtime whose server is one of [hosts]. A personal
/// server has no known key to pin and keeps ordinary validation; it is reached
/// over https only (`ServerPolicy`). Because a pinned client trusts nothing but
/// the pin, it also reaches nothing but [hosts]: that is how the REST client
/// and the realtime socket behave today (one server per runtime), and a server
/// that handed out a link on another host would find it unreachable.
///
/// **Rotation.** The pin is the **leaf** key (the only certificate a Dart
/// callback sees). [builtInPins] carries the value from
/// `helix_remote_network_security.xml`; ADR 022 requires the *next* key's pin
/// to ship before the key changes. Add it without a code change:
/// `--dart-define=HELIX_GLOBAL_PINS=<base64>,<base64>` is **added** to the
/// built-in list. If the server's certificate is renewed with a new key and no
/// matching pin was shipped, Helix Global is unreachable from that build -
/// that is the fail-closed behaviour, not a bug. A **backup pin** placeholder
/// is deliberately not invented here: generate it from the standby key with
/// `openssl x509 -in cert.pem -pubkey -noout | openssl pkey -pubin -outform
/// der | openssl dgst -sha256 -binary | openssl base64` and pass it as above.
///
/// Debug builds are not pinned, mirroring the debug network security config
/// (a local server, an emulator, a staging certificate).
final class TlsPinPolicy {
  const TlsPinPolicy({
    required this.hosts,
    required this.pins,
    required this.enforce,
  });

  /// The policy this build runs with.
  factory TlsPinPolicy.forThisBuild() => TlsPinPolicy(
    hosts: globalHosts,
    pins: {
      ...builtInPins,
      for (final pin in _definedPins.split(','))
        if (pin.trim().isNotEmpty) pin.trim(),
    },
    enforce: !kDebugMode,
  );

  /// Added to [builtInPins]; see the class comment.
  static const _definedPins = String.fromEnvironment('HELIX_GLOBAL_PINS');

  /// The hosts that are Helix Global (`helix_remote_network_security.xml`'s
  /// `domain-config`).
  static const globalHosts = {'helix.agiletechbd.com', 'hr.agiletechbd.com'};

  /// SHA-256(SPKI), base64: the `pin` in `helix_remote_network_security.xml`,
  /// captured 2026-08-07. A test keeps the two in step.
  static const builtInPins = {'fjt5zE6K0c3n1+uhpv6oLsJ+ksWtV511oiwSd79rpzs='};

  final Set<String> hosts;
  final Set<String> pins;

  /// False in debug builds: nothing is pinned, ordinary validation applies.
  final bool enforce;

  /// Whether a runtime for [server] is pinned.
  bool appliesTo(Uri server) =>
      enforce && hosts.contains(server.host.toLowerCase());

  /// The certificate check: [host] is one we pin and [der] carries a pinned
  /// key. Refuses (false) on anything it cannot read.
  bool accepts(Uint8List der, {required String host}) {
    if (!hosts.contains(host.toLowerCase())) return false;
    try {
      return pins.contains(spkiPin(der));
    } on FormatException {
      return false;
    }
  }

  /// Runs [body] so that every `HttpClient` it creates is pinned. The REST
  /// client creates its client in its constructor, so build it inside this.
  T run<T>(T Function() body) =>
      HttpOverrides.runWithHttpOverrides(body, _PinnedOverrides(this));

  /// The realtime socket factory for a pinned runtime: the api package's own
  /// `dart:io` factory, run under [run] (it makes a fresh `HttpClient` per
  /// connection).
  api.RealtimeSocketFactory get socketFactory =>
      (uri, {required headers, required protocols}) => run(
        () => api.defaultSocketFactory(
          uri,
          headers: headers,
          protocols: protocols,
        ),
      );

  /// SHA-256 of the SubjectPublicKeyInfo inside the DER certificate [der],
  /// base64 - the value of an Android `<pin digest="SHA-256">`.
  ///
  /// Throws [FormatException] when [der] is not a certificate.
  static String spkiPin(Uint8List der) {
    final spki = _subjectPublicKeyInfo(der);
    final digest = Sha256Accumulator()..add(spki);
    return base64.encode(digest.close());
  }
}

final class _PinnedOverrides extends HttpOverrides {
  _PinnedOverrides(this._policy);

  final TlsPinPolicy _policy;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    // Ignores the caller's context: a context that trusts nothing is what
    // sends every certificate to the callback below.
    final client = super.createHttpClient(
      SecurityContext(withTrustedRoots: false),
    );
    client.badCertificateCallback = (certificate, host, port) =>
        _policy.accepts(certificate.der, host: host);
    return client;
  }
}

/// Slices the SubjectPublicKeyInfo out of an X.509 certificate.
///
/// Certificate ::= SEQUENCE { tbsCertificate, signatureAlgorithm, signature }
/// tbsCertificate ::= SEQUENCE { [0] version OPTIONAL, serialNumber,
///   signature, issuer, validity, subject, subjectPublicKeyInfo, ... }
Uint8List _subjectPublicKeyInfo(Uint8List der) {
  final certificate = _Tlv.read(der, 0);
  if (certificate.tag != 0x30) throw const FormatException('not a SEQUENCE');
  final tbs = _Tlv.read(der, certificate.contentStart);
  if (tbs.tag != 0x30) throw const FormatException('no tbsCertificate');
  var offset = tbs.contentStart;
  final end = tbs.end;
  final first = _Tlv.read(der, offset);
  if (first.tag == 0xA0) offset = first.end; // the explicit version
  // serialNumber, signature, issuer, validity, subject.
  for (var i = 0; i < 5; i++) {
    offset = _Tlv.read(der, offset).end;
    if (offset >= end) throw const FormatException('truncated certificate');
  }
  final spki = _Tlv.read(der, offset);
  if (spki.tag != 0x30 || spki.end > end) {
    throw const FormatException('no SubjectPublicKeyInfo');
  }
  return Uint8List.sublistView(der, offset, spki.end);
}

/// One DER tag-length-value, read with every bound checked.
final class _Tlv {
  const _Tlv(this.tag, this.contentStart, this.end);

  final int tag;
  final int contentStart;
  final int end;

  static _Tlv read(Uint8List bytes, int offset) {
    if (offset < 0 || offset + 2 > bytes.length) {
      throw const FormatException('truncated DER');
    }
    final tag = bytes[offset];
    var i = offset + 1;
    var length = bytes[i++];
    if (length & 0x80 != 0) {
      final count = length & 0x7f;
      if (count == 0 || count > 4 || i + count > bytes.length) {
        throw const FormatException('bad DER length');
      }
      length = 0;
      for (var k = 0; k < count; k++) {
        length = (length << 8) | bytes[i++];
      }
    }
    final end = i + length;
    if (end > bytes.length) throw const FormatException('DER overruns');
    return _Tlv(tag, i, end);
  }
}
