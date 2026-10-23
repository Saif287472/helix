import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/engine/failure_copy.dart';
import 'package:helix_remote/core/engine/runtime_providers.dart';
import 'package:helix_remote/core/theme/orbit_app_theme.dart';
import 'package:helix_remote/core/theme/orbit_packs.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart'
    show OrbitPackEntry;

/// The download manager for theme packs (`orbit/PORT_PLAN.md` Part C step 3):
/// what this device holds, what this account's server offers, and the three
/// things a person can do about it - get one, bring it up to date, delete it.
///
/// The rules are not here: [ThemePackStore] keeps the files and `checkOrbitPack`
/// in `helix_remote_domain` decides what the app may draw with. This is the
/// wiring, and the sentences. Failures are whatever the store, the API or the
/// file system throws; every method returns the one line a page shows, or null
/// when there is nothing to say.

/// The packs the account's server offers, read through the runtime's API
/// client.
///
/// One method per pack route, and nothing of its own: token refresh, TLS
/// pinning, retries and the server's rate limits all belong to that client, so
/// a pack is fetched exactly like a message is.
final class ApiPackSource implements PackSource {
  ApiPackSource(this._ref);

  final Ref _ref;

  @override
  Future<List<OrbitPackEntry>> list() async {
    final ops = (await _ref.read(runtimeProvider.future)).api.ops;
    return (await ops.packs()).packs;
  }

  @override
  Future<List<int>> manifest(String id, int revision) async {
    final ops = (await _ref.read(runtimeProvider.future)).api.ops;
    return ops.packManifest(id, revision);
  }

  @override
  Future<List<int>> file(String id, int revision, String digest) async {
    final ops = (await _ref.read(runtimeProvider.future)).api.ops;
    return ops.packFile(id, revision, digest);
  }
}

final packSourceProvider = Provider<PackSource>(ApiPackSource.new);

/// The packs on this device that the app can draw with, newest revision of
/// each. Errors only when the pack folder itself cannot be read.
final installedPacksProvider = FutureProvider<List<InstalledPack>>(
  (ref) => ref.watch(themePackStoreProvider).installed(),
);

/// The packs this account's server offers, one entry per published revision.
/// An error is `NoServerChosen` on sign-in, which is why the page that lists
/// them is only reached from Settings.
final hostedPacksProvider = FutureProvider.autoDispose<List<OrbitPackEntry>>(
  (ref) => ref.watch(packSourceProvider).list(),
);

final themePackActionsProvider = Provider<ThemePackActions>(
  ThemePackActions.new,
);

/// Getting, updating and deleting a pack, with the page's sentence back.
final class ThemePackActions {
  ThemePackActions(this._ref);

  final Ref _ref;

  /// Downloads pack [id] - [revision] for a specific one, else the newest on
  /// offer - and offers its theme to the app.
  ///
  /// The theme library is re-read afterwards, so the theme is on Appearance and
  /// choosable without a restart. A pack that fails its checks never replaces
  /// the theme on screen: the store has moved nothing into place by then.
  Future<String?> install(String id, {int? revision}) async {
    if (builtInThemeIds.contains(id)) {
      return 'That theme is built into the app, so there is nothing to '
          'download.';
    }
    final store = _ref.read(themePackStoreProvider);
    try {
      final change = await store.install(
        _ref.read(packSourceProvider),
        id,
        revision: revision,
      );
      await _refresh();
      if (change == PackChange.alreadyCurrent) return 'Already up to date.';
      final pack = await store.load(id);
      return '${pack?.name ?? id} theme downloaded.';
    } on PackNotHosted {
      return 'That theme is no longer on offer.';
    } on PackRefused catch (e) {
      // The format's own words, which never quote anything from inside the pack.
      return 'That pack cannot be used: ${e.failure.reason}.';
    } on Object catch (e) {
      return describeFailure(e).message;
    }
  }

  /// Deletes pack [id] and the bytes it downloaded. If it was the theme on
  /// screen, the app goes back to Orbit - the choice is kept, so a re-download
  /// brings it back.
  Future<String?> remove(String id) async {
    final store = _ref.read(themePackStoreProvider);
    try {
      final name = (await store.load(id))?.name;
      if (!await store.remove(id)) return 'That theme is not on this device.';
      await _refresh();
      return '${name ?? id} theme deleted.';
    } on Object catch (e) {
      return describeFailure(e).message;
    }
  }

  /// Re-reads the packs, and whatever is watching them.
  Future<void> _refresh() async {
    await _ref.read(downloadedThemesProvider.notifier).reload();
    _ref.invalidate(installedPacksProvider);
  }
}
