import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/engine/clock.dart';
import 'package:helix_remote/core/engine/failure_copy.dart';
import 'package:helix_remote/core/engine/global_server.dart';
import 'package:helix_remote/core/engine/runtime_providers.dart';
import 'package:helix_remote/core/engine/session_providers.dart';
import 'package:helix_remote/core/platform/account_slots.dart';
import 'package:helix_remote/core/push/account_badges.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart' show maskPhone;

/// An account on the Accounts page, in its words. [unread] is how many of its
/// messages are waiting on this phone.
typedef AccountLine = ({
  String id,
  String title,
  String detail,
  bool current,
  int unread,
});

/// The accounts signed in on this device: the one on screen first, then the
/// others, most recently used first.
final accountLinesProvider = Provider<List<AccountLine>>((ref) {
  final accounts = ref.watch(accountsProvider);
  // Counted on the last pass that read each account; the ones not on screen
  // are closed, so this is read from what they left behind.
  final unread = ref.watch(accountUnreadProvider).value ?? const {};
  final signedIn = accounts.signedIn;
  return [
    for (final s in signedIn)
      if (s.id == accounts.active)
        accountLineOf(s, current: true, unread: unread[s.id] ?? 0),
    for (final s in signedIn)
      if (s.id != accounts.active)
        accountLineOf(s, current: false, unread: unread[s.id] ?? 0),
  ];
});

/// "Rahman / +880 1*** ***001", or the number over the server, or the
/// server alone for an account whose number is not known yet.
AccountLine accountLineOf(
  AccountSlot s, {
  required bool current,
  int unread = 0,
}) {
  final server = s.server == kGlobalServerUrl.toString()
      ? 'Helix Global'
      : (Uri.tryParse(s.server)?.host ?? s.server);
  final number = s.e164.isEmpty ? '' : maskPhone(s.e164);
  return (
    id: s.id,
    title: s.name.isNotEmpty
        ? s.name
        : number.isNotEmpty
        ? number
        : 'Account on $server',
    detail: [
      if (s.name.isNotEmpty && number.isNotEmpty) number,
      if (s.name.isEmpty || number.isEmpty) server,
    ].join(' · '),
    current: current,
    unread: unread,
  );
}

class AccountsPageState {
  const AccountsPageState({this.busy = false, this.error});

  final bool busy;
  final String? error;
}

final accountsPageProvider =
    NotifierProvider.autoDispose<AccountsPageActions, AccountsPageState>(
      AccountsPageActions.new,
    );

final class AccountsPageActions extends Notifier<AccountsPageState> {
  @override
  AccountsPageState build() => const AccountsPageState();

  /// Opens [id] in place of the account on screen.
  Future<void> open(String id) async {
    if (state.busy) return;
    await ref.read(accountsProvider.notifier).switchTo(id);
  }

  /// Sign-in for one more account; the ones signed in stay listed there.
  void add() {
    if (state.busy) return;
    ref.read(accountsProvider.notifier).addAccount();
  }

  /// Signs [id] out of this device and deletes its data here.
  Future<void> remove(String id) async {
    if (state.busy) return;
    state = const AccountsPageState(busy: true);
    try {
      await ref.read(removeAccountProvider)(id);
      if (ref.mounted) state = const AccountsPageState();
    } on Object catch (error) {
      if (!ref.mounted) return;
      state = AccountsPageState(
        error: describeFailure(error, now: ref.read(clockProvider)()).message,
      );
    }
  }
}
