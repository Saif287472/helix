import 'dart:convert';

import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/src/backup/errors.dart';
import 'package:helix_remote_engine/src/backup/models.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:meta/meta.dart';

/// Where the backup feature keeps its bookkeeping: typed settings holding
/// small JSON documents (the schema has no tables for it, and none is needed:
/// the heavy data is in `transfer_chunks` and on the server).
abstract final class BackupSettings {
  /// The "back up automatically" switch; null means the engine's default.
  static const autoBackup = Setting<bool?>('backup.auto', null);

  /// The last history-backup attempt ([HistoryBackupState]).
  static const history = Setting<String?>('backup.history', null);

  /// The last full backup ([FullBackupState]).
  static const full = Setting<String?>('backup.full', null);

  /// Offers from this account's other devices ([IncomingOffer] by id).
  static const incoming = Setting<String?>('backup.transfers.in', null);

  /// Transfers this device offered ([OutgoingTransfer] by id).
  static const outgoing = Setting<String?>('backup.transfers.out', null);

  /// The newest device link time already considered for an automatic offer
  /// (epoch ms; null: this device's own link time).
  static const offerCursor = Setting<int?>('backup.transfers.cursor', null);
}

/// The history backup's own record of itself.
@immutable
final class HistoryBackupState {
  const HistoryBackupState({
    this.version = 0,
    this.at,
    this.attemptAt,
    this.messages = 0,
    this.bytes = 0,
    this.truncated = false,
    this.failure,
  });

  /// The highest server version this device wrote or merged. A new upload is
  /// `version + 1`; the server refuses it when another device got further.
  final int version;
  final DateTime? at;
  final DateTime? attemptAt;
  final int messages;
  final int bytes;
  final bool truncated;
  final BackupFailure? failure;

  HistoryBackupState copyWith({
    int? version,
    DateTime? at,
    DateTime? attemptAt,
    int? messages,
    int? bytes,
    bool? truncated,
    BackupFailure? failure,
    bool clearFailure = false,
  }) => HistoryBackupState(
    version: version ?? this.version,
    at: at ?? this.at,
    attemptAt: attemptAt ?? this.attemptAt,
    messages: messages ?? this.messages,
    bytes: bytes ?? this.bytes,
    truncated: truncated ?? this.truncated,
    failure: clearFailure ? null : failure ?? this.failure,
  );

  String encode() => jsonEncode(
    compact({
      'version': version,
      'at': at?.millisecondsSinceEpoch,
      'attempt': attemptAt?.millisecondsSinceEpoch,
      'messages': messages,
      'bytes': bytes,
      'truncated': truncated ? true : null,
      'failure': failure?.name,
    }),
  );

  static HistoryBackupState decode(String? text) {
    if (text == null) return const HistoryBackupState();
    try {
      final r = JsonReader.decode(text);
      return HistoryBackupState(
        version: r.optInt('version') ?? 0,
        at: r.optTime('at'),
        attemptAt: r.optTime('attempt'),
        messages: r.optInt('messages') ?? 0,
        bytes: r.optInt('bytes') ?? 0,
        truncated: r.flag('truncated'),
        failure: BackupFailure.values.asNameMap()[r.optString('failure')],
      );
    } on FormatException {
      return const HistoryBackupState();
    }
  }
}

/// The last full backup this device made or restored.
@immutable
final class FullBackupState {
  const FullBackupState({this.version = 0, this.at});

  final int version;
  final DateTime? at;

  String encode() => jsonEncode(
    compact({'version': version, 'at': at?.millisecondsSinceEpoch}),
  );

  static FullBackupState decode(String? text) {
    if (text == null) return const FullBackupState();
    try {
      final r = JsonReader.decode(text);
      return FullBackupState(
        version: r.optInt('version') ?? 0,
        at: r.optTime('at'),
      );
    } on FormatException {
      return const FullBackupState();
    }
  }
}

/// An offer from another of this account's devices, as the receiver tracks it.
@immutable
final class IncomingOffer {
  const IncomingOffer({
    required this.transferId,
    required this.fromDevice,
    required this.receivedAt,
    required this.manifest,
    this.phase = HistoryTransferPhase.waiting,
    this.segments,
    this.imported = 0,
    this.error,
  });

