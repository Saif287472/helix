// Tests for Phase F8: Group calls, call links, scheduled calls.
import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:helix_remote_backend/helix_remote_backend.dart';

class _Client {
  _Client(this.baseUrl, this.token);
  final String baseUrl;
  final String token;
  final _http = HttpClient();

  Future<({int status, Map<String, dynamic> json})> get(String path) async {
    final req = await _http.getUrl(Uri.parse('$baseUrl$path'));
    if (token.isNotEmpty) req.headers.set('Authorization', 'Bearer $token');
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    final decoded = body.isEmpty ? <String, dynamic>{} : jsonDecode(body);
    return (
      status: res.statusCode,
      json: decoded is Map<String, dynamic> ? decoded : {'_body': decoded},
    );
  }

  Future<({int status, Map<String, dynamic> json})> post(
    String path,
    Map<String, dynamic> payload,
  ) async {
    final req = await _http.postUrl(Uri.parse('$baseUrl$path'));
    if (token.isNotEmpty) req.headers.set('Authorization', 'Bearer $token');
    req.headers.set('Content-Type', 'application/json');
    req.write(jsonEncode(payload));
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    final decoded = body.isEmpty ? <String, dynamic>{} : jsonDecode(body);
    return (
      status: res.statusCode,
      json: decoded is Map<String, dynamic> ? decoded : {'_body': decoded},
    );
  }

  Future<({int status, Map<String, dynamic> json})> delete(String path) async {
    final req = await _http.deleteUrl(Uri.parse('$baseUrl$path'));
    if (token.isNotEmpty) req.headers.set('Authorization', 'Bearer $token');
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    final decoded = body.isEmpty ? <String, dynamic>{} : jsonDecode(body);
    return (
      status: res.statusCode,
      json: decoded is Map<String, dynamic> ? decoded : {'_body': decoded},
    );
  }
}

