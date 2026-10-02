import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:helix_remote_api/v2.dart' show ApiException, CancellationToken;
import 'package:helix_remote_crypto/v2.dart';
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/src/account/device_service.dart';
import 'package:helix_remote_engine/src/backup/archive.dart';
import 'package:helix_remote_engine/src/backup/errors.dart';
import 'package:helix_remote_engine/src/backup/models.dart';
import 'package:helix_remote_engine/src/backup/options.dart';
import 'package:helix_remote_engine/src/backup/snapshot.dart';
import 'package:helix_remote_engine/src/backup/state.dart';
import 'package:helix_remote_engine/src/context.dart';
import 'package:helix_remote_engine/src/messaging/outbox.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// Device-to-device history transfer (F2, CONTENT_V2.md §4
/// `device_transfer_offer`), adapted to v2.
///
/// ```
/// sender                                         receiver (another own device)
/// export (pages -> frames -> segments)
/// each segment: AES-GCM STREAM, random key,
///   uploaded as a relay object (media, random id)
/// manifest {segments: [pointer...]}, same way
/// offer ---- pairwise-encrypted content ------> record the offer
///   {transfer_id, relay_media: manifest}          fetch + decrypt the manifest
///                                                 fetch each segment, check its
///                                                 digest, decrypt, keep it as a
///                                                 chunk (transfer_chunks)
///                                                 gap? ask the relay again for
///                                                 just those sequences
///                                                 all there: import in order,
///                                                 a frame per transaction
/// <----------- done / declined ----------------- answer
/// delete the relay objects when everybody answered (or after 48 h)
/// ```
///
/// Everything that identifies or opens the history (the manifest's key, every
/// segment's key and digest) travels only inside the pairwise-encrypted offer;
/// the relay sees random ids and ciphertext. Only the account's own devices
/// can send or act on an offer (the inbound hook checks the authenticated
/// sender account), and an archive is only imported when its header names this
/// account and this transfer.
///
/// Memory: the sender holds one segment (about 4 MiB) at a time; the receiver
/// holds one chunk at a time while importing.
///
/// The transport is the media relay, not the mailbox: the relay stores
/// attachment-kind objects for up to 30 days and the server has no route that
/// relays raw transfer chunks. (CONTENT_V2.md leaves `relay_media` optional;
/// without it there is nothing to fetch, so such an offer is ignored.)
final class DeviceTransferJob {
  DeviceTransferJob(
    this._ctx,
    this._options,
    this._relay,
    this._exporter,
    this._importer,
    this._outbox,
    this._devices, {
    required this._onProgress,
  });

  final EngineContext _ctx;
  final BackupOptions _options;
  final RelayStore _relay;
  final SnapshotExporter _exporter;
  final SnapshotImporter _importer;
  final OutboxService _outbox;
  final DeviceService _devices;
  final void Function(TransferProgress) _onProgress;

  /// What a relay segment's pointer says about its content.
  static const mime = 'application/octet-stream';
  static const manifestVersion = 1;
  static const maxSegments = 4096;
  static const maxSegmentBytes = 64 * 1024 * 1024;

  final Map<String, CancellationToken> _sending = {};
  final Map<String, CancellationToken> _receiving = {};
  final Map<String, Future<RestoreResult>> _accepting = {};
  final Set<String> _paused = {};

  HelixDb get _db => _ctx.db;
  TransferLedger get _ledger => TransferLedger(_db);

  // ----------------------------------------------------------- the sender

