import 'dart:convert';
import 'dart:typed_data';

import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/src/modules/calls/api.dart';
import 'package:helix_remote_server/src/modules/identity/api.dart';
import 'package:helix_remote_server/src/modules/messaging/api.dart';
import 'package:helix_remote_server/src/platform/config/server_config.dart';
import 'package:helix_remote_server/src/platform/db/migrations.dart';
import 'package:helix_remote_server/src/platform/http/request.dart';
import 'package:helix_remote_server/src/platform/http/routes.dart';
import 'package:helix_remote_server/src/platform/jobs/jobs.dart';
import 'package:helix_remote_server/src/platform/module.dart';
import 'package:helix_remote_server/src/platform/push/push.dart';
import 'package:helix_remote_server/src/platform/ratelimit/rate_limiter.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:shelf/shelf.dart';

/// TURN REST credentials (`HELIX_TURN_URLS`, `HELIX_TURN_SECRET`).
final class TurnConfig {
  const TurnConfig({required this.urls, required this.secret});

  final List<String> urls;
  final String secret;

  bool get isConfigured => urls.isNotEmpty && secret.isNotEmpty;

  factory TurnConfig.from(ServerConfig config) {
    final urls = (config.env['HELIX_TURN_URLS'] ?? '')
        .split(',')
        .map((u) => u.trim())
        .where((u) => u.isNotEmpty)
        .toList();
    final secret = config.env['HELIX_TURN_SECRET']?.trim() ?? '';
    if (urls.isNotEmpty != secret.isNotEmpty) {
      throw ConfigError([
        'HELIX_TURN_URLS and HELIX_TURN_SECRET must be set together',
      ]);
    }
    return TurnConfig(urls: urls, secret: secret);
  }
}

/// 1:1 call signalling (REST_V2.md "calls"). Signals are sealed pairwise;
/// the server sees the call id, the parties and the signal kind only.
final class CallsModule extends ModuleBase {
  CallsModule(super.context, {required this.identity, required this.messaging})
    : turn = TurnConfig.from(context.config) {
    identity.onDeviceRevoked(
      (tx, device) => tx.execute(
        'DELETE FROM $schema.pending_calls WHERE callee_device = @d:uuid',
        {'d': device.id},
      ),
    );
  }

  final IdentityApi identity;
  final MessagingApi messaging;
  final TurnConfig turn;
  late final CallsApi api = _CallsFacade(this);
  CallRelay? _relay;

  static const pushJob = 'calls.push';
  static const credentialLifetime = Duration(hours: 1);
  static const maxTtl = Duration(seconds: 120);
  static final RegExp _callId = RegExp(r'^[A-Za-z0-9._:-]{8,128}$');
  static final _turnLimit = RateLimitPolicy.per(
    'calls.turn',
    10,
    const Duration(hours: 1),
  );
  static final _offers = RateLimitPolicy.per(
    'calls.offers',
    30,
    const Duration(minutes: 10),
  );

  @override
  String get name => 'calls';

  @override
  List<Migration> get migrations => const [
    Migration(1, 'calls_baseline', _baseline),
    Migration(2, 'federated_callers', _federatedCallers),
  ];

  /// Callers on other servers are stored qualified (`uuid@domain`).
  static String _federatedCallers(String s) =>
      'ALTER TABLE $s.pending_calls ALTER COLUMN caller_account TYPE text '
      'USING caller_account::text;';

  static String _baseline(String s) =>
      '''
CREATE TABLE $s.pending_calls (
  call_id text NOT NULL,
  callee_device uuid NOT NULL,
  caller_account uuid NOT NULL,
  caller_device uuid NOT NULL,
  payload bytea NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  PRIMARY KEY (call_id, callee_device)
);
CREATE INDEX pending_calls_device ON $s.pending_calls (callee_device, expires_at);
CREATE TABLE $s.call_metrics (
  id uuid PRIMARY KEY,
  call_id text NOT NULL,
  setup_ms integer,
  duration_s integer,
  reconnects integer,
  packet_loss_pct double precision,
  rtt_ms integer,
  relayed boolean,
  outcome text,
  created_at timestamptz NOT NULL DEFAULT now()
);
''';

  @override
  Map<String, JobHandler> get jobs => {pushJob: _push};

  @override
  List<PeriodicJob> get periodic => [
    PeriodicJob('calls.expire', const Duration(minutes: 5), () async {
      await context.db.execute(
        'DELETE FROM $schema.pending_calls WHERE expires_at < now()',
      );
      await context.db.execute(
        "DELETE FROM $schema.call_metrics WHERE created_at < now() - interval '90 days'",
      );
    }),
  ];

