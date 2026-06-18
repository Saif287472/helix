import 'package:meta/meta.dart';

@immutable
class DeviceIdentity {
  final String certPem;
  final String privateKeyPem;
  final String staticPublicKeyFingerprint;
  final String deviceSuffix;

  const DeviceIdentity({
    required this.certPem,
    required this.privateKeyPem,
    required this.staticPublicKeyFingerprint,
    required this.deviceSuffix,
  });
}