  final String transferId;
  final String fromDevice;
  final DateTime receivedAt;

  /// The relay pointer from the offer: an encrypted manifest.
  final MediaPointer manifest;
  final HistoryTransferPhase phase;

  /// The segments the manifest listed, once it was fetched; their order is
  /// the chunk sequence.
  final List<MediaPointer>? segments;

  /// How many segments (in order) have been applied to the database.
  final int imported;

  /// The last failure, a [BackupFailure] name.
  final String? error;

  int get total => segments?.length ?? 0;

  IncomingOffer copyWith({
    HistoryTransferPhase? phase,
    List<MediaPointer>? segments,
    int? imported,
    String? error,
    bool clearError = false,
  }) => IncomingOffer(
    transferId: transferId,
    fromDevice: fromDevice,
    receivedAt: receivedAt,
    manifest: manifest,
    phase: phase ?? this.phase,
    segments: segments ?? this.segments,
    imported: imported ?? this.imported,
    error: clearError ? null : error ?? this.error,
  );

  JsonMap toJson() => compact({
    'id': transferId,
    'from': fromDevice,
    'at': receivedAt.millisecondsSinceEpoch,
    'manifest': manifest.toJson(),
    'phase': phase.name,
    'segments': segments == null
        ? null
        : [for (final s in segments!) s.toJson()],
    'imported': imported,
    'error': error,
  });

  factory IncomingOffer.fromJson(JsonReader r) => IncomingOffer(
    transferId: r.nonEmpty('id'),
    fromDevice: r.string('from'),
    receivedAt: r.time('at'),
    manifest: MediaPointer.fromJson(r.object('manifest')),
    phase:
        HistoryTransferPhase.values.asNameMap()[r.optString('phase')] ??
        HistoryTransferPhase.failed,
    segments: r.has('segments')
        ? r.objects('segments', MediaPointer.fromJson)
        : null,
    imported: r.optInt('imported') ?? 0,
    error: r.optString('error'),
  );
}

/// A transfer this device offered, kept so its relay objects can be removed
/// once every recipient answered (or after a while).
@immutable
final class OutgoingTransfer {
  const OutgoingTransfer({
    required this.transferId,
    required this.createdAt,
    this.phase = HistoryTransferPhase.preparing,
    this.mediaIds = const [],
    this.recipients = const [],
    this.answered = const [],
  });

  final String transferId;
  final DateTime createdAt;
  final HistoryTransferPhase phase;

  /// Relay objects (segments and the manifest) to delete afterwards.
  final List<String> mediaIds;

  /// The devices the offer went to, and the ones that answered.
  final List<String> recipients;
  final List<String> answered;

  bool get allAnswered =>
      recipients.isNotEmpty && recipients.every(answered.contains);

  OutgoingTransfer copyWith({
    HistoryTransferPhase? phase,
    List<String>? mediaIds,
    List<String>? recipients,
    List<String>? answered,
  }) => OutgoingTransfer(
    transferId: transferId,
    createdAt: createdAt,
    phase: phase ?? this.phase,
    mediaIds: mediaIds ?? this.mediaIds,
    recipients: recipients ?? this.recipients,
    answered: answered ?? this.answered,
  );

  JsonMap toJson() => {
    'id': transferId,
    'at': createdAt.millisecondsSinceEpoch,
    'phase': phase.name,
    'media': mediaIds,
    'to': recipients,
    'answered': answered,
  };

  factory OutgoingTransfer.fromJson(JsonReader r) => OutgoingTransfer(
    transferId: r.nonEmpty('id'),
    createdAt: r.time('at'),
    phase:
        HistoryTransferPhase.values.asNameMap()[r.optString('phase')] ??
        HistoryTransferPhase.failed,
    mediaIds: r.optStrings('media'),
    recipients: r.optStrings('to'),
    answered: r.optStrings('answered'),
  );
}

/// Reads and writes the two transfer ledgers. Shared by the service and by
/// the inbound pipeline's hook (which runs inside the envelope's
/// transaction), so every change is a read-modify-write inside
/// `db.transaction`.
final class TransferLedger {
  const TransferLedger(this._db);

  final HelixDb _db;

