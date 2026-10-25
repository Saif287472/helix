import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/engine/helix_runtime.dart';
import 'package:helix_remote/core/engine/runtime_providers.dart';
import 'package:helix_remote/core/platform/app_storage.dart';

/// How many messages wait in each account on this phone.
///
/// A pass that reads an account's mailbox writes the number it found: the push
/// isolate for an account that is not on screen, the running app for the one
/// that is. The account lists read it back, because they cannot open those
/// databases - only one engine may hold one at a time (see `EngineLease`), and
/// the others are closed.
///
/// It is a count, so it names no person and carries no content: what the badge
/// shows is the same number the chats of that account would add up to.
final class AccountBadgeStore {
  const AccountBadgeStore();

  /// Remembers that [account] has [unread] messages waiting.
  Future<void> write(String account, int unread) async {
    try {
      final file = await AppPaths.unreadFile(account);
      await file.writeAsString(jsonEncode({'u': unread}));
    } on Object {
      // The number is a convenience: a device that cannot write it still
      // delivers the messages, and the list simply shows no count.
    }
  }

  /// What was last counted for [account]: nothing has waited here if no pass
  /// ever wrote, or if what it wrote cannot be read.
  Future<int> read(String account) async {
    try {
      final file = await AppPaths.unreadFile(account);
      final json = jsonDecode(await file.readAsString());
      final unread = json is Map ? json['u'] : null;
      return unread is int && unread > 0 ? unread : 0;
    } on Object {
      return 0;
    }
  }
}

/// The messages waiting in every account signed in on this device, by id.
///
/// Read when an account list opens: a count only changes when a mailbox is
/// read, which happens on a push or in the running app, and never because
/// someone looked at this list.
final accountUnreadProvider =
    FutureProvider.autoDispose<Map<String, int>>((ref) async {
      const store = AccountBadgeStore();
      return {
        for (final account in ref.watch(accountsProvider).signedIn)
          account.id: await store.read(account.id),
      };
    });

/// Keeps the account on screen's count current while the app runs, so reading
/// its chats takes the number off its row and a message that arrives puts it
/// back.
final unreadBadgeSyncProvider = Provider<void>((ref) {
  const store = AccountBadgeStore();
  StreamSubscription<int>? counts;
  ref.listen<AsyncValue<HelixRuntime>>(runtimeProvider, (_, next) {
    unawaited(counts?.cancel());
    counts = null;
    final runtime = next.value;
    if (runtime == null) return;
    counts = runtime.engine.chats.watchUnread().map((t) => t.messages).listen((
      unread,
    ) {
      unawaited(store.write(runtime.account, unread));
      // The list may be open; this is the only moment its own account's
      // number moves.
      ref.invalidate(accountUnreadProvider);
    });
  }, fireImmediately: true);
  ref.onDispose(() => unawaited(counts?.cancel()));
});
