class RemoteContact {
  const RemoteContact({
    required this.peerAccountId,
    required this.nickname,
    required this.status,
  });

  final String peerAccountId;
  final String nickname;
  final String status; // PendingSent, PendingReceived, Accepted, Blocked

  Map<String, dynamic> toJson() => {
    'peer_account_id': peerAccountId,
    'nickname': nickname,
    'status': status,
  };

  factory RemoteContact.fromJson(Map<String, dynamic> json) {
    return RemoteContact(
      peerAccountId: json['peer_account_id'] as String,
      nickname: json['nickname'] as String,
      status: json['status'] as String,
    );
  }
}

class RemoteContactRequest {
  const RemoteContactRequest({
    required this.requestId,
    required this.peerAccountId,
    required this.direction,
    required this.status,
    required this.updatedAt,
    this.nickname = '',
  });

  final String requestId;
  final String peerAccountId;
  final String direction; // sent, received
  final String status; // Pending, Accepted, Rejected, Cancelled
  final int updatedAt;
  final String nickname;

  Map<String, dynamic> toJson() => {
    'request_id': requestId,
    'peer_account_id': peerAccountId,
    'direction': direction,
    'status': status,
    'updated_at': updatedAt,
    'nickname': nickname,
  };

  factory RemoteContactRequest.fromJson(Map<String, dynamic> json) {
    return RemoteContactRequest(
      requestId: json['request_id'] as String,
      peerAccountId: json['peer_account_id'] as String,
      direction: json['direction'] as String,
      status: json['status'] as String,
      updatedAt: json['updated_at'] as int,
      nickname: json['nickname'] as String? ?? '',
    );
  }
}
