/// The words for a group member the server's roster added but this device has
/// not confirmed (engine `member_unconfirmed`, reasons `unattributed` and
/// `link_join`). One place, so the chat notice, the prompt and the banner
/// explain it the same way.
library;

/// Why a member is waiting, in plain English. [name] is who it is about;
/// [reason] is the engine's `fields.reason` as sent (anything but `link_join`
/// reads as unattributed, the cautious reading).
String pendingReasonSentence(String name, String? reason) =>
    reason == 'link_join'
    ? '$name joined this group through its invite link, and nothing else '
          'vouches for them.'
    : '$name was added by the server roster, but no admin of this group '
          'announced it.';

/// The notice row in the chat.
String memberUnconfirmedNoticeText(String name, String? reason) {
  final why = reason == 'link_join'
      ? 'They joined with the group link.'
      : 'No admin announced it.';
  return '$name was added by the server roster. $why Your messages stay '
      'hidden from them until you confirm them in the group info.';
}
