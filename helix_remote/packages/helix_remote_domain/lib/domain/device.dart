class RemoteDevice {
  const RemoteDevice({
    required this.deviceId,
    required this.deviceName,
    required this.deviceSigningPublicKey,
    required this.deviceAgreementPublicKey,
    required this.createdAt,
    this.status = 'Active',
  });

  final String deviceId;
  final String deviceName;
  final String deviceSigningPublicKey;
  final String deviceAgreementPublicKey;
  final DateTime createdAt;
  final String status;

  String get devicePublicKey => deviceAgreementPublicKey;

  Map<String, dynamic> toJson() => {
    'device_id': deviceId,
    'device_name': deviceName,
    'device_signing_public_key': deviceSigningPublicKey,
    'device_agreement_public_key': deviceAgreementPublicKey,
    'created_at': createdAt.toIso8601String(),
    'status': status,
  };

  factory RemoteDevice.fromJson(Map<String, dynamic> json) {
    final legacyDevicePublicKey = json['device_public_key'] as String?;
    final createdAtValue = json['created_at'];
    return RemoteDevice(
      deviceId: json['device_id'] as String,
      deviceName: json['device_name'] as String,
      deviceSigningPublicKey:
          json['device_signing_public_key'] as String? ??
          legacyDevicePublicKey ??
          '',
      deviceAgreementPublicKey:
          json['device_agreement_public_key'] as String? ??
          legacyDevicePublicKey ??
          '',
      createdAt: createdAtValue is int
          ? DateTime.fromMillisecondsSinceEpoch(createdAtValue)
          : DateTime.parse(createdAtValue as String),
      status: json['status'] as String? ?? 'Active',
    );
  }
}
