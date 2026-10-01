import 'dart:convert';
import 'dart:typed_data';

import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/src/kernel/presence.dart';
import 'package:helix_remote_server/src/modules/identity/api.dart';
import 'package:helix_remote_server/src/modules/keys/api.dart';
import 'package:helix_remote_server/src/modules/messaging/api.dart';
import 'package:helix_remote_server/src/modules/messaging/data/mailbox_store.dart';
import 'package:helix_remote_server/src/platform/db/db.dart';
import 'package:helix_remote_server/src/platform/db/migrations.dart';
import 'package:helix_remote_server/src/platform/http/request.dart';
import 'package:helix_remote_server/src/platform/http/routes.dart';
import 'package:helix_remote_server/src/platform/jobs/jobs.dart';
import 'package:helix_remote_server/src/platform/module.dart';
import 'package:helix_remote_server/src/platform/push/push.dart';
import 'package:shelf/shelf.dart';

/// Mailbox delivery (REST_V2.md messaging, ADR-028): the server keeps only
/// undelivered envelopes, one row per recipient device, deleted on ack.
final class MessagingModule extends ModuleBase {
  MessagingModule(
    super.context, {
    required this.identity,
    required KeysApi keys,
  }) {
    _store = MailboxStore(schema);
    api = _MessagingFacade(this);
    identity
      ..onDeviceRevoked((tx, device) => _store.purgeDevice(tx, device.id))
      ..onAccountSignal(_accountSignal)
      ..onDeviceListChanged(_deviceListChanged);
    keys.onPrekeysLow(_prekeysLow);
  }

  final IdentityApi identity;
  late final MailboxStore _store;
  late final MessagingApi api;
  BlockPolicy _blockPolicy = (db, sender, recipients) async => const <String>{};

  static const pushJob = 'messaging.push';
  static const maxRecipients = 1100;

  @override
  String get name => 'messaging';

  @override
  List<Migration> get migrations => const [
    Migration(1, 'mailbox_baseline', mailboxBaseline),
  ];

  @override
  Map<String, JobHandler> get jobs => {pushJob: _push};

  @override
  List<PeriodicJob> get periodic => [
    PeriodicJob('messaging.expire', const Duration(minutes: 10), () async {
      while (await _store.purgeExpired(context.db) > 0) {}
      await _store.purgeSends(context.db);
    }),
  ];

  @override
  void routes(RouteRegistry r) {
    r
      ..add(name, Routes.sendMessage, _send, maxBodyBytes: 8 * 1024 * 1024)
      ..add(name, Routes.mailbox, _mailbox, allowSuspended: true)
      ..add(name, Routes.ackMailbox, _ack, allowSuspended: true);
  }

  // ------------------------------------------------------------------- send

  Future<Response> _send(HelixRequest q) async {
    final me = q.device;
    final req = q.json(SendMessageRequest.fromJson);
    if (!Uuid.isValid(req.id)) {
      throw const ApiError(ErrorCode.invalidField, details: {'field': 'id'});
    }
    if (req.recipients.isEmpty) {
      throw const ApiError(
        ErrorCode.invalidField,
        details: {'field': 'recipients'},
      );
    }
    final previous = await _store.acceptedAt(context.db, req.id);
    if (previous != null) {
      return jsonResponse(
        SendMessageResponse(acceptedAt: previous, replayed: true).toJson(),
      );
    }

    final payloads = <String, Uint8List>{};
    final addressed = <String, Set<String>>{};
    for (final recipient in req.recipients) {
      if (recipient.account.contains('@')) {
        throw const ApiError(
          ErrorCode.federationUnavailable,
          message: 'messages to other servers arrive with federation',
        );
      }
      if (!Uuid.isValid(recipient.account) ||
          addressed.containsKey(recipient.account)) {
        throw const ApiError(
          ErrorCode.invalidField,
          details: {'field': 'recipients'},
        );
      }
      final devices = addressed[recipient.account] = <String>{};
      for (final d in recipient.devices) {
        if (!Uuid.isValid(d.device) ||
            !devices.add(d.device) ||
            d.device == me.deviceId) {
          throw const ApiError(
            ErrorCode.invalidField,
            details: {'field': 'recipients.devices'},
          );
        }
        if (d.payload.isEmpty ||
            d.payload.length > SendMessageRequest.maxPayloadBytes) {
          throw const ApiError(ErrorCode.payloadTooLarge);
        }
        payloads[d.device] = d.payload;
      }
    }
    if (payloads.length > maxRecipients) {
      throw const ApiError(
        ErrorCode.invalidField,
        message: 'too many recipient devices',
      );
    }

    await api.checkDevices(
      context.db,
      addressed,
      senderAccount: me.accountId,
      senderDevice: me.deviceId,
    );

    // Recipients who blocked the sender get nothing; the sender is not told.
    final blockers = await api.blockedBy(
      context.db,
      me.accountId,
      addressed.keys.where((a) => a != me.accountId),
    );
    for (final account in blockers) {
      for (final device in addressed[account]!) {
        payloads.remove(device);
      }
    }

    final delivery = Delivery(
      kind: EnvelopeKind.message,
      id: req.id,
      from: EnvelopeSender(account: me.accountId, device: me.deviceId),
      urgent: req.urgent,
    );

    if (req.ephemeral) {
      await api.deliverEphemeral(payloads, delivery);
      return jsonResponse(
        SendMessageResponse(acceptedAt: context.clock.now()).toJson(),
      );
    }

    final accepted = await context.db.tx((tx) async {
      final at = await _store.recordSend(tx, req.id, me.deviceId);
      if (at == null) return null;
      await api.deliver(tx, payloads, delivery);
      return at;
    });
    if (accepted == null) {
      final at = await _store.acceptedAt(context.db, req.id);
      return jsonResponse(
        SendMessageResponse(
          acceptedAt: at ?? context.clock.now(),
          replayed: true,
        ).toJson(),
      );
    }
    return jsonResponse(SendMessageResponse(acceptedAt: accepted).toJson());
  }

