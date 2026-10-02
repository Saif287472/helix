import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/engine/runtime_providers.dart';
import 'package:helix_remote/core/engine/session_providers.dart';
import 'package:helix_remote/features/home/application/chat_list_provider.dart';

/// What the Settings tab draws, in one value object.
///
/// The tab reads this and nothing else. It does not know that a server has a
/// URL, that an account has an id, or what "signed out" means at the protocol
/// level - so the screen has no engine import and cannot drift from the data.
class SettingsTabModel {
  const SettingsTabModel({
    this.account = const HelixProfileSummary(),
    this.serverHost = '',
    this.signedIn = false,
  });

  final HelixProfileSummary account;

  /// The host of the server this device is on, for the header and the Server
  /// row. Empty when no server has been chosen yet.
  final String serverHost;

  final bool signedIn;
}

final settingsTabProvider = StreamProvider<SettingsTabModel>((ref) async* {
  final serverHost = ref.watch(serverHostProvider) ?? '';
  final signedIn = ref.watch(authStateProvider).value == AppAuthState.ready;
  final account = ref.watch(selfAccountProvider).value;

  yield SettingsTabModel(
    account: account ?? const HelixProfileSummary(),
    serverHost: serverHost,
    signedIn: signedIn,
  );
});

/// The host of the chosen server, or null before one is chosen.
///
/// Sign-in opens on Helix Global, so the host is normally set by the time this
/// is read; it is null only on a first install, before sign-in completes.
final serverHostProvider = Provider<String?>((ref) {
  return ref.watch(serverUrlProvider)?.host;
});
