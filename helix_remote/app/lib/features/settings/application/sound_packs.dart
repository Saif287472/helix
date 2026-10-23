import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/engine/failure_copy.dart';
import 'package:helix_remote/core/format/labels.dart' show formatBytes;
import 'package:helix_remote/core/sounds/orbit_sounds.dart';
import 'package:helix_remote/core/theme/orbit_app_theme.dart'
    show deviceSettingsStoreProvider;
import 'package:helix_remote/core/theme/orbit_packs.dart';
import 'package:helix_remote/features/settings/application/about_providers.dart'
    show serverTitleProvider;
import 'package:helix_remote/features/settings/application/theme_packs.dart'
    show packBusyProvider, packSourceProvider;
import 'package:orbit_ui/orbit_ui.dart'
    show
        ListStatus,
        RingtoneGalleryItem,
        RingtoneGalleryModel,
        ThemePackPlace,
        phoneRingtoneId,
        phoneRingtoneLabel;

/// The download manager for ringtones (`orbit/PORT_PLAN.md` Part C step 5), the
/// sibling of `theme_packs.dart`'s manager for themes.
///
/// One folder, one gate and one set of rules hold both kinds, so what is here is
/// only what a sound's own: it is named by its pack id, because a sound pack
/// carries no display-name document, and choosing one is a device setting the
/// ringer reads when a call arrives rather than something the screen redraws.
/// The offer list is read the same way as the themes' - one manifest per pack,
/// checked before a row is shown - because a server folder holds both kinds and
/// its list route says nothing about which a row is.

/// The sounds on this device the app can ring with, newest revision of each.
final installedSoundsProvider = FutureProvider<List<InstalledSound>>(
  (ref) => ref.watch(soundPackStoreProvider).installed(),
);

/// Whether this phone can ring a call with a sound chosen on the Ringtones
/// page. A ringtone here is the sound of the notification channel an incoming
/// call arrives on, which only Android has; on Windows a call rings through
/// the app, so the row that would open a page with no power over it is hidden.
final canChooseRingtoneProvider = Provider<bool>(
  (ref) => defaultTargetPlatform == TargetPlatform.android,
);

/// The sound packs this account's server offers.
final hostedSoundsProvider = FutureProvider.autoDispose<PackOffers>(
  (ref) => hostedPacks(
    ref.watch(packSourceProvider),
    'sound',
    ref.watch(packPublishersProvider),
  ),
);

/// The sound an incoming call rings with: a pack id, or null for the phone's
/// own. Read from the device's settings file, so it survives a sign-out, and
/// re-read when the app starts.
final ringtoneChoiceProvider = AsyncNotifierProvider<RingtoneChoice, String?>(
  RingtoneChoice.new,
);

final class RingtoneChoice extends AsyncNotifier<String?> {
  @override
  Future<String?> build() =>
      ref.read(deviceSettingsStoreProvider).readRingtone();

  /// Rings with [id] from now on, or with the phone's own ringtone for
  /// [phoneRingtoneId]. A pack this device cannot ring with is refused the
  /// choice, exactly as a theme page refuses a theme it cannot draw.
  Future<void> choose(String id) async {
    if (id != phoneRingtoneId &&
        await ref.read(soundPackStoreProvider).load(id) == null) {
      return;
    }
    final store = ref.read(deviceSettingsStoreProvider);
    await store.writeRingtone(id == phoneRingtoneId ? null : id);
    // Read back, so a write that could not reach the file leaves the page
    // showing what the next call will actually ring with.
    state = AsyncData(await store.readRingtone());
  }
}

/// What the next incoming call rings with, in the one line Settings >
/// Notifications shows: the chosen pack, or the phone's own ringtone when
/// nothing was chosen - or when the chosen pack is no longer on this phone,
/// since a deleted pack keeps its choice but cannot be rung.
final ringtoneLabelProvider = Provider<String>((ref) {
  final chosen = ref.watch(ringtoneChoiceProvider).value;
  if (chosen == null) return phoneRingtoneLabel;
  final held = ref.watch(installedSoundsProvider).value;
  // Still reading the folder: the row says nothing rather than the wrong thing
  // about a ringtone it has not seen yet.
  if (held == null) return '';
  return held.any((sound) => sound.id == chosen) ? chosen : phoneRingtoneLabel;
});

final soundPackActionsProvider = Provider<SoundPackActions>(
  SoundPackActions.new,
);

/// Getting and deleting a sound pack, with the page's sentence back.
final class SoundPackActions {
  SoundPackActions(this._ref);

  final Ref _ref;

  /// Downloads sound [id] - [revision] for a specific one, else the newest on
  /// offer - and lists it on the Ringtones page.
  Future<String?> install(String id, {int? revision}) async {
    final store = _ref.read(soundPackStoreProvider);
    try {
      final change = await store.install(
        _ref.read(packSourceProvider),
        id,
        revision: revision,
      );
      await _refresh();
      if (change == PackChange.alreadyCurrent) return 'Already up to date.';
      final sound = await store.load(id);
      if (sound == null) return 'That sound cannot be used on this phone.';
      // The copy Android's system reads is made when the choice is made, not
      // here: downloading a ringtone must not put a file outside the app's own
      // folder that a person never chose.
      return '${sound.id} ringtone downloaded.';
    } on PackNotHosted {
      return 'That ringtone is no longer on offer.';
    } on PackRefused catch (e) {
      // The format's own words, which never quote anything from inside the pack.
      return 'That pack cannot be used: ${e.failure.reason}.';
    } on Object catch (e) {
      return describeFailure(e).message;
    }
  }

