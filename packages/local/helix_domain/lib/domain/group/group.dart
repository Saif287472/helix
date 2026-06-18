import 'dart:typed_data';

enum GroupVisibility { publicLobby, private }

enum GroupJoinDecision { approved, denied, blocked }

class GroupMember {
  const GroupMember({
    required this.fingerprint,
    required this.displayName,
    required this.deviceSuffix,
    required this.endpoint,
    required this.joinedAt,
    this.isAdmin = false,
  });

  final String fingerprint;
  final String displayName;
  final String deviceSuffix;
  final String endpoint;
  final DateTime joinedAt;
  final bool isAdmin;

  GroupMember copyWith({
    String? displayName,
    String? deviceSuffix,
    String? endpoint,
    bool? isAdmin,
  }) => GroupMember(
    fingerprint: fingerprint,
    displayName: displayName ?? this.displayName,
    deviceSuffix: deviceSuffix ?? this.deviceSuffix,
    endpoint: endpoint ?? this.endpoint,
    joinedAt: joinedAt,
    isAdmin: isAdmin ?? this.isAdmin,
  );
}

class GroupSnapshot {
  const GroupSnapshot({
    required this.groupId,
    required this.name,
    required this.visibility,
    required this.hostFingerprint,
    required this.hostEndpoint,
    required this.epoch,
    required this.membershipVersion,
    required this.members,
    required this.pending,
    required this.banned,
  });

  final String groupId;
  final String name;
  final GroupVisibility visibility;
  final String hostFingerprint;
  final String hostEndpoint;
  final int epoch;
  final int membershipVersion;
  final List<GroupMember> members;
  final List<GroupMember> pending;
  final Set<String> banned;

  bool get isPublicLobby => visibility == GroupVisibility.publicLobby;
  bool get isPrivate => visibility == GroupVisibility.private;
  int get memberCount => members.length;
}

class GroupInvite {
  const GroupInvite({
    required this.groupId,
    required this.hostEndpoint,
    required this.hostFingerprint,
    required this.epoch,
    required this.expiresAt,
  });

  final String groupId;
  final String hostEndpoint;
  final String hostFingerprint;
  final int epoch;
  final DateTime expiresAt;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

class GroupMessageReceipt {
  const GroupMessageReceipt({
    required this.groupId,
    required this.messageId,
    required this.senderFingerprint,
    required this.encryptedPayload,
  });

  final String groupId;
  final String messageId;
  final String senderFingerprint;
  final Uint8List encryptedPayload;
}
