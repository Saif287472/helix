import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

import 'options.dart';
import 'stats.dart';

/// One client isolate: simulates a slice of the devices end to end, over
/// real HTTP and WebSockets only (no server internals).
///
/// Spawned with `Isolate.spawnUri`, so it has its own heap and its garbage
/// collections never pause the server isolate. Messages to and from the
/// coordinator are maps with a `t` (type) field; see coordinator.dart.
Future<void> main(List<String> args, Object? message) async {
  final m = (message! as Map<Object?, Object?>).cast<String, Object?>();
  final out = m['port']! as SendPort;
  try {
    await _Worker(
      out: out,
      id: m['worker']! as int,
      base: Uri.parse(m['base']! as String),
      tag: m['tag']! as int,
      options: LoadOptions.fromJson(
        (m['options']! as Map<Object?, Object?>).cast<String, Object?>(),
      ),
    ).run();
  } on Object catch (e, stack) {
    out.send({'t': 'fatal', 'error': '$e', 'stack': '$stack'});
  }
}

/// `HXLT` + run tag (u32) + send time (µs, i64) + kind; then padding.
const _magic = [0x48, 0x58, 0x4c, 0x54];
const _headerBytes = 17;
const _kindDirect = 1;
const _kindGroup = 2;

/// A realistic sealed payload size: padded plaintext is a multiple of 160
/// bytes (CRYPTO_V2.md §6), plus about 100 bytes of sealed-message
/// overhead. Mostly short texts, some longer ones and media pointers.
int payloadSize(math.Random random, int fixed) {
  if (fixed > 0) return math.max(fixed, _headerBytes);
  final x = random.nextDouble();
  final blocks = x < 0.55
      ? 1
      : x < 0.80
      ? 2
      : x < 0.90
      ? 3
      : 4 + random.nextInt(5);
  return blocks * 160 + 100;
}

final Ed25519 _ed = Ed25519();
final X25519 _x = X25519();

Future<Uint8List> _publicOf(KeyPair pair) async => Uint8List.fromList(
  (await pair.extractPublicKey() as SimplePublicKey).bytes,
);

Future<Uint8List> _sign(SimpleKeyPair pair, List<int> message) async =>
    Uint8List.fromList((await _ed.sign(message, keyPair: pair)).bytes);

final class _Device {
  _Device(this.index);

  final int index;

  /// `+88017` + 8 digits: a valid Bangladeshi mobile number, never printed.
  String get phone => '+88017${index.toString().padLeft(8, '0')}';

  /// Behind Caddy every phone has its own address; the in-process node
  /// trusts loopback as its proxy, so `X-Forwarded-For` gives each simulated
  /// device its own per-IP rate-limit buckets.
  String get ip =>
      '10.${(index >> 16) & 255}.${(index >> 8) & 255}.'
      '${index & 255}';

  late String accountId;
  late String deviceId;
  String? token;
  WebSocket? ws;
  int lastSeq = 0;
  int? group;
  Uint8List? digest;
  Timer? timer;
  final Set<String> seen = {};
}

final class _Response {
  _Response(this.status, this.body);

  final int status;
  final String body;

  bool get ok => status >= 200 && status < 300;

  String get errorKey {
    try {
      final error =
          (jsonDecode(body) as Map<String, Object?>)['error']
              as Map<String, Object?>;
      return '$status:${error['code']}';
    } on Object {
      return '$status';
    }
  }

  JsonReader get json => JsonReader.decode(body);
}

final class _Worker {
  _Worker({
    required this.out,
    required this.id,
    required this.base,
    required this.tag,
    required this.options,
  }) : _random = math.Random(id * 7919 + tag);

  final SendPort out;
  final int id;
  final Uri base;
  final int tag;
  final LoadOptions options;
  final math.Random _random;
  final ReceivePort _inbox = ReceivePort();
  final HttpClient _http = HttpClient()
    ..maxConnectionsPerHost = 256
    ..idleTimeout = const Duration(seconds: 30);
  late final Uint8List _pool = Uint8List.fromList(
    List.generate(512 * 1024, (_) => _random.nextInt(256)),
  );

