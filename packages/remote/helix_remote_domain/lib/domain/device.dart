class RemoteDevice {
  const RemoteDevice({
    required this.deviceId,
    required this.deviceName,
    required this.devicePublicKey,
    required this.createdAt,
    this.status = 'Active',
  });

  final int deviceId;
  final String deviceName;
  final String devicePublicKey;
  final DateTime createdAt;
  final String status;

  Map<String, dynamic> toJson() => {
    'device_id': deviceId,
    'device_name': deviceName,
    'device_public_key': devicePublicKey,
    'created_at': createdAt.toIso8601String(),
    'status': status,
  };

  factory RemoteDevice.fromJson(Map<String, dynamic> json) {
    return RemoteDevice(
      deviceId: json['device_id'] as int,
      deviceName: json['device_name'] as String,
      devicePublicKey: json['device_public_key'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      status: json['status'] as String? ?? 'Active',
    );
  }
}
