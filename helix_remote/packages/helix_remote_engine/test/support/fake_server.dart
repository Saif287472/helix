import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hashes;
import 'package:helix_remote_crypto/v2.dart' show ed25519Verify;
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A device on the fake server.
final class FakeDevice {
  FakeDevice(this.id, this.accountId, this.registration, this.signedPrekey);

  final String id;
  final String accountId;
  final DeviceRegistration registration;
  SignedPrekey signedPrekey;
  final List<OneTimePrekey> oneTimePrekeys = [];
  final List<Envelope> mailbox = [];
  int nextSeq = 1;
  String accessToken = '';
  String refreshToken = '';
  bool revoked = false;
  bool lowSignalSent = false;
}

final class FakeAccount {
  FakeAccount(this.id, this.identityKey);

  final String id;
  Uint8List identityKey;
  final Map<String, FakeDevice> devices = {};
  final Set<String> blocked = {};
  String? phone;
  String? helixName;
}

/// What the fake saw of one send.
final class RecordedSend {
  RecordedSend(this.from, this.request, this.status);

  final FakeDevice from;
  final SendMessageRequest request;
  final int status;
}

/// An in-memory Helix server behind an `http.Client`: enough of identity,
/// keys, messaging and people for the engine's unit tests, with the same
/// device-list rules as the real server (a send must address every device
/// of every listed account, else `409 device_list_stale`), per-device
/// mailboxes with sequence numbers, one-time prekey hand-out and the
/// `prekeys_low` envelope. Faults can be injected per route.
final class FakeServer {
  FakeServer({DateTime Function()? clock}) : _clock = clock ?? DateTime.now {
    client = MockClient(_handle);
  }

  static final baseUri = Uri.parse('https://fake.helix.test');

  final DateTime Function() _clock;
  late final http.Client client;

  final Map<String, FakeAccount> accounts = {};
  final Map<String, FakeDevice> _byToken = {};
  final Map<String, FakeDevice> _byRefresh = {};
  final List<RecordedSend> sends = [];
  final List<String> calls = [];
  final Set<String> _seenSends = {};
  int _tokens = 0;
  final Uint8List salt = Uint8List.fromList(List.generate(32, (i) => i + 1));

  final List<_Fault> _faults = [];
  final Map<String, _Link> _links = {};
  final Map<String, ({FakeDevice device, Uint8List challenge})> _challenges =
      {};
  final Map<String, EncryptedProfile> profiles = {};

  /// Ends the device's session (tokens stop working) without revoking it.
  void invalidateSession(String deviceId) {
    final d = device(deviceId);
    _byToken.remove(d.accessToken);
    _byRefresh.remove(d.refreshToken);
  }

  // -------------------------------------------------------------- faults

  /// The next [times] requests to [route] answer with [code].
  void failNext(
    ApiRoute route, {
    int times = 1,
    ErrorCode code = ErrorCode.unavailable,
    Duration? retryAfter,
  }) {
    _faults.add(_Fault(route, times, code: code, retryAfter: retryAfter));
  }

  /// The next [times] requests to [route] get no answer at all (offline).
  void dropNext(ApiRoute route, {int times = 1}) {
    _faults.add(_Fault(route, times));
  }

  /// The next [times] requests to [route] are processed, but the answer
  /// never arrives (the client cannot tell and retries).
  void loseResponseNext(ApiRoute route, {int times = 1}) {
    _faults.add(_Fault(route, times, loseResponse: true));
  }

  /// Reverses the order of the stored envelopes of [deviceId] (payloads and
  /// ids swap places; sequence numbers stay increasing), to test messages
  /// that arrive out of order.
  void reverseMailbox(String deviceId) {
    final box = device(deviceId).mailbox;
    final reversed = box.reversed.toList();
    for (var i = 0; i < box.length; i++) {
      final e = reversed[i];
      box[i] = Envelope(
        id: e.id,
        kind: e.kind,
        sentAt: e.sentAt,
        seq: box[i].seq,
        from: e.from,
        payload: e.payload,
        data: e.data,
        urgent: e.urgent,
      );
    }
  }

  int callsTo(ApiRoute route) => calls
      .where((c) => c == '${route.method.name.toUpperCase()} ${route.path}')
      .length;

  // ------------------------------------------------------------- helpers

  FakeDevice device(String id) {
    for (final account in accounts.values) {
      final d = account.devices[id];
      if (d != null) return d;
    }
    throw StateError('no device $id');
  }