void main() {
  late BackendServer server;
  late int port;
  late String tokenAlice;
  late String tokenBob;
  late String tokenCarol;

  String base() => 'http://127.0.0.1:$port/api/v1';

  setUp(() async {
    server = BackendServer.create(
      sqliteDb: sqlite3.openInMemory(),
      jwtSecret: 'test_jwt_f8_group_calls',
      rateLimitMaxTokens: 500.0,
      rateLimitRefillRate: 100.0,
    );
    await server.start('127.0.0.1', 0);
    port = server.httpServer!.port;

    server.db.createAccount('alice', 'alice_user', 'alice_identity_key');
    server.db.registerDevice(
      'alice_dev1',
      'alice',
      'alice_device_key',
      'Alice Phone',
    );
    server.db.createAccount('bob', 'bob_user', 'bob_identity_key');
    server.db.registerDevice('bob_dev1', 'bob', 'bob_device_key', 'Bob Phone');
    server.db.createAccount('carol', 'carol_user', 'carol_identity_key');
    server.db.registerDevice(
      'carol_dev1',
      'carol',
      'carol_device_key',
      'Carol Phone',
    );

    tokenAlice = server.jwt.generateToken({
      'account_id': 'alice',
      'device_id': 'alice_dev1',
    }, const Duration(hours: 1));

    tokenBob = server.jwt.generateToken({
      'account_id': 'bob',
      'device_id': 'bob_dev1',
    }, const Duration(hours: 1));

    tokenCarol = server.jwt.generateToken({
      'account_id': 'carol',
      'device_id': 'carol_dev1',
    }, const Duration(hours: 1));
  });

  tearDown(() async => server.stop());

  // -------------------------------------------------------------------------
  // Room lifecycle
  // -------------------------------------------------------------------------

  group('room lifecycle', () {
    test(
      'host creates a video room and gets 201-like 200 with room_id',
      () async {
        final alice = _Client(base(), tokenAlice);
        final r = await alice.post('/group-calls/', {'is_video': true});
        expect(r.status, 200);
        expect(r.json['room_id'], isA<String>());
        expect(r.json['is_video'], true);
      },
    );

    test('participant can join the room', () async {
      final alice = _Client(base(), tokenAlice);
      final bob = _Client(base(), tokenBob);

      final create = await alice.post('/group-calls/', {'is_video': false});
      final roomId = create.json['room_id'] as String;

      final join = await bob.post('/group-calls/$roomId/join', {});
      expect(join.status, 200);
      expect(join.json['status'], 'joined');
    });

    test('GET room returns participants list', () async {
      final alice = _Client(base(), tokenAlice);
      final bob = _Client(base(), tokenBob);

      final create = await alice.post('/group-calls/', {'is_video': true});
      final roomId = create.json['room_id'] as String;
      await bob.post('/group-calls/$roomId/join', {});

      final get = await alice.get('/group-calls/$roomId');
      expect(get.status, 200);
      final participants = get.json['participants'] as List<dynamic>;
      expect(participants.length, greaterThanOrEqualTo(2));
    });

    test('room rejects a 5th joiner', () async {
      final alice = _Client(base(), tokenAlice);
      final bob = _Client(base(), tokenBob);
      final carol = _Client(base(), tokenCarol);

      // Seed dave and eve directly.
      server.db.createAccount('dave', 'dave_user', 'dave_identity_key');
      server.db.registerDevice(
        'dave_dev1',
        'dave',
        'dave_device_key',
        'Dave Phone',
      );
      final tokenDave = server.jwt.generateToken({
        'account_id': 'dave',
        'device_id': 'dave_dev1',
      }, const Duration(hours: 1));
      final dave = _Client(base(), tokenDave);

      server.db.createAccount('eve', 'eve_user', 'eve_identity_key');
      server.db.registerDevice(
        'eve_dev1',
        'eve',
        'eve_device_key',
        'Eve Phone',
      );
      final tokenEve = server.jwt.generateToken({
        'account_id': 'eve',
        'device_id': 'eve_dev1',
      }, const Duration(hours: 1));
      final eve = _Client(base(), tokenEve);

      final create = await alice.post('/group-calls/', {'is_video': true});
      final roomId = create.json['room_id'] as String;

      // Alice, Bob, Carol, Dave join -> 4 participants (max capacity).
      await alice.post('/group-calls/$roomId/join', {});
      await bob.post('/group-calls/$roomId/join', {});
      await carol.post('/group-calls/$roomId/join', {});
      final joinDave = await dave.post('/group-calls/$roomId/join', {});
      expect(joinDave.status, 200);

      // Eve attempts to join (5th) -> should get 409 room_full.
      final joinEve = await eve.post('/group-calls/$roomId/join', {});
      expect(joinEve.status, 409);
      expect(joinEve.json['error'], contains('room_full'));
    });

    test('participant can leave room', () async {
      final alice = _Client(base(), tokenAlice);
      final bob = _Client(base(), tokenBob);

      final create = await alice.post('/group-calls/', {'is_video': false});
      final roomId = create.json['room_id'] as String;
      await bob.post('/group-calls/$roomId/join', {});

      final leave = await bob.post('/group-calls/$roomId/leave', {});
      expect(leave.status, 200);
      expect(leave.json['status'], 'left');
    });

    test('host can end room', () async {
      final alice = _Client(base(), tokenAlice);
      final bob = _Client(base(), tokenBob);

      final create = await alice.post('/group-calls/', {'is_video': true});
      final roomId = create.json['room_id'] as String;
      await bob.post('/group-calls/$roomId/join', {});

      final end = await alice.post('/group-calls/$roomId/end', {});
      expect(end.status, 200);
      expect(end.json['status'], 'ended');
    });

    test('non-host cannot end room', () async {
      final alice = _Client(base(), tokenAlice);
      final bob = _Client(base(), tokenBob);

      final create = await alice.post('/group-calls/', {'is_video': true});
      final roomId = create.json['room_id'] as String;
      await bob.post('/group-calls/$roomId/join', {});

      final end = await bob.post('/group-calls/$roomId/end', {});
      expect(end.status, 403);
    });

    test('host can kick a participant', () async {
      final alice = _Client(base(), tokenAlice);
      final bob = _Client(base(), tokenBob);

      final create = await alice.post('/group-calls/', {'is_video': true});
      final roomId = create.json['room_id'] as String;
      await bob.post('/group-calls/$roomId/join', {});

      final kick = await alice.post('/group-calls/$roomId/kick', {
        'device_id': 'bob_dev1',
      });
      expect(kick.status, 200);
      expect(kick.json['status'], 'kicked');
    });
  });

  // -------------------------------------------------------------------------
  // Room keys
  // -------------------------------------------------------------------------

  group('room keys', () {
    test('host delivers wrapped room key for each participant', () async {
      final alice = _Client(base(), tokenAlice);
      final bob = _Client(base(), tokenBob);

      final create = await alice.post('/group-calls/', {'is_video': true});
      final roomId = create.json['room_id'] as String;
      await bob.post('/group-calls/$roomId/join', {});

      final r = await alice.post('/group-calls/$roomId/key', {
        'key_id': 'key_001',
        'epoch': 0,
        'keys': [
          {'device_id': 'bob_dev1', 'wrapped_key': 'WRAPPED_BOB_KEY'},
        ],
      });
      expect(r.status, 200);
      expect(r.json['saved'], 1);
      expect(r.json['epoch'], 0);
    });

    test('non-host cannot deliver room key', () async {
      final alice = _Client(base(), tokenAlice);
      final bob = _Client(base(), tokenBob);

      final create = await alice.post('/group-calls/', {'is_video': true});
      final roomId = create.json['room_id'] as String;
      await bob.post('/group-calls/$roomId/join', {});

      final r = await bob.post('/group-calls/$roomId/key', {
        'key_id': 'key_x',
        'epoch': 0,
        'keys': [],
      });
      expect(r.status, 403);
    });

    test('screen-sharing flag can be toggled', () async {
      final alice = _Client(base(), tokenAlice);
      final create = await alice.post('/group-calls/', {'is_video': true});
      final roomId = create.json['room_id'] as String;

      final on = await alice.post('/group-calls/$roomId/screen-sharing', {
        'active': true,
      });
      expect(on.status, 200);
      expect(on.json['active'], true);

      final off = await alice.post('/group-calls/$roomId/screen-sharing', {
        'active': false,
      });
      expect(off.status, 200);
      expect(off.json['active'], false);
    });
  });

  // -------------------------------------------------------------------------
  // Call links
  // -------------------------------------------------------------------------

  group('call links', () {
    test('creates a call link with token', () async {
      final alice = _Client(base(), tokenAlice);
      final r = await alice.post('/group-calls/links', {});
      expect(r.status, 200);
      expect(r.json['link_token'], isA<String>());
      expect((r.json['link_token'] as String).length, 64);
    });

    test('resolves an active call link', () async {
      final alice = _Client(base(), tokenAlice);
      final bob = _Client(base(), tokenBob);

      final create = await alice.post('/group-calls/links', {
        'requires_approval': false,
      });
      final token = create.json['link_token'] as String;

      final resolve = await bob.get('/group-calls/links/$token');
      expect(resolve.status, 200);
      expect(resolve.json['link_id'], isA<String>());
    });

    test('creator can revoke link', () async {
      final alice = _Client(base(), tokenAlice);
      final bob = _Client(base(), tokenBob);

      final create = await alice.post('/group-calls/links', {});
      final token = create.json['link_token'] as String;

      final revoke = await alice.delete('/group-calls/links/$token');
      expect(revoke.status, 200);
      expect(revoke.json['status'], 'revoked');

      final resolve = await bob.get('/group-calls/links/$token');
      expect(resolve.status, 410);
    });

    test('non-creator cannot revoke link', () async {
      final alice = _Client(base(), tokenAlice);
      final bob = _Client(base(), tokenBob);

      final create = await alice.post('/group-calls/links', {});
      final token = create.json['link_token'] as String;

      final revoke = await bob.delete('/group-calls/links/$token');
      expect(revoke.status, 403);
    });

    test('unknown link returns 404', () async {
      final bob = _Client(base(), tokenBob);
      final r = await bob.get(
        '/group-calls/links/deadbeef0000000000000000000000000000000000000000000000000000dead',
      );
      expect(r.status, 404);
    });
  });

  // -------------------------------------------------------------------------
  // Scheduled calls
  // -------------------------------------------------------------------------

  group('scheduled calls', () {
    int _futureMs(int minutesFromNow) => DateTime.now()
        .add(Duration(minutes: minutesFromNow))
        .millisecondsSinceEpoch;

    test('creates a scheduled call', () async {
      final alice = _Client(base(), tokenAlice);
      final r = await alice.post('/group-calls/scheduled', {
        'title': 'Weekly sync',
        'scheduled_at': _futureMs(60),
        'attendee_ids': ['bob'],
      });
      expect(r.status, 200);
      expect(r.json['scheduled_call_id'], isA<String>());
      expect(r.json['title'], 'Weekly sync');
    });

    test('lists upcoming scheduled calls for attendee', () async {
      final alice = _Client(base(), tokenAlice);
      final bob = _Client(base(), tokenBob);

      await alice.post('/group-calls/scheduled', {
        'title': 'Team standup',
        'scheduled_at': _futureMs(30),
        'attendee_ids': ['bob'],
      });

      final list = await bob.get('/group-calls/scheduled');
      expect(list.status, 200);
      final calls = list.json['calls'] as List<dynamic>;
      expect(calls.any((c) => (c as Map)['title'] == 'Team standup'), isTrue);
    });

    test('attendee can RSVP YES', () async {
      final alice = _Client(base(), tokenAlice);
      final bob = _Client(base(), tokenBob);

      final create = await alice.post('/group-calls/scheduled', {
        'title': 'Design review',
        'scheduled_at': _futureMs(120),
        'attendee_ids': ['bob'],
      });
      final scId = create.json['scheduled_call_id'] as String;

      final rsvp = await bob.post('/group-calls/scheduled/$scId/rsvp', {
        'rsvp': 'YES',
      });
      expect(rsvp.status, 200);
      expect(rsvp.json['rsvp'], 'YES');
    });

    test('rejects invalid RSVP value', () async {
      final alice = _Client(base(), tokenAlice);
      final bob = _Client(base(), tokenBob);

      final create = await alice.post('/group-calls/scheduled', {
        'title': 'Retro',
        'scheduled_at': _futureMs(90),
        'attendee_ids': ['bob'],
      });
      final scId = create.json['scheduled_call_id'] as String;

      final r = await bob.post('/group-calls/scheduled/$scId/rsvp', {
        'rsvp': 'MAYBE',
      });
      expect(r.status, 400);
    });

    test('host can cancel scheduled call', () async {
      final alice = _Client(base(), tokenAlice);

      final create = await alice.post('/group-calls/scheduled', {
        'title': 'All hands',
        'scheduled_at': _futureMs(180),
        'attendee_ids': [],
      });
      final scId = create.json['scheduled_call_id'] as String;

      final cancel = await alice.delete('/group-calls/scheduled/$scId');
      expect(cancel.status, 200);
      expect(cancel.json['status'], 'cancelled');
    });

    test('non-host cannot cancel', () async {
      final alice = _Client(base(), tokenAlice);
      final bob = _Client(base(), tokenBob);

      final create = await alice.post('/group-calls/scheduled', {
        'title': 'Sprint planning',
        'scheduled_at': _futureMs(60),
        'attendee_ids': ['bob'],
      });
      final scId = create.json['scheduled_call_id'] as String;

      final r = await bob.delete('/group-calls/scheduled/$scId');
      expect(r.status, 403);
    });

    test('rejects past scheduled_at', () async {
      final alice = _Client(base(), tokenAlice);
      final r = await alice.post('/group-calls/scheduled', {
        'title': 'Old meeting',
        'scheduled_at': DateTime.now()
            .subtract(const Duration(minutes: 5))
            .millisecondsSinceEpoch,
        'attendee_ids': [],
      });
      expect(r.status, 400);
    });

    test('requires auth on all group-calls endpoints', () async {
      final anon = _Client(base(), '');
      final r = await anon.post('/group-calls/', {'is_video': false});
      expect(r.status, 401);
    });
  });
}
