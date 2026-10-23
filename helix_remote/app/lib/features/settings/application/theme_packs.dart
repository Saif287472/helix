import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/engine/failure_copy.dart';
import 'package:helix_remote/core/engine/runtime_providers.dart';
import 'package:helix_remote/core/format/labels.dart' show formatBytes;
import 'package:helix_remote/core/theme/orbit_app_theme.dart';
import 'package:helix_remote/core/theme/orbit_packs.dart';
import 'package:helix_remote/features/settings/application/about_providers.dart'
    show serverTitleProvider;
import 'package:helix_remote/features/settings/application/appearance.dart'
    show chooseThemeProvider;
import 'package:helix_remote_protocol/helix_remote_protocol.dart'
    show OrbitPackEntry;
import 'package:orbit_ui/orbit_ui.dart'
    show ListStatus, ThemeGalleryModel, ThemePackItem, ThemePackPlace;

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

/// The theme packs this account's server offers: one row per pack id, at the
/// newest revision, and only where that revision's own signed manifest says it
/// is a theme (a server folder holds both kinds and its list route says nothing
/// about which a row is).
///
/// An error is `NoServerChosen` on sign-in, which is why the page that lists
/// them is only reached from Settings.
final hostedPacksProvider = FutureProvider.autoDispose<PackOffers>(
  (ref) => hostedPacks(
    ref.watch(packSourceProvider),
    'theme',
    ref.watch(packPublishersProvider),
  ),
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
  /// The theme library is re-read afterwards, so the theme is on the More
  /// themes page and choosable without a restart. A pack that fails its checks
  /// never replaces the theme on screen: the store has moved nothing into place
  /// by then.
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
  ///
  /// The await is what keeps the page honest: without it a theme just
  /// downloaded would have a frame where it is neither on this phone nor on
  /// offer, and the row would blink back to "Get".
  Future<void> _refresh() async {
    await _ref.read(downloadedThemesProvider.notifier).reload();
    _ref.invalidate(installedPacksProvider);
    await _ref.read(installedPacksProvider.future);
  }
}

/// Which theme the page has an action running on, so only that row waits.
final packBusyProvider = NotifierProvider<PackBusy, String?>(PackBusy.new);

final class PackBusy extends Notifier<String?> {
  @override
  String? build() => null;

  /// Runs [work] for theme [id], marking the row busy for as long as it takes.
  Future<String?> around(String id, Future<String?> Function() work) async {
    state = id;
    try {
      return await work();
    } finally {
      state = null;
    }
  }
}

/// The More themes page's verbs (`orbit/PORT_PLAN.md` Part C step 4): the same
/// four words the page shows, each handing back the one line to toast. It is
/// not auto-disposed, because a download outlives the frame that started it.
final themePackPageProvider = Provider<ThemePackPage>(ThemePackPage.new);

final class ThemePackPage {
  ThemePackPage(this._ref);

  final Ref _ref;

  /// Downloads [id] - the newest revision on offer, and the same call whether
  /// this device had nothing of it or an older one.
  Future<String?> get(String id) => _busy(id, () => _install(id));

  Future<String?> update(String id) => _busy(id, () => _install(id));

  Future<String?> delete(String id) =>
      _busy(id, () => _ref.read(themePackActionsProvider).remove(id));

  /// Draws the app in [id] from now on. Only a theme this device can draw with
  /// gets there: the page lists what it holds, and a pack deleted from under a
  /// chosen theme falls back to Orbit on its own.
  Future<String?> use(String id) async {
    final name = _ref.read(themeLibraryProvider)[id]?.meta.name;
    if (name == null) return 'That theme is not on this device.';
    await _ref.read(chooseThemeProvider)(id);
    return '$name theme on';
  }

  void retry() => _ref.invalidate(hostedPacksProvider);

  Future<String?> _install(String id) =>
      _ref.read(themePackActionsProvider).install(id);

  Future<String?> _busy(String id, Future<String?> Function() work) =>
      _ref.read(packBusyProvider.notifier).around(id, work);
}

/// Everything the More themes page draws: the themes this device can draw with,
/// then the ones this account's server will hand over.
///
/// A theme on this phone is named by its own signed document; an offer is named
/// by nothing but its id, because the list route carries no display name on
/// purpose (a name there would be unsigned). So the second group reads as a
/// slug until the pack is downloaded and checked.
final themeGalleryProvider = Provider.autoDispose<ThemeGalleryModel>((ref) {
  final library = ref.watch(themeLibraryProvider);
  final chosen = ref.watch(themeChoiceProvider);
  final busy = ref.watch(packBusyProvider);
  final installed =
      ref.watch(installedPacksProvider).value ?? const <InstalledPack>[];
  final hosted = ref.watch(hostedPacksProvider);

  // The newest revision the server lists for each pack id, of the kind this
  // page is about.
  final newest = {
    for (final offer in hosted.value?.rows ?? const <PackOffer>[])
      offer.id: offer.entry,
  };

  // The theme actually on screen: the chosen one, or Orbit when the choice
  // names a pack this device no longer holds (deleting one keeps the choice,
  // so a re-download brings it back, but today it draws with the default).
  final inUse = library.containsKey(chosen) ? chosen : defaultThemeId;

  final items = <ThemePackItem>[
    for (final id in builtInThemeIds)
      if (library[id] case final tokens?)
        ThemePackItem(
          id: id,
          name: tokens.meta.name,
          place: ThemePackPlace.onThisPhone,
          detail: tokens.meta.vibe,
          builtIn: true,
          inUse: inUse == id,
        ),
    for (final pack in installed)
      if (!builtInThemeIds.contains(pack.id))
        ThemePackItem(
          id: pack.id,
          name: pack.name,
          place: ThemePackPlace.onThisPhone,
          detail: '${pack.tokens.meta.vibe} · ${formatBytes(pack.bytes)}',
          inUse: inUse == pack.id,
          updateAvailable:
              (newest[pack.id]?.revision ?? pack.revision) > pack.revision,
          busy: busy == pack.id,
        ),
    for (final entry
        in (newest.values.toList()..sort((a, b) => a.id.compareTo(b.id))))
      // This device already draws with it (or the server republished a built
      // in theme), so it belongs to the group above, not to the offers.
      if (!library.containsKey(entry.id))
        ThemePackItem(
          id: entry.id,
          name: entry.id,
          detail: '${formatBytes(entry.totalBytes)} to download',
          busy: busy == entry.id,
        ),
  ];

  final failure = hosted.error;
  final offers = hosted.value;
  // A server that listed packs this app could not vouch for - unsigned, by a
  // publisher this build does not trust, or the other kind of pack - is not a
  // server with nothing on it, and the page must not say it is.
  final unverified = offers == null ? 0 : offers.unverified;
  return ThemeGalleryModel(
    themes: items,
    status: hosted.isLoading
        ? ListStatus.loading
        : failure != null
        ? ListStatus.failed
        : ListStatus.ready,
    host: ref.watch(serverTitleProvider) ?? '',
    error: failure == null ? '' : describeFailure(failure).message,
    emptyNote: offers != null && offers.rows.isEmpty && unverified > 0
        ? 'Nothing on offer here is a theme pack this app can use. A server '
              'folder holds themes and sounds together, and a pack this app '
              'cannot check is never offered.'
        : '',
  );
});
