import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

/// The server-side cap on `device_name` (see the backend's device rename
/// handler). Labels are clipped to it rather than rejected.
const _maxDeviceNameLength = 80;

/// The name every device registered under before this label existed:
/// `Dev ` plus the first eight characters of the device id (`dev_68b8`). It
/// told an admin nothing, so a device still carrying it is renamed once.
final _legacyDefaultName = RegExp(r'^Dev dev_[0-9a-f]{4}$');

bool isLegacyDefaultDeviceName(String name) =>
    _legacyDefaultName.hasMatch(name.trim());

/// A human-readable label for this device, e.g. `Samsung SM-G990B2
/// (Android 14)`.
///
/// Hardware model and OS only. The OS-level device name (`Settings.Global
/// .DEVICE_NAME`, the computer name) is deliberately not used: users often
/// put their own name there, and a device name is visible to contacts in
/// prekey bundles, not just to the admin.
///
/// ASCII-only because the name is part of the signed registration
/// transcript. Falls back to [fallback] when the platform cannot be read.
Future<String> describeThisDevice({required String fallback}) async {
  try {
    final info = DeviceInfoPlugin();
    final String label;
    if (Platform.isAndroid) {
      final a = await info.androidInfo;
      final maker = _titleCase(a.manufacturer);
      final model = a.model.trim();
      // Some OEMs already prefix the model with the brand ("Pixel" aside).
      final hardware = model.toLowerCase().startsWith(maker.toLowerCase())
          ? model
          : '$maker $model';
      label = '$hardware (Android ${a.version.release})';
    } else if (Platform.isIOS) {
      final i = await info.iosInfo;
      label = '${i.modelName} (iOS ${i.systemVersion})';
    } else if (Platform.isWindows) {
      final w = await info.windowsInfo;
      label = 'Windows PC (${w.productName})';
    } else if (Platform.isMacOS) {
      final m = await info.macOsInfo;
      label = '${m.model} (macOS ${m.osRelease})';
    } else if (Platform.isLinux) {
      final l = await info.linuxInfo;
      label = 'Linux PC (${l.prettyName})';
    } else {
      return fallback;
    }
    final ascii = label.replaceAll(RegExp(r'[^\x20-\x7E]'), '').trim();
    if (ascii.isEmpty) return fallback;
    return ascii.length > _maxDeviceNameLength
        ? ascii.substring(0, _maxDeviceNameLength)
        : ascii;
  } catch (_) {
    return fallback;
  }
}

String _titleCase(String value) {
  final v = value.trim();
  if (v.isEmpty) return v;
  return v[0].toUpperCase() + v.substring(1);
}