  @override
  void routes(RouteRegistry r) {
    r
      ..add(name, Routes.turnCredentials, _turn)
      ..add(name, Routes.sendCallSignal, _signal, maxBodyBytes: 1024 * 1024)
      ..add(name, Routes.setCallState, _state)
      ..add(name, Routes.pendingCalls, _pending)
      ..add(name, Routes.callMetrics, _metrics);
  }

  Future<void> _limit(RateLimitPolicy policy, String key) async {
    final d = await context.rateLimiter.hit(policy, key);
    if (!d.allowed) {
      throw ApiError(ErrorCode.rateLimited, retryAfter: d.retryAfter);
    }
  }

  /// coturn's REST credential scheme: `username = <expiry>:<account>`,
  /// `credential = base64(HMAC-SHA1(secret, username))`.
  Future<Response> _turn(HelixRequest q) async {
    if (!turn.isConfigured) {
      throw const ApiError(
        ErrorCode.unavailable,
        message: 'this server has no relay for calls',
      );
    }
    await _limit(_turnLimit, q.device.deviceId);
    final expires = context.clock.now().add(credentialLifetime);
    final username =
        '${expires.millisecondsSinceEpoch ~/ 1000}:${q.device.accountId}';
    final credential = base64.encode(
      crypto.Hmac(
        crypto.sha1,
        utf8.encode(turn.secret),
      ).convert(utf8.encode(username)).bytes,
    );
    return jsonResponse(
      TurnCredentials(
        urls: turn.urls,
        username: username,
        credential: credential,
        expiresAt: expires,
      ).toJson(),
    );
  }

  String _checkCallId(HelixRequest q) {
    final id = q.param('call_id');
    if (!_callId.hasMatch(id)) {
      throw const ApiError(
        ErrorCode.invalidField,
        details: {'field': 'call_id'},
      );
    }
    return id;
  }

  Future<Response> _signal(HelixRequest q) async {
    final callId = _checkCallId(q);
    final me = q.device;
    final req = q.json(CallSignalRequest.fromJson);
    if (req.kind == CallSignalKind.unknown || req.recipients.isEmpty) {
      throw const ApiError(ErrorCode.invalidField);
    }
    if (req.kind == CallSignalKind.offer) await _limit(_offers, me.accountId);
    final parsed = _parse(req.recipients, excludeDevice: me.deviceId);

    final delivered = <String>[];
    final pending = <String>[];
    // Remote parts first: a stale or unreachable callee server fails the
    // signal before any local device rings.
    final relay = _relay;
    for (final entry in parsed.remote.entries) {
      final answer = await relay!.relayCall(
        entry.key,
        callId,
        S2SCallSignal(
          sender: AccountAddress.local(
            me.accountId,
          ).qualified(relay.localDomain),
          senderDevice: me.deviceId,
          signal: CallSignalRequest(
            kind: req.kind,
            recipients: entry.value,
            ttl: req.ttl,
          ),
        ),
      );
      delivered.addAll(answer.delivered);
      pending.addAll(answer.pending);
    }
    final local = await _deliverLocal(
      callId,
      senderAccount: me.accountId,
      senderDevice: me.deviceId,
      kind: req.kind,
      ttl: req.ttl,
      parsed: parsed,
    );
    return jsonResponse(
      CallSignalResponse(
        delivered: [...delivered, ...local.delivered],
        pending: [...pending, ...local.pending],
      ).toJson(),
    );
  }

  /// Local recipients become `addressed` and `payloads`; `uuid@domain`
  /// recipients are grouped by domain with that server's bare ids.
  _ParsedSignal _parse(List<Recipient> recipients, {String? excludeDevice}) {
    final local = _relay?.localDomain;
    final payloads = <String, Uint8List>{};
    final addressed = <String, Set<String>>{};
    final remote = <String, List<Recipient>>{};
    for (final r in recipients) {
      var address = AccountAddress.tryParse(r.account);
      if (address != null && local != null) {
        address = address.relativeTo(local);
      }
      if (address == null) {
        throw const ApiError(
          ErrorCode.invalidField,
          details: {'field': 'recipients'},
        );
      }
      for (final d in r.devices) {
        if (!Uuid.isValid(d.device) ||
            d.device == excludeDevice ||
            d.payload.length > 64 * 1024) {
          throw const ApiError(
            ErrorCode.invalidField,
            details: {'field': 'recipients.devices'},
          );
        }
      }
      if (address.isRemote) {
        if (local == null) {
          throw const ApiError(
            ErrorCode.federationUnavailable,
            message: 'this server does not federate',
          );
        }
        remote
            .putIfAbsent(address.domain!, () => [])
            .add(Recipient(account: address.id, devices: r.devices));
        continue;
      }
      final set = addressed.putIfAbsent(address.id, () => {});
      for (final d in r.devices) {
        set.add(d.device);
        payloads[d.device] = d.payload;
      }
    }
    return _ParsedSignal(addressed, payloads, remote);
  }