  /// Puts an envelope into [deviceId]'s mailbox.
  Envelope deliver(
    String deviceId, {
    EnvelopeKind kind = EnvelopeKind.message,
    EnvelopeSender? from,
    Uint8List? payload,
    JsonMap? data,
    String? id,
    bool ephemeral = false,
    bool urgent = false,
  }) {
    final target = device(deviceId);
    final envelope = Envelope(
      id: id ?? Uuid.v7(),
      kind: kind,
      sentAt: _clock().toUtc(),
      seq: ephemeral ? null : target.nextSeq++,
      from: from,
      payload: payload,
      data: data,
      urgent: urgent,
    );
    if (!ephemeral) target.mailbox.add(envelope);
    return envelope;
  }

  String discoveryHash(String number) => hashes.Hmac(hashes.sha256, salt)
      .convert(utf8.encode(number))
      .bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();

  /// Revokes a device the way the server does: its token stops working and
  /// every list drops it.
  void revoke(String deviceId) {
    final d = device(deviceId);
    d.revoked = true;
    accounts[d.accountId]!.devices.remove(deviceId);
  }

  // ------------------------------------------------------------- handling

  Future<http.Response> _handle(http.Request request) async {
    final match = _match(request);
    calls.add('${request.method} ${request.url.path}');
    if (match == null) return _error(ErrorCode.notFound);
    final (route, params) = match;
    _Fault? lose;
    for (final fault in _faults) {
      if (fault.route == route && fault.times > 0) {
        fault.times--;
        if (fault.loseResponse) {
          lose = fault;
          break;
        }
        if (fault.code == null) throw http.ClientException('offline');
        return _error(fault.code!, retryAfter: fault.retryAfter);
      }
    }
    final bearer = request.headers['authorization']?.replaceFirst(
      'Bearer ',
      '',
    );
    FakeDevice? caller;
    if (route.access == RouteAccess.device) {
      caller = _byToken[bearer];
      if (caller == null) return _error(ErrorCode.unauthenticated);
      if (caller.revoked) return _error(ErrorCode.deviceRevoked);
    }
    final req = _Req(
      params,
      request.url.queryParametersAll,
      request.body.isEmpty ? null : JsonReader.decode(request.body),
      caller,
    );
    try {
      final response = await _dispatch(route, req);
      if (lose != null) throw http.ClientException('connection lost');
      return response;
    } on ApiError catch (e) {
      return _error(e.code, details: e.details);
    }
  }

  (ApiRoute, Map<String, String>)? _match(http.Request request) {
    for (final route in Routes.all) {
      if (route.method.name.toUpperCase() != request.method) continue;
      final names = route.parameters;
      final pattern = RegExp(
        '^${route.path.replaceAllMapped(RegExp(r'\{[a-z_]+\}'), (_) => '([^/]+)')}\$',
      );
      final m = pattern.firstMatch(request.url.path);
      if (m == null) continue;
      return (
        route,
        {
          for (var i = 0; i < names.length; i++)
            names[i]: Uri.decodeComponent(m.group(i + 1)!),
        },
      );
    }
    return null;
  }

