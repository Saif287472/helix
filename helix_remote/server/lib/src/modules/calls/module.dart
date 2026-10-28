import 'dart:convert';
import 'dart:typed_data';

import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/src/kernel/crypto.dart';
import 'package:helix_remote_server/src/modules/billing/api.dart';
import 'package:helix_remote_server/src/modules/groups/api.dart';
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

/// TURN REST credentials (`HELIX_TURN_URLS`, `HELIX_TURN_SECRET`). The URLs
/// may be `turn:` (port 3478, credentials in the clear) or `turns:` (TLS,
/// port 5349); anything else is a startup error.
final class TurnConfig {
  const TurnConfig({
    required this.urls,
    required this.secret,
    this.voiceUrls = const [],
    this.voiceSecret = '',
  });

  final List<String> urls;
  final String secret;

  /// The voice relay (`HELIX_TURN_VOICE_URLS`, `HELIX_TURN_VOICE_SECRET`): a
  /// second coturn whose sessions are capped at voice bandwidth, with **its own
  /// secret**, so a credential for it is no good on the main relay and one for
  /// the main relay is no good on it (ADR-036). Optional: without it voice
  /// calls use the main relay, and a Free caller's voice minutes are charged
  /// but not capped.
  final List<String> voiceUrls;
  final String voiceSecret;

  bool get isConfigured => urls.isNotEmpty && secret.isNotEmpty;
  bool get hasVoiceRelay => voiceUrls.isNotEmpty && voiceSecret.isNotEmpty;

  static List<String> _urls(String? raw, String name) {
    final urls = (raw ?? '')
        .split(',')
        .map((u) => u.trim())
        .where((u) => u.isNotEmpty)
        .toList();
    if (urls.any((u) => !u.startsWith('turn:') && !u.startsWith('turns:'))) {
      throw ConfigError(['$name entries must start with turn: or turns:']);
    }
    return urls;
  }

  factory TurnConfig.from(ServerConfig config) {
    final urls = _urls(config.env['HELIX_TURN_URLS'], 'HELIX_TURN_URLS');
    final secret = config.env['HELIX_TURN_SECRET']?.trim() ?? '';
    if (urls.isNotEmpty != secret.isNotEmpty) {
      throw ConfigError([
        'HELIX_TURN_URLS and HELIX_TURN_SECRET must be set together',
      ]);
    }
    final voiceUrls = _urls(
      config.env['HELIX_TURN_VOICE_URLS'],
      'HELIX_TURN_VOICE_URLS',
    );
    final voiceSecret = config.env['HELIX_TURN_VOICE_SECRET']?.trim() ?? '';
    if (voiceUrls.isNotEmpty != voiceSecret.isNotEmpty) {
      throw ConfigError([
        'HELIX_TURN_VOICE_URLS and HELIX_TURN_VOICE_SECRET must be set together',
      ]);
    }
    if (voiceSecret.isNotEmpty && voiceSecret == secret) {
      throw ConfigError([
        'HELIX_TURN_VOICE_SECRET must differ from HELIX_TURN_SECRET: a shared '
            'secret would let a voice credential open the uncapped relay',
      ]);
    }
    return TurnConfig(
      urls: urls,
      secret: secret,
      voiceUrls: voiceUrls,
      voiceSecret: voiceSecret,
    );
  }
}

/// 1:1 call signalling (REST_V2.md "calls"). Signals are sealed pairwise;
/// the server sees the call id, the parties and the signal kind only.
final class CallsModule extends ModuleBase {
  CallsModule(
    super.context, {
    required this.identity,
    required this.messaging,
    required this.billing,
    required this.groups,
  }) : turn = TurnConfig.from(context.config) {
    _wakes = PushTrail(log, context.metrics);
    identity.onDeviceRevoked(
      (tx, device) => tx.execute(
        'DELETE FROM $schema.pending_calls WHERE callee_device = @d:uuid',
        {'d': device.id},
      ),
    );
  }

  final IdentityApi identity;
  final MessagingApi messaging;
  final BillingApi billing;
  final GroupsApi groups;
  final TurnConfig turn;
  late final CallsApi api = _CallsFacade(this);
  late final PushTrail _wakes;
  CallRelay? _relay;

