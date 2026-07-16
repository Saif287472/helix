class RemoteAccount {
  const RemoteAccount({
    required this.accountId,
    required this.username,
    required this.identityPublicKey,
    required this.createdAt,
    this.status = 'Active',
  });

  final String accountId;
  final String username;
  final String identityPublicKey;
  final DateTime createdAt;
  final String status;

  Map<String, dynamic> toJson() => {
    'account_id': accountId,
    'username': username,
    'identity_public_key': identityPublicKey,
    'created_at': createdAt.toIso8601String(),
    'status': status,
  };

  factory RemoteAccount.fromJson(Map<String, dynamic> json) {
    return RemoteAccount(
      accountId: json['account_id'] as String,
      username: json['username'] as String,
      identityPublicKey: json['identity_public_key'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      status: json['status'] as String? ?? 'Active',
    );
  }
}
