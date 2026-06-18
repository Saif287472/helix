import 'package:meta/meta.dart';

// ---------------------------------------------------------------------------
// Known / Trusted peer
// ---------------------------------------------------------------------------

@immutable
class KnownPeer {
  final String fingerprint;
  final String lastPublicName;
  final String deviceSuffix;
  final String lastHost;
  final int lastPort;
  final DateTime firstSeenAt;
  final DateTime lastSeenAt;
  final bool trusted;
  final String? nickname;

  const KnownPeer({
    required this.fingerprint,
    required this.lastPublicName,
    required this.deviceSuffix,
    required this.lastHost,
    required this.lastPort,
    required this.firstSeenAt,
    required this.lastSeenAt,
    this.trusted = false,
    this.nickname,
  });

  String get displayName =>
      (trusted && nickname != null) ? nickname! : lastPublicName;

  KnownPeer copyWith({
    String? lastPublicName,
    String? lastHost,
    int? lastPort,
    DateTime? lastSeenAt,
    bool? trusted,
    Object? nickname = _sentinel,
  }) => KnownPeer(
    fingerprint: fingerprint,
    lastPublicName: lastPublicName ?? this.lastPublicName,
    deviceSuffix: deviceSuffix,
    lastHost: lastHost ?? this.lastHost,
    lastPort: lastPort ?? this.lastPort,
    firstSeenAt: firstSeenAt,
    lastSeenAt: lastSeenAt ?? this.lastSeenAt,
    trusted: trusted ?? this.trusted,
    nickname: identical(nickname, _sentinel)
        ? this.nickname
        : nickname as String?,
  );

  static const _sentinel = Object();

  Map<String, dynamic> toJson() => {
    'fingerprint': fingerprint,
    'lastPublicName': lastPublicName,
    'deviceSuffix': deviceSuffix,
    'lastHost': lastHost,
    'lastPort': lastPort,
    'firstSeenAt': firstSeenAt.millisecondsSinceEpoch,
    'lastSeenAt': lastSeenAt.millisecondsSinceEpoch,
    'trusted': trusted,
    'nickname': nickname,
  };

  factory KnownPeer.fromJson(Map<String, dynamic> j) => KnownPeer(
    fingerprint: j['fingerprint'] as String,
    lastPublicName: j['lastPublicName'] as String? ?? '',
    deviceSuffix: j['deviceSuffix'] as String? ?? '',
    lastHost: j['lastHost'] as String? ?? '',
    lastPort: (j['lastPort'] as num?)?.toInt() ?? 0,
    firstSeenAt: DateTime.fromMillisecondsSinceEpoch(j['firstSeenAt'] as int),
    lastSeenAt: DateTime.fromMillisecondsSinceEpoch(j['lastSeenAt'] as int),
    trusted: j['trusted'] as bool? ?? false,
    nickname: j['nickname'] as String?,
  );
}
