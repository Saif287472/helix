import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/notifications/local_notifications.dart';

/// The operating system's permission to show notifications at all.
///
/// Behind an interface so the Notifications page is tested without a platform.
abstract interface class NotificationPermissionSource {
  Future<bool> allowed();

  /// Asks. Returns whether it is allowed afterwards.
  Future<bool> request();
}

final class SystemNotificationPermission
    implements NotificationPermissionSource {
  const SystemNotificationPermission();

  @override
  Future<bool> allowed() async {
    try {
      return await LocalNotifications.allowed();
    } on Object {
      return false;
    }
  }

  @override
  Future<bool> request() async {
    try {
      return await LocalNotifications.request();
    } on Object {
      return false;
    }
  }
}

final notificationPermissionSourceProvider =
    Provider<NotificationPermissionSource>(
      (ref) => const SystemNotificationPermission(),
    );
