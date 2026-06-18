import 'package:helix_groups/domain/lobby_constants.dart';

class LobbyMember {
  const LobbyMember({
    required this.fp,
    required this.name,
    required this.suffix,
  });

  final String fp;
  final String name;
  final String suffix;

  Map<String, dynamic> toJson() => {'fp': fp, 'name': name, 'suffix': suffix};

  factory LobbyMember.fromJson(Map<String, dynamic> j) => LobbyMember(
        fp: j['fp'] as String? ?? '',
        name: j['name'] as String? ?? '',
        suffix: j['suffix'] as String? ?? '',
      );

  LobbyMember copyWith({String? fp, String? name, String? suffix}) => LobbyMember(
        fp: fp ?? this.fp,
        name: name ?? this.name,
        suffix: suffix ?? this.suffix,
      );
}

class LobbyState {
  const LobbyState({
    required this.sessionId,
    required this.members,
    required this.localFp,
    required this.hostFp,
    required this.generation,
    required this.membershipVersion,
  });

  final String            sessionId;
  final List<LobbyMember> members;
  final String            localFp;
  final String            hostFp;
  final int               generation;
  final int               membershipVersion;

  bool get isHost => localFp == hostFp;
  int  get memberCount => members.length;

  LobbyMember? memberByFp(String fp) {
    for (final m in members) {
      if (m.fp == fp) return m;
    }
    return null;
  }

  LobbyState copyWith({
    String?            sessionId,
    List<LobbyMember>? members,
    String?            localFp,
    String?            hostFp,
    int?               generation,
    int?               membershipVersion,
  }) =>
      LobbyState(
        sessionId:         sessionId         ?? this.sessionId,
        members:           members           ?? this.members,
        localFp:           localFp           ?? this.localFp,
        hostFp:            hostFp            ?? this.hostFp,
        generation:        generation        ?? this.generation,
        membershipVersion: membershipVersion ?? this.membershipVersion,
      );
}

class LobbyMessage {
  const LobbyMessage({
    required this.msgId,
    required this.senderFp,
    required this.senderName,
    required this.text,
    required this.sentAt,
  });

  final String   msgId;
  final String   senderFp;
  final String   senderName;
  final String   text;
  final DateTime sentAt;
}

// ---------------------------------------------------------------------------
// Frame builder helpers — shared by discovery and service
// ---------------------------------------------------------------------------

Map<String, dynamic> buildEnvelope({
  required String type,
  String sid = '',
  int gen = -1,
}) =>
    {
      'v':   kLobbyProtocolVersion,
      't':   type,
      if (sid.isNotEmpty) 'sid': sid,
      if (gen >= 0) 'gen': gen,
    };

List<Map<String, dynamic>> membersToJson(List<LobbyMember> members) =>
    members.map((m) => m.toJson()).toList();

List<LobbyMember> membersFromJson(dynamic raw) {
  if (raw is! List) return [];
  return raw
      .whereType<Map<Object?, Object?>>()
      .map((m) => LobbyMember.fromJson(Map<String, dynamic>.from(m)))
      .toList();
}
