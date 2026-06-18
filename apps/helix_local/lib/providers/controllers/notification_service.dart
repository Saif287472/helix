import 'dart:async';

import 'package:helix_domain/core/product_descriptor.dart';
import 'package:helix_protocol/application/contracts/gateways.dart';
import 'package:helix_platform/infrastructure/platform/platform_notification_gateway.dart';

export 'package:helix_protocol/application/contracts/gateways.dart'
    show NotificationActionIntent;

class NotificationService {
  final NotificationGateway _notificationGateway;

  NotificationService({NotificationGateway? notificationGateway})
    : _notificationGateway = notificationGateway ?? _defaultLocalGateway();

  Stream<NotificationActionIntent> get actions => _notificationGateway.actions;
  Stream<String> get taps => _notificationGateway.taps;

  Future<void> init() async {
    await _notificationGateway.init();
  }

  Future<void> showForegroundServiceNotification() async {
    await _notificationGateway.showForegroundServiceNotification();
  }

  Future<void> showIncomingRequest(
    String requesterName,
    String requestId,
  ) async {
    await _notificationGateway.showIncomingRequest(requesterName, requestId);
  }

  Future<void> showNewMessage(
    String? senderName,
    bool showSender, {
    String? threadId,
    bool soundEnabled = true,
  }) async {
    await _notificationGateway.showNewMessage(
      senderName,
      showSender,
      threadId: threadId,
      soundEnabled: soundEnabled,
    );
  }

  Future<void> showIncomingCall(String callId, String peerDisplayName) async {
    await _notificationGateway.showIncomingCall(callId, peerDisplayName);
  }

  Future<void> cancelIncomingCall(String callId) async {
    await _notificationGateway.cancelIncomingCall(callId);
  }

  Future<void> cancelNotification(int id) async {
    await _notificationGateway.cancelNotification(id);
  }

  Future<void> cancelAll() async {
    await _notificationGateway.cancelAll();
  }

  void dispose() {
    _notificationGateway.dispose();
  }
}

PlatformNotificationGateway _defaultLocalGateway() {
  const d = LocalProductDescriptor();
  return PlatformNotificationGateway(
    appName: d.displayName,
    appUserModelId: d.packageId,
    windowsNotificationGuid: d.windowsNotificationGuid,
    channelPrefix: d.logNamespace,
    methodChannelNamespace: d.methodChannelNamespace,
  );
}
