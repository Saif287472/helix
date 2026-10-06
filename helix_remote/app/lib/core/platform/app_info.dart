import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What the About page says about this build.
///
/// The version is a constant rather than a plugin call so it works on every
/// platform and in every test; `test/settings/app_info_test.dart` keeps it
/// equal to the `version:` line of `pubspec.yaml`.
final class AppInfo {
  const AppInfo({this.version = kAppVersion, this.name = 'Helix Remote'});

  final String version;
  final String name;
}

/// Keep equal to `version:` in `pubspec.yaml` (a test checks).
const kAppVersion = '2.0.0';

final appInfoProvider = Provider<AppInfo>((ref) => const AppInfo());
