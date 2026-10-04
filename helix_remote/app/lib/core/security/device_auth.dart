import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

/// Asks the phone to prove its owner is holding it (fingerprint, face, PIN).
///
/// Used before the two things that hand over the account: approving a new
/// device, and turning the app lock on. Behind an interface so a test answers
/// without a biometric prompt. [AppLock] has its own prompt for the lock
/// screen; this one is for one-off confirmations.
abstract interface class DeviceAuthenticator {
  /// Whether the phone has a screen lock to ask with at all.
  Future<bool> isAvailable();

  /// Shows the system prompt with [reason]. True when the owner passed it.
  Future<bool> confirm(String reason);
}

final class SystemDeviceAuthenticator implements DeviceAuthenticator {
  const SystemDeviceAuthenticator();

  @override
  Future<bool> isAvailable() async {
    try {
      return await LocalAuthentication().isDeviceSupported();
    } on Object {
      return false;
    }
  }

  @override
  Future<bool> confirm(String reason) async {
    try {
      return await LocalAuthentication().authenticate(
        localizedReason: reason,
        persistAcrossBackgrounding: true,
      );
    } on Object {
      return false;
    }
  }
}

final deviceAuthenticatorProvider = Provider<DeviceAuthenticator>(
  (ref) => const SystemDeviceAuthenticator(),
);