  Future<Response> _mailbox(HelixRequest q) async {
    final after = int.tryParse(q.query('after') ?? '') ?? 0;
    final limit = (int.tryParse(q.query('limit') ?? '') ?? 100).clamp(1, 500);
    final envelopes = await api.fetch(
      q.device.deviceId,
      after: after,
      limit: limit + 1,
    );
    final more = envelopes.length > limit;
    return jsonResponse(
      MailboxPage(
        envelopes: envelopes.take(limit).toList(),
        lastSeq: await api.lastSeq(q.device.deviceId),
        more: more,
      ).toJson(),
    );
  }

  Future<Response> _ack(HelixRequest q) async {
    final req = q.json(AckRequest.fromJson);
    return jsonResponse(
      AckResponse(deleted: await api.ack(q.device.deviceId, req.seq)).toJson(),
    );
  }

  // ------------------------------------------------------------ push wakes

  Future<void> _push(Map<String, Object?> payload) async {
    final deviceId = payload['device']! as String;
    final reason = PushReason.values.firstWhere(
      (r) => r.wire == payload['reason'],
    );
    if (reason == PushReason.message &&
        await Presence.isOnline(context.ephemeral, deviceId)) {
      return; // It connected meanwhile; the socket delivers.
    }
    final target = await identity.pushTarget(context.db, deviceId);
    if (target == null || !context.push.isConfigured) return;
    try {
      await context.push.send(
        token: target.token,
        kind: target.kind.wire,
        reason: reason,
        callId: payload['call_id'] as String?,
      );
    } on PushTokenGone {
      await identity.dropPushToken(context.db, deviceId);
    }
  }

  /// Enqueues one pending push per device and reason (later sends coalesce
  /// into it until it has run).
  Future<void> enqueuePush(
    Tx tx,
    String deviceId,
    PushReason reason, {
    String? callId,
  }) => context.outbox.enqueue(
    tx,
    pushJob,
    {'device': deviceId, 'reason': reason.wire, 'call_id': ?callId},
    maxAttempts: 5,
    dedupeKey:
        'push:${reason.wire}:$deviceId${callId == null ? '' : ':$callId'}',
  );

  // ------------------------------------------------------------ hooks

  Future<void> _accountSignal(
    Tx tx,
    String accountId,
    AccountSignalEvent event, {
    String? exceptDevice,
  }) async {
    final devices = (await identity.activeDevices(
      tx,
      accountId,
    )).map((d) => d.id).where((id) => id != exceptDevice);
    await api.deliver(
      tx,
      {for (final d in devices) d: null},
      Delivery(
        kind: EnvelopeKind.accountSignal,
        data: event.toJson(),
        urgent: event.signal == AccountSignalKind.newSignIn,
      ),
    );
  }

  /// Device lists go to the account's own devices only: the server keeps no
  /// record of who talks to whom, so peers learn of new devices from
  /// `device_list_stale` on their next send (ADR-028).
  Future<void> _deviceListChanged(
    Tx tx,
    String accountId, {
    String? exceptDevice,
  }) async {
    final devices = (await identity.activeDevices(
      tx,
      accountId,
    )).map((d) => d.id).where((id) => id != exceptDevice);
    await api.deliver(
      tx,
      {for (final d in devices) d: null},
      Delivery(
        kind: EnvelopeKind.deviceListChange,
        data: DeviceListChangeEvent(account: accountId).toJson(),
      ),
    );
  }