  Future<CallSignalResponse> _deliverLocal(
    String callId, {
    required String senderAccount,
    required String senderDevice,
    required CallSignalKind kind,
    required Duration ttl,
    required _ParsedSignal parsed,
  }) async {
    final payloads = parsed.payloads;
    final addressed = parsed.addressed;
    if (addressed.isEmpty) {
      return const CallSignalResponse(delivered: [], pending: []);
    }
    // Offers ring every device of the callee: the list must be complete.
    if (kind == CallSignalKind.offer) {
      await messaging.checkDevices(
        context.db,
        addressed,
        senderAccount: senderAccount,
        senderDevice: senderDevice,
      );
    }
    final blockers = await messaging.blockedBy(
      context.db,
      senderAccount,
      addressed.keys.where((a) => a != senderAccount),
    );
    for (final account in blockers) {
      addressed[account]!.forEach(payloads.remove);
    }

    final delivery = Delivery(
      kind: EnvelopeKind.callSignal,
      callId: callId,
      from: EnvelopeSender(account: senderAccount, device: senderDevice),
      data: {'kind': kind.wire},
      urgent: kind == CallSignalKind.offer,
    );
    final delivered = await messaging.deliverEphemeral(payloads, delivery);
    final pending = <String>[];
    if (kind == CallSignalKind.offer) {
      final capped = ttl > maxTtl ? maxTtl : ttl;
      await context.db.tx((tx) async {
        for (final device in payloads.keys.where(
          (d) => !delivered.contains(d),
        )) {
          await tx.execute(
            'INSERT INTO $schema.pending_calls (call_id, callee_device, caller_account, caller_device, payload, expires_at) '
            'VALUES (@c:text, @d:uuid, @a:text, @cd:uuid, @p:bytea, now() + make_interval(secs => @ttl:int8)) '
            'ON CONFLICT (call_id, callee_device) DO UPDATE SET payload = excluded.payload, expires_at = excluded.expires_at',
            {
              'c': callId,
              'd': device,
              'a': senderAccount,
              'cd': senderDevice,
              'p': payloads[device],
              'ttl': capped.inSeconds,
            },
          );
          await context.outbox.enqueue(
            tx,
            pushJob,
            {
              'device': device,
              'reason': PushReason.call.wire,
              'call_id': callId,
            },
            maxAttempts: 3,
            dedupeKey: 'call:$callId:$device',
          );
          pending.add(device);
        }
      });
    } else if (kind == CallSignalKind.end) {
      await _endPending(callId, notifyEnded: true);
    }
    return CallSignalResponse(delivered: delivered.toList(), pending: pending);
  }

  Future<CallSignalResponse> _receive(
    String domain,
    String callId,
    S2SCallSignal signal,
  ) async {
    if (!_callId.hasMatch(callId)) {
      throw const ApiError(
        ErrorCode.invalidField,
        details: {'field': 'call_id'},
      );
    }
    final sender = AccountAddress.tryParse(signal.sender);
    if (sender == null || sender.domain != domain) {
      throw const ApiError(
        ErrorCode.forbidden,
        message: 'the sender must belong to the calling server',
      );
    }
    final req = signal.signal;
    if (req.kind == CallSignalKind.unknown ||
        req.recipients.isEmpty ||
        !Uuid.isValid(signal.senderDevice)) {
      throw const ApiError(ErrorCode.invalidField);
    }
    if (req.kind == CallSignalKind.offer) {
      await _limit(_offers, sender.toString());
    }
    final parsed = _parse(req.recipients);
    if (parsed.remote.isNotEmpty) {
      throw const ApiError(
        ErrorCode.invalidField,
        message: 'recipients must be accounts on this server',
      );
    }
    return _deliverLocal(
      callId,
      senderAccount: sender.toString(),
      senderDevice: signal.senderDevice,
      kind: req.kind,
      ttl: req.ttl,
      parsed: parsed,
    );
  }

