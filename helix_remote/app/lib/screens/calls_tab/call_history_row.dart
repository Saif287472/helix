part of '../calls_tab_screen.dart';

class _CallHistoryRow {
  const _CallHistoryRow({
    required this.callId,
    required this.peerId,
    required this.peerName,
    required this.identifier,
    required this.direction,
    required this.outcome,
    required this.isVideo,
    required this.timestamp,
    required this.dateTime,
    required this.timeLabel,
    required this.durationSeconds,
    required this.durationLabel,
    this.repeatCount = 1,
  });

  final String callId;
  final String peerId;
  final String peerName;
  final String identifier;
  final String direction;
  final String outcome;
  final bool isVideo;
  final int timestamp;
  final DateTime dateTime;
  final String timeLabel;
  final int durationSeconds;
  final String durationLabel;
  final int repeatCount;

  bool get isMissed =>
      direction.toUpperCase() == kCallDirectionMissed ||
      outcome.toLowerCase().contains('missed');

  bool get isNotAnswered =>
      durationSeconds == 0 &&
      (direction.toUpperCase() == kCallDirectionOutgoing ||
          outcome.toLowerCase() == 'declined' ||
          outcome.toLowerCase() == 'failed' ||
          outcome.toLowerCase() == 'busy' ||
          outcome.toLowerCase() == 'ended');

  String get displayTitle =>
      repeatCount > 1 ? '$peerName ($repeatCount)' : peerName;

  _CallHistoryRow copyWith({int? repeatCount}) {
    return _CallHistoryRow(
      callId: callId,
      peerId: peerId,
      peerName: peerName,
      identifier: identifier,
      direction: direction,
      outcome: outcome,
      isVideo: isVideo,
      timestamp: timestamp,
      dateTime: dateTime,
      timeLabel: timeLabel,
      durationSeconds: durationSeconds,
      durationLabel: durationLabel,
      repeatCount: repeatCount ?? this.repeatCount,
    );
  }

  String get directionLabel {
    if (isMissed) return 'Missed';
    return switch (direction.toUpperCase()) {
      kCallDirectionOutgoing => 'Outgoing',
      _ => 'Incoming',
    };
  }

  String get infoTitle {
    if (isMissed || isNotAnswered) return directionLabel;
    return directionLabel;
  }

  IconData get directionIcon {
    if (isMissed) return Icons.call_missed;
    return switch (direction.toUpperCase()) {
      kCallDirectionOutgoing => Icons.call_made,
      _ => Icons.call_received,
    };
  }
}

Color _avatarColor(String name, ColorScheme cs) {
  final colors = [
    cs.primaryContainer,
    cs.secondaryContainer,
    cs.tertiaryContainer,
    HelixColorTokens.cFFD7ECFF,
    HelixColorTokens.cFFFFE0CC,
    HelixColorTokens.cFFDFF6DE,
  ];
  return colors[name.hashCode.abs() % colors.length];
}

String _initials(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return '?';
  final parts = trimmed.split(RegExp(r'\s+'));
  if (parts.length >= 2) {
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
  return trimmed.substring(0, trimmed.length.clamp(1, 2)).toUpperCase();
}
