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

  Future<String> _register(String username) async {
    final http = HttpClient();
    final req = await http.postUrl(Uri.parse('${base()}/auth/register'));
    req.headers.set('Content-Type', 'application/json');
    req.write(jsonEncode({
      'account_id': username,
      'device_id': '${username}_dev1',
      'password': 'pass_$username',
      'device_name': 'Phone',
    }));
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    http.close();
    return (jsonDecode(body) as Map<String, dynamic>)['access_token'] as String;
  }

  setUp(() async {
    server = BackendServer.create(
      sqliteDb: sqlite3.openInMemory(),
      jwtSecret: 'test_jwt_f8_group_calls',
      rateLimitMaxTokens: 500.0,
      rateLimitRefillRate: 100.0,
    );
    await server.start('127.0.0.1', 0);
    port = server.httpServer!.port;
    tokenAlice = await _register('alice');
    tokenBob = await _register('bob');
    tokenCarol = await _register('carol');
  });

  tearDown(() async => server.stop());

  // -------------------------------------------------------------------------
  // Room lifecycle
  // -------------------------------------------------------------------------

  group('room lifecycle', () {
    test('host creates a video room and gets 201-like 200 with room_id', () async {
      final alice = _Client(base(), tokenAlice);
      final r = await alice.post('/group-calls/', {'is_video': true});
      expect(r.status, 200);
      expect(r.json['room_id'], isA<String>());
      expect(r.json['is_video'], true);
    });

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
      // alice is host (counts as 1), bob + carol join (3). A 4th would be rejected.
      // We only have 3 accounts so test the capacity count directly via join attempts.
      final alice = _Client(base(), tokenAlice);
      final bob = _Client(base(), tokenBob);
      final carol = _Client(base(), tokenCarol);

      final create = await alice.post('/group-calls/', {'is_video': true});
      final roomId = create.json['room_id'] as String;
      await bob.post('/group-calls/$roomId/join', {});
      await carol.post('/group-calls/$roomId/join', {});

      // Register a 4th account and try to join — should get 409 room_full.
      final http = HttpClient();
      final req = await http.postUrl(Uri.parse('${base()}/auth/register'));
      req.headers.set('Content-Type', 'application/json');
      req.write(jsonEncode({
        'account_id': 'dave',
        'device_id': 'dave_dev1',
        'password': 'pass_dave',
        'device_name': 'Phone',
      }));
      final res = await req.close();
      final tokenDave =
          (jsonDecode(await res.transform(utf8.decoder).join())
              as Map<String, dynamic>)['access_token'] as String;
      http.close();

      final dave = _Client(base(), tokenDave);
      final join4 = await dave.post('/group-calls/$roomId/join', {});
      expect(join4.status, 409);
      expect(join4.json['error'], contains('room_full'));
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

      final on = await alice.post('/group-calls/$roomId/screen-sharing', {'active': true});
      expect(on.status, 200);
      expect(on.json['active'], true);

      final off = await alice.post('/group-calls/$roomId/screen-sharing', {'active': false});
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

      final create = await alice.post('/group-calls/links', {'requires_approval': false});
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
      final r = await bob.get('/group-calls/links/deadbeef0000000000000000000000000000000000000000000000000000dead');
      expect(r.status, 404);
    });
  });

  // -------------------------------------------------------------------------
  // Scheduled calls
  // -------------------------------------------------------------------------

  group('scheduled calls', () {
    int _futureMs(int minutesFromNow) =>
        DateTime.now()
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

      final rsvp = await bob.post('/group-calls/scheduled/$scId/rsvp', {'rsvp': 'YES'});
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

      final r = await bob.post('/group-calls/scheduled/$scId/rsvp', {'rsvp': 'MAYBE'});
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
