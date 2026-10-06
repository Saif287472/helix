import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/engine/helix_runtime.dart';
import 'package:helix_remote/core/engine/runtime_providers.dart';
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart'
    show ReportCategory;
import 'package:helix_remote_ui/helix_remote_ui.dart' show HelixQrMatrix;
import 'package:qr_flutter/qr_flutter.dart'
    show QrCode, QrErrorCorrectLevel, QrImage;

/// A group, as the people screens need it (the groups in common with
/// somebody, and group results in a search).
final class GroupSummary {
  const GroupSummary({required this.id, required this.title});

  /// The group id; its conversation is `group:<id>`.
  final String id;
  final String title;

  String get conversationId => GroupIds.conversationId(id);

  @override
  bool operator ==(Object other) =>
      other is GroupSummary && other.id == id && other.title == title;

  @override
  int get hashCode => Object.hash(id, title);
}

/// The safety number of a chat, as plain values: the groups of digits to read
/// out, and the QR payload both phones show for each other to scan.
///
/// The QR carries the payload as unpadded base64url *text*: a scanner reports
/// text reliably, where raw binary in a QR code is read back differently by
/// every camera library.
final class SafetyNumberData {
  const SafetyNumberData({required this.groups, required this.qrPayload});

  /// Twelve groups of five digits.
  final List<String> groups;

  /// `"HXSN" ‖ version ‖ both fingerprints`, from the crypto layer.
  final Uint8List qrPayload;

  /// The text the QR code holds.
  String get qrText => base64Url.encode(qrPayload).replaceAll('=', '');

  /// The QR code as modules for `HelixQrDisplay`.
  HelixQrMatrix get qrMatrix {
    final code = QrCode.fromData(
      data: qrText,
      errorCorrectLevel: QrErrorCorrectLevel.M,
    );
    final image = QrImage(code);
    final size = image.moduleCount;
    return HelixQrMatrix(size, [
      for (var y = 0; y < size; y++)
        for (var x = 0; x < size; x++) image.isDark(y, x),
    ]);
  }

  /// Whether a scanned QR [text] is exactly this chat's payload (both halves,
  /// so both phones agree on the same two keys).
  bool matchesQrText(String text) {
    try {
      final padded = text.trim();
      final bytes = base64Url.decode(
        padded.padRight((padded.length + 3) ~/ 4 * 4, '='),
      );
      return listEquals(bytes, qrPayload);
    } on FormatException {
      return false;
    }
  }
}

/// When the address book was last matched against the server, and what the
/// daily discovery budget looked like then. Kept in the encrypted database so a
/// restart does not forget it and spend the budget twice.
final class PhoneBookSyncLog {
  const PhoneBookSyncLog({
    required this.at,
    required this.checked,
    required this.remainingToday,
  });

  final DateTime at;
  final int checked;
  final int remainingToday;

  Map<String, Object?> toJson() => {
    'at': at.millisecondsSinceEpoch,
    'checked': checked,
    'remaining': remainingToday,
  };

  static PhoneBookSyncLog? fromJson(Object? json) {
    if (json is! Map) return null;
    final at = json['at'];
    final checked = json['checked'];
    final remaining = json['remaining'];
    if (at is! int || checked is! int || remaining is! int) return null;
    return PhoneBookSyncLog(
      at: DateTime.fromMillisecondsSinceEpoch(at, isUtc: true),
      checked: checked,
      remainingToday: remaining,
    );
  }
}

/// Everything the people screens ask of the engine, in one interface.
///
/// `application/` is where the engine is used (plan §6.4); this is the narrow
/// shape of it the people feature needs, so the providers and the screens
/// above can be tested against a fake and never open a database or a socket.
abstract interface class PeopleGateway {
  /// This account's id, or null before sign-in completes.
  String? get selfAccountId;

  /// This account's own phone number (E.164), when it has one: its country
  /// code is how a number typed without one is read.
  Future<String?> ownNumber();

  Stream<PersonRow?> watchPerson(String accountId);

  /// The "about" line from their encrypted profile.
  Stream<String?> watchAbout(String accountId);

  /// The direct chat with them (mute, disappearing timer); null until there
  /// is one.
  Stream<ConversationRow?> watchDirectChat(String accountId);

  Stream<List<GroupSummary>> watchGroups();
  Stream<List<GroupSummary>> watchCommonGroups(String accountId);

  /// Null until a key has been pinned (nothing has been exchanged yet).
  Future<SafetyNumberData?> safetyNumber(String accountId);

  /// Reads and decrypts their profile when the key is here. Best effort.
  Future<void> refreshProfile(String accountId);

  /// Names them (null removes the nickname). The engine keeps the account's
  /// other devices in step and writes the name to the phone's contacts.
  Future<void> setNickname(String accountId, String? nickname);

  Future<void> setVerified(String accountId, {required bool verified});
  Future<void> block(String accountId);
  Future<void> unblock(String accountId);
  Future<void> report(
    String accountId,
    ReportCategory category, {
    String? note,
  });

