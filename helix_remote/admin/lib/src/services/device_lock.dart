import 'package:local_auth/local_auth.dart';

/// The device's own screen lock (biometrics, PIN, pattern or password), used
/// to gate opening the console when the operator turns App lock on. There is
/// no separate PIN to store.
abstract interface class DeviceLock {
  /// Whether the device has a screen lock the console can ask for.
  Future<bool> isSupported();

  /// Asks the operator to unlock; false when they cancel or fail.
  Future<bool> authenticate(String reason);
}

final class LocalAuthDeviceLock implements DeviceLock {
  LocalAuthDeviceLock([LocalAuthentication? auth])
    : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  // `Exception` covers `PlatformException` and `MissingPluginException` (a
  // platform with no screen-lock plugin, such as the web): either way there
  // is no lock to ask for.
  @override
  Future<bool> isSupported() async {
    try {
      return await _auth.isDeviceSupported();
    } on Exception {
      return false;
    }
  }

  @override
  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
    } on Exception {
      return false;
    }
  }
}
