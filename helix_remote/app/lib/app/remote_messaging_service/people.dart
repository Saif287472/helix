part of '../remote_messaging_service.dart';

/// Someone this device can message or call.
///
/// There are no contact requests: anyone on the server can be reached. A
/// person comes from the phone book (matched to a Helix account), from a
/// name the user gave them, or from having been in touch (a chat or call).
class RemotePerson {
  const RemotePerson({
    required this.accountId,
    required this.name,
    this.phoneNumber,
    this.helixName = '',
    this.inPhoneBook = false,
  });

  final String accountId;

  /// What the UI calls them: the phone-book name, a saved name, their number,
  /// or their Helix name - in that order.
  final String name;
  final String? phoneNumber;

  /// The name they gave themselves on Helix.
  final String helixName;

  /// Whether the phone's contacts know them by name.
  final bool inPhoneBook;

  /// Whether [name] is only their number or Helix name - an unsaved person.
  bool get isUnsaved =>
      !inPhoneBook && (name == phoneNumber || name == helixLabel);

  String get helixLabel => helixName.isEmpty ? '' : '~$helixName';

  /// Lowercase text a search matches against.
  String get searchText =>
      '${name.toLowerCase()} ${helixName.toLowerCase()} '
      '${(phoneNumber ?? '').replaceAll(RegExp(r'[^\d+]'), '')}';
}

mixin RemotePeople on RemoteMessagingServiceBase {
  /// The name to show for [accountId] (never null; falls back to a neutral
  /// label rather than an internal id).
  String personName(String accountId) {
    final phoneBook = db.phoneContactName(accountId);
    if (phoneBook != null && phoneBook.isNotEmpty) return phoneBook;
    final saved = _savedNickname(accountId);
    if (saved != null) return saved;
    final profile = db.peerProfile(accountId);
    final number = profile?['phone_number'] as String? ?? '';
    if (number.isNotEmpty) return number;
    final helix = profile?['display_name'] as String? ?? '';
    if (helix.isNotEmpty) return '~$helix';
    return 'Helix user';
  }

  /// The phone number behind [accountId], when this device knows it.
  String? peerPhoneNumber(String accountId) {
    final fromPhoneBook = db.phoneContactNumber(accountId);
    if (fromPhoneBook != null) return fromPhoneBook;
    final number = db.peerProfile(accountId)?['phone_number'] as String? ?? '';
    return number.isEmpty ? null : number;
  }

  RemotePerson person(String accountId) {
    final profile = db.peerProfile(accountId);
    final phoneBook = db.phoneContactName(accountId);
    return RemotePerson(
      accountId: accountId,
      name: personName(accountId),
      phoneNumber: peerPhoneNumber(accountId),
      helixName: profile?['display_name'] as String? ?? '',
      inPhoneBook: phoneBook != null && phoneBook.isNotEmpty,
    );
  }

  /// Everyone this device can reach by name: phone-book matches, people the
  /// user named, and everyone in a direct chat. Sorted by name.
  List<RemotePerson> people() {
    final me = _accountId;
    final ids = <String>{
      ...db.phoneContactNames().keys,
      for (final contact in db.getContacts())
        if (contact.status != 'Blocked' && contact.status != 'BLOCKED')
          contact.peerAccountId,
      ...db.peerProfiles().keys,
      for (final conversation in db.getConversations())
        if (conversation.type == 'DIRECT')
          ...db.getConversationMembers(conversation.conversationId),
    }..remove(me);
    ids.removeWhere((id) => id.isEmpty);
    final people = ids.map(person).toList()
      ..sort((a, b) {
        // Named people first, then unsaved numbers.
        if (a.isUnsaved != b.isUnsaved) return a.isUnsaved ? 1 : -1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return people;
  }

  /// Direct-chat and call peers this device has no name or number for yet.
  List<String> peersWithoutProfile() {
    final me = _accountId;
    final known = db.peerProfiles().keys.toSet();
    final ids = <String>{
      for (final conversation in db.getConversations())
        ...db.getConversationMembers(conversation.conversationId),
    }..remove(me);
    return ids
        .where((id) => id.isNotEmpty && !known.contains(id))
        .where((id) => db.phoneContactNumber(id) == null)
        .toList(growable: false);
  }

  /// Stores what the server said about people (`/contacts/people`).
  void recordPeerProfiles(List<Map<String, dynamic>> people) {
    if (people.isEmpty) return;
    final now = _clock().millisecondsSinceEpoch;
    for (final person in people) {
      final id = person['account_id'] as String?;
      if (id == null || id.isEmpty) continue;
      db.savePeerProfile(
        peerAccountId: id,
        displayName: (person['display_name'] as String? ?? '').trim(),
        phoneNumber: (person['phone_number'] as String? ?? '').trim(),
        updatedAt: now,
      );
    }
    _emitChange(
      const RemoteSyncChange(
        areas: {
          RemoteSyncChangeArea.contacts,
          RemoteSyncChangeArea.conversations,
        },
      ),
    );
  }

  /// Remembers someone found by number, before any chat exists.
  void recordFoundPerson({
    required String accountId,
    required String phoneNumber,
    String helixName = '',
  }) {
    db.savePeerProfile(
      peerAccountId: accountId,
      displayName: helixName,
      phoneNumber: phoneNumber,
      updatedAt: _clock().millisecondsSinceEpoch,
    );
    _emitChange(const RemoteSyncChange(areas: {RemoteSyncChangeArea.contacts}));
  }

  /// The direct chat with [accountId], created when there is none yet. No
  /// request: the other person just receives the messages. An existing chat
  /// is reused as is - creating it again would reset its sequence.
  String directChatWith(String accountId) {
    final conversations = this as RemoteConversationManagement;
    final existing = conversations.conversationIdForPeer(accountId);
    if (existing != null &&
        conversations.conversationMemberIds(existing).isNotEmpty) {
      return existing;
    }
    return conversations.createDirectConversation(
      peerAccountId: accountId,
      title: personName(accountId),
    );
  }

  /// Gives [accountId] the name [name] on this device. The phone-book side of
  /// a rename is the composition root's job (it needs the platform).
  void renamePerson(String accountId, String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final now = _clock().millisecondsSinceEpoch;
    db.upsertContact(
      RemoteContact(
        peerAccountId: accountId,
        nickname: trimmed,
        status: 'Accepted',
      ),
    );
    if (db.phoneContactName(accountId) != null ||
        peerPhoneNumber(accountId) != null) {
      db.savePhoneContactName(
        peerAccountId: accountId,
        phoneBookName: trimmed,
        updatedAt: now,
        phoneNumber: peerPhoneNumber(accountId) ?? '',
      );
    }
    _emitChange(
      const RemoteSyncChange(
        areas: {
          RemoteSyncChangeArea.contacts,
          RemoteSyncChangeArea.conversations,
        },
      ),
    );
  }

  String? _savedNickname(String accountId) {
    for (final contact in db.getContacts()) {
      if (contact.peerAccountId != accountId) continue;
      final nickname = contact.nickname.trim();
      if (nickname.isNotEmpty && nickname != accountId) return nickname;
    }
    return null;
  }
}
