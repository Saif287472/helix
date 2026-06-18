import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:helix_domain/core/constants.dart';
import 'package:helix_domain/domain/models.dart';

class MdnsDiscovery {
  bool _running = false;
  bool _discoverable = false;

  String _sessionId = '';
  String _displayName = '';
  String _deviceSuffix = '';

  // Platform channels
  static const _method = MethodChannel(kMdnsMethodChannel);
  static const _event = EventChannel(kMdnsEventChannel);

  // Streams
  final StreamController<Peer> _discoveredController =
      StreamController<Peer>.broadcast();
  final StreamController<String> _errorController =
      StreamController<String>.broadcast();

  Stream<Peer> get discovered => _discoveredController.stream;
  Stream<String> get errors => _errorController.stream;

  StreamSubscription<dynamic>? _eventSub;

  // ---------------------------------------------------------------------------
  // Start
  // ---------------------------------------------------------------------------

  Future<void> start(
    String sessionId,
    String displayName,
    String deviceSuffix,
    int tcpPort,
    bool discoverable,
  ) async {
    if (_running) return;
    _sessionId = sessionId;
    _displayName = displayName;
    _deviceSuffix = deviceSuffix;
    _discoverable = discoverable;
    _running = true;

    if (!_platformSupported) {
      // UDP handles discovery on unsupported platforms.
      return;
    }

    try {
      await _method.invokeMethod<void>('start', {
        'sessionId': sessionId,
        'displayName': displayName,
        'deviceSuffix': deviceSuffix,
        'port': tcpPort,
        'discoverable': discoverable,
      });

      _eventSub = _event.receiveBroadcastStream().listen(
        _onPlatformEvent,
        onError: (Object e) {
          if (!_errorController.isClosed) {
            _errorController.add('mDNS event error: $e');
          }
        },
      );
    } on PlatformException catch (e) {
      _running = false;
      if (!_errorController.isClosed) {
        _errorController.add('mDNS start failed: ${e.message}');
      }
    } on MissingPluginException {
      _running = false;
      // Native plugin not registered on this platform — silent fallback to UDP.
    }
  }

  // ---------------------------------------------------------------------------
  // Stop
  // ---------------------------------------------------------------------------

  Future<void> stop() async {
    _running = false;
    await _eventSub?.cancel();
    _eventSub = null;

    if (!_platformSupported) return;

    try {
      await _method.invokeMethod<void>('stop');
    } on PlatformException catch (_) {
      // Best-effort; ignore errors during stop.
    } on MissingPluginException {
      // no-op
    }
  }

  // ---------------------------------------------------------------------------
  // Update discoverability at runtime
  // ---------------------------------------------------------------------------

  Future<void> updateDiscoverability(bool discoverable) async {
    _discoverable = discoverable;
    if (!_running || !_platformSupported) return;

    try {
      await _method.invokeMethod<void>('updateDiscoverability', {
        'discoverable': discoverable,
      });
    } on PlatformException catch (_) {
      // Best-effort; ignore errors during discoverability toggle.
    } on MissingPluginException {
      // no-op — native plugin absent on this platform.
    }
  }

  // ---------------------------------------------------------------------------
  // TXT record helpers (retained for diagnostics / future native advertisement)
  // ---------------------------------------------------------------------------

  String get localTxtRecord => [
    'v=$kProtocolMajor.$kProtocolMinor',
    'sid=$_sessionId',
    'sfx=$_deviceSuffix',
    'disc=${_discoverable ? 1 : 0}',
  ].join('\n');

  String get localServiceInstanceName =>
      '$_displayName.$kMdnsServiceType.local';

  // ---------------------------------------------------------------------------
  // Dispose
  // ---------------------------------------------------------------------------

  Future<void> dispose() async {
    await stop();
    await _discoveredController.close();
    await _errorController.close();
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  static bool get _platformSupported => Platform.isWindows;

  void _onPlatformEvent(dynamic event) {
    if (event is! Map) return;
    final type = event['type'] as String?;

    if (type == 'discovered') {
      final sessionId = event['sessionId'] as String? ?? '';
      final displayName = event['displayName'] as String? ?? '';
      final deviceSuffix = event['deviceSuffix'] as String? ?? '';
      final host = event['host'] as String? ?? '';
      final port = (event['port'] as int?) ?? 0;
      final pmaj = (event['pmaj'] as int?) ?? kProtocolMajor;
      final pmin = (event['pmin'] as int?) ?? kProtocolMinor;

      if (sessionId.isEmpty ||
          displayName.isEmpty ||
          host.isEmpty ||
          port <= 0) {
        return;
      }

      final peer = Peer(
        sessionId: sessionId,
        displayName: displayName,
        deviceSuffix: deviceSuffix,
        host: host,
        port: port,
        source: PeerSource.mdns,
        seenAt: DateTime.now(),
        protocolMajor: pmaj,
        protocolMinor: pmin,
      );

      if (!_discoveredController.isClosed) {
        _discoveredController.add(peer);
      }
    }
  }
}