  /// Mutes the direct chat until [until]; null unmutes.
  Future<void> setMutedUntil(String accountId, DateTime? until);

  /// Sets the chat's disappearing timer; null or 0 turns it off.
  Future<void> setDisappearing(String accountId, int? seconds);

  /// The direct chat with them, created if there is none: its conversation id.
  Future<String> openChat(String accountId);

  /// One discovery lookup by E.164 number. Costs one unit of the daily budget.
  Future<PersonRow?> findByNumber(String e164);

  Future<PersonRow?> findByHelixName(String name);

  /// Matches the address book against the server.
  Future<PhoneBookSyncResult> syncPhoneBook();

  Future<PhoneBookSyncLog?> readSyncLog();
  Future<void> writeSyncLog(PhoneBookSyncLog log);
}

/// The gateway over the live engine.
final class EnginePeopleGateway implements PeopleGateway {
  EnginePeopleGateway(this._runtime);

  final HelixRuntime _runtime;

  Engine get _engine => _runtime.engine;
  HelixDb get _db => _runtime.db;

  static const _syncLog = Setting<String?>('app.phonebook_sync', null);

  @override
  String? get selfAccountId => _engine.accountId;

  @override
  Future<String?> ownNumber() async =>
      (await _db.accountDao.current())?.phoneNumber;

  @override
  Stream<PersonRow?> watchPerson(String accountId) =>
      _engine.people.watchPerson(accountId);

  @override
  Stream<String?> watchAbout(String accountId) =>
      _engine.people.watchAbout(accountId);

  @override
  Stream<ConversationRow?> watchDirectChat(String accountId) =>
      _engine.chats.watchChat(directConversationId(accountId));

  @override
  Stream<List<GroupSummary>> watchGroups() => _engine.groups.watchGroups().map(
    (rows) => [
      for (final row in rows) GroupSummary(id: row.id, title: row.title),
    ],
  );

  @override
  Stream<List<GroupSummary>> watchCommonGroups(String accountId) =>
      _engine.groups.watchGroups().asyncMap((rows) async {
        final common = <GroupSummary>[];
        for (final row in rows) {
          if (await _db.groupsDao.member(row.id, accountId) != null) {
            common.add(GroupSummary(id: row.id, title: row.title));
          }
        }
        return common;
      });

  @override
  Future<SafetyNumberData?> safetyNumber(String accountId) async {
    final number = await _engine.people.safetyNumber(accountId);
    if (number == null) return null;
    return SafetyNumberData(groups: number.groups, qrPayload: number.qrPayload);
  }

  @override
  Future<void> refreshProfile(String accountId) async {
    await _engine.people.refreshProfile(accountId);
  }

  @override
  Future<void> setNickname(String accountId, String? nickname) =>
      _engine.people.setNickname(accountId, nickname);

  @override
  Future<void> setVerified(String accountId, {required bool verified}) =>
      _engine.people.setVerified(accountId, verified: verified);

  @override
  Future<void> block(String accountId) => _engine.people.block(accountId);

  @override
  Future<void> unblock(String accountId) => _engine.people.unblock(accountId);

  @override
  Future<void> report(
    String accountId,
    ReportCategory category, {
    String? note,
  }) => _engine.people.report(accountId, category, note: note);

  @override
  Future<void> setMutedUntil(String accountId, DateTime? until) async {
    final chat = await _engine.chats.openDirect(accountId);
    await _engine.chats.setMutedUntil(chat.id, until);
  }

  @override
  Future<void> setDisappearing(String accountId, int? seconds) async {
    final chat = await _engine.chats.openDirect(accountId);
    await _engine.chats.setDisappearing(chat.id, seconds);
  }

  @override
  Future<String> openChat(String accountId) async =>
      (await _engine.chats.openDirect(accountId)).id;

  @override
  Future<PersonRow?> findByNumber(String e164) =>
      _engine.people.findByNumber(e164);

  @override
  Future<PersonRow?> findByHelixName(String name) =>
      _engine.people.findByHelixName(name);

  @override
  Future<PhoneBookSyncResult> syncPhoneBook() => _engine.people.syncPhoneBook();

  @override
  Future<PhoneBookSyncLog?> readSyncLog() async {
    final stored = await _db.settingsDao.get(_syncLog);
    if (stored == null) return null;
    try {
      return PhoneBookSyncLog.fromJson(jsonDecode(stored));
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> writeSyncLog(PhoneBookSyncLog log) =>
      _db.settingsDao.set(_syncLog, jsonEncode(log.toJson()), now: log.at);
}

/// The people gateway for the live runtime. Tests override this with a fake.
final peopleGatewayProvider = FutureProvider<PeopleGateway>((ref) async {
  final runtime = await ref.watch(runtimeProvider.future);
  return EnginePeopleGateway(runtime);
});
