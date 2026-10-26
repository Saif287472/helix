import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/features/devices/application/devices_providers.dart';
import 'package:helix_remote/features/profile/application/profile_providers.dart';
import 'package:helix_remote/features/settings/application/about_providers.dart';
import 'package:helix_remote/features/settings/application/account_providers.dart';
import 'package:helix_remote/features/settings/application/privacy_providers.dart';
import 'package:helix_remote/features/settings/application/settings_providers.dart';

/// Facts about you that the You page, Edit profile and Account all show, from
/// the profile, settings and devices features.

/// How many devices the account is signed in on (1 until the list comes).
final youDeviceCountProvider = Provider.autoDispose<int>(
  (ref) => ref.watch(deviceHealthProvider).value?.count ?? 1,
);

/// Your number with the middle hidden: from the profile, else (a linked
/// device) the account overview, which needs the network.
final youPhoneMaskedProvider = Provider.autoDispose<String?>(
  (ref) =>
      ref.watch(profileProvider).value?.phoneMasked ??
      ref.watch(accountOverviewProvider).value?.phoneMasked,
);

/// The server's name ("Orbit Global"), else its host.
final youServerNameProvider = Provider.autoDispose<String>(
  (ref) =>
      ref.watch(serverTitleProvider) ??
      ref.watch(settingsHeaderProvider).value?.serverHost ??
      '',
);

/// "+880 ... 1234 · Orbit Global": the mono line under your name.
final youMetaLineProvider = Provider.autoDispose<String>(
  (ref) => [
    ?ref.watch(youPhoneMaskedProvider),
    ref.watch(youServerNameProvider),
  ].where((s) => s.isNotEmpty).join(' · '),
);

/// "Find me by ~name" is on (or not known yet): anyone who knows your
/// `~name` can look it up.
final findableByNameProvider = Provider.autoDispose<bool>(
  (ref) => ref.watch(privacyProvider).prefs?.discoverableByName ?? true,
);
