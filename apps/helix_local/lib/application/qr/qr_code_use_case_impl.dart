import 'dart:typed_data';

import 'package:cbor/cbor.dart';
import 'package:helix_protocol/application/contracts/use_cases.dart';
import 'package:helix_domain/domain/models.dart';

class QrCodeUseCaseImpl implements QrCodeUseCase {
  const QrCodeUseCaseImpl();

  /// Encode a [QrPayload] as a CBOR byte string, then base64url-encode it.
  @override
  String encode(QrPayload payload) {
    final map = CborValue({
      'n': payload.displayName,
      's': payload.deviceSuffix,
      'i': payload.localIp,
      if (payload.localIps.isNotEmpty) 'ips': payload.localIps,
      'p': payload.tcpPort,
      'sid': payload.sessionId,
    });
    final bytes = Uint8List.fromList(cbor.encode(map));
    // Use URL-safe base64 without padding to stay compact inside the QR.
    final b64 = _base64UrlEncode(bytes);
    return 'wsp:$b64';
  }

  /// Decode a string produced by [encode].
  @override
  QrPayload? decode(String raw) {
    if (!raw.startsWith('wsp:')) return null;
    final b64 = raw.substring(4);
    final bytes = _base64UrlDecode(b64);
    if (bytes == null) return null;

    try {
      final decoded = cbor.decode(bytes);
      final obj = decoded.toObject(parseDateTime: false, parseUri: false);
      if (obj is! Map) return null;
      final m = obj as Map<Object?, Object?>;

      String s(String key) => (m[key] as String?) ?? '';
      int i(String key) => (m[key] as int?) ?? 0;

      final displayName = s('n');
      final deviceSuffix = s('s');
      final localIp = s('i');
      final localIps = switch (m['ips']) {
        final List<Object?> values => values.whereType<String>().toList(),
        _ => const <String>[],
      };
      final tcpPort = i('p');
      final sessionId = s('sid');

      if (localIp.isEmpty || tcpPort <= 0 || sessionId.isEmpty) return null;

      return QrPayload(
        displayName: displayName,
        deviceSuffix: deviceSuffix,
        localIp: localIp,
        localIps: localIps,
        tcpPort: tcpPort,
        sessionId: sessionId,
      );
    } catch (_) {
      return null;
    }
  }

  /// Build a [Peer] stub from a decoded payload so the UI can call
  /// DiscoveryCoordinator.probeDirectIp or RequestService.sendRequest.
  @override
  Peer payloadToPeer(QrPayload payload) => Peer(
    sessionId: payload.sessionId,
    displayName: payload.displayName,
    deviceSuffix: payload.deviceSuffix,
    host: payload.localIp,
    port: payload.tcpPort,
    source: PeerSource.directIp,
    seenAt: DateTime.now(),
    protocolMajor: 2,
    protocolMinor: 0,
  );

  @override
  List<Peer> payloadToPeers(QrPayload payload) {
    final hosts = <String>{
      payload.localIp,
      ...payload.localIps,
    }.where((host) => host.trim().isNotEmpty).toList();
    return hosts
        .map(
          (host) => Peer(
            sessionId: payload.sessionId,
            displayName: payload.displayName,
            deviceSuffix: payload.deviceSuffix,
            host: host,
            port: payload.tcpPort,
            source: PeerSource.directIp,
            seenAt: DateTime.now(),
            protocolMajor: 2,
            protocolMinor: 0,
          ),
        )
        .toList();
  }

  // ── Base64 URL helpers (no dart:convert dependency on base64url) ───────────

  static const _chars =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';

  String _base64UrlEncode(Uint8List bytes) {
    final sb = StringBuffer();
    for (var i = 0; i < bytes.length; i += 3) {
      final b0 = bytes[i];
      final b1 = i + 1 < bytes.length ? bytes[i + 1] : 0;
      final b2 = i + 2 < bytes.length ? bytes[i + 2] : 0;
      sb.write(_chars[(b0 >> 2) & 0x3F]);
      sb.write(_chars[((b0 << 4) | (b1 >> 4)) & 0x3F]);
      if (i + 1 < bytes.length) {
        sb.write(_chars[((b1 << 2) | (b2 >> 6)) & 0x3F]);
      }
      if (i + 2 < bytes.length) {
        sb.write(_chars[b2 & 0x3F]);
      }
    }
    return sb.toString();
  }

  Uint8List? _base64UrlDecode(String s) {
    try {
      // Restore padding if needed, then decode manually.
      final padded = s + '=' * ((4 - s.length % 4) % 4);
      final out = <int>[];
      for (var i = 0; i < padded.length; i += 4) {
        int v(String c) {
          final idx = _chars.indexOf(c);
          if (idx == -1 && c != '=') throw const FormatException('bad char');
          return idx == -1 ? 0 : idx;
        }

        final c0 = v(padded[i]);
        final c1 = v(padded[i + 1]);
        final c2 = v(padded[i + 2]);
        final c3 = v(padded[i + 3]);
        out.add((c0 << 2) | (c1 >> 4));
        if (padded[i + 2] != '=') {
          out.add(((c1 & 0xF) << 4) | (c2 >> 2));
        }
        if (padded[i + 3] != '=') {
          out.add(((c2 & 0x3) << 6) | c3);
        }
      }
      return Uint8List.fromList(out);
    } catch (_) {
      return null;
    }
  }
}