  static const pushJob = 'calls.push';

  /// How long the relay credential of a call that spends no call time lasts
  /// (`CallTimeLimits.unmeteredLifetime`).
  static const maxTtl = Duration(seconds: 120);
  static final RegExp _callId = RegExp(r'^[A-Za-z0-9._:-]{8,128}$');
  // One credential per call, and one per leg of a group call, and again for a
  // retry: generous for people, small for a script.
  static final _turnLimit = RateLimitPolicy.per(
    'calls.turn',
    60,
    const Duration(hours: 1),
  );

  /// A call's record (who it was offered to) is kept this long.
  static const legRetention = Duration(hours: 12);
  static final _offers = RateLimitPolicy.per(
    'calls.offers',
    30,
    const Duration(minutes: 10),
  );
  // Everything but the offer (update, end, ICE candidates) is cheap to send
  // and rings nothing, but it still costs a fan-out and a push wake, so each
  // sending device gets a budget on top of the per-address one.
  static final _signals = RateLimitPolicy.per(
    'calls.signals',
    240,
    const Duration(minutes: 1),
  );

  @override
  String get name => 'calls';

  @override
  List<Migration> get migrations => const [
    Migration(1, 'calls_baseline', _baseline),
    Migration(2, 'federated_callers', _federatedCallers),
    Migration(3, 'drop_call_metrics', _dropCallMetrics),
    Migration(4, 'call_legs', _callLegs),
  ];

  /// Who a call was offered to, so the answering side can be told from anyone
  /// else asking for relay credentials (ADR-036). The server already sees this
  /// while it routes the offer; it now keeps it for a few hours.
  static String _callLegs(String s) =>
      '''
CREATE TABLE $s.call_legs (
  call_id text NOT NULL,
  callee_account text NOT NULL,
  caller_account text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (call_id, callee_account)
);
CREATE INDEX call_legs_age ON $s.call_legs (created_at);
''';

