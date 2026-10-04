import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/engine/clock.dart';
import 'package:helix_remote/core/engine/failure_copy.dart';
import 'package:helix_remote/features/settings/application/settings_gateway.dart';
import 'package:helix_remote/features/settings/application/settings_models.dart';

/// Server-side privacy: who may see last seen and online, who may add this
/// account to a group, and whether people can find it by number or `~name`.
///
/// Loaded from the server, and every change is sent at once. A change that
/// fails goes back to what the server has, with a sentence saying why, so the
/// switches never show something the server does not hold.
class PrivacyState {
  const PrivacyState({
    this.prefs,
    this.loading = true,
    this.saving = false,
    this.error,
  });

  final PrivacyPrefs? prefs;
  final bool loading;
  final bool saving;
  final String? error;

  PrivacyState copyWith({
    PrivacyPrefs? prefs,
    bool? loading,
    bool? saving,
    String? error,
    bool clearError = false,
  }) => PrivacyState(
    prefs: prefs ?? this.prefs,
    loading: loading ?? this.loading,
    saving: saving ?? this.saving,
    error: clearError ? null : (error ?? this.error),
  );
}

final privacyProvider =
    NotifierProvider.autoDispose<PrivacyController, PrivacyState>(
      PrivacyController.new,
    );

final class PrivacyController extends Notifier<PrivacyState> {
  @override
  PrivacyState build() {
    Future.microtask(load);
    return const PrivacyState();
  }

  SettingsGateway get _gateway => ref.read(settingsGatewayProvider);

  Future<void> load() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final prefs = await _gateway.privacy();
      state = PrivacyState(prefs: prefs, loading: false);
    } on Object catch (error) {
      state = PrivacyState(
        loading: false,
        error: describeFailure(error, now: ref.read(clockProvider)()).message,
      );
    }
  }

  Future<void> update(PrivacyPrefs next) async {
    final previous = state.prefs;
    if (previous == null || previous == next || state.saving) return;
    state = PrivacyState(prefs: next, loading: false, saving: true);
    try {
      await _gateway.setPrivacy(next);
      state = PrivacyState(prefs: next, loading: false);
    } on Object catch (error) {
      state = PrivacyState(
        prefs: previous,
        loading: false,
        error:
            'That was not saved. '
            '${describeFailure(error, now: ref.read(clockProvider)()).message}',
      );
    }
  }

  Future<void> setLastSeen(AudienceChoice a) =>
      update(state.prefs!.copyWith(lastSeen: a));

  Future<void> setOnline(AudienceChoice a) =>
      update(state.prefs!.copyWith(online: a));

  Future<void> setGroupAdd(AudienceChoice a) =>
      update(state.prefs!.copyWith(groupAdd: a));

  Future<void> setDiscoverableByPhone(bool on) =>
      update(state.prefs!.copyWith(discoverableByPhone: on));

  Future<void> setDiscoverableByName(bool on) =>
      update(state.prefs!.copyWith(discoverableByName: on));
}

String audienceLabel(AudienceChoice a) => switch (a) {
  AudienceChoice.everyone => 'Everyone',
  AudienceChoice.contacts => 'My contacts',
  AudienceChoice.nobody => 'Nobody',
};

/// The audiences a person may pick. "My contacts" is left out: it relies on
/// an uploaded contact list that this version of Helix does not send, so
/// choosing it would hide the setting from everybody. A server that already
/// holds it (set from another client) still shows as "My contacts".
List<AudienceChoice> audienceChoicesFor(AudienceChoice current) => [
  AudienceChoice.everyone,
  if (current == AudienceChoice.contacts) AudienceChoice.contacts,
  AudienceChoice.nobody,
];

// ------------------------------------------------------------- blocked list

final blockedProvider = StreamProvider.autoDispose<List<BlockedPerson>>(
  (ref) => ref.watch(settingsGatewayProvider).watchBlocked(),
);

class BlockedActionState {
  const BlockedActionState({this.busyId, this.error});

  final String? busyId;
  final String? error;
}

final blockedActionsProvider =
    NotifierProvider.autoDispose<BlockedActions, BlockedActionState>(
      BlockedActions.new,
    );

final class BlockedActions extends Notifier<BlockedActionState> {
  @override
  BlockedActionState build() => const BlockedActionState();

  Future<void> unblock(String accountId) async {
    state = BlockedActionState(busyId: accountId);
    try {
      await ref.read(settingsGatewayProvider).unblock(accountId);
      state = const BlockedActionState();
    } on Object catch (error) {
      state = BlockedActionState(
        error: describeFailure(error, now: ref.read(clockProvider)()).message,
      );
    }
  }
}

// -------------------------------------------------------------- muted chats

final mutedChatsProvider = StreamProvider.autoDispose<List<MutedChat>>(
  (ref) => ref.watch(settingsGatewayProvider).watchMuted(),
);

final mutedActionsProvider = Provider<MutedActions>(MutedActions.new);

final class MutedActions {
  MutedActions(this._ref);

  final Ref _ref;

  Future<void> unmute(String chatId) =>
      _ref.read(settingsGatewayProvider).unmute(chatId);
}
