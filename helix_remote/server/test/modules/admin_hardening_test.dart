import 'dart:async';
import 'dart:io';

import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/src/modules/admin/domain/local_address.dart';
import 'package:helix_remote_server/src/modules/admin/module.dart';
import 'package:test/test.dart';

import '../support/harness.dart';
import '../support/test_client.dart';
import '../support/test_database.dart';

const adminPassword = 'correct horse battery staple';
const newPassword = 'a brand new admin password';

/// The admin API hardening of the 2026-10-09 review, batch 6 (B-02, B-03,
/// B-04, B-07, B-08). The console's own items are in `helix_remote/admin`.
void main() {
  group('isLocalNetworkAddress', () {
    test('this machine and the LAN, never the internet or CGNAT', () {
      for (final local in [
        '127.0.0.1',
        '10.1.2.3',
        '172.16.0.1',
        '172.31.255.255',
        '192.168.0.10',
        '169.254.1.1',
        '::1',
        'fd12:3456::1',
        'fe80::1',
        '::ffff:192.168.1.5',
      ]) {
        expect(isLocalNetworkAddress(local), isTrue, reason: local);
      }
      for (final remote in [
        '8.8.8.8',
        '172.32.0.1',
        '100.64.0.1',
        '203.0.113.7',
        '2001:db8::1',
        '::ffff:8.8.8.8',
        'not an address',
        '',
      ]) {
        expect(isLocalNetworkAddress(remote), isFalse, reason: remote);
      }
    });
  });

  /// A peer that forwards for others without being a listed proxy is a proxy
  /// the configuration forgot: its address is every client behind it, so
  /// sign-in says so and does not treat it as a LAN host (AUD-7-1).
  group(
    'a proxy missing from the trusted list',
    skip: databaseTestSkipReason,
    () {
      Future<Harness> start(Map<String, String> proxies) => Harness.start(
        extra: {'HELIX_ADMIN_PASSWORD': adminPassword, ...proxies},
      );

      Future<TestResponse> signIn(Harness h, {String? from}) => h.api.call(
        Routes.adminSignIn,
        headers: {'x-forwarded-for': ?from},
        body: const AdminPasswordRequest(password: 'wrong password!!').toJson(),
      );

      test('is reported, and a listed one is not', () async {
        final unlisted = await start({'HELIX_TRUSTED_PROXIES': '203.0.113.77'});
        try {
          await signIn(unlisted, from: '198.51.100.9');
          expect(
            unlisted.env.log.lines.where(
              (l) => l.contains('admin_untrusted_proxy'),
            ),
            hasLength(1),
          );
          await signIn(unlisted);
          expect(
            unlisted.env.log.lines.where(
              (l) => l.contains('admin_untrusted_proxy'),
            ),
            hasLength(1),
            reason:
                'a direct client with no forwarding header is just a client',
          );
        } finally {
          await unlisted.stop();
        }
        final listed = await start(const {});
        try {
          await signIn(listed, from: '198.51.100.9');
          expect(
            listed.env.log.lines.where(
              (l) => l.contains('admin_untrusted_proxy'),
            ),
            isEmpty,
          );
        } finally {
          await listed.stop();
        }
      });
    },
  );

  group('admin hardening', skip: databaseTestSkipReason, () {
    late Harness h;

    setUp(
      () async => h = await Harness.start(
        extra: {'HELIX_ADMIN_PASSWORD': adminPassword},
      ),
    );
    tearDown(() async => h.stop());

    AdminModule admin() => h.server.modules.whereType<AdminModule>().single;

    Future<TestResponse> signIn(String password, {String? from}) => h.api.call(
      Routes.adminSignIn,
      headers: {'x-forwarded-for': ?from},
      body: AdminPasswordRequest(password: password).toJson(),
    );

    Future<String> token() async =>
        AdminSession.fromJson((await signIn(adminPassword)).json).token;

    Future<int> configStatus(String bearer) async =>
        (await h.api.call(Routes.adminConfig, bearer: bearer)).status;

    Future<List<String>> auditActions(String bearer) async => [
      for (final e in Page.fromJson(
        (await h.api.call(Routes.adminAudit, bearer: bearer)).json,
        AuditEntry.fromJson,
      ).items)
        e.action,
    ];

    /// A live log stream and the close code it ends with.
    Future<(WebSocket, Future<int?>)> logStream(String bearer) async {
      final socket = await WebSocket.connect(
        h.server.baseUri
            .replace(scheme: 'ws', path: Routes.adminLogStream.path)
            .toString(),
        headers: {'authorization': 'Bearer $bearer'},
      );
      final closed = Completer<int?>();
      socket.listen(
        (_) {},
        onDone: () => closed.complete(socket.closeCode),
        onError: (Object _) {},
      );
      return (socket, closed.future.timeout(const Duration(seconds: 5)));
    }

    test('signing out ends every session of the operator and closes its log '
        'streams', () async {
      final console = await token();
      final elsewhere = await token();
      final (_, closed) = await logStream(elsewhere);

      final out = await h.api.call(Routes.adminSignOut, bearer: console);
      expect(out.status, 204);
      expect(await configStatus(console), 401);
      expect(
        await configStatus(elsewhere),
        401,
        reason: 'a copied token is cut off too',
      );
      expect(await closed, RealtimeCloseCode.unauthorized);

      final again = await token();
      expect(await configStatus(again), 200);
      expect(await auditActions(again), contains('admin.sign_out'));
    });

    test('a log stream closes when the password changes, and refuses big '
        'messages', () async {
      final console = await token();
      final (_, closed) = await logStream(await token());
      final changed = await h.api.call(
        Routes.adminPassword,
        bearer: console,
        body: const ChangeAdminPasswordRequest(
          currentPassword: adminPassword,
          newPassword: newPassword,
        ).toJson(),
      );
      expect(changed.status, 200);
      expect(await closed, RealtimeCloseCode.unauthorized);

      final fresh = AdminSession.fromJson(
        (await signIn(newPassword)).json,
      ).token;
      final (socket, ended) = await logStream(fresh);
      await admin().recheckLogStreams();
      socket.add('x' * (AdminModule.maxLogStreamMessageBytes + 1));
      await expectLater(ended, completes, reason: 'a big message ends it');
    });

    test('the local network is exempt from the global sign-in cap', () async {
      for (var batch = 0; batch < 4; batch++) {
        await Future.wait([
          for (var ip = 0; ip < 5; ip++)
            for (var i = 0; i < 5; i++)
              signIn('wrong password!!', from: '192.0.2.${batch * 5 + ip + 1}'),
        ]);
      }
      expect(
        (await signIn(adminPassword, from: '198.51.100.30')).errorCode,
        'password_locked',
        reason: 'the internet is capped',
      );
      expect(
        (await signIn(adminPassword, from: '192.168.1.20')).status,
        200,
        reason: 'the operator at home is not',
      );
      expect((await signIn(adminPassword)).status, 200, reason: 'loopback');
    });

    test('audit rows older than a year are deleted', () async {
      final bearer = await token();
      final audit = '${h.env.platform.schemas.of('admin')}.audit';
      await h.env.platform.db.execute(
        'INSERT INTO $audit (id, action, at) VALUES '
        "(gen_random_uuid(), 'old.action', now() - interval '366 days')",
      );
      final job = admin().periodic.singleWhere(
        (j) => j.name == 'admin.purge_audit',
      );
      expect(job.interval, const Duration(hours: 24));
      await job.run();
      final actions = await auditActions(bearer);
      expect(actions, isNot(contains('old.action')));
      expect(actions, contains('admin.sign_in'), reason: 'recent rows stay');
    });

    test(
      'recovery codes, invites and purges are audited with the action',
      () async {
        final bearer = await token();
        final alice = await h.registerGlobal('+8801711000001');
        final code = await h.api.call(
          Routes.adminRecoveryCode,
          params: {'account': alice.accountId},
          bearer: bearer,
        );
        expect(code.status, 201);
        final invite = CreatedInvite.fromJson(
          (await h.api.call(Routes.adminCreateInvite, bearer: bearer)).json,
        );
        expect(
          (await h.api.call(
            Routes.adminCancelInvite,
            params: {'invite_id': invite.inviteId},
            bearer: bearer,
          )).status,
          204,
        );
        expect(
          (await h.api.call(Routes.adminPurge, bearer: bearer)).status,
          200,
        );
        expect(
          await auditActions(bearer),
          containsAll([
            'recovery_code.issue',
            'invite.create',
            'invite.cancel',
            'purge',
            'admin.sign_in',
          ]),
        );
      },
    );

    test('reset-password sets the password, ends every session, clears the '
        'locks and is audited', () async {
      final before = await token();
      for (var i = 0; i < 5; i++) {
        await signIn('wrong password!!', from: '203.0.113.9');
      }
      expect(
        (await signIn(adminPassword, from: '203.0.113.9')).errorCode,
        'password_locked',
      );

      await expectLater(
        admin().resetPassword('too short'),
        throwsA(
          isA<ApiError>().having((e) => e.code, 'code', ErrorCode.invalidField),
        ),
      );
      await admin().resetPassword(newPassword);

      expect(await configStatus(before), 401);
      expect(
        (await signIn(adminPassword, from: '198.51.100.40')).errorCode,
        'invalid_credentials',
      );
      final after = await signIn(newPassword, from: '203.0.113.9');
      expect(after.status, 200, reason: 'the address lock is cleared');
      expect(
        await auditActions(AdminSession.fromJson(after.json).token),
        contains('admin.password_reset'),
      );
    });

    test(
      'reset-password creates the operator on a server without one',
      () async {
        await h.stop();
        h = await Harness.start();
        await admin().resetPassword(newPassword);
        expect((await signIn(newPassword)).status, 200);
      },
    );
  });
}
