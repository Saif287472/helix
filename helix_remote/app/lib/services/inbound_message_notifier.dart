import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:helix_remote/app/remote_messaging_service.dart';
import 'package:helix_remote/services/app_logger.dart';
import 'package:helix_remote/services/local_notification_service.dart';
import 'package:helix_remote_sync/helix_remote_sync.dart';

/// Shows a notification for a message that arrives over the live connection
/// while the app is not in front - the phone is locked, or another app is
/// open. A push (FCM) covers the app being closed; this covers it being
/// alive in the background, which needs no Google service at all.
///
/// Each message is announced at most once, and only the first time this
/// device sees it: edits, reactions and receipts touch the same message id
/// again and must not re-notify. Messages this account sent (from any of its
/// devices) never notify.
class InboundMessageNotifier {
  InboundMessageNotifier(
    this._ms, {
    bool Function()? isInForeground,
    Future<void> Function({
      required String notificationKey,
      required String title,
      required String body,
    })?
    show,
    DateTime Function()? clock,
  }) : _isInForeground = isInForeground ?? _appIsInForeground,
       _show = show ?? _showSystemNotification,
       _clock = clock ?? DateTime.now;

  final RemoteMessagingService _ms;
  final bool Function() _isInForeground;
  final Future<void> Function({
    required String notificationKey,
    required String title,
    required String body,
  })
  _show;
  final DateTime Function() _clock;

  /// A message older than this when it arrives is history being filled in
  /// (a backup restore, a long catch-up), not something to ring about.
  static const maxAge = Duration(hours: 6);

  final _seen = <String>{};
  StreamSubscription<RemoteSyncChange>? _sub;

  void start() {
    _sub ??= _ms.changes.listen(_onChange);
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
  }

  Future<void> _onChange(RemoteSyncChange change) async {
    final messageId = change.messageId;
    if (messageId == null ||
        !change.areas.contains(RemoteSyncChangeArea.messages) ||
        !_seen.add(messageId)) {
      return;
    }
    if (_isInForeground()) return;
    try {
      final message = await _ms.messageById(messageId);
      if (message == null) return;
      final me = _ms.currentAccountId;
      if (me == null || message.senderAccountId == me) return;
      final sentAt = DateTime.fromMillisecondsSinceEpoch(message.timestamp);
      if (_clock().difference(sentAt) > maxAge) return;

      final conversationId = message.conversationId;
      final previewsAllowed =
          _ms.db.getNotificationPreviewsEnabled() &&
          !_ms.db.getConversationPrivacy(conversationId).isLocked;
      await _show(
        notificationKey: messageId,
        title: _titleFor(conversationId, message.senderAccountId),
        body: previewsAllowed ? _previewOf(message) : 'New message',
      );
    } catch (e) {
      AppLogger.instance.warn(
        'NOTIFY',
        'message notification failed: ${e.runtimeType}',
      );
    }
  }

  String _titleFor(String conversationId, String senderAccountId) {
    for (final c in _ms.conversationList()) {
      if (c.conversationId != conversationId) continue;
      if (c.type != 'DIRECT' && c.title.isNotEmpty) {
        return '${_ms.personName(senderAccountId)} @ ${c.title}';
      }
      break;
    }
    return _ms.personName(senderAccountId);
  }

  static String _previewOf(RemoteDecryptedMessage m) {
    if (m.viewOnce) return 'View-once message';
    if (m.text.trim().isNotEmpty) return m.text.trim();
    if (m.media != null) return 'Photo or video';
    if (m.attachment != null) return 'File';
    if (m.poll != null) return 'Poll';
    if (m.location != null) return 'Location';
    if (m.sticker != null) return 'Sticker';
    if (m.event != null) return 'Event';
    return 'New message';
  }

  static bool _appIsInForeground() =>
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  static Future<void> _showSystemNotification({
    required String notificationKey,
    required String title,
    required String body,
  }) => LocalNotificationService.showMessage(
    notificationKey: notificationKey,
    title: title,
    body: body,
  );
}
