/// Message `kind`s the engine stores beyond the CONTENT_V2 types (those use
/// the content `type` name as the kind).
abstract final class MessageKinds {
  /// A message that could not be decrypted or read: shown as "couldn't
  /// decrypt" (and, while a re-send was requested, "waiting for this
  /// message"). Its `payload` is `{"code": …, "waiting": bool, "device": …}`.
  static const undecryptable = 'undecryptable';

  /// Content written by a newer client than this one understands
  /// (`ContentMessage.isFromNewerVersion`): shown as "This message needs a
  /// newer version of Helix". `payload` keeps the raw body.
  static const unsupported = 'unsupported';

  /// `system` bodies the engine itself writes locally.
  static const safetyNumberChanged = 'safety_number_changed';
  static const timerChanged = 'timer_changed';

  /// `IncomingNotice.kind` of a missed call this device saw ring (there is
  /// no message row behind it).
  static const missedCall = 'missed_call';

  /// Row kinds only the engine writes: content from a peer never gets one of
  /// these (`ContentCodec.storedKind`).
  static const reserved = {undecryptable, unsupported, missedCall};

  /// Types this engine renders. Anything else is shown as "needs a newer
  /// version" (CONTENT_V2.md §1).
  static const known = {
    'text',
    'media',
    'sticker',
    'location',
    'live_location',
    'contact',
    'poll',
    'event',
    'system',
    'call_log',
  };

  static bool isRenderable(String kind) => known.contains(kind);
}