  Future<http.Response> _dispatch(ApiRoute route, _Req r) async {
    if (route == Routes.phoneChallenge) {
      return _ok(
        PhoneChallengeResponse(
          challengeId: 'challenge',
          expiresAt: _clock().add(const Duration(minutes: 10)),
          resendAfter: Duration.zero,
        ).toJson(),
      );
    }
    if (route == Routes.phoneVerify) {
      return _ok(
        PhoneVerifyResponse(
          verificationToken: 'verification',
          expiresAt: _clock().add(const Duration(minutes: 10)),
          accountExists: false,
          hasPassword: false,
        ).toJson(),
      );
    }
    if (route == Routes.register) {
      final req = RegisterRequest.fromJson(r.json!);
      if (req.replaceExisting && accounts.containsKey(req.accountId)) {
        final old = accounts[req.accountId]!;
        for (final d in old.devices.values) {
          d.revoked = true;
        }
        old.devices.clear();
        old.identityKey = req.identityKey;
      }
      final account = accounts.putIfAbsent(
        req.accountId,
        () => FakeAccount(req.accountId, req.identityKey),
      );
      return _ok(
        RegisterResponse(
          session: _addDevice(account, req.device, req.prekeys),
        ).toJson(),
      );
    }
    if (route == Routes.linkCreate) {
      final id = Uuid.v7();
      _links[id] = _Link('poll-$id');
      return _ok(
        LinkCreateResponse(
          linkId: id,
          pollToken: 'poll-$id',
          expiresAt: _clock().add(const Duration(minutes: 10)),
        ).toJson(),
      );
    }
    if (route == Routes.linkPoll) {
      final link = _links[r.params['link_id']];
      if (link == null) return _error(ErrorCode.notFound);
      if (link.provision == null) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return _ok(const LinkPollResponse(status: LinkStatus.pending).toJson());
      }
      return _ok(
        LinkPollResponse(
          status: LinkStatus.approved,
          provision: link.provision,
          linkToken: 'link-${r.params['link_id']}',
        ).toJson(),
      );
    }
    if (route == Routes.approveLink) {
      final link = _links[r.params['link_id']];
      if (link == null) return _error(ErrorCode.notFound);
      link.provision = LinkApproveRequest.fromJson(r.json!).provision;
      link.accountId = r.caller!.accountId;
      return _empty();
    }
    if (route == Routes.addDevice) {
      final req = AddDeviceRequest.fromJson(r.json!);
      final entry = _links.entries
          .where((e) => 'link-${e.key}' == req.linkToken)
          .firstOrNull;
      if (entry == null || entry.value.accountId == null) {
        return _error(ErrorCode.invalidCode);
      }
      final account = accounts[entry.value.accountId]!;
      final others = account.devices.keys.toList();
      final session = _addDevice(account, req.device, req.prekeys);
      for (final id in others) {
        deliver(
          id,
          kind: EnvelopeKind.deviceListChange,
          data: DeviceListChangeEvent(account: account.id).toJson(),
        );
      }
      return _ok(session.toJson());
    }
    if (route == Routes.deviceChallenge) {
      final req = DeviceChallengeRequest.fromJson(r.json!);
      final account = accounts[req.accountId];
      final d = account?.devices[req.deviceId];
      if (d == null) return _error(ErrorCode.deviceRevoked);
      final challenge = Uint8List.fromList(
        List.generate(32, (i) => i * 7 % 256),
      );
      final id = Uuid.v7();
      _challenges[id] = (device: d, challenge: challenge);
      return _ok(
        DeviceChallengeResponse(
          challengeId: id,
          challenge: challenge,
          expiresAt: _clock().add(const Duration(minutes: 5)),
        ).toJson(),
      );
    }
    if (route == Routes.deviceSignIn) {
      final req = DeviceSignInRequest.fromJson(r.json!);
      final issued = _challenges.remove(req.challengeId);
      if (issued == null) return _error(ErrorCode.invalidCredentials);
      final ok = await ed25519Verify(
        publicKey: issued.device.registration.signingKey,
        message: signInSignatureBody(req.challenge),
        signature: req.signature,
      );
      if (!ok) return _error(ErrorCode.invalidCredentials);
      return _ok(_issue(issued.device).toJson());
    }
    if (route == Routes.setHelixName) {
      final name = SetHelixNameRequest.fromJson(r.json!).name;
      if (accounts.values.any((a) => a.helixName == name)) {
        return _error(ErrorCode.nameTaken);
      }
      accounts[r.caller!.accountId]!.helixName = name;
      return _empty();
    }
    if (route == Routes.clearHelixName) {
      accounts[r.caller!.accountId]!.helixName = null;
      return _empty();
    }
    if (route == Routes.findByName) {
      final found = accounts.values
          .where((a) => a.helixName == r.params['name'])
          .firstOrNull;
      return found == null
          ? _error(ErrorCode.notFound)
          : _ok(
              FindByNameResponse(
                account: found.id,
                name: found.helixName!,
              ).toJson(),
            );
    }
    if (route == Routes.profile) {
      final profile = profiles[r.params['account']];
      return profile == null
          ? _error(ErrorCode.notFound)
          : _ok(profile.toJson());
    }
    if (route == Routes.setOwnProfile) {
      profiles[r.caller!.accountId] = EncryptedProfile.fromJson(r.json!);
      return _empty();
    }
    if (route == Routes.revokeDevice) {
      final account = accounts[r.caller!.accountId]!;
      final target = account.devices[r.params['device_id']];
      if (target == null) return _error(ErrorCode.notFound);
      target.revoked = true;
      account.devices.remove(target.id);
      for (final id in account.devices.keys) {
        deliver(
          id,
          kind: EnvelopeKind.deviceListChange,
          data: DeviceListChangeEvent(account: account.id).toJson(),
        );
      }
      return _empty();
    }
    if (route == Routes.refreshSession) {
      final token = RefreshRequest.fromJson(r.json!).refreshToken;
      final d = _byRefresh[token];
      if (d == null) return _error(ErrorCode.unauthenticated);
      return _ok(_issue(d).toJson());
    }
    if (route == Routes.signOut) return _empty();
    if (route == Routes.devices) {
      final account = accounts[r.caller!.accountId]!;
      return _ok(
        DeviceList(
          devices: [
            for (final d in account.devices.values)
              DeviceInfo(
                deviceId: d.id,
                name: d.registration.name,
                platform: d.registration.platform,
                createdAt: _clock(),
                current: d.id == r.caller!.id,
              ),
          ],
        ).toJson(),
      );
    }
    if (route == Routes.keyStatus) {
      return _ok(
        KeyStatus(
          oneTimeRemaining: r.caller!.oneTimePrekeys.length,
          signedPrekeyId: r.caller!.signedPrekey.id,
        ).toJson(),
      );
    }
    if (route == Routes.setSignedPrekey) {
      r.caller!.signedPrekey = SignedPrekey.fromJson(r.json!);
      return _empty();
    }
    if (route == Routes.addOneTimePrekeys) {
      r.caller!.oneTimePrekeys.addAll(
        AddOneTimePrekeysRequest.fromJson(r.json!).keys,
      );
      r.caller!.lowSignalSent = false;
      return _ok(
        KeyStatus(oneTimeRemaining: r.caller!.oneTimePrekeys.length).toJson(),
      );
    }
    if (route == Routes.accountKeys) return _accountKeys(r);
    if (route == Routes.sendMessage) return _send(r);
    if (route == Routes.mailbox) {
      final after = int.parse(r.query['after']?.first ?? '0');
      final all = [
        for (final e in r.caller!.mailbox)
          if (e.seq! > after) e,
      ];
      final page = all.take(100).toList();
      return _ok(
        MailboxPage(
          envelopes: page,
          lastSeq: r.caller!.nextSeq - 1,
          more: all.length > page.length,
        ).toJson(),
      );
    }
    if (route == Routes.ackMailbox) {
      final seq = AckRequest.fromJson(r.json!).seq;
      final before = r.caller!.mailbox.length;
      r.caller!.mailbox.removeWhere((e) => e.seq! <= seq);
      return _ok(
        AckResponse(deleted: before - r.caller!.mailbox.length).toJson(),
      );
    }
    if (route == Routes.discoverySalt) {
      return _ok(DiscoverySalt(salt: salt, version: 1).toJson());
    }
    if (route == Routes.discover) {
      final wanted = DiscoverRequest.fromJson(r.json!).phoneHashes.toSet();
      return _ok(
        DiscoverResponse(
          matches: [
            for (final a in accounts.values)
              if (a.phone != null &&
                  a.id != r.caller!.accountId &&
                  wanted.contains(discoveryHash(a.phone!)))
                DiscoverMatch(
                  phoneHash: discoveryHash(a.phone!),
                  account: a.id,
                ),
          ],
          remainingToday: 5000,
        ).toJson(),
      );
    }
    if (route == Routes.blocks) {
      return _ok(
        BlockList(
          accounts: accounts[r.caller!.accountId]!.blocked.toList(),
        ).toJson(),
      );
    }
    if (route == Routes.block) {
      accounts[r.caller!.accountId]!.blocked.add(r.params['account']!);
      return _empty();
    }
    if (route == Routes.unblock) {
      accounts[r.caller!.accountId]!.blocked.remove(r.params['account']);
      return _empty();
    }
    if (route == Routes.setPushToken || route == Routes.clearPushToken) {
      return _empty();
    }
    return _error(ErrorCode.notFound);
  }

  Session _addDevice(
    FakeAccount account,
    DeviceRegistration reg,
    PrekeyUpload prekeys,
  ) {
    final d = FakeDevice(reg.deviceId, account.id, reg, prekeys.signedPrekey)
      ..oneTimePrekeys.addAll(prekeys.oneTimePrekeys);
    account.devices[d.id] = d;
    return _issue(d);
  }

  Session _issue(FakeDevice d) {
    _byToken.remove(d.accessToken);
    _byRefresh.remove(d.refreshToken);
    d.accessToken = 'access-${++_tokens}';
    d.refreshToken = 'refresh-$_tokens';
    _byToken[d.accessToken] = d;
    _byRefresh[d.refreshToken] = d;
    return Session(
      accountId: d.accountId,
      deviceId: d.id,
      accessToken: d.accessToken,
      accessExpiresAt: _clock().add(const Duration(hours: 1)),
      refreshToken: d.refreshToken,
      refreshExpiresAt: _clock().add(const Duration(days: 30)),
    );
  }

  http.Response _accountKeys(_Req r) {
    final account = accounts[r.params['account']];
    if (account == null) return _error(ErrorCode.notFound);
    final wanted = r.query['device'];
    final bundles = <DeviceBundle>[];
    for (final d in account.devices.values) {
      if (wanted != null && !wanted.contains(d.id)) continue;
      final otk = d.oneTimePrekeys.isEmpty
          ? null
          : d.oneTimePrekeys.removeAt(0);
      bundles.add(
        DeviceBundle(
          deviceId: d.id,
          identityKey: d.registration.identityKey,
          signingKey: d.registration.signingKey,
          certificate: d.registration.certificate,
          signedPrekey: d.signedPrekey,
          oneTimePrekey: otk,
        ),
      );
      if (d.oneTimePrekeys.length < KeyStatus.lowWatermark &&
          !d.lowSignalSent) {
        d.lowSignalSent = true;
        deliver(
          d.id,
          kind: EnvelopeKind.prekeysLow,
          data: PrekeysLowEvent(remaining: d.oneTimePrekeys.length).toJson(),
        );
      }
    }
    return _ok(
      AccountKeys(
        account: account.id,
        identityKey: account.identityKey,
        devices: bundles,
      ).toJson(),
    );
  }

  http.Response _send(_Req r) {
    final from = r.caller!;
    final request = SendMessageRequest.fromJson(r.json!);
    final stale = <StaleAccountDevices>[];
    for (final recipient in request.recipients) {
      final account = accounts[recipient.account];
      final expected = {
        for (final d in account?.devices.values ?? const <FakeDevice>[])
          if (d.id != from.id) d.id,
      };
      final given = {for (final d in recipient.devices) d.device};
      if (expected.difference(given).isNotEmpty ||
          given.difference(expected).isNotEmpty) {
        stale.add(
          StaleAccountDevices(
            account: recipient.account,
            missing: expected.difference(given).toList(),
            extra: given.difference(expected).toList(),
          ),
        );
      }
    }
    if (stale.isNotEmpty) {
      sends.add(RecordedSend(from, request, 409));
      return _error(
        ErrorCode.deviceListStale,
        details: StaleDevices(accounts: stale).toJson(),
      );
    }
    sends.add(RecordedSend(from, request, 200));
    final key = '${from.id}/${request.id}';
    if (!_seenSends.add(key)) {
      return _ok(
        SendMessageResponse(acceptedAt: _clock(), replayed: true).toJson(),
      );
    }
    for (final recipient in request.recipients) {
      final account = accounts[recipient.account]!;
      final dropped = account.blocked.contains(from.accountId);
      for (final payload in recipient.devices) {
        if (dropped) continue;
        deliver(
          payload.device,
          id: request.id,
          from: EnvelopeSender(account: from.accountId, device: from.id),
          payload: payload.payload,
          ephemeral: request.ephemeral,
          urgent: request.urgent,
        );
      }
    }
    return _ok(SendMessageResponse(acceptedAt: _clock()).toJson());
  }

  http.Response _ok(JsonMap json) => http.Response(
    jsonEncode(json),
    200,
    headers: {'content-type': 'application/json'},
  );

  http.Response _empty() => http.Response('', 204);

  http.Response _error(
    ErrorCode code, {
    JsonMap? details,
    Duration? retryAfter,
  }) => http.Response(
    jsonEncode(
      ApiError(code, details: details, retryAfter: retryAfter).toJson(),
    ),
    code.status,
    headers: {
      'content-type': 'application/json',
      if (retryAfter != null) 'retry-after': '${retryAfter.inSeconds}',
    },
  );
}

final class _Fault {
  _Fault(
    this.route,
    this.times, {
    this.code,
    this.retryAfter,
    this.loseResponse = false,
  });

  final ApiRoute route;
  int times;
  final ErrorCode? code;
  final Duration? retryAfter;
  final bool loseResponse;
}

final class _Link {
  _Link(this.pollToken);

  final String pollToken;
  Uint8List? provision;
  String? accountId;
}

final class _Req {
  _Req(this.params, this.query, this.json, this.caller);

  final Map<String, String> params;
  final Map<String, List<String>> query;
  final JsonReader? json;
  final FakeDevice? caller;
}