  /// Exports the history, uploads it to the relay in segments and offers it to
  /// [to] (default: every other device of the account). Completes once the
  /// offer is queued for sending (the outbox delivers it) and returns the
  /// transfer id; progress is on the progress stream. Throws
  /// [BackupException] (`noOtherDevices`, `cancelled`, `offline`, ...); what
  /// was uploaded is removed again on failure.
  Future<String> send({List<String>? to}) async {
    final identity = _ctx.identity;
    try {
      // A device that joined since the list was last read is a recipient.
      await _devices.refresh();
    } on Object {
      // Offline: the stored list is the best there is.
    }
    final others = await _devices.otherDeviceIds();
    final recipients = to == null
        ? others.toList()
        : [
            for (final d in to)
              if (others.contains(d)) d,
          ];
    if (recipients.isEmpty) {
      throw const BackupException(BackupFailure.noOtherDevices);
    }
    recipients.sort();
    final id = _ctx.ids.next();
    final token = _sending[id] = CancellationToken();
    final now = _ctx.now();
    await _ledger.updateOutgoing(
      id,
      (_) => OutgoingTransfer(
        transferId: id,
        createdAt: now,
        recipients: recipients,
      ),
      now: now,
    );
    var done = 0;
    void progress(HistoryTransferPhase phase, {BackupFailure? failure}) => _onProgress(
      TransferProgress(
        transferId: id,
        role: TransferRole.sending,
        phase: phase,
        done: done,
        failure: failure,
      ),
    );
    progress(HistoryTransferPhase.preparing);
    final uploaded = <String>[];
    try {
      final segments = <MediaPointer>[];
      final buffer = BytesBuilder(copy: false);
      final stats = ExportStats();
      Future<void> flush() async {
        final bytes = buffer.takeBytes();
        segments.add(await _put(id, bytes, uploaded, token));
        done = segments.length;
        progress(HistoryTransferPhase.preparing);
      }

      await for (final frame in _exporter.export(
        kind: ArchiveKind.transfer,
        stats: stats,
        transferId: id,
        cancel: token,
      )) {
        buffer.add(frame.bytes);
        if (buffer.length >= _options.segmentBytes) await flush();
      }
      if (buffer.length > 0 || segments.isEmpty) await flush();
      final manifest = await _put(
        id,
        utf8.encode(
          jsonEncode({
            'v': manifestVersion,
            'transfer': id,
            'account': identity.accountId,
            'created': toWireTime(now),
            'messages': stats.messages,
            'segments': [for (final s in segments) s.toJson()],
          }),
        ),
        uploaded,
        token,
      );
      if (token.isCancelled) {
        throw const BackupException(BackupFailure.cancelled);
      }
      await _db.transaction(() async {
        await _ledger.updateOutgoing(
          id,
          (t) => t?.copyWith(phase: HistoryTransferPhase.offered),
          now: _ctx.now(),
        );
        await _enqueue(
          DeviceTransferOfferBody(
            transferId: id,
            relayMedia: manifest,
            devices: recipients,
          ),
        );
      });
      progress(HistoryTransferPhase.offered);
      return id;
    } on Object catch (error) {
      final failure = BackupException.translate(error);
      await _discard(id, uploaded);
      progress(
        failure is BackupException
            ? (failure.failure == BackupFailure.cancelled
                  ? HistoryTransferPhase.cancelled
                  : HistoryTransferPhase.failed)
            : HistoryTransferPhase.failed,
        failure: failure is BackupException ? failure.failure : null,
      );
      if (failure is BackupException) throw failure;
      rethrow;
    } finally {
      _sending.remove(id);
    }
  }

  /// Encrypts [plain] under a fresh key, uploads it and returns its pointer.
  /// Every uploaded id is recorded as it lands, so a crash leaves a ledger
  /// entry that maintenance can still clean up.
  Future<MediaPointer> _put(
    String transferId,
    List<int> plain,
    List<String> uploaded,
    CancellationToken token,
  ) async {
    if (token.isCancelled) {
      throw const BackupException(BackupFailure.cancelled);
    }
    final key = AttachmentCrypto.newKey(_ctx.random);
    final sealed = await AttachmentCrypto.encryptBytes(
      plain,
      key,
      random: _ctx.random,
    );
    final mediaId = await _relay.upload(sealed.ciphertext, cancel: token);
    uploaded.add(mediaId);
    await _ledger.updateOutgoing(
      transferId,
      (t) => t?.copyWith(mediaIds: List.of(uploaded)),
      now: _ctx.now(),
    );
    return MediaPointer(
      id: mediaId,
      key: key,
      digest: sealed.digest,
      size: plain.length,
      mime: mime,
    );
  }

  /// Withdraws an offer or abandons a running export: stops the upload,
  /// deletes the relay objects and tells the receivers.
  Future<void> cancelSend(String transferId) async {
    _sending[transferId]?.cancel();
    final current = (await _ledger.outgoing())[transferId];
    if (current == null) return;
    await _discard(transferId, current.mediaIds, keepEntry: false);
    if (current.phase == HistoryTransferPhase.offered) {
      await _enqueue(
        DeviceTransferOfferBody(
          transferId: transferId,
          state: DeviceTransferState.cancelled,
          devices: current.recipients,
        ),
      );
    }
    _onProgress(
      TransferProgress(
        transferId: transferId,
        role: TransferRole.sending,
        phase: HistoryTransferPhase.cancelled,
      ),
    );
  }

