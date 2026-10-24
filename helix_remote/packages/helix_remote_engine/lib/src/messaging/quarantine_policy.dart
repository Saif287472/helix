import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// What an envelope this device could not decrypt is worth, decided in one
/// place because the direct and group pipelines must not drift (AUD-12f-1).
///
/// The receiver cannot read the body - reading it is exactly what failed - so
/// the only classifier the wire offers is the sender's `urgent` flag. Its real
/// purpose is waking a phone, and the engine uses it that way: a receipt, an
/// edit, a delete, a reaction, a poll vote and an RSVP all go out non-urgent.
/// So `urgent` decides only what is worth *showing*, and no longer whether the
/// sender is asked to repair (that was AUD-12f-1: a "delete for everyone" that
/// one device could not read stayed visible there forever, with the author
/// told it had been deleted).
abstract final class QuarantinePolicy {
  /// A placeholder row for this envelope: what the user would have seen.
  ///
  /// Ephemeral deliveries (typing) have no [Envelope.seq] and no row.
  static bool showsPlaceholder(Envelope envelope) =>
      envelope.urgent && envelope.seq != null;

  /// Ask the sender for a fresh session and a re-send.
  ///
  /// [curable] is the crypto layer's own answer - a missing sender key or a
  /// failed authentication is cured by a re-send, a bad signature or a replay
  /// is not. Everything stored is then asked, because a quiet action that
  /// never arrived is worse for the reader than a control message is for the
  /// sender: asking for one the sender cannot rebuild (a receipt names no row
  /// it would re-send) costs one small message, and the cooldown on starting a
  /// session, the reset op's idempotency key and the sender's own re-send
  /// checks bound it.
  static bool asksForRepair(Envelope envelope, {required bool curable}) =>
      curable && envelope.seq != null;
}
