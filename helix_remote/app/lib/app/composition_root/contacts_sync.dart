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

/// Outcome of a single [RemoteCompositionContactsSync.syncPhoneContacts]
/// pass: phone-book contacts matched to a Helix account, and phone-book
/// contacts that had at least one valid, hashable number but matched none -
/// i.e. not (yet) registered on this server.
class PhoneContactsSyncResult {
  const PhoneContactsSyncResult({
    required this.matches,
    required this.unmatchedNames,
    this.complete = true,
    this.hashesRemainingToday,
    this.retryAfter,
  });

  final Map<String, PhoneContactMatch> matches;
  final List<String> unmatchedNames;

  /// False when the server's daily discovery budget ran out part-way. The
  /// matches found so far are still valid and have been applied - a large
  /// phone book that cannot finish today is a partial success, not a
  /// failure, and the UI should say so rather than discarding the work.
  final bool complete;

  /// What the server says is left of today's budget, when it told us.
  final int? hashesRemainingToday;

  /// How long until the budget window rolls over, when the sync was cut
  /// short. Lets the caller schedule the remainder instead of retrying into
  /// a wall.
  final Duration? retryAfter;

  /// Names whose lookup never happened because the budget ran out.
  bool get isPartial => !complete;
}

mixin RemoteCompositionContactsSync
    on RemoteCompositionRootBase, RemoteCompositionRegistration {
  /// Matches the device's phone book against the backend's phone-hash
  /// contacts index and records phone-book names locally as display-name
  /// overrides (see RemoteMessagingService.recordPhoneContactMatches).
  /// Only salted hashes are ever sent to the server - raw numbers and
  /// phone-book names never leave the device.
  Future<PhoneContactsSyncResult> syncPhoneContacts(
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
    if (hashToName.isEmpty) {
      return const PhoneContactsSyncResult(matches: {}, unmatchedNames: []);
    }

    // Chunked, and sequentially rather than with Future.wait: parallel
    // bursts would spike memory on a large phone book and hit the server's
    // discovery budget all at once, losing the ability to stop cleanly at
    // the point the budget runs out.
    final allHashes = hashToName.keys.toList(growable: false);
    final matchesJson = <String, dynamic>{};
    var complete = true;
    int? hashesRemaining;
    Duration? retryAfter;

    for (var start = 0; start < allHashes.length; start += _matchChunkSize) {
      final end = (start + _matchChunkSize).clamp(0, allHashes.length);
      final chunk = allHashes.sublist(start, end);

      final Map<String, dynamic> response;
      try {
        response = await rest.matchPhoneHashes(
          chunk,
          // Only a single-chunk sync is the complete set; telling the server
          // otherwise would let it cache one chunk as the whole phone book.
          fullSync: allHashes.length <= _matchChunkSize,
        );
      } on RemoteRestException catch (e) {
        if (e.statusCode == 429) {
          // Budget exhausted. Keep everything matched so far rather than
          // discarding the whole sync over its last chunk.
          complete = false;
          retryAfter = _retryAfterFrom(e);
          break;
        }
        rethrow;
      }

      final chunkMatches =
          response['matches'] as Map<String, dynamic>? ?? const {};
      matchesJson.addAll(chunkMatches);
      hashesRemaining =
          response['hashes_remaining_today'] as int? ?? hashesRemaining;

      if (response['partial'] == true) {
        // The server answered as much of this chunk as the budget allowed.
        complete = false;
        final seconds = response['retry_after_seconds'] as int?;
        if (seconds != null) retryAfter = Duration(seconds: seconds);
        break;
      }
    }

    // Applied incrementally rather than only on a clean finish: a sync that
    // stops at chunk 3 of 5 should keep chunks 1-2, not throw them away.
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

    final hashesByName = groupPhoneBookHashesByName(
      contacts: phoneBookContacts,
      discoverySaltBase64: salt,
    );
    final matchedHashes = matchesJson.keys.toSet();
    final unmatchedNames =
        hashesByName.entries
            .where((entry) => !entry.value.any(matchedHashes.contains))
            .map((entry) => entry.key)
            .toList()
          ..sort();

    // Persisted only on a complete sync, for the same reason the result
    // below withholds them on a partial one: a truncated sync cannot tell
    // "not on Helix" from "never looked up", and storing that view would
    // drop names that were simply never checked.
    if (complete) {
      ms.recordUnmatchedPhoneContacts(unmatchedNames);
    }

    return PhoneContactsSyncResult(
      matches: results,
      // Only meaningful for the hashes actually looked up: a contact whose
      // chunk was never sent is "not yet checked", not "not on Helix".
      unmatchedNames: complete ? unmatchedNames : const [],
      complete: complete,
      hashesRemainingToday: hashesRemaining,
      retryAfter: retryAfter,
    );
  }

  /// Chunk size for contact discovery. Matches the server's per-request cap
  /// (`ContactsModule.contactsMatchBatchLimit`); the daily budget is metered
  /// per hash, so this affects only request size, never the cost of a sync.
  static const int _matchChunkSize = 1000;

  Duration? _retryAfterFrom(RemoteRestException error) {
    if (error.retryAfter != null) return error.retryAfter;
    try {
      final decoded = jsonDecode(error.message);
      if (decoded is Map<String, dynamic>) {
        final details = decoded['details'];
        if (details is Map<String, dynamic>) {
          final seconds = details['retry_after_seconds'];
          if (seconds is int) return Duration(seconds: seconds);
        }
      }
    } catch (_) {
      // Not JSON - no hint available, caller just retries later.
    }
    return null;
  }
}