  Future<void> _discard(
    String transferId,
    Iterable<String> mediaIds, {
    bool keepEntry = false,
  }) async {
    for (final media in mediaIds) {
      try {
        await _relay.delete(media);
      } on Object {
        // Gone already, or unreachable: the server expires it anyway.
      }
    }
    await _ledger.updateOutgoing(
      transferId,
      (t) => keepEntry ? t?.copyWith(mediaIds: const []) : null,
      now: _ctx.now(),
    );
  }

  Future<void> _enqueue(DeviceTransferOfferBody body) {
    final self = _ctx.identity.accountId;
    return _outbox.enqueueContent(
      content: ContentMessage(
        id: _ctx.ids.next(),
        sentAt: _ctx.now(),
        conversation: DirectConversation(to: self),
        body: body,
      ),
      audience: [self],
      urgent: false,
    );
  }

  // --------------------------------------------------------- the receiver

  /// Fetches and imports an offer (merging into the local history). Safe to
  /// call again after a failure or a crash: chunks already fetched are kept
  /// (`transfer_chunks`, gap-checked) and segments already applied are not
  /// applied twice. Concurrent calls for one offer share one run.
  Future<RestoreResult> accept(String transferId) =>
      _accepting[transferId] ??= _accept(transferId).whenComplete(() {
        // A block body: `remove` returns this very future.
        _accepting.remove(transferId);
      });

