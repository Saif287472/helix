import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Tracks whether the user has been through the first-launch server-choice
/// screen (Helix Global / personal server / host-your-own / offline), so it
/// is never shown again once completed - including for installs that
/// already had a server configured before this screen existed.
class OnboardingStateStore {
  const OnboardingStateStore._();
  static const OnboardingStateStore instance = OnboardingStateStore._();
  static const _key = 'helix_remote_first_launch_completed';
  final _storage = const FlutterSecureStorage();

  Future<bool> isFirstLaunchCompleted() async {
    final value = await _storage.read(key: _key);
    return value == 'true';
  }

  Future<void> markFirstLaunchCompleted() =>
      _storage.write(key: _key, value: 'true');
}