  Future<void> _prekeysLow(String deviceId, int remaining) => context.db.tx(
    (tx) => api.deliver(
      tx,
      {deviceId: null},
      Delivery(
        kind: EnvelopeKind.prekeysLow,
        data: PrekeysLowEvent(remaining: remaining).toJson(),
      ),
    ),
  );
}

final class _MessagingFacade implements MessagingApi {
  _MessagingFacade(this._m);

  final MessagingModule _m;

  MailboxStore get _store => _m._store;

  @override
  Future<void> deliver(
    Tx tx,
    Map<String, Uint8List?> payloads,
    Delivery delivery,
  ) async {
    if (payloads.isEmpty) return;
    final devices = payloads.keys.toList();
    final seqs = await _store.allocate(tx, devices);
    await _store.insert(
      tx,
      seqs: seqs,
      payloads: payloads,
      id: delivery.id ?? Uuid.v7(),
      kind: delivery.kind,
      from: delivery.from,
      groupId: delivery.groupId,
      callId: delivery.callId,
      data: delivery.data,
      urgent: delivery.urgent,
    );
    if (delivery.urgent) {
      final online = await Presence.online(_m.context.ephemeral, devices);
      for (final device in devices.where((d) => !online.contains(d))) {
        await _m.enqueuePush(tx, device, PushReason.message);
      }
    }
    tx.afterCommit(() async {
      // NOTIFY payloads are limited; wake in chunks.
      for (var i = 0; i < devices.length; i += 150) {
        await _m.context.bus.publish(MailboxTopics.wake, {
          'd': devices.sublist(
            i,
            i + 150 > devices.length ? devices.length : i + 150,
          ),
        });
      }
    });
  }

  @override
  Future<Set<String>> deliverEphemeral(
    Map<String, Uint8List?> payloads,
    Delivery delivery,
  ) async {
    final online = await Presence.online(_m.context.ephemeral, payloads.keys);
    final id = delivery.id ?? Uuid.v7();
    for (final device in online) {
      final envelope = Envelope(
        id: id,
        kind: delivery.kind,
        sentAt: _m.context.clock.now(),
        from: delivery.from,
        groupId: delivery.groupId,
        callId: delivery.callId,
        payload: payloads[device],
        data: delivery.data,
        urgent: delivery.urgent,
      );
      final ref = Uuid.v7();
      await _m.context.ephemeral.put(
        'msg:eph:$ref',
        jsonEncode(envelope.toJson()),
        const Duration(seconds: 60),
      );
      await _m.context.bus.publish(MailboxTopics.ephemeral, {
        'd': device,
        'r': ref,
      });
    }
    return online;
  }

  @override
  Future<Envelope?> takeEphemeral(String ref) async {
    final raw = await _m.context.ephemeral.take('msg:eph:$ref');
    return raw == null ? null : Envelope.fromJson(JsonReader.decode(raw));
  }

  @override
  Future<void> checkDevices(
    SqlSession db,
    Map<String, Set<String>> addressed, {
    required String senderAccount,
    required String senderDevice,
  }) async {
    final active = await _m.identity.activeDevicesOf(db, addressed.keys);
    final stale = <StaleAccountDevices>[];
    for (final entry in addressed.entries) {
      final devices = active[entry.key] ?? const [];
      if (devices.isEmpty && entry.key != senderAccount) {
        throw const ApiError(
          ErrorCode.notFound,
          message: 'a recipient account does not exist',
        );
      }
      final required = {
        for (final d in devices)
          if (d.id != senderDevice) d.id,
      };
      final missing = required.difference(entry.value);
      final extra = entry.value.difference(required);
      if (missing.isNotEmpty || extra.isNotEmpty) {
        stale.add(
          StaleAccountDevices(
            account: entry.key,
            missing: missing.toList(),
            extra: extra.toList(),
          ),
        );
      }
    }
    if (stale.isNotEmpty) {
      throw ApiError(
        ErrorCode.deviceListStale,
        message: 'the device list changed',
        details: StaleDevices(accounts: stale).toJson(),
      );
    }
  }

  @override
  Future<List<Envelope>> fetch(
    String deviceId, {
    required int after,
    required int limit,
  }) => _store.fetch(_m.context.db, deviceId, after: after, limit: limit);

  @override
  Future<int> ack(String deviceId, int seq) =>
      _m.context.db.tx((tx) => _store.ack(tx, deviceId, seq));

  @override
  Future<int> lastSeq(String deviceId) =>
      _store.lastSeq(_m.context.db, deviceId);

  @override
  void setBlockPolicy(BlockPolicy policy) => _m._blockPolicy = policy;

  @override
  Future<Set<String>> blockedBy(
    SqlSession db,
    String sender,
    Iterable<String> recipients,
  ) => _m._blockPolicy(db, sender, recipients);
}