  final Map<int, _Device> _mine = {};
  List<String?> _accounts = const [];
  List<String?> _devices = const [];
  List<int> _live = const [];
  List<List<int>> _groups = const [];
  List<String> _groupIds = const [];

  final Map<int, Completer<String>> _codes = {};
  int _nextCode = 0;

  // Run window, epoch microseconds.
  int _measureFrom = 0;
  int _measureTo = 0;
  int _stopAt = 0;
  bool _finishing = false;
  int _inflight = 0;
  Timer? _heartbeat;
  Timer? _lagTimer;

  final Map<String, Samples> _samples = {
    for (final k in [
      'keygen',
      'challenge',
      'verify',
      'register',
      'registration',
      'group_create',
      'connect',
      'send_direct',
      'send_group',
      'e2e_direct',
      'e2e_group',
      'ack_rest',
      'loop_lag',
    ])
      k: Samples(),
  };
  final Counts _errors = Counts();
  final Counts _counts = Counts();

  Future<void> run() async {
    final done = Completer<void>();
    _inbox.listen((raw) async {
      final m = (raw as Map<Object?, Object?>).cast<String, Object?>();
      try {
        switch (m['t']) {
          case 'code':
            _codes.remove(m['id'])?.complete(m['code']! as String);
          case 'provision':
            await _provisionAll((m['devices']! as List).cast<int>());
          case 'directory':
            _directory(m);
          case 'groups':
            await _createGroups();
          case 'connect':
            await _connectAll();
          case 'run':
            await _run(m);
          case 'progress':
            out.send({
              't': 'progress',
              'received': _counts.values['received'] ?? 0,
            });
          case 'finish':
            await _finish();
            done.complete();
        }
      } on Object catch (e, stack) {
        out.send({'t': 'fatal', 'error': '$e', 'stack': '$stack'});
      }
    });
    out.send({'t': 'ready', 'port': _inbox.sendPort});
    await done.future;
    _inbox.close();
  }

  // ------------------------------------------------------------------ http

  Future<_Response> _call(
    ApiRoute route, {
    required _Device as,
    Map<String, String> params = const {},
    Map<String, Object?>? body,
    bool auth = true,
  }) async {
    final request = await _http.openUrl(
      route.method.name.toUpperCase(),
      base.replace(path: route.expand(params)),
    );
    request.headers.set('x-forwarded-for', as.ip);
    if (auth) request.headers.set('authorization', 'Bearer ${as.token}');
    if (body != null) {
      final bytes = utf8.encode(jsonEncode(body));
      request.headers.contentType = ContentType.json;
      request.contentLength = bytes.length;
      request.add(bytes);
    }
    final response = await request.close();
    final text = await utf8.decodeStream(response);
    return _Response(response.statusCode, text);
  }

  Future<_Response> _timed(
    String metric,
    Future<_Response> Function() call, {
    bool record = true,
  }) async {
    final watch = Stopwatch()..start();
    final response = await call().timeout(const Duration(seconds: 30));
    if (record && response.ok) _samples[metric]!.add(watch.elapsedMicroseconds);
    return response;
  }

  // --------------------------------------------------------- provisioning

  Future<void> _provisionAll(List<int> indices) async {
    final queue = [...indices];
    Future<void> lane() async {
      while (queue.isNotEmpty) {
        final d = _Device(queue.removeLast());
        try {
          await _register(d);
          _mine[d.index] = d;
        } on _StepFailed catch (e) {
          _errors.add('register:${e.step}:${e.key}');
        } on Object catch (e) {
          _errors.add('register:${e.runtimeType}');
        }
      }
    }

    await Future.wait([
      for (var i = 0; i < options.provisionConcurrency; i++) lane(),
    ]);
    out.send({
      't': 'provisioned',
      'devices': [
        for (final d in _mine.values) [d.index, d.accountId, d.deviceId],
      ],
      'samples': _wire([
        'keygen',
        'challenge',
        'verify',
        'register',
        'registration',
      ]),
      'errors': _errors.values,
    });
  }

