import 'dart:convert';

import 'package:flutter/material.dart' show IconData, Icons;
import 'package:helix_remote/core/people/people_names.dart';
import 'package:helix_remote/core/format/labels.dart';
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// What a stored message *means*, shared by the chat list (its preview line)
/// and the conversation (its bubbles): which kind of thing it is, the words
/// for a notice, the delivery tick.
///
/// Everything here is pure: a row (and the people table) in, plain values out.

/// The row's JSON `payload` as a map; empty when there is none or it is not
/// readable (a row must never fail to draw because of its payload).
Map<String, Object?> payloadOf(MessageRow row) {
  final raw = row.payload;
  if (raw == null || raw.isEmpty) return const {};
  try {
    final decoded = jsonDecode(raw);
    return decoded is Map ? decoded.cast<String, Object?>() : const {};
  } on Object {
    return const {};
  }
}

/// The wire name of a media message's first item (`image`, `video`,
/// `voice_note`, ...). An upload still in flight has no payload yet; it is
/// shown as a photo, which is what is most often being sent.
String mediaKindOf(MessageRow row) {
  final items = payloadOf(row)['items'];
  if (items is List && items.isNotEmpty && items.first is Map) {
    final kind = (items.first as Map)['kind'];
    if (kind is String) return kind;
  }
  return 'image';
}

/// The list-preview kind of [row].
HelixPreviewKind previewKindOf(MessageRow row) {
  if (row.deletedAt != null) return HelixPreviewKind.deleted;
  switch (row.kind) {
    case 'text':
      return HelixPreviewKind.text;
    case 'media':
      return switch (mediaKindOf(row)) {
        'video' || 'video_note' => HelixPreviewKind.video,
        'gif' => HelixPreviewKind.gif,
        'voice_note' => HelixPreviewKind.voiceNote,
        'document' => HelixPreviewKind.document,
        _ => HelixPreviewKind.image,
      };
    case 'sticker':
      return HelixPreviewKind.sticker;
    case 'location' || 'live_location':
      return HelixPreviewKind.location;
    case 'contact':
      return HelixPreviewKind.contact;
    case 'poll' || 'event':
      return HelixPreviewKind.poll;
    case 'call_log':
      return HelixPreviewKind.call;
    case 'undecryptable':
      return HelixPreviewKind.undecryptable;
    case 'unsupported':
      return HelixPreviewKind.unsupported;
    default:
      return HelixPreviewKind.text;
  }
}

/// The delivery state shown as ticks, or null for a message that is not ours.
HelixDeliveryStatus? deliveryStatusOf(MessageRow row) {
  if (!row.outgoing) return null;
  return switch (row.status) {
    MessageStatus.pending => HelixDeliveryStatus.pending,
    MessageStatus.sent => HelixDeliveryStatus.sent,
    MessageStatus.delivered => HelixDeliveryStatus.delivered,
    MessageStatus.read || MessageStatus.viewed => HelixDeliveryStatus.read,
    MessageStatus.failed => HelixDeliveryStatus.failed,
    MessageStatus.received => HelixDeliveryStatus.sent,
  };
}

/// Message kinds that are notices in the timeline rather than bubbles.
bool isNoticeKind(String kind) => kind == 'system' || kind == 'call_log';

/// The text of a text-like preview: the message text, a caption, a poll
/// question, a place, a contact's name. Empty when the kind speaks for itself
/// ("Photo", "Voice message").
String previewTextOf(MessageRow row) {
  if (row.deletedAt != null) return '';
  final payload = payloadOf(row);
  switch (row.kind) {
    case 'poll':
      return (payload['question'] as String?) ?? '';
    case 'event':
      return (payload['title'] as String?) ?? '';
    case 'location':
      return (payload['label'] as String?) ?? '';
    case 'contact':
      return (payload['name'] as String?) ?? '';
    case 'system':
    case 'call_log':
      return '';
    default:
      return (row.body ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}

/// A notice's words, or null when this build does not know the kind (it is
/// then left out of the timeline rather than shown as raw text).
///
/// [selfId] is this account: it reads "You" rather than a name.
String? systemNoticeText(
  MessageRow row, {
  required String? selfId,
  required PeopleDirectory people,
}) {
  if (row.kind == 'call_log') return callLogText(row);
  if (row.kind != 'system') return null;
  final payload = payloadOf(row);
  final kind = payload['kind'] as String?;
  final actorId = (payload['actor'] as String?) ?? row.sender;
  String name(String account) =>
      account == selfId ? 'You' : people.displayOf(account);
  final members = [
    for (final m in (payload['members'] as List? ?? const []))
      if (m is String) name(m),
  ];
  final actor = name(actorId);
  final who = _list(members);
  switch (kind) {
    case 'timer_changed':
      final seconds = (payload['seconds'] as num?)?.toInt() ?? 0;
      final by = row.outgoing ? 'You' : people.displayOf(row.sender);
      return seconds <= 0
          ? '$by turned off disappearing messages'
          : '$by set disappearing messages to ${describeDisappearing(seconds)}';
    case 'safety_number_changed':
      return 'Your safety number with ${people.displayOf(row.sender)} changed';
    case 'group_created':
      return '$actor created this group';
    case 'member_added':
      return who.isEmpty ? '$actor added someone' : '$actor added $who';
    case 'member_joined':
      return who.isEmpty ? '$actor joined' : '$who joined';
    case 'member_removed':
      return who.isEmpty ? '$actor removed someone' : '$actor removed $who';
    case 'member_left':
      return who.isEmpty ? '$actor left' : '$who left';
    case 'role_changed':
      return who.isEmpty
          ? '$actor changed a role'
          : '$actor changed the role of $who';
    case 'group_settings_changed':
      return '$actor changed the group settings';
    case 'group_renamed':
      final title = payload['name'] as String?;
      return title == null || title.isEmpty
          ? '$actor renamed the group'
          : '$actor renamed the group to "$title"';
    case 'group_picture_changed':
      return '$actor changed the group picture';
    case 'join_requested':
      return '$actor asked to join the group';
    case 'you_were_removed':
      return 'You were removed from this group';
    case 'you_left':
      return 'You left this group';
    case 'group_deleted':
      return 'This group was deleted';
  }
  return null;
}

/// "Missed voice call", "Video call, 2:13", "No answer".
String callLogText(MessageRow row) {
  final payload = payloadOf(row);
  final video = payload['media'] == 'video';
  final kind = video ? 'video call' : 'voice call';
  final seconds = (payload['duration_s'] as num?)?.toInt();
  switch (payload['outcome']) {
    case 'answered':
      final label = video ? 'Video call' : 'Voice call';
      return seconds == null || seconds <= 0
          ? label
          : '$label, ${formatDurationMs(seconds * 1000)}';
    case 'missed':
      return row.outgoing ? 'No answer' : 'Missed $kind';
    case 'declined':
      return row.outgoing ? 'Call declined' : 'Declined $kind';
    default:
      return 'Call failed';
  }
}

/// The glyph on a call log notice.
IconData callLogIcon(MessageRow row) {
  final payload = payloadOf(row);
  if (payload['outcome'] == 'missed' && !row.outgoing) return Icons.call_missed;
  return payload['media'] == 'video' ? Icons.videocam : Icons.call;
}

String _list(List<String> names) {
  if (names.isEmpty) return '';
  if (names.length == 1) return names.first;
  return '${names.take(names.length - 1).join(', ')} and ${names.last}';
}