  /// Offers kept at most; more are ignored (a misbehaving own device cannot
  /// grow the table).
  static const maxOffers = 20;

  /// The most a manifest pointer may claim, in plaintext bytes.
  static const maxManifestBytes = 1024 * 1024;

  // ----------------------------------------------------------- incoming

  Future<Map<String, IncomingOffer>> incoming() async =>
      _readIncoming(await _db.settingsDao.get(BackupSettings.incoming));

  Stream<Map<String, IncomingOffer>> watchIncoming() =>
      _db.settingsDao.watch(BackupSettings.incoming).map(_readIncoming);

  static Map<String, IncomingOffer> _readIncoming(String? text) {
    if (text == null) return const {};
    try {
      final r = JsonReader.decode(text);
      return {
        for (final key in r.json.keys)
          key: IncomingOffer.fromJson(r.object(key)),
      };
    } on FormatException {
      return const {};
    }
  }

  Future<void> _writeIncoming(
    Map<String, IncomingOffer> offers,
    DateTime now,
  ) => _db.settingsDao.set(
    BackupSettings.incoming,
    offers.isEmpty
        ? null
        : jsonEncode({for (final e in offers.entries) e.key: e.value.toJson()}),
    now: now,
  );

  /// Records an offer (idempotent: a repeat keeps the state it reached).
  /// Returns whether it was newly recorded.
  Future<bool> recordOffer({
    required String transferId,
    required String fromDevice,
    required MediaPointer manifest,
    required DateTime now,
  }) => _db.transaction(() async {
    final offers = {...await incoming()};
    if (offers.containsKey(transferId) || offers.length >= maxOffers) {
      return false;
    }
    offers[transferId] = IncomingOffer(
      transferId: transferId,
      fromDevice: fromDevice,
      receivedAt: now,
      manifest: manifest,
    );
    await _writeIncoming(offers, now);
    return true;
  });

  /// Changes one offer; no-op when it is gone. Returns the new value.
  Future<IncomingOffer?> updateIncoming(
    String transferId,
    IncomingOffer Function(IncomingOffer offer) change, {
    required DateTime now,
  }) => _db.transaction(() async {
    final offers = {...await incoming()};
    final current = offers[transferId];
    if (current == null) return null;
    final next = change(current);
    offers[transferId] = next;
    await _writeIncoming(offers, now);
    return next;
  });

  Future<void> removeIncoming(String transferId, {required DateTime now}) =>
      _db.transaction(() async {
        final offers = {...await incoming()};
        if (offers.remove(transferId) != null) {
          await _writeIncoming(offers, now);
        }
        await _db.transfersDao.dropTransfer(transferId);
      });

  // ----------------------------------------------------------- outgoing

  Future<Map<String, OutgoingTransfer>> outgoing() async {
    final text = await _db.settingsDao.get(BackupSettings.outgoing);
    if (text == null) return const {};
    try {
      final r = JsonReader.decode(text);
      return {
        for (final key in r.json.keys)
          key: OutgoingTransfer.fromJson(r.object(key)),
      };
    } on FormatException {
      return const {};
    }
  }

  Future<void> _writeOutgoing(
    Map<String, OutgoingTransfer> all,
    DateTime now,
  ) => _db.settingsDao.set(
    BackupSettings.outgoing,
    all.isEmpty
        ? null
        : jsonEncode({for (final e in all.entries) e.key: e.value.toJson()}),
    now: now,
  );

  Future<OutgoingTransfer?> updateOutgoing(
    String transferId,
    OutgoingTransfer? Function(OutgoingTransfer? current) change, {
    required DateTime now,
  }) => _db.transaction(() async {
    final all = {...await outgoing()};
    final next = change(all[transferId]);
    if (next == null) {
      all.remove(transferId);
    } else {
      all[transferId] = next;
    }
    await _writeOutgoing(all, now);
    return next;
  });

  /// A device answered an offer of ours (`done` or `declined`).
  Future<void> recordAnswer(
    String transferId,
    String device, {
    required DateTime now,
  }) async {
    await updateOutgoing(transferId, (t) {
      if (t == null || t.answered.contains(device)) return t;
      return t.copyWith(answered: [...t.answered, device]);
    }, now: now);
  }
}
