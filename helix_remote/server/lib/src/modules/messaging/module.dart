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
final class MessagingModule extends ModuleBase
    implements ProvidesAccountExport {
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
  MessageRelay? _relay;

  static const pushJob = 'messaging.push';
  static const maxRecipients = 1100;

  /// Undelivered envelopes are sealed; they are counted, never exported.
  @override
  Future<Object?> exportAccount(SqlSession s, String accountId) async {
    final devices = await identity.activeDevices(s, accountId);
    return {
      'undelivered_envelopes': {
        for (final d in devices)
          d.id: (await s.queryOne(
            'SELECT count(*)::int8 AS n FROM $schema.mailbox WHERE device_id = @d:uuid',
            {'d': d.id},
          ))!.integer('n'),
      },
    };
  }

  @override
  String get name => 'messaging';

  @override
  List<Migration> get migrations => const [
    Migration(1, 'mailbox_baseline', mailboxBaseline),
    Migration(2, 'federated_senders', _federatedSenders),
  ];

  /// Senders on other servers are stored qualified (`uuid@domain`).
  static String _federatedSenders(String s) =>
      'ALTER TABLE $s.mailbox ALTER COLUMN sender_account TYPE text '
      'USING sender_account::text;';

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
    final parsed = _parse(
      req.id,
      req.recipients,
      excludeDevice: me.deviceId,
      allowRemote: true,
    );
    final remote = parsed.remote;
    final relay = _relay;
    return jsonResponse(
      (await _accept(
        id: req.id,
        senderAccount: me.accountId,
        senderDevice: me.deviceId,
        parsed: parsed,
        urgent: req.urgent,
        ephemeral: req.ephemeral,
        beforeDelivery: remote.isEmpty
            ? null
            : () => _relayAll(
                relay!,
                remote,
                id: req.id,
                sender: AccountAddress.local(
                  me.accountId,
                ).qualified(relay.localDomain),
                senderDevice: me.deviceId,
                urgent: req.urgent,
                ephemeral: req.ephemeral,
              ),
      )).toJson(),
    );
  }

  /// Sends the remote part of a send to each server. Stale device lists
  /// from several servers are reported together.
  Future<void> _relayAll(
    MessageRelay relay,
    Map<String, List<Recipient>> remote, {
    required String id,
    required String sender,
    required String senderDevice,
    required bool urgent,
    required bool ephemeral,
  }) async {
    final stale = <StaleAccountDevices>[];
    for (final entry in remote.entries) {
      try {
        await relay.relay(
          entry.key,
          S2SMessageBatch(
            id: id,
            sender: sender,
            senderDevice: senderDevice,
            recipients: entry.value,
            urgent: urgent,
            ephemeral: ephemeral,
          ),
        );
      } on ApiError catch (e) {
        if (e.code != ErrorCode.deviceListStale || e.details == null) rethrow;
        stale.addAll(StaleDevices.fromJson(JsonReader.of(e.details)).accounts);
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

  /// Validates recipients: local accounts become `addressed` and
  /// `payloads`; with [allowRemote], `uuid@domain` accounts are grouped by
  /// domain (with bare ids, as that server knows them).
  _ParsedSend _parse(
    String id,
    List<Recipient> recipients, {
    String? excludeDevice,
    required bool allowRemote,
  }) {
    if (!Uuid.isValid(id)) {
      throw const ApiError(ErrorCode.invalidField, details: {'field': 'id'});
    }
    if (recipients.isEmpty) {
      throw const ApiError(
        ErrorCode.invalidField,
        details: {'field': 'recipients'},
      );
    }
    final local = _relay?.localDomain;
    final payloads = <String, Uint8List>{};
    final addressed = <String, Set<String>>{};
    final remote = <String, List<Recipient>>{};
    final seen = <AccountAddress>{};
    var deviceCount = 0;
    for (final recipient in recipients) {
      var address = AccountAddress.tryParse(recipient.account);
      if (address != null && local != null) {
        address = address.relativeTo(local);
      }
      if (address == null || !seen.add(address)) {
        throw const ApiError(
          ErrorCode.invalidField,
          details: {'field': 'recipients'},
        );
      }
      final devices = <String>{};
      for (final d in recipient.devices) {
        if (!Uuid.isValid(d.device) ||
            !devices.add(d.device) ||
            d.device == excludeDevice) {
          throw const ApiError(
            ErrorCode.invalidField,
            details: {'field': 'recipients.devices'},
          );
        }
        if (d.payload.isEmpty ||
            d.payload.length > SendMessageRequest.maxPayloadBytes) {
          throw const ApiError(ErrorCode.payloadTooLarge);
        }
      }
      deviceCount += devices.length;
      if (address.isRemote) {
        if (!allowRemote || local == null) {
          throw const ApiError(
            ErrorCode.federationUnavailable,
            message: 'this server does not federate',
          );
        }
        remote
            .putIfAbsent(address.domain!, () => [])
            .add(Recipient(account: address.id, devices: recipient.devices));
      } else {
        addressed[address.id] = devices;
        for (final d in recipient.devices) {
          payloads[d.device] = d.payload;
        }
      }
    }
    if (deviceCount > maxRecipients) {
      throw const ApiError(
        ErrorCode.invalidField,
        message: 'too many recipient devices',
      );
    }
    return _ParsedSend(addressed, payloads, remote);
  }

  /// The shared acceptance path of local and relayed sends: replay check,
  /// exact device lists, [beforeDelivery] (relays to other servers), block
  /// policy, then storage (or live delivery for ephemeral sends).
  Future<SendMessageResponse> _accept({
    required String id,
    required String senderAccount,
    required String senderDevice,
    required _ParsedSend parsed,
    required bool urgent,
    required bool ephemeral,
    Future<void> Function()? beforeDelivery,
  }) async {
    final previous = await _store.acceptedAt(context.db, id);
    if (previous != null) {
      return SendMessageResponse(acceptedAt: previous, replayed: true);
    }
    final payloads = parsed.payloads;
    final addressed = parsed.addressed;
    if (addressed.isNotEmpty) {
      await api.checkDevices(
        context.db,
        addressed,
        senderAccount: senderAccount,
        senderDevice: senderDevice,
      );
    }
    await beforeDelivery?.call();

    // Recipients who blocked the sender get nothing; the sender is not told.
    final blockers = await api.blockedBy(
      context.db,
      senderAccount,
      addressed.keys.where((a) => a != senderAccount),
    );
    for (final account in blockers) {
      for (final device in addressed[account]!) {
        payloads.remove(device);
      }
    }

    final delivery = Delivery(
      kind: EnvelopeKind.message,
      id: id,
      from: EnvelopeSender(account: senderAccount, device: senderDevice),
      urgent: urgent,
    );

    if (ephemeral) {
      await api.deliverEphemeral(payloads, delivery);
      return SendMessageResponse(acceptedAt: context.clock.now());
    }

    final accepted = await context.db.tx((tx) async {
      final at = await _store.recordSend(tx, id, senderDevice);
      if (at == null) return null;
      await api.deliver(tx, payloads, delivery);
      return at;
    });
    if (accepted == null) {
      final at = await _store.acceptedAt(context.db, id);
      return SendMessageResponse(
        acceptedAt: at ?? context.clock.now(),
        replayed: true,
      );
    }
    return SendMessageResponse(acceptedAt: accepted);
  }

  Future<SendMessageResponse> _receive(
    String domain,
    S2SMessageBatch batch,
  ) async {
    final sender = AccountAddress.tryParse(batch.sender);
    if (sender == null || sender.domain != domain) {
      throw const ApiError(
        ErrorCode.forbidden,
        message: 'the sender must belong to the calling server',
      );
    }
    if (!Uuid.isValid(batch.senderDevice)) {
      throw const ApiError(
        ErrorCode.invalidField,
        details: {'field': 'sender_device'},
      );
    }
    final parsed = _parse(batch.id, batch.recipients, allowRemote: false);
    return _accept(
      id: batch.id,
      senderAccount: sender.toString(),
      senderDevice: batch.senderDevice,
      parsed: parsed,
      urgent: batch.urgent,
      ephemeral: batch.ephemeral,
    );
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
  void setRelay(MessageRelay relay) => _m._relay = relay;

  @override
  String? get localDomain => _m._relay?.localDomain;

  @override
  Future<SendMessageResponse> receive(String domain, S2SMessageBatch batch) =>
      _m._receive(domain, batch);

  @override
  Future<Set<String>> blockedBy(
    SqlSession db,
    String sender,
    Iterable<String> recipients,
  ) => _m._blockPolicy(db, sender, recipients);
}

final class _ParsedSend {
  _ParsedSend(this.addressed, this.payloads, this.remote);

  /// Local account -> addressed device ids.
  final Map<String, Set<String>> addressed;

  /// Local device -> sealed payload.
  final Map<String, Uint8List> payloads;

  /// Domain -> recipients with that server's bare account ids.
  final Map<String, List<Recipient>> remote;
}
