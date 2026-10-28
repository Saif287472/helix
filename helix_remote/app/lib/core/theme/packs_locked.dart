import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether downloadable theme and sound packs are locked for this account
/// (ADR-035): plans are on and the account is on the Free plan. The two themes
/// and the ringtones the app carries are never locked.
///
/// False until the plan has been read, and whenever it cannot be read: a phone
/// that is offline keeps what it has. The plan feature sets it; the theme and
/// the pack pages only read it, so core stays free of the features.
final packsLockedProvider = NotifierProvider<PacksLocked, bool>(
  PacksLocked.new,
);

final class PacksLocked extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool locked) => state = locked;
}

/// The sentence a locked download or choice answers with.
const packsLockedThemes = 'Downloadable themes are part of Orbit Premium.';
const packsLockedSounds = 'Downloadable ringtones are part of Orbit Premium.';
