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