  /// The real Helix Global sign-up: phone challenge, verify, register with
  /// a certified device and real prekeys (signed + one-time).
  Future<void> _register(_Device d) async {
    final keygen = Stopwatch()..start();
    final aik = await _ed.newKeyPair();
    final dsk = await _ed.newKeyPair();
    final dik = await _x.newKeyPair();
    d
      ..accountId = Uuid.v7()
      ..deviceId = Uuid.v7();
    final created = DateTime.now().toUtc();
    final dskPublic = await _publicOf(dsk);
    final certBody = deviceCertificateBody(
      accountId: d.accountId,
      deviceId: d.deviceId,
      identityKey: await _publicOf(dik),
      signingKey: dskPublic,
      createdAt: created,
    );
    final registration = DeviceRegistration(
      deviceId: d.deviceId,
      name: 'Load device ${d.index}',
      platform: DevicePlatform.cli,
      identityKey: await _publicOf(dik),
      signingKey: dskPublic,
      certificate: DeviceCertificate(
        createdAt: created,
        signature: await _sign(aik, certBody),
      ),
      proof: await _sign(dsk, certBody),
    );
    final spk = await _publicOf(await _x.newKeyPair());
    final prekeys = PrekeyUpload(
      signedPrekey: SignedPrekey(
        id: 1,
        publicKey: spk,
        signature: await _sign(dsk, signedPrekeySignatureBody(1, spk)),
      ),
      oneTimePrekeys: [
        for (var i = 0; i < options.oneTimePrekeys; i++)
          OneTimePrekey(
            id: 2 + i,
            publicKey: await _publicOf(await _x.newKeyPair()),
          ),
      ],
    );
    final aikPublic = await _publicOf(aik);
    _samples['keygen']!.add(keygen.elapsedMicroseconds);

    final flow = Stopwatch()..start();
    final challenge = await _timed(
      'challenge',
      () => _call(
        Routes.phoneChallenge,
        as: d,
        auth: false,
        body: PhoneChallengeRequest(
          phoneNumber: d.phone,
          purpose: PhonePurpose.register,
        ).toJson(),
      ),
    );
    if (!challenge.ok) throw _StepFailed('challenge', challenge.errorKey);
    final code = await _askCode(d.phone);
    final verify = await _timed(
      'verify',
      () => _call(
        Routes.phoneVerify,
        as: d,
        auth: false,
        body: PhoneVerifyRequest(
          challengeId: PhoneChallengeResponse.fromJson(
            challenge.json,
          ).challengeId,
          code: code,
        ).toJson(),
      ),
    );
    if (!verify.ok) throw _StepFailed('verify', verify.errorKey);
    final register = await _timed(
      'register',
      () => _call(
        Routes.register,
        as: d,
        auth: false,
        body: RegisterRequest(
          accountId: d.accountId,
          identityKey: aikPublic,
          device: registration,
          prekeys: prekeys,
          verificationToken: PhoneVerifyResponse.fromJson(
            verify.json,
          ).verificationToken,
          termsVersion: HelixLegalDocuments.termsVersion,
        ).toJson(),
      ),
    );
    if (register.status != 201) {
      throw _StepFailed('register', register.errorKey);
    }
    d.token = RegisterResponse.fromJson(register.json).session.accessToken;
    _samples['registration']!.add(flow.elapsedMicroseconds);
  }

  /// The code the in-process server "texted" (held only in memory).
  Future<String> _askCode(String phone) {
    final id = _nextCode++;
    final waiter = _codes[id] = Completer<String>();
    out.send({'t': 'code?', 'id': id, 'phone': phone});
    return waiter.future.timeout(const Duration(seconds: 30));
  }

