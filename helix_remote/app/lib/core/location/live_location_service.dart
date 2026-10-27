import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/chat/chat_gateway.dart';
import 'package:helix_remote/core/platform/chat_platform.dart';
import 'package:helix_remote/core/platform/location_source.dart';

/// Sends this phone's place into a chat, once or as a live share, and keeps
/// the shares running while the app lives.
///
/// Location is read only for what the person started. One position stream
/// serves every running share, and it is closed when the last share ends.
/// A share ends by itself at its time, when the person stops it, or when the
/// engine says it is over (the chat was deleted, the account signed out).
final class LiveLocationService {
  LiveLocationService({
    required Future<ChatGateway> Function() gateway,
    required LocationSource source,
    required DateTime Function() now,
    this.minInterval = const Duration(seconds: 10),
  }) : _gateway = gateway,
       _source = source,
       _now = now;

  final Future<ChatGateway> Function() _gateway;
  final LocationSource _source;
  final DateTime Function() _now;

  /// The least time between two updates of a share.
  final Duration minInterval;

  /// Running shares: the message row, and when each ends.
  final Map<int, DateTime> _ends = {};
  StreamSubscription<LocationFix>? _tracking;
  Timer? _clock;
  DateTime? _lastUpdate;
  bool _disposed = false;

  /// The rows of the shares running now.
  Set<int> get running => {..._ends.keys};

  /// Sends the phone's place once. Null when it went, else the sentence to
  /// show.
  Future<String?> sendOnce(String conversationId) async {
    final fix = await _fixOrReason();
    if (fix.reason != null) return fix.reason;
    try {
      await (await _gateway()).sendLocation(
        conversationId,
        latE7: fix.fix!.latE7,
        lngE7: fix.fix!.lngE7,
        accuracyM: fix.fix!.accuracyM,
      );
      return null;
    } on Object {
      return 'The location could not be sent.';
    }
  }

  /// Starts sharing live for [duration]. Null when it started, else the
  /// sentence to show.
  Future<String?> startLive(String conversationId, Duration duration) async {
    final fix = await _fixOrReason();
    if (fix.reason != null) return fix.reason;
    try {
      final row = await (await _gateway()).startLiveLocation(
        conversationId,
        latE7: fix.fix!.latE7,
        lngE7: fix.fix!.lngE7,
        accuracyM: fix.fix!.accuracyM,
        duration: duration,
      );
      _ends[row.localRowid] = _now().add(duration);
      _lastUpdate = _now();
      _track();
      return null;
    } on Object {
      return 'Live location could not be started.';
    }
  }

  /// Stops sharing in [rowid]: the chat is told, and the place leaves this
  /// phone's copy.
  Future<void> stop(int rowid) async {
    _ends.remove(rowid);
    try {
      await (await _gateway()).stopLiveLocation(rowid);
    } on Object {
      // Already over.
    }
    _settle();
  }

  /// Carries on the shares that were running when the app last closed, when
  /// location is still allowed (it never asks again here).
  Future<void> resume() async {
    try {
      final shares = await (await _gateway()).activeLiveShares();
      if (shares.isEmpty) return;
      if (await _source.access(ask: false) != LocationAccess.granted) return;
      for (final row in shares) {
        final ends = _endOf(row.payload);
        if (ends != null) _ends[row.localRowid] = ends;
      }
      _track();
    } on Object {
      // Offline or signed out: nothing to carry on.
    }
  }

  void dispose() {
    _disposed = true;
    unawaited(_tracking?.cancel());
    _clock?.cancel();
    _tracking = null;
    _clock = null;
  }

  static final _expiresAt = RegExp(r'"expires_at"\s*:\s*(\d+)');

  static DateTime? _endOf(String? payload) {
    final ms = int.tryParse(
      _expiresAt.firstMatch(payload ?? '')?.group(1) ?? '',
    );
    return ms == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  }

  Future<({LocationFix? fix, String? reason})> _fixOrReason() async {
    final access = await _source.access(ask: true);
    switch (access) {
      case LocationAccess.granted:
        break;
      case LocationAccess.serviceOff:
        return (
          fix: null,
          reason: 'Turn on location on your phone to share it.',
        );
      case LocationAccess.denied:
      case LocationAccess.deniedForever:
        return (
          fix: null,
          reason: 'Allow location access in your phone’s settings to share it.',
        );
    }
    final fix = await _source.current();
    return fix == null
        ? (
            fix: null,
            reason: 'Your location could not be found. Try again in the open.',
          )
        : (fix: fix, reason: null);
  }

  void _track() {
    if (_disposed || _ends.isEmpty) return;
    _tracking ??= _source
        .track(interval: minInterval)
        .listen(_onFix, onError: (Object _) {});
    _clock ??= Timer.periodic(const Duration(seconds: 30), (_) => _prune());
  }

  Future<void> _onFix(LocationFix fix) async {
    final now = _now();
    final last = _lastUpdate;
    if (last != null && now.difference(last) < minInterval) return;
    _lastUpdate = now;
    _prune();
    if (_ends.isEmpty) return;
    final gateway = await _gateway();
    for (final rowid in running) {
      try {
        final sent = await gateway.updateLiveLocation(
          rowid,
          latE7: fix.latE7,
          lngE7: fix.lngE7,
          accuracyM: fix.accuracyM,
        );
        if (!sent) _ends.remove(rowid);
      } on Object {
        // Try again with the next reading.
      }
    }
    _settle();
  }

  void _prune() {
    final now = _now();
    _ends.removeWhere((_, ends) => !ends.isAfter(now));
    _settle();
  }

  /// Closes the position stream and the clock when nothing is shared.
  void _settle() {
    if (_ends.isNotEmpty) return;
    unawaited(_tracking?.cancel());
    _clock?.cancel();
    _tracking = null;
    _clock = null;
  }
}

/// The running shares of this account. Alive for as long as the app is: a
/// share must not end because a screen closed.
final liveLocationServiceProvider = Provider<LiveLocationService>((ref) {
  final service = LiveLocationService(
    gateway: () => ref.read(chatGatewayProvider.future),
    source: ref.watch(locationSourceProvider),
    now: ref.watch(clockProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});
