import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/engine/runtime_providers.dart';
import 'package:helix_remote/core/people/people_names.dart';
import 'package:helix_remote/core/security/app_settings.dart';
import 'package:helix_remote/features/settings/application/settings_models.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart' show maskPhone;
import 'package:helix_remote_protocol/helix_remote_protocol.dart' as proto;

/// The account-level calls the settings pages make: who this account is,
/// changing the password, exporting and deleting.
///
/// An interface so the Account page and its notifier are tested against a
/// fake; [EngineSettingsGateway] is the one implementation that touches the
/// engine. Failures are whatever the engine and API throw; the notifiers turn
/// them into sentences.
abstract interface class SettingsGateway {
  /// The header of the Settings tab: who this device is signed in as.
  Stream<SettingsHeader> watchHeader();

  Future<AccountOverview> account();

  /// Sets or changes the password. [currentPassword] is the proof the server
  /// asks for when one exists already; [phoneNumber] is only needed when this
  /// device does not remember the account's number.
  Future<void> changePassword({
    required String newPassword,
    String? currentPassword,
    String? phoneNumber,
  });

  /// Everything the server holds about the account, as JSON bytes. Metadata
  /// only: the server holds no message content.
  Future<Uint8List> exportAccount();

  /// Deletes the account on the server. Not reversible. The caller signs this
  /// device out afterwards.
  Future<void> deleteAccount();

  // ------------------------------------------------------------- privacy

  Future<PrivacyPrefs> privacy();

  Future<void> setPrivacy(PrivacyPrefs prefs);

  Stream<List<BlockedPerson>> watchBlocked();

  Future<void> unblock(String accountId);

  // ------------------------------------------------------- notifications

  Stream<List<MutedChat>> watchMuted();

  Future<void> unmute(String chatId);

  // -------------------------------------------------------------- server

  Future<ServerDetails> serverDetails();

  Future<LegalText> legal();

  /// Reads the mailbox once, now, instead of waiting for the socket.
  Future<void> syncNow();
}

final settingsGatewayProvider = Provider<SettingsGateway>(
  EngineSettingsGateway.new,
);

final class EngineSettingsGateway implements SettingsGateway {
  EngineSettingsGateway(this._ref);

  final Ref _ref;

  @override
  Stream<SettingsHeader> watchHeader() async* {
    final runtime = await _ref.read(runtimeProvider.future);
    final engine = runtime.engine;
    await for (final row in engine.account.watch()) {
      final about = await engine.settings.get(AppSettings.profileAbout);
      final helix = row?.helixName;
      final profile = row?.profileName;
      yield SettingsHeader(
        accountId: row?.accountId ?? '',
        name: (profile != null && profile.isNotEmpty)
            ? profile
            : (helix != null && helix.isNotEmpty ? '~$helix' : 'Helix'),
        about: about,
        serverHost: runtime.serverUrl.host,
      );
    }
  }

  @override
  Future<AccountOverview> account() async {
    final runtime = await _ref.read(runtimeProvider.future);
    final engine = runtime.engine;
    final row = await engine.account.current();
    final info = await engine.settings.refreshAccount();
    final phone = row?.phoneNumber;
    final last4 = info.phoneLast4;
    return AccountOverview(
      phoneMasked: phone != null
          ? maskPhone(phone)
          : (last4 == null ? null : '*******$last4'),
      helixName: info.helixName,
      hasPassword: info.hasPassword,
      passwordUpdatedAt: info.passwordUpdatedAt,
      phoneKnownOnDevice: phone != null,
    );
  }

  @override
  Future<void> changePassword({
    required String newPassword,
    String? currentPassword,
    String? phoneNumber,
  }) async {
    final engine = (await _ref.read(runtimeProvider.future)).engine;
    await engine.account.changePassword(
      newPassword: newPassword,
      currentPassword: currentPassword,
      phoneNumber: phoneNumber,
    );
  }

  @override
  Future<Uint8List> exportAccount() async {
    final api = (await _ref.read(runtimeProvider.future)).api;
    final export = await api.compliance.export();
    const encoder = JsonEncoder.withIndent('  ');
    return Uint8List.fromList(utf8.encode(encoder.convert(export.toJson())));
  }

  @override
  Future<void> deleteAccount() async {
    final api = (await _ref.read(runtimeProvider.future)).api;
    await api.compliance.deleteAccount();
  }