  // ------------------------------------------------------------ directory

  void _directory(Map<String, Object?> m) {
    _accounts = (m['accounts']! as List).cast<String?>();
    _devices = (m['devices']! as List).cast<String?>();
    _live = [
      for (var i = 0; i < _accounts.length; i++)
        if (_accounts[i] != null) i,
    ];
    _groups = [for (final g in m['groups']! as List) (g as List).cast<int>()];
    _groupIds = (m['group_ids']! as List).cast<String>();
    for (var g = 0; g < _groups.length; g++) {
      for (final member in _groups[g]) {
        final d = _mine[member];
        if (d == null) continue;
        d
          ..group = g
          // Every member device except the sending one (groups MODULE.md).
          ..digest = membersDigest({
            for (final other in _groups[g])
              if (other != member) _accounts[other]!: [_devices[other]!],
          });
      }
    }
    out.send({'t': 'directory_ok'});
  }

  Future<void> _createGroups() async {
    for (var g = 0; g < _groups.length; g++) {
      final owner = _mine[_groups[g].first];
      if (owner == null) continue;
      try {
        final r = await _timed(
          'group_create',
          () => _call(
            Routes.createGroup,
            as: owner,
            body: CreateGroupRequest(
              groupId: _groupIds[g],
              encryptedState: _bytes(120),
              members: [for (final m in _groups[g].skip(1)) _accounts[m]!],
            ).toJson(),
          ),
        );
        if (r.status != 201) {
          _errors.add('group_create:${r.errorKey}');
        } else if (Group.fromJson(r.json).members.length != _groups[g].length) {
          _errors.add('group_create:members_rejected');
        }
      } on Object catch (e) {
        _errors.add('group_create:${e.runtimeType}');
      }
    }
    out.send({
      't': 'groups_done',
      'samples': _wire(['group_create']),
      'errors': _errors.values,
    });
  }

  // -------------------------------------------------------------- sockets

  Future<void> _connectAll() async {
    final queue = _mine.values.toList();
    Future<void> lane() async {
      while (queue.isNotEmpty) {
        final d = queue.removeLast();
        try {
          await _connect(d, record: true);
        } on Object catch (e) {
          _errors.add('connect:${e.runtimeType}');
        }
      }
    }

    await Future.wait([
      for (var i = 0; i < options.connectConcurrency; i++) lane(),
    ]);
    _heartbeat = Timer.periodic(const Duration(seconds: 20), (_) {
      for (final d in _mine.values) {
        d.ws?.add(const PingFrame().encode());
      }
    });
    out.send({
      't': 'connected',
      'open': _mine.values.where((d) => d.ws != null).length,
      'samples': _wire(['connect']),
      'errors': _errors.values,
    });
  }

  /// Connects and waits for `hello`; replayed envelopes are processed as
  /// they arrive.
  Future<void> _connect(_Device d, {bool record = false}) async {
    final watch = Stopwatch()..start();
    final uri = base.replace(
      scheme: 'ws',
      path: Routes.websocket.path,
      queryParameters: d.lastSeq > 0 ? {'after': '${d.lastSeq}'} : null,
    );
    final ws = await WebSocket.connect(
      uri.toString(),
      protocols: const [realtimeSubprotocolJson],
      headers: {'authorization': 'Bearer ${d.token}', 'x-forwarded-for': d.ip},
    ).timeout(const Duration(seconds: 30));
    final hello = Completer<void>();
    ws.listen(
      (data) => _onFrame(d, data as String, hello),
      onDone: () => _onClosed(d, ws),
      onError: (Object _) {},
      cancelOnError: false,
    );
    await hello.future.timeout(const Duration(seconds: 30));
    d.ws = ws;
    if (record) _samples['connect']!.add(watch.elapsedMicroseconds);
  }