  Future<RestoreResult> _accept(String id) async {
    var offer = (await _ledger.incoming())[id];
    if (offer == null) throw const BackupException(BackupFailure.noBackup);
    if (offer.phase == HistoryTransferPhase.cancelled) {
      throw const BackupException(BackupFailure.cancelled);
    }
    if (offer.phase == HistoryTransferPhase.done) {
      // Already imported (a repeat tap, a second device asking): nothing to do.
      return const RestoreResult(version: 0, added: 0, existing: 0, invalid: 0);
    }
    final token = _receiving[id] = CancellationToken();
    void progress(
      HistoryTransferPhase phase,
      int done,
      int total, [
      BackupFailure? f,
    ]) => _onProgress(
      TransferProgress(
        transferId: id,
        role: TransferRole.receiving,
        phase: phase,
        done: done,
        total: total,
        failure: f,
      ),
    );
    try {
      offer = await _setPhase(id, HistoryTransferPhase.downloading);
      progress(HistoryTransferPhase.downloading, 0, offer.total);

      final segments = offer.segments ?? await _fetchManifest(offer, token);
      if (offer.segments == null) {
        offer = await _ledger.updateIncoming(
          id,
          (o) => o.copyWith(segments: segments),
          now: _ctx.now(),
        );
      }
      final total = segments.length;
      // Fetch only what is missing: a resumed transfer asks the relay for the
      // gaps and nothing else.
      final missing =
          await _db.transfersDao.missingSequences(id) ??
          [for (var i = 0; i < total; i++) i];
      var have = total - missing.length;
      for (final seq in missing) {
        await _checkLive(id, token);
        final plain = await _fetchSegment(segments[seq], token);
        await _db.transfersDao.addChunk(
          transferId: id,
          sequence: seq,
          payload: plain,
          total: total,
          isFinal: seq == total - 1,
          now: _ctx.now(),
        );
        progress(HistoryTransferPhase.downloading, ++have, total);
      }
      if (!await _db.transfersDao.isComplete(id)) {
        throw const BackupException(BackupFailure.incomplete);
      }

      offer = await _setPhase(id, HistoryTransferPhase.importing);
      progress(HistoryTransferPhase.importing, offer.imported, total);
      final session = _importer.begin(
        kind: ArchiveKind.transfer,
        transferId: id,
        headerChecked: offer.imported > 0,
      );
      final store = HistoryStore(_db);
      for (var seq = offer.imported; seq < total; seq++) {
        await _checkLive(id, token);
        final chunk = await store.chunk(id, seq);
        if (chunk == null) {
          throw const BackupException(BackupFailure.incomplete);
        }
        for (final frame in ArchiveReader.frames(
          chunk.payload,
          gzip: _options.gzip,
        )) {
          await session.addFrame(frame);
        }
        await _ledger.updateIncoming(
          id,
          (o) => o.copyWith(imported: seq + 1),
          now: _ctx.now(),
        );
        progress(HistoryTransferPhase.importing, seq + 1, total);
      }
      session.finish();

      await _ledger.updateIncoming(
        id,
        (o) => o.copyWith(phase: HistoryTransferPhase.done, clearError: true),
        now: _ctx.now(),
      );
      await _db.transfersDao.dropTransfer(id);
      await _enqueue(
        DeviceTransferOfferBody(
          transferId: id,
          state: DeviceTransferState.done,
          devices: [offer.fromDevice],
        ),
      );
      progress(HistoryTransferPhase.done, total, total);
      return RestoreResult(
        version: 0,
        added: session.report.messagesAdded,
        existing: session.report.messagesExisting,
        invalid: session.report.invalidRecords,
      );
    } on Object catch (error) {
      final failure = BackupException.translate(error);
      final code = failure is BackupException ? failure.failure : null;
      if (code == BackupFailure.cancelled && _paused.remove(id)) {
        // The user paused: keep the chunks and what was applied.
        await _ledger.updateIncoming(
          id,
          (o) => o.copyWith(phase: HistoryTransferPhase.waiting, clearError: true),
          now: _ctx.now(),
        );
        progress(
          HistoryTransferPhase.waiting,
          offer?.imported ?? 0,
          offer?.total ?? 0,
        );
      } else if (code == BackupFailure.cancelled) {
        // A withdrawn offer (or the user's cancel): drop what was fetched.
        await _ledger.updateIncoming(
          id,
          (o) => o.copyWith(phase: HistoryTransferPhase.cancelled),
          now: _ctx.now(),
        );
        await _db.transfersDao.dropTransfer(id);
        progress(HistoryTransferPhase.cancelled, 0, 0, code);
      } else if (code != null) {
        // Trouble the network may fix stays "waiting" with its chunks, to be
        // resumed; anything else (a bad digest, the wrong key, a gone relay
        // object) ends this offer and says so to the sender.
        final transient = code == BackupFailure.offline;
        await _ledger.updateIncoming(
          id,
          (o) => o.copyWith(
            phase: transient ? HistoryTransferPhase.waiting : HistoryTransferPhase.failed,
            error: code.name,
          ),
          now: _ctx.now(),
        );
        if (!transient) {
          await _db.transfersDao.dropTransfer(id);
          final from = offer?.fromDevice;
          if (from != null) {
            await _enqueue(
              DeviceTransferOfferBody(
                transferId: id,
                state: DeviceTransferState.declined,
                devices: [from],
              ),
            );
          }
        }
        progress(
          transient ? HistoryTransferPhase.waiting : HistoryTransferPhase.failed,
          0,
          offer?.total ?? 0,
          code,
        );
      }
      if (failure is BackupException) throw failure;
      rethrow;
    } finally {
      _receiving.remove(id);
      _paused.remove(id);
    }
  }

  Future<IncomingOffer> _setPhase(String id, HistoryTransferPhase phase) async =>
      (await _ledger.updateIncoming(
        id,
        (o) => o.copyWith(phase: phase, clearError: true),
        now: _ctx.now(),
      ))!;

  Future<void> _checkLive(String id, CancellationToken token) async {
    final current = (await _ledger.incoming())[id];
    if (token.isCancelled ||
        current == null ||
        current.phase == HistoryTransferPhase.cancelled) {
      throw const BackupException(BackupFailure.cancelled);
    }
  }

  Future<List<MediaPointer>> _fetchManifest(
    IncomingOffer offer,
    CancellationToken token,
  ) async {
    final plain = await _fetch(offer.manifest, token);
    final JsonReader r;
    try {
      r = JsonReader.decode(utf8.decode(plain));
    } on FormatException {
      throw const BackupException(BackupFailure.corrupt, 'manifest');
    }
    try {
      if (r.integer('v') > manifestVersion) {
        throw const BackupException(BackupFailure.newerFormat, 'manifest');
      }
      if (r.string('transfer') != offer.transferId ||
          r.string('account') != _ctx.identity.accountId) {
        throw const BackupException(BackupFailure.corrupt, 'manifest identity');
      }
      final segments = r.objects('segments', MediaPointer.fromJson);
      if (segments.isEmpty ||
          segments.length > maxSegments ||
          segments.any((s) => s.size < 0 || s.size > maxSegmentBytes)) {
        throw const BackupException(BackupFailure.corrupt, 'manifest size');
      }
      return segments;
    } on FormatException {
      throw const BackupException(BackupFailure.corrupt, 'manifest');
    }
  }