  @override
  Future<PrivacyPrefs> privacy() async {
    final engine = (await _ref.read(runtimeProvider.future)).engine;
    final p = await engine.settings.privacy();
    return PrivacyPrefs(
      discoverableByPhone: p.discoverableByPhone,
      discoverableByName: p.discoverableByName,
      lastSeen: _audience(p.lastSeen),
      online: _audience(p.online),
      groupAdd: _audience(p.groupAdd),
    );
  }

  @override
  Future<void> setPrivacy(PrivacyPrefs prefs) async {
    final engine = (await _ref.read(runtimeProvider.future)).engine;
    await engine.settings.setPrivacy(
      proto.PrivacySettings(
        discoverableByPhone: prefs.discoverableByPhone,
        discoverableByName: prefs.discoverableByName,
        lastSeen: _wire(prefs.lastSeen),
        online: _wire(prefs.online),
        groupAdd: _wire(prefs.groupAdd),
      ),
    );
  }

  @override
  Stream<List<BlockedPerson>> watchBlocked() async* {
    final engine = (await _ref.read(runtimeProvider.future)).engine;
    yield* engine.people.watchAll().map(
      (people) => [
        for (final p in people)
          if (p.blocked)
            BlockedPerson(id: p.accountId, name: PersonName.fromRow(p).display),
      ],
    );
  }

  @override
  Future<void> unblock(String accountId) async {
    final engine = (await _ref.read(runtimeProvider.future)).engine;
    await engine.people.unblock(accountId);
  }

  @override
  Stream<List<MutedChat>> watchMuted() async* {
    final engine = (await _ref.read(runtimeProvider.future)).engine;
    yield* engine.chats.watchChats().asyncMap((active) async {
      final archived = await engine.chats.watchChats(archived: true).first;
      final now = DateTime.now();
      return [
        for (final item in [...active, ...archived])
          if (item.conversation.mutedUntil?.isAfter(now) ?? false)
            MutedChat(
              id: item.conversation.id,
              title: (item.conversation.title ?? '').trim().isEmpty
                  ? 'Chat'
                  : item.conversation.title!.trim(),
              until: item.conversation.mutedUntil,
            ),
      ];
    });
  }

  @override
  Future<void> unmute(String chatId) async {
    final engine = (await _ref.read(runtimeProvider.future)).engine;
    await engine.chats.setMutedUntil(chatId, null);
  }

  @override
  Future<ServerDetails> serverDetails() async {
    final runtime = await _ref.read(runtimeProvider.future);
    final info = await runtime.api.ops.serverInfo();
    return ServerDetails(
      name: info.name,
      host: runtime.serverUrl.host,
      version: info.version,
      openRegistration:
          info.registration == proto.RegistrationMode.phone ||
          info.registration == proto.RegistrationMode.invite,
      maxAttachmentBytes: info.maxAttachmentBytes,
      termsVersion: info.termsVersion,
      privacyVersion: info.privacyVersion,
      federationDomain: info.federationDomain,
      features: info.features,
    );
  }

  @override
  Future<LegalText> legal() async {
    try {
      final api = (await _ref.read(runtimeProvider.future)).api;
      final d = await api.ops.legal();
      return LegalText(
        termsTitle: d.termsTitle,
        termsVersion: d.termsVersion,
        terms: d.terms,
        privacyTitle: d.privacyTitle,
        privacyVersion: d.privacyVersion,
        privacy: d.privacy,
        fromServer: true,
      );
    } on Object {
      // Offline: the documents shipped with the app are the same versions the
      // sign-in page shows.
      return const LegalText(
        termsTitle: proto.HelixLegalDocuments.termsTitle,
        termsVersion: proto.HelixLegalDocuments.termsVersion,
        terms: proto.HelixLegalDocuments.termsOfService,
        privacyTitle: proto.HelixLegalDocuments.privacyTitle,
        privacyVersion: proto.HelixLegalDocuments.privacyVersion,
        privacy: proto.HelixLegalDocuments.privacyPolicy,
      );
    }
  }

  @override
  Future<void> syncNow() async {
    final engine = (await _ref.read(runtimeProvider.future)).engine;
    await engine.syncOnce();
  }

  static AudienceChoice _audience(proto.Audience a) => switch (a) {
    proto.Audience.everyone => AudienceChoice.everyone,
    proto.Audience.contacts => AudienceChoice.contacts,
    proto.Audience.nobody => AudienceChoice.nobody,
  };

  static proto.Audience _wire(AudienceChoice a) => switch (a) {
    AudienceChoice.everyone => proto.Audience.everyone,
    AudienceChoice.contacts => proto.Audience.contacts,
    AudienceChoice.nobody => proto.Audience.nobody,
  };
}