  void _onFrame(_Device d, String text, Completer<void> hello) {
    final frame = ServerFrame.decode(text);
    switch (frame) {
      case HelloFrame():
        if (!hello.isCompleted) hello.complete();
      case EnvelopeFrame(:final envelope):
        _onEnvelope(d, envelope);
      default:
        break;
    }
  }

  void _onEnvelope(_Device d, Envelope e) {
    final now = DateTime.now().microsecondsSinceEpoch;
    final p = e.payload;
    if (p != null && _isLoadPayload(p)) {
      final sentAt = ByteData.sublistView(p).getInt64(8, Endian.little);
      if (sentAt >= _measureFrom && sentAt < _measureTo) {
        if (d.seen.add(e.id)) {
          _counts.add('received');
          _samples[p[16] == _kindGroup ? 'e2e_group' : 'e2e_direct']!.add(
            now - sentAt,
          );
        } else {
          _counts.add('duplicates');
        }
      }
    }
    final seq = e.seq;
    if (seq == null) return;
    if (seq > d.lastSeq) d.lastSeq = seq;
    if (now >= _measureFrom &&
        now < _measureTo &&
        _random.nextDouble() < options.ackSample) {
      unawaited(_restAck(d, seq));
    } else {
      d.ws?.add(AckFrame(seq: seq).encode());
    }
  }

  /// Times a REST ack, then acks on the socket too so the server's window
  /// credit is released as usual.
  Future<void> _restAck(_Device d, int seq) async {
    try {
      final r = await _timed(
        'ack_rest',
        () => _call(
          Routes.ackMailbox,
          as: d,
          body: AckRequest(seq: seq).toJson(),
        ),
      );
      if (!r.ok) _errors.add('ack:${r.errorKey}');
    } on Object catch (e) {
      _errors.add('ack:${e.runtimeType}');
    }
    d.ws?.add(AckFrame(seq: seq).encode());
  }

  void _onClosed(_Device d, WebSocket ws) {
    if (!identical(d.ws, ws)) return;
    d.ws = null;
    if (_finishing) return;
    _errors.add('ws_closed:${ws.closeCode}');
    // Reconnect once after a second, like the app's backoff.
    Timer(const Duration(seconds: 1), () async {
      if (_finishing) return;
      try {
        await _connect(d);
        _counts.add('reconnects');
      } on Object catch (e) {
        _errors.add('reconnect:${e.runtimeType}');
      }
    });
  }

  // ------------------------------------------------------------------ run

