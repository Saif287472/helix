part of '../composition_root.dart';

/// A Helix account matched from a phone-book contact via the discovery-salt
/// hash comparison. [phoneBookName] is what the device's contacts app calls
/// this person; [displayName] is their Helix profile name, kept only as a
/// fallback for the UI.
class PhoneContactMatch {
  const PhoneContactMatch({
    required this.accountId,
    required this.phoneBookName,
    required this.displayName,
  });

  final String accountId;
  final String phoneBookName;
  final String displayName;
}

mixin RemoteCompositionContactsSync
    on RemoteCompositionRootBase, RemoteCompositionRegistration {
  /// Matches the device's phone book against the backend's phone-hash
  /// contacts index and records phone-book names locally as display-name
  /// overrides (see RemoteMessagingService.recordPhoneContactMatches).
  /// Only salted hashes are ever sent to the server - raw numbers and
  /// phone-book names never leave the device.
  Future<Map<String, PhoneContactMatch>> syncPhoneContacts(
    List<PhoneBookContact> phoneBookContacts,
  ) async {
    final rest = _requireReady(_restClient, 'restClient');
    final store = _requireReady(_keyValue, 'keyValue');
    final ms = _requireReady(_messagingService, 'messagingService');

    final salt = await _getOrFetchDiscoverySalt(store: store, rest: rest);
    final hashToName = hashPhoneBookContacts(
      contacts: phoneBookContacts,
      discoverySaltBase64: salt,
    );
    if (hashToName.isEmpty) return const {};

    final response = await rest.matchPhoneHashes(hashToName.keys.toList());
    final matchesJson =
        response['matches'] as Map<String, dynamic>? ?? const {};

    final overrides = <String, String>{};
    final results = <String, PhoneContactMatch>{};
    for (final entry in matchesJson.entries) {
      final data = entry.value as Map<String, dynamic>;
      final accountId = data['account_id'] as String?;
      if (accountId == null) continue;
      final phoneBookName = hashToName[entry.key] ?? '';
      if (phoneBookName.isEmpty) continue;
      overrides[accountId] = phoneBookName;
      results[accountId] = PhoneContactMatch(
        accountId: accountId,
        phoneBookName: phoneBookName,
        displayName: data['display_name'] as String? ?? '',
      );
    }
    ms.recordPhoneContactMatches(overrides);
    return results;
  }
}