  /// Drops pending offers of [callId]; ringing devices get a `call_ended`
  /// push so their notification stops.
  Future<void> _endPending(
    String callId, {
    required bool notifyEnded,
    String? except,
  }) async {
    await context.db.tx((tx) async {
      final rows = await tx.query(
        'DELETE FROM $schema.pending_calls WHERE call_id = @c:text RETURNING callee_device',
        {'c': callId},
      );
      if (!notifyEnded) return;
      for (final r in rows) {
        final device = r.string('callee_device');
        if (device == except) continue;
        await context.outbox.enqueue(
          tx,
          pushJob,
          {
            'device': device,
            'reason': PushReason.callEnded.wire,
            'call_id': callId,
          },
          maxAttempts: 3,
          dedupeKey: 'call_ended:$callId:$device',
        );
      }
    });
  }

  /// A callee device answered or declined (others stop ringing), or the
  /// caller cancelled or hung up.
  Future<Response> _state(HelixRequest q) async {
    final callId = _checkCallId(q);
    final me = q.device;
    final state = q.json(CallStateRequest.fromJson).state;
    await _endPending(callId, notifyEnded: true, except: me.deviceId);
    final others = (await identity.activeDevices(
      context.db,
      me.accountId,
    )).where((d) => d.id != me.deviceId);
    await messaging.deliverEphemeral(
      {for (final d in others) d.id: null},
      Delivery(
        kind: EnvelopeKind.callSignal,
        callId: callId,
        from: EnvelopeSender(account: me.accountId, device: me.deviceId),
        data: {'kind': CallSignalKind.end.wire, 'state': state.wire},
      ),
    );
    return noContent();
  }

  Future<Response> _pending(HelixRequest q) async {
    final rows = await context.db.query(
      'SELECT call_id, caller_account, caller_device, payload, created_at, expires_at FROM $schema.pending_calls '
      'WHERE callee_device = @d:uuid AND expires_at > now() ORDER BY created_at',
      {'d': q.device.deviceId},
    );
    return jsonResponse(
      PendingCallList(
        calls: [
          for (final r in rows)
            PendingCall(
              callId: r.string('call_id'),
              from: EnvelopeSender(
                account: r.string('caller_account'),
                device: r.string('caller_device'),
              ),
              createdAt: r.time('created_at'),
              expiresAt: r.time('expires_at'),
              payload: r.bytes('payload'),
            ),
        ],
      ).toJson(),
    );
  }

  Future<Response> _metrics(HelixRequest q) async {
    final m = q.json(CallMetricsRequest.fromJson);
    if (!_callId.hasMatch(m.callId)) {
      throw const ApiError(ErrorCode.invalidField);
    }
    await context.db.execute(
      'INSERT INTO $schema.call_metrics (id, call_id, setup_ms, duration_s, reconnects, packet_loss_pct, rtt_ms, relayed, outcome) '
      'VALUES (@id:uuid, @c:text, @s:int4, @d:int4, @r:int4, @l:float8, @rtt:int4, @rel:boolean, @o:text)',
      {
        'id': Uuid.v7(),
        'c': m.callId,
        's': m.setupMs,
        'd': m.durationS,
        'r': m.reconnects,
        'l': m.packetLossPercent,
        'rtt': m.rttMs,
        'rel': m.relayed,
        'o': m.outcome,
      },
    );
    return noContent();
  }

  Future<void> _push(Map<String, Object?> payload) async {
    final device = payload['device']! as String;
    final target = await identity.pushTarget(context.db, device);
    if (target == null || !context.push.isConfigured) return;
    try {
      await context.push.send(
        token: target.token,
        kind: target.kind.wire,
        reason: PushReason.values.firstWhere(
          (r) => r.wire == payload['reason'],
        ),
        callId: payload['call_id'] as String?,
      );
    } on PushTokenGone {
      await identity.dropPushToken(context.db, device);
    }
  }
}

final class _ParsedSignal {
  _ParsedSignal(this.addressed, this.payloads, this.remote);

  final Map<String, Set<String>> addressed;
  final Map<String, Uint8List> payloads;
  final Map<String, List<Recipient>> remote;
}

final class _CallsFacade implements CallsApi {
  _CallsFacade(this._m);

  final CallsModule _m;

  @override
  void setRelay(CallRelay relay) => _m._relay = relay;

  @override
  Future<CallSignalResponse> receive(
    String domain,
    String callId,
    S2SCallSignal signal,
  ) => _m._receive(domain, callId, signal);
}