  Future<Uint8List> _fetchSegment(
    MediaPointer pointer,
    CancellationToken token,
  ) => _fetch(pointer, token);

  /// Downloads a relay object, checks its digest, decrypts it, and checks the
  /// size the pointer promised.
  Future<Uint8List> _fetch(
    MediaPointer pointer,
    CancellationToken token,
  ) async {
    final Uint8List ciphertext;
    try {
      ciphertext = await _relay.download(pointer.id, cancel: token);
    } on ApiException catch (e) {
      if (e.code == ErrorCode.notFound || e.code == ErrorCode.expired) {
        throw const BackupException(BackupFailure.expired, 'relay object');
      }
      rethrow;
    }
    final Uint8List plain;
    try {
      plain = await AttachmentCrypto.decryptBytes(
        ciphertext,
        pointer.key,
        digest: pointer.digest,
      );
    } on CryptoV2Exception {
      throw const BackupException(BackupFailure.corrupt, 'relay object');
    }
    if (plain.length != pointer.size) {
      throw const BackupException(BackupFailure.corrupt, 'relay object size');
    }
    return plain;
  }

  /// Declines an offer (the sender may then clean up) and forgets it.
  Future<void> decline(String transferId) async {
    final offer = (await _ledger.incoming())[transferId];
    if (offer == null) return;
    _receiving[transferId]?.cancel();
    await _ledger.updateIncoming(
      transferId,
      (o) => o.copyWith(phase: HistoryTransferPhase.declined),
      now: _ctx.now(),
    );
    await _db.transfersDao.dropTransfer(transferId);
    await _enqueue(
      DeviceTransferOfferBody(
        transferId: transferId,
        state: DeviceTransferState.declined,
        devices: [offer.fromDevice],
      ),
    );
    _onProgress(
      TransferProgress(
        transferId: transferId,
        role: TransferRole.receiving,
        phase: HistoryTransferPhase.declined,
      ),
    );
  }

  /// Stops a running fetch or import; the offer stays and may be accepted
  /// again.
  void pause(String transferId) {
    final token = _receiving[transferId];
    if (token == null) return;
    _paused.add(transferId);
    token.cancel();
  }

  // ---------------------------------------------------------- housekeeping

  /// Removes relay objects whose offer was answered by everybody, withdrawn
  /// or has outlived [BackupOptions.relayTtl]; drops stale offers.
  Future<void> cleanUp() async {
    final now = _ctx.now();
    for (final t in (await _ledger.outgoing()).values) {
      final old = now.difference(t.createdAt) > _options.relayTtl;
      if (t.allAnswered || old || t.phase == HistoryTransferPhase.failed) {
        await _discard(t.transferId, t.mediaIds);
      }
    }
    for (final o in (await _ledger.incoming()).values) {
      final age = now.difference(o.receivedAt);
      final stale = switch (o.phase) {
        HistoryTransferPhase.done ||
        HistoryTransferPhase.declined ||
        HistoryTransferPhase.cancelled => age > const Duration(days: 1),
        HistoryTransferPhase.failed => age > const Duration(days: 2),
        _ => age > _options.offerTtl,
      };
      if (stale) await _ledger.removeIncoming(o.transferId, now: now);
    }
  }

  /// This account's devices in the order that decides who sends an
  /// automatic offer: the longest-linked device first.
  Future<List<SelfDeviceRow>> senderOrder() async {
    final rows = await _db.accountDao.devices();
    final sorted = [...rows]
      ..sort((a, b) {
        final byTime = (a.linkedAt?.millisecondsSinceEpoch ?? 0).compareTo(
          b.linkedAt?.millisecondsSinceEpoch ?? 0,
        );
        return byTime != 0 ? byTime : a.deviceId.compareTo(b.deviceId);
      });
    return sorted;
  }
}
