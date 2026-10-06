import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/engine/runtime_providers.dart';

/// The account this device is signed in as: its id, its `~Helix name` and the
/// server it is on. The Settings tab's header.
final selfAccountProvider = StreamProvider<HelixProfileSummary>((ref) async* {
  final runtime = await ref.watch(runtimeProvider.future);
  yield* runtime.engine.account.watch().map(
    (account) => account == null
        ? const HelixProfileSummary()
        : HelixProfileSummary(
            accountId: account.accountId,
            phoneNumber: account.phoneNumber,
            profileName: account.profileName ?? '',
            helixName: account.helixName,
          ),
  );
});

/// What the Settings tab needs about the signed-in account.
///
/// A projection, not a widget's private state, so both the header and
/// anything else that needs the account reads one thing.
class HelixProfileSummary {
  const HelixProfileSummary({
    this.accountId = '',
    this.phoneNumber,
    this.profileName = '',
    this.helixName,
  });

  final String accountId;
  final String? phoneNumber;

  /// The name this person chose at sign-up.
  final String profileName;

  /// The `~Helix name` they claimed on the server.
  final String? helixName;

  /// What the Settings header shows: the profile name if there is one, then
  /// the Helix name, then a plain default.
  String get displayName {
    if (profileName.isNotEmpty) return profileName;
    final helix = helixName;
    if (helix != null && helix.isNotEmpty) return '~$helix';
    return 'Helix';
  }
}

/// The number of unread messages across all non-archived chats, for the tab
/// badge.
final unreadCountProvider = StreamProvider<int>((ref) async* {
  final runtime = await ref.watch(runtimeProvider.future);
  yield* runtime.engine.chats.watchUnread().map((totals) => totals.messages);
});
