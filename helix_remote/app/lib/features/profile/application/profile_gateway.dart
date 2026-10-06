import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/engine/runtime_providers.dart';
import 'package:helix_remote/core/security/app_settings.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart' show maskPhone;

/// This account's own profile, as the profile page shows it.
@immutable
final class ProfileData {
  const ProfileData({
    this.accountId = '',
    this.name = '',
    this.about = '',
    this.helixName,
    this.phoneMasked,
  });

  final String accountId;

  /// The name people see, chosen at sign-up or here. Encrypted on the server.
  final String name;
  final String about;

  /// The claimed `~name`, without the tilde.
  final String? helixName;

  /// The phone number with the middle hidden (`+880 ... 1234`), or null when
  /// this device does not know it.
  final String? phoneMasked;

  @override
  bool operator ==(Object other) =>
      other is ProfileData &&
      other.accountId == accountId &&
      other.name == name &&
      other.about == about &&
      other.helixName == helixName &&
      other.phoneMasked == phoneMasked;

  @override
  int get hashCode =>
      Object.hash(accountId, name, about, helixName, phoneMasked);
}

/// The profile and the calls that change it. An interface so the page and its
/// notifier are tested with a fake; [EngineProfileGateway] is the only
/// implementation that touches the engine.
///
/// Failures are whatever the engine and API throw (`ApiException` for a
/// refused `~name`); the notifier turns them into sentences.
abstract interface class ProfileGateway {
  Stream<ProfileData> watch();

  /// Publishes the name and about line, encrypted with the account's profile
  /// key (created on first use). The server never sees either in the clear.
  Future<void> saveProfile({required String name, required String about});

  /// Claims `~name` (already normalised). Throws `ApiException(name_taken)`
  /// when it is taken or could pass for Helix staff: the server answers both
  /// the same way on purpose.
  Future<void> setHelixName(String name);

  Future<void> clearHelixName();
}

final profileGatewayProvider = Provider<ProfileGateway>(
  EngineProfileGateway.new,
);

final class EngineProfileGateway implements ProfileGateway {
  EngineProfileGateway(this._ref);

  final Ref _ref;

  @override
  Stream<ProfileData> watch() async* {
    final engine = (await _ref.read(runtimeProvider.future)).engine;
    await for (final account in engine.account.watch()) {
      if (account == null) {
        yield const ProfileData();
        continue;
      }
      final about = await engine.settings.get(AppSettings.profileAbout);
      final phone = account.phoneNumber;
      yield ProfileData(
        accountId: account.accountId,
        name: account.profileName ?? '',
        about: about,
        helixName: account.helixName,
        phoneMasked: phone == null ? null : maskPhone(phone),
      );
    }
  }

  @override
  Future<void> saveProfile({
    required String name,
    required String about,
  }) async {
    final engine = (await _ref.read(runtimeProvider.future)).engine;
    await engine.people.setOwnProfile(
      name: name,
      about: about.isEmpty ? null : about,
    );
    await engine.settings.set(AppSettings.profileAbout, about);
  }

  @override
  Future<void> setHelixName(String name) async {
    final engine = (await _ref.read(runtimeProvider.future)).engine;
    await engine.settings.setHelixName(name);
  }

  @override
  Future<void> clearHelixName() async {
    final engine = (await _ref.read(runtimeProvider.future)).engine;
    await engine.settings.clearHelixName();
  }
}
