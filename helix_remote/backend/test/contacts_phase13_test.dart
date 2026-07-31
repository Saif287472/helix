import 'dart:async';
import 'dart:convert';

import 'package:helix_remote_backend/helix_remote_backend.dart';
import 'package:helix_remote_backend/src/modules/contacts.dart';
import 'package:helix_remote_backend/src/modules/messaging.dart';
import 'package:shelf/shelf.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  late BackendDatabase db;
  late ContactsModule contacts;

  setUp(() {
    db = BackendDatabase(sqlite3.openInMemory());
    contacts = ContactsModule(db);

    _seedAccount(db, 'alice', 'alice', 'alice_device');
    _seedAccount(db, 'bob', 'bob', 'bob_device');
    _seedAccount(db, 'carol', 'carol', 'carol_device');
    _seedAccount(db, 'admin', 'admin_user', 'admin_device');
  });

  tearDown(() {
    db.close();
  });

  test('Phase 13 contact request lifecycle and removal', () async {
    final delivered = <Map<String, dynamic>>[];
    contacts = ContactsModule(
      db,
      notifyDevice: (deviceId, payload) {
        delivered.add({'device_id': deviceId, 'payload': payload});
      },
    );
    final create = await _json(
      contacts.router.call(
        _request(
          'POST',
          '/requests',
          authAccount: 'alice',
          authDevice: 'alice_device',
          body: {'request_id': 'cr_alice_bob', 'peer_account_id': 'bob'},
        ),
      ),
    );
    expect(create.statusCode, 200);
    expect(db.getContacts('alice').single['status'], 'PENDING_SENT');
    expect(db.getContacts('bob').single['status'], 'PENDING_RECEIVED');
    expect(
      db.getDeviceEvents('bob_device', 0).map((e) => e['event_type']),
      contains('contact_updated'),
    );
    expect(
      jsonEncode(delivered),
      allOf(contains('PendingReceived'), contains('cr_alice_bob')),
    );

    final duplicateReverse = await _json(
      contacts.router.call(
        _request(
          'POST',
          '/requests',
          authAccount: 'bob',
          authDevice: 'bob_device',
          body: {'request_id': 'cr_bob_alice', 'peer_account_id': 'alice'},
        ),
      ),
    );
    expect(duplicateReverse.statusCode, 403);

    final accept = await _json(
      contacts.router.call(
        _request(
          'POST',
          '/requests/accept',
          authAccount: 'bob',
          authDevice: 'bob_device',
          body: {'request_id': 'cr_alice_bob'},
        ),
      ),
    );
    expect(accept.statusCode, 200);
    expect(db.areContacts('alice', 'bob'), isTrue);
    expect(db.areContacts('bob', 'alice'), isTrue);
    expect(
      jsonEncode(db.getDeviceEvents('alice_device', 0)),
      contains('Accepted'),
    );

    final remove = await _json(
      contacts.router.call(
        _request(
          'POST',
          '/remove',
          authAccount: 'alice',
          authDevice: 'alice_device',
          body: {'peer_account_id': 'bob'},
        ),
      ),
    );
    expect(remove.statusCode, 200);
    expect(db.areContacts('alice', 'bob'), isFalse);

    await contacts.router.call(
      _request(
        'POST',
        '/requests',
        authAccount: 'carol',
        authDevice: 'carol_device',
        body: {'request_id': 'cr_carol_alice', 'peer_account_id': 'alice'},
      ),
    );
    final reject = await _json(
      contacts.router.call(
        _request(
          'POST',
          '/requests/reject',
          authAccount: 'alice',
          authDevice: 'alice_device',
          body: {'request_id': 'cr_carol_alice'},
        ),
      ),
    );
    expect(reject.statusCode, 200);
    expect(db.areContacts('carol', 'alice'), isFalse);
  });

  test('Phase 13 privacy, presence, report, and safety contracts', () async {
    await contacts.router.call(
      _request(
        'POST',
        '/requests',
        authAccount: 'alice',
        authDevice: 'alice_device',
        body: {'request_id': 'cr_presence', 'peer_account_id': 'bob'},
      ),
    );
    await contacts.router.call(
      _request(
        'POST',
        '/requests/accept',
        authAccount: 'bob',
        authDevice: 'bob_device',
        body: {'request_id': 'cr_presence'},
      ),
    );

    final privacy = await _json(
      contacts.router.call(
        _request(
          'POST',
          '/privacy',
          authAccount: 'bob',
          authDevice: 'bob_device',
          body: {
            'search_discoverable': false,
            'presence_visibility': 'CONTACTS',
            'last_seen_visibility': 'NOBODY',
          },
        ),
      ),
    );
    expect(privacy.statusCode, 200);

    final search = await _json(
      contacts.router.call(
        _request(
          'GET',
          '/search?q=bo',
          authAccount: 'alice',
          authDevice: 'alice_device',
        ),
      ),
    );
    expect(search.body['accounts'], isEmpty);

    final hiddenSearch = await _json(
      contacts.router.call(
        _request(
          'GET',
          '/search?q=bob',
          authAccount: 'alice',
          authDevice: 'alice_device',
        ),
      ),
    );
    expect(hiddenSearch.body['accounts'], isEmpty);

    final heartbeat = await _json(
      contacts.router.call(
        _request(
          'POST',
          '/presence',
          authAccount: 'bob',
          authDevice: 'bob_device',
        ),
      ),
    );
    expect(heartbeat.statusCode, 200);

    final presence = await _json(
      contacts.router.call(
        _request(
          'GET',
          '/presence/bob',
          authAccount: 'alice',
          authDevice: 'alice_device',
        ),
      ),
    );
    expect(presence.statusCode, 200);
    final presenceBody = presence.body['presence'] as Map<String, dynamic>;
    expect(presenceBody['presence'], 'RECENTLY_ACTIVE');
    expect(presenceBody['last_seen_at'], isNull);

    final badReport = await _json(
      contacts.router.call(
        _request(
          'POST',
          '/report',
          authAccount: 'alice',
          authDevice: 'alice_device',
          body: {
            'report_id': 'r_bad',
            'subject_account_id': 'bob',
            'category': 'spam',
            'reason_code': 'plaintext_attempt',
            'message_text': 'secret message',
          },
        ),
      ),
    );
    expect(badReport.statusCode, 400);

    final report = await _json(
      contacts.router.call(
        _request(
          'POST',
          '/report',
          authAccount: 'alice',
          authDevice: 'alice_device',
          body: {
            'report_id': 'r_good',
            'subject_account_id': 'bob',
            'category': 'spam',
            'reason_code': 'unsolicited',
            'context_hash': 'sha256:deadbeef',
          },
        ),
      ),
    );
    expect(report.statusCode, 200);
    expect(jsonEncode(db.getReports()), isNot(contains('secret message')));

    final action = await _json(
      contacts.router.call(
        _request(
          'POST',
          '/reports/action',
          authAccount: 'admin',
          authDevice: 'admin_device',
          body: {
            'action_id': 'sa_1',
            'report_id': 'r_good',
            'action': 'WARNED',
          },
        ),
      ),
    );
    expect(action.statusCode, 200);
    expect(db.getReports().single['status'], 'ACTIONED');
  });

  test('F3 account search is minimum-length and rate limited', () async {
    final short = await _json(
      contacts.router.call(
        _request(
          'GET',
          '/search?q=bo',
          authAccount: 'alice',
          authDevice: 'alice_device',
        ),
      ),
    );
    expect(short.statusCode, 200);
    expect(short.body['accounts'], isEmpty);

    _JsonResponse? last;
    for (var i = 0; i < ContactsModule.accountSearchMinuteLimit + 1; i++) {
      last = await _json(
        contacts.router.call(
          _request(
            'GET',
            '/search?q=bob',
            authAccount: 'alice',
            authDevice: 'alice_device',
          ),
        ),
      );
    }
    expect(last!.statusCode, 429);
  });

  test(
    'contact discovery fuzzy matches display names without usernames',
    () async {
      _seedAccount(
        db,
        'saif_mahmud',
        'hidden_saif_one',
        'saif_mahmud_device',
        displayName: 'Saif Mahmud',
      );
      _seedAccount(
        db,
        'saiful_islam',
        'hidden_saif_two',
        'saiful_islam_device',
        displayName: 'Saiful Islam',
      );
      _seedAccount(
        db,
        'sara_miller',
        'hidden_sara',
        'sara_miller_device',
        displayName: 'Sara Miller',
      );

      final search = await _json(
        contacts.router.call(
          _request(
            'GET',
            '/search?q=Saif',
            authAccount: 'alice',
            authDevice: 'alice_device',
          ),
        ),
      );

      expect(search.statusCode, 200);
      final accounts = (search.body['accounts'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(accounts.map((a) => a['display_name']), contains('Saif Mahmud'));
      expect(accounts.first['display_name'], 'Saif Mahmud');
      expect(accounts.first['similarity'], greaterThanOrEqualTo(0.9));
      expect(jsonEncode(accounts), isNot(contains('hidden_saif_one')));
      expect(jsonEncode(accounts), isNot(contains('username')));
    },
  );

  test('Phase 13 contact request quota enforced', () async {
    for (var i = 0; i < ContactsModule.contactRequestDailyLimit; i++) {
      _seedAccount(db, 'quota_$i', 'quota_$i', 'quota_device_$i');
      final response = await _json(
        contacts.router.call(
          _request(
            'POST',
            '/requests',
            authAccount: 'alice',
            authDevice: 'alice_device',
            body: {
              'request_id': 'quota_request_$i',
              'peer_account_id': 'quota_$i',
            },
          ),
        ),
      );
      expect(response.statusCode, 200);
    }

    _seedAccount(
      db,
      'quota_overflow',
      'quota_overflow',
      'quota_device_overflow',
    );
    final overflow = await _json(
      contacts.router.call(
        _request(
          'POST',
          '/requests',
          authAccount: 'alice',
          authDevice: 'alice_device',
          body: {
            'request_id': 'quota_overflow_request',
            'peer_account_id': 'quota_overflow',
          },
        ),
      ),
    );
    expect(overflow.statusCode, 429);
  });

  test('Phase 13 blocked sender delivery is silently dropped', () async {
    final messaging = MessagingModule(db, _FakeRelay());
    db.createConversation('conv_blocked', 'DIRECT', 'Blocked chat', [
      'alice',
      'bob',
    ]);
    db.blockContact('bob', 'alice');

    final send = await _json(
      messaging.router.call(
        _request(
          'POST',
          '/send',
          authAccount: 'alice',
          authDevice: 'alice_device',
          body: {
            'message_id': 'msg_blocked',
            'conversation_id': 'conv_blocked',
            'envelopes': [
              {
                'recipient_device_id': 'bob_device',
                'ciphertext': 'opaque-ciphertext',
              },
            ],
          },
        ),
      ),
    );

    expect(send.statusCode, 200);
    expect(send.body['envelopes_count'], 0);
    expect(db.getMessagesForDevice('bob_device', 'conv_blocked', 0), isEmpty);
  });
}

class _FakeRelay implements MessageRelay {
  @override
  void sendToDevice(String deviceId, Map<String, dynamic> payload) {}
}

void _seedAccount(
  BackendDatabase db,
  String accountId,
  String username,
  String deviceId, {
  String? displayName,
}) {
  db.createAccount(accountId, username, '${accountId}_identity');
  db.upsertAccountProfile(
    accountId: accountId,
    displayName: displayName ?? username,
  );
  db.registerDevice(
    deviceId,
    accountId,
    '${deviceId}_public',
    '$username phone',
  );
}

Request _request(
  String method,
  String path, {
  required String authAccount,
  required String authDevice,
  Map<String, dynamic>? body,
}) {
  return Request(
    method,
    Uri.parse('http://localhost$path'),
    body: body == null ? null : jsonEncode(body),
    headers: {'content-type': 'application/json'},
    context: {
      'auth': {'account_id': authAccount, 'device_id': authDevice},
      'client_ip': '127.0.0.1',
    },
  );
}

Future<_JsonResponse> _json(FutureOr<Response> responseFuture) async {
  final response = await responseFuture;
  final text = await response.readAsString();
  return _JsonResponse(
    response.statusCode,
    text.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(text) as Map<String, dynamic>,
  );
}

class _JsonResponse {
  const _JsonResponse(this.statusCode, this.body);

  final int statusCode;
  final Map<String, dynamic> body;
}
