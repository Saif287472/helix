import 'package:drift/drift.dart';

/// Stored as `INTEGER` epoch milliseconds (UTC). drift's own `DateTime`
/// columns keep whole seconds only, which is too coarse for message order.
final class EpochMs extends TypeConverter<DateTime, int> {
  const EpochMs();

  @override
  DateTime fromSql(int fromDb) =>
      DateTime.fromMillisecondsSinceEpoch(fromDb, isUtc: true);

  @override
  int toSql(DateTime value) => value.millisecondsSinceEpoch;
}

enum ConversationKind { direct, group }

/// Delivery state of a message.
///
/// Outgoing messages go `pending → sent → delivered → read → viewed` (or
/// `failed`). Incoming messages are `received` until the user reads them,
/// then `read`; only `received` messages count as unread.
enum MessageStatus {
  pending,
  sent,
  delivered,
  read,
  viewed,
  failed,
  received;

  /// Rank along the outgoing path; [advance] never moves backwards.
  int get _rank => switch (this) {
    pending => 0,
    sent => 1,
    delivered => 2,
    read => 3,
    viewed => 4,
    failed => -1,
    received => -1,
  };

  /// The status after learning [next]: outgoing statuses only move forward,
  /// and `failed` replaces only `pending`.
  MessageStatus advance(MessageStatus next) {
    if (next == failed) return this == pending ? failed : this;
    if (this == failed && next == pending) return pending;
    if (_rank < 0 || next._rank < 0) return this;
    return next._rank > _rank ? next : this;
  }
}

/// A view-once message before and after it was opened (CONTENT_V2.md §5).
enum ViewOnceState { unopened, opened }

/// Trust in one device of another account (CRYPTO_V2.md §2). A device is
/// `trusted` when its certificate verifies under the account's pinned AIK;
/// `stale` after a key change, until it is seen again under the new AIK.
enum DeviceTrust { trusted, stale }

enum AttachmentTransfer { remote, downloading, uploading, ready, failed }

enum PrekeyKind { signed, oneTime }

/// What happened to an envelope this device processed.
enum EnvelopeOutcome { applied, quarantined, ignored }

/// `pending` ops are retried with backoff; `inFlight` ops hold a lease (and
/// return to `pending` when it runs out, e.g. after a crash); `failed` ops
/// were given up on and are shown to the user.
enum OutboxState { pending, inFlight, failed }

/// Local sort key of a message: `(ts, id)` as one string that orders
/// correctly (CONTENT_V2.md §1). The author's clock, as 12 hex digits of
/// epoch milliseconds, then `:` and the message id.
abstract final class SortKey {
  static const _maxMs = 0xFFFFFFFFFFFF;

  static String of(DateTime sentAt, String messageId) {
    final ms = sentAt.millisecondsSinceEpoch.clamp(0, _maxMs);
    return '${ms.toRadixString(16).padLeft(12, '0')}:$messageId';
  }
}

/// Conversation id of the direct chat with [peerAccountId].
String directConversationId(String peerAccountId) => 'direct:$peerAccountId';