  /// Deletes sound [id]. The choice is kept, exactly as a chosen theme's is
  /// when its pack is deleted: the page then rings with the phone's own sound,
  /// and a re-download brings the choice back.
  Future<String?> remove(String id) async {
    final store = _ref.read(soundPackStoreProvider);
    try {
      if (!await store.remove(id)) return 'That ringtone is not on this phone.';
      await _refresh();
      return '$id ringtone deleted.';
    } on Object catch (e) {
      return describeFailure(e).message;
    }
  }

  Future<void> _refresh() async {
    _ref.invalidate(installedSoundsProvider);
    await _ref.read(installedSoundsProvider.future);
    _ref.invalidate(hostedSoundsProvider);
    await _ref.read(hostedSoundsProvider.future);
  }
}

/// The Ringtones page's verbs: the same four words the page shows, each handing
/// back the one line to toast. Not auto-disposed, because a download outlives
/// the frame that started it.
final ringtonePageProvider = Provider<RingtonePage>(RingtonePage.new);

final class RingtonePage {
  RingtonePage(this._ref);

  final Ref _ref;

  Future<String?> get(String id) => _busy(id, () => _install(id));

  Future<String?> update(String id) => _busy(id, () => _install(id));

  Future<String?> delete(String id) =>
      _busy(id, () => _ref.read(soundPackActionsProvider).remove(id));

  /// Rings with [id] - or with the phone's own sound for [phoneRingtoneId] -
  /// from now on. Only a sound this device holds gets there; the page lists
  /// what it holds.
  Future<String?> use(String id) async {
    if (id == phoneRingtoneId) {
      await _ref.read(ringtoneChoiceProvider.notifier).choose(id);
      return '$phoneRingtoneLabel on';
    }
    if (await _ref.read(soundPackStoreProvider).load(id) == null) {
      return 'That ringtone is not on this phone.';
    }
    await _ref.read(ringtoneChoiceProvider.notifier).choose(id);
    return '$id ringtone on';
  }

  void retry() => _ref.invalidate(hostedSoundsProvider);

  Future<String?> _install(String id) =>
      _ref.read(soundPackActionsProvider).install(id);

  Future<String?> _busy(String id, Future<String?> Function() work) =>
      _ref.read(packBusyProvider.notifier).around(id, work);
}

/// Everything the Ringtones page draws: the phone's own sound, then the packs
/// this device holds, then the ones its server will hand over.
///
/// A downloaded sound is named by its pack id - the only name a sound pack
/// carries, because it has no theme document and a name in the server's list
/// would be unsigned.
final ringtoneGalleryProvider = Provider.autoDispose<RingtoneGalleryModel>((
  ref,
) {
  final busy = ref.watch(packBusyProvider);
  final installed =
      ref.watch(installedSoundsProvider).value ?? const <InstalledSound>[];
  final hosted = ref.watch(hostedSoundsProvider);
  final chosen = ref.watch(ringtoneChoiceProvider).value;

  final offers = <String, PackOffer>{
    for (final offer in hosted.value?.rows ?? const <PackOffer>[])
      offer.id: offer,
  };
  final held = {for (final sound in installed) sound.id};

  // The sound a call actually rings with: the chosen pack when this device
  // still holds it, else the phone's own (deleting a ringtone keeps the choice,
  // so a re-download brings it back, but today it rings with the default).
  final ringing = chosen != null && held.contains(chosen) ? chosen : null;

  final items = <RingtoneGalleryItem>[
    RingtoneGalleryItem(
      id: phoneRingtoneId,
      name: phoneRingtoneLabel,
      place: ThemePackPlace.onThisPhone,
      detail: 'What the phone rings with for every other call',
      phone: true,
      inUse: ringing == null,
    ),
    for (final sound in installed)
      RingtoneGalleryItem(
        id: sound.id,
        name: sound.id,
        place: ThemePackPlace.onThisPhone,
        detail: formatBytes(sound.bytes),
        inUse: ringing == sound.id,
        updateAvailable:
            (offers[sound.id]?.revision ?? sound.revision) > sound.revision,
        busy: busy == sound.id,
      ),
    for (final id in offers.keys.toList()..sort())
      // This device already holds it, so it belongs to the group above.
      if (!held.contains(id))
        RingtoneGalleryItem(
          id: id,
          name: id,
          detail: '${formatBytes(offers[id]!.entry.totalBytes)} to download',
          busy: busy == id,
        ),
  ];

  final failure = hosted.error;
  final listed = hosted.value;
  return RingtoneGalleryModel(
    ringtones: items,
    status: hosted.isLoading
        ? ListStatus.loading
        : failure != null
        ? ListStatus.failed
        : ListStatus.ready,
    host: ref.watch(serverTitleProvider) ?? '',
    error: failure == null ? '' : describeFailure(failure).message,
    emptyNote: listed != null && listed.rows.isEmpty && listed.unverified > 0
        ? 'Nothing on offer here is a sound pack this app can use. A server '
              'folder holds themes and sounds together, and a pack this app '
              'cannot check is never offered.'
        : '',
  );
});