  /// Nothing ever sent a quality sample, so the table (and its unbounded
  /// `outcome` column) goes rather than gets bounded (Q9, AUD-6-1, AUD-12l-3).
  /// A new migration: migration 1 created it and has run.
  static String _dropCallMetrics(String s) =>
      'DROP TABLE IF EXISTS $s.call_metrics;';

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
        'DELETE FROM $schema.call_legs WHERE created_at < @c:timestamptz',
        {'c': context.clock.now().subtract(legRetention)},
      );
    }),
  ];

  @override
  void routes(RouteRegistry r) {
    r
      ..add(name, Routes.turnCredentials, _turn)
      ..add(name, Routes.sendCallSignal, _signal, maxBodyBytes: 1024 * 1024)
      ..add(name, Routes.setCallState, _state)
      ..add(name, Routes.pendingCalls, _pending);
  }

  Future<void> _limit(RateLimitPolicy policy, String key) async {
    final d = await context.rateLimiter.hit(policy, key);
    if (!d.allowed) {
      throw ApiError(ErrorCode.rateLimited, retryAfter: d.retryAfter);
    }
  }

  /// coturn's REST credential scheme: `username = <expiry>:<random id>`,
  /// `credential = base64(HMAC-SHA1(secret, username))`. A `turn:` handshake is
  /// unencrypted, so the name carries nothing about the account: an on-path
  /// observer cannot link an address to a person.
  ///
  /// A credential is for one call (ADR-036). The billing module decides what
  /// it may carry: a Free caller's call time is set aside and the credential
  /// ends with it (coturn re-checks the expiry every `stale-nonce` seconds, so
  /// the relay stops then); an answering side runs under the caller's
  /// reservation; a call nobody metered gets a long lifetime. Voice goes to the
  /// voice relay when there is one, whose own secret keeps its credentials off
  /// the uncapped relay.
  Future<Response> _turn(HelixRequest q) async {
    if (!turn.isConfigured) {
      throw const ApiError(
        ErrorCode.unavailable,
        message: 'this server has no relay for calls',
      );
    }
    final req = q.json(TurnRequest.fromJson);
    if (req.role == CallRole.unknown || req.media == CallPool.unknown) {
      throw const ApiError(ErrorCode.invalidField);
    }
    await _limit(_turnLimit, q.device.deviceId);
    final accountId = q.device.accountId;

    // A room's call time belongs to its group: only a member may start or join
    // it, whoever learns the room id (ADR-036).
    final groupId = req.groupId;
    if (groupId != null && !await groups.isMember(groupId, accountId)) {
      throw const ApiError(
        ErrorCode.forbidden,
        message: 'you are not in that group',
      );
    }

    var callerIsRemote = false;
    if (req.role == CallRole.callee && await billing.enabled()) {
      // Only the person the offer was addressed to may answer it.
      final leg = await context.db.queryOne(
        'SELECT caller_account FROM $schema.call_legs '
        'WHERE call_id = @c:text AND callee_account = @a:text',
        {'c': req.callId, 'a': accountId},
      );
      if (leg == null) {
        throw const ApiError(
          ErrorCode.notFound,
          message: 'no call is ringing for you under that id',
        );
      }
      callerIsRemote = leg.string('caller_account').contains('@');
    }

    final grant = await billing.grantCall(
      accountId: accountId,
      callId: req.callId,
      role: req.role,
      pool: req.media,
      roomId: req.roomId,
      groupId: groupId,
      callerIsRemote: callerIsRemote,
    );

    final voice = grant.pool == CallPool.voice && turn.hasVoiceRelay;
    final secret = voice ? turn.voiceSecret : turn.secret;
    final username =
        '${grant.expiresAt.millisecondsSinceEpoch ~/ 1000}:${encodeBytes(randomBytes(12))}';
    final credential = base64.encode(
      crypto.Hmac(
        crypto.sha1,
        utf8.encode(secret),
      ).convert(utf8.encode(username)).bytes,
    );
    return jsonResponse(
      TurnCredentials(
        urls: voice ? turn.voiceUrls : turn.urls,
        username: username,
        credential: credential,
        expiresAt: grant.expiresAt,
        metered: grant.metered,
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
    if (req.kind == CallSignalKind.offer) {
      await _limit(_offers, me.accountId);
    } else {
      await _limit(_signals, me.deviceId);
    }
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
    // A blocked caller is told at once (blocks are not secret) rather than
    // left ringing; the other signals of a call are still dropped silently.
    if (kind == CallSignalKind.offer && blockers.isNotEmpty) {
      throw ApiError(
        ErrorCode.blocked,
        message: 'the callee has blocked you',
        details: {'accounts': blockers.toList()..sort()},
      );
    }
    for (final account in blockers) {
      addressed[account]!.forEach(payloads.remove);
    }

    if (kind == CallSignalKind.offer) {
      // Who the call was offered to (not the people who blocked the caller):
      // only they may ask for the answering side's relay credentials.
      for (final account in addressed.keys.where(
        (a) => !blockers.contains(a),
      )) {
        await context.db.execute(
          'INSERT INTO $schema.call_legs (call_id, callee_account, caller_account) '
          'VALUES (@c:text, @a:text, @s:text) ON CONFLICT DO NOTHING',
          {'c': callId, 'a': account, 's': senderAccount},
        );
      }
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
          // A repeated offer from the same caller device refreshes its
          // pending row; anyone else's offer under this call id is ignored.
          final stored = await tx.query(
            'INSERT INTO $schema.pending_calls AS p (call_id, callee_device, caller_account, caller_device, payload, expires_at) '
            'VALUES (@c:text, @d:uuid, @a:text, @cd:uuid, @p:bytea, now() + make_interval(secs => @ttl:int8)) '
            'ON CONFLICT (call_id, callee_device) DO UPDATE SET payload = excluded.payload, expires_at = excluded.expires_at '
            'WHERE p.caller_account = excluded.caller_account AND p.caller_device = excluded.caller_device '
            'RETURNING callee_device',
            {
              'c': callId,
              'd': device,
              'a': senderAccount,
              'cd': senderDevice,
              'p': payloads[device],
              'ttl': capped.inSeconds,
            },
          );
          if (stored.isEmpty) continue;
          pending.add(device);
        }
        if (pending.isNotEmpty) {
          await context.outbox.enqueueMany(tx, [
            for (final device in pending)
              QueuedJob(
                pushJob,
                {
                  'device': device,
                  'reason': PushReason.call.wire,
                  'call_id': callId,
                },
                maxAttempts: 3,
                dedupeKey: 'call:$callId:$device',
              ),
          ]);
        }
      });
    } else if (kind == CallSignalKind.end) {
      // The call is over for whoever pays for it.
      final party = await context.db.queryOne(
        'SELECT 1 FROM $schema.call_legs WHERE call_id = @c:text '
        'AND (callee_account = @a:text OR caller_account = @a:text)',
        {'c': callId, 'a': senderAccount},
      );
      await billing.callEnded(
        callId,
        by: senderAccount,
        isParty: party != null,
      );
      await _endPending(
        callId,
        notifyEnded: true,
        party: senderAccount,
        partyDevices: senderAccount.contains('@')
            ? const []
            : [
                for (final d in await identity.activeDevices(
                  context.db,
                  senderAccount,
                ))
                  d.id,
              ],
      );
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
    } else {
      await _limit(_signals, '$sender/${signal.senderDevice}');
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

  /// Drops pending offers of [callId] that [party] is in: as the caller
  /// ([party] is the caller account) or as the callee (the row's device is
  /// one of [partyDevices]). Nobody else can clear a call they are not in.
  /// Ringing devices get a `call_ended` push so their notification stops.
  Future<void> _endPending(
    String callId, {
    required bool notifyEnded,
    required String party,
    required List<String> partyDevices,
    String? except,
  }) async {
    await context.db.tx((tx) async {
      final rows = await tx.query(
        'DELETE FROM $schema.pending_calls WHERE call_id = @c:text '
        'AND (caller_account = @a:text OR callee_device = ANY(@ds:_uuid)) '
        'RETURNING callee_device',
        {'c': callId, 'a': party, 'ds': partyDevices},
      );
      if (!notifyEnded) return;
      final ringing = [
        for (final r in rows) r.string('callee_device'),
      ].where((device) => device != except);
      await context.outbox.enqueueMany(tx, [
        for (final device in ringing)
          QueuedJob(
            pushJob,
            {
              'device': device,
              'reason': PushReason.callEnded.wire,
              'call_id': callId,
            },
            maxAttempts: 3,
            dedupeKey: 'call_ended:$callId:$device',
          ),
      ]);
    });
  }

  /// A callee device answered or declined (others stop ringing), or the
  /// caller cancelled or hung up.
  Future<Response> _state(HelixRequest q) async {
    final callId = _checkCallId(q);
    final me = q.device;
    final state = q.json(CallStateRequest.fromJson).state;
    final devices = await identity.activeDevices(context.db, me.accountId);
    await _endPending(
      callId,
      notifyEnded: true,
      party: me.accountId,
      partyDevices: [for (final d in devices) d.id],
      except: me.deviceId,
    );
    final others = devices.where((d) => d.id != me.deviceId);
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

  Future<void> _push(Map<String, Object?> payload) async {
    final device = payload['device']! as String;
    final reason = PushReason.values.firstWhere(
      (r) => r.wire == payload['reason'],
    );
    final target = await identity.pushTarget(context.db, device);
    if (target == null) {
      _wakes.record(PushOutcome.noToken, reason, device);
      return;
    }
    if (!context.push.isConfigured) {
      _wakes.record(PushOutcome.providerOff, reason, device);
      return;
    }
    try {
      await context.push.send(
        token: target.token,
        kind: target.kind.wire,
        reason: reason,
        callId: payload['call_id'] as String?,
      );
      _wakes.record(PushOutcome.sent, reason, device);
    } on PushTokenGone {
      await identity.dropPushToken(context.db, device);
      _wakes.record(PushOutcome.tokenGone, reason, device);
    } on PushFailed catch (failure) {
      // A ringing phone is worth one retry even if the next offer may already
      // have arrived: the call is over by the time the backoff runs.
      _wakes.record(PushOutcome.failed, reason, device, error: failure.reason);
      rethrow;
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
  bool get turnConfigured => _m.turn.isConfigured;

  @override
  int get turnUrlCount => _m.turn.urls.length;

  @override
  void setRelay(CallRelay relay) => _m._relay = relay;

  @override
  Future<CallSignalResponse> receive(
    String domain,
    String callId,
    S2SCallSignal signal,
  ) => _m._receive(domain, callId, signal);
}