  Future<void> _run(Map<String, Object?> m) async {
    final startAt = m['start_us']! as int;
    _measureFrom = m['measure_from_us']! as int;
    _measureTo = _stopAt = m['measure_to_us']! as int;
    final lag = _samples['loop_lag']!;
    var expected = DateTime.now().microsecondsSinceEpoch + 50000;
    _lagTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      final now = DateTime.now().microsecondsSinceEpoch;
      if (now >= _measureFrom && now < _measureTo) {
        lag.add(math.max(0, now - expected));
      }
      expected = now + 50000;
    });

    final senders = _mine.values.where((d) => d.ws != null).toList();
    await Future<void>.delayed(
      Duration(
        microseconds: math.max(
          0,
          startAt - DateTime.now().microsecondsSinceEpoch,
        ),
      ),
    );
    for (final d in senders) {
      _schedule(d);
    }
    await Future<void>.delayed(
      Duration(
        microseconds: math.max(
          0,
          _stopAt - DateTime.now().microsecondsSinceEpoch,
        ),
      ),
    );
    for (final d in senders) {
      d.timer?.cancel();
    }
    final deadline = DateTime.now().add(const Duration(seconds: 35));
    while (_inflight > 0 && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    _lagTimer?.cancel();
    out.send({
      't': 'sent',
      'expected': _counts.values['expected'] ?? 0,
      'inflight': _inflight,
    });
  }

  /// Poisson arrivals: exponential gaps at [LoadOptions.rate] per second.
  void _schedule(_Device d) {
    final gap = -math.log(1 - _random.nextDouble()) / options.rate;
    d.timer = Timer(Duration(microseconds: (gap * 1e6).round()), () {
      if (DateTime.now().microsecondsSinceEpoch >= _stopAt) return;
      unawaited(_sendOne(d));
      _schedule(d);
    });
  }

  Future<void> _sendOne(_Device d) async {
    final group = d.group != null && _random.nextDouble() < options.groupShare;
    final issued = DateTime.now().microsecondsSinceEpoch;
    final measured = issued >= _measureFrom && issued < _measureTo;
    final payload = _payload(group ? _kindGroup : _kindDirect, issued);
    final metric = group ? 'send_group' : 'send_direct';
    if (measured) _counts.add('attempted');
    _inflight++;
    try {
      final _Response r;
      if (group) {
        r = await _timed(
          metric,
          record: measured,
          () => _call(
            Routes.sendGroupMessage,
            as: d,
            params: {'group_id': _groupIds[d.group!]},
            body: GroupMessageRequest(
              id: Uuid.v7(),
              payload: payload,
              devicesDigest: d.digest!,
            ).toJson(),
          ),
        );
      } else {
        var peer = d.index;
        while (peer == d.index) {
          peer = _live[_random.nextInt(_live.length)];
        }
        r = await _timed(
          metric,
          record: measured,
          () => _call(
            Routes.sendMessage,
            as: d,
            body: SendMessageRequest(
              id: Uuid.v7(),
              recipients: [
                Recipient(
                  account: _accounts[peer]!,
                  devices: [
                    DevicePayload(device: _devices[peer]!, payload: payload),
                  ],
                ),
              ],
            ).toJson(),
          ),
        );
      }
      if (!measured) return;
      if (r.ok) {
        _counts.add('expected', group ? _groups[d.group!].length - 1 : 1);
      } else {
        _errors.add('$metric:${r.errorKey}');
      }
    } on Object catch (e) {
      if (measured) _errors.add('$metric:${e.runtimeType}');
    } finally {
      _inflight--;
    }
  }

  Uint8List _payload(int kind, int sentAt) {
    final size = payloadSize(_random, options.payloadBytes);
    final p = Uint8List(size)..setRange(0, 4, _magic);
    ByteData.sublistView(p)
      ..setUint32(4, tag, Endian.little)
      ..setInt64(8, sentAt, Endian.little);
    p[16] = kind;
    final offset = _random.nextInt(_pool.length - size);
    p.setRange(_headerBytes, size, _pool, offset);
    return p;
  }

  bool _isLoadPayload(Uint8List p) =>
      p.length >= _headerBytes &&
      p[0] == _magic[0] &&
      p[1] == _magic[1] &&
      p[2] == _magic[2] &&
      p[3] == _magic[3] &&
      ByteData.sublistView(p).getUint32(4, Endian.little) == tag;

  Uint8List _bytes(int n) =>
      Uint8List.fromList(List.generate(n, (_) => _random.nextInt(256)));

  // --------------------------------------------------------------- finish

  Future<void> _finish() async {
    _finishing = true;
    _heartbeat?.cancel();
    _lagTimer?.cancel();
    for (final d in _mine.values) {
      d.timer?.cancel();
      await d.ws?.close(1000);
    }
    _http.close(force: true);
    out.send({
      't': 'report',
      'samples': _wire([
        'send_direct',
        'send_group',
        'e2e_direct',
        'e2e_group',
        'ack_rest',
        'loop_lag',
      ]),
      'errors': _errors.values,
      'counts': _counts.values,
    });
  }

  Map<String, Object?> _wire(List<String> keys) => {
    for (final k in keys) k: _samples[k]!.toWire(),
  };
}

final class _StepFailed implements Exception {
  _StepFailed(this.step, this.key);

  final String step;
  final String key;
}
