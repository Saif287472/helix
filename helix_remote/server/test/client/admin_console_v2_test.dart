import 'dart:async';
import 'dart:convert';

import 'package:helix_remote_api/v2.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:test/test.dart';

import '../support/flows.dart';
import '../support/harness.dart';
import '../support/test_client.dart';
import '../support/test_database.dart';

const password = 'correct horse battery staple';
const newPassword = 'a second long passphrase';

/// The operator console's calls (Phase AD: `helix_admin`) against a real
/// in-process v2 server. The console package may not depend on the server, so
/// its screens are tested against a fake in `admin/test/`; this file drives
/// the same `HelixAdminApi` calls the screens make, so the two agree on the
/// real wire behaviour (setup, lockout, session rules, paging, one-time
/// codes, redaction).
void main() {
  group('operator console API', skip: databaseTestSkipReason, () {
    late Harness h;
    final opened = <HelixAdminApi>[];
    final devices = <HelixApi>[];

    /// [seed] true gives the server `HELIX_ADMIN_PASSWORD`; false leaves it
    /// waiting for first-run setup.
    Future<void> start({bool seed = true}) async => h = await Harness.start(
      extra: {if (seed) 'HELIX_ADMIN_PASSWORD': password},
    );

    tearDown(() async {
      for (final api in opened) {
        await api.close();
      }
      opened.clear();
      for (final api in devices) {
        await api.close();
      }
      devices.clear();
      await h.stop();
    });

    HelixAdminApi console({AdminSession? session}) {
      final api = HelixAdminApi(
        baseUrl: h.server.baseUri,
        session: session,
        clientName: 'admin/test',
        retry: RetryPolicy.none,
      );
      opened.add(api);
      return api;
    }

    Future<HelixAdminApi> signedIn() async {
      final api = console();
      await api.admin.signIn(password);
      return api;
    }

    Future<TestDevice> person(String number) => h.registerGlobal(number);

    HelixApi deviceApi(TestDevice device) {
      final api = HelixApi(
        baseUrl: h.server.baseUri,
        sessions: MemorySessionStore(device.session),
        retry: RetryPolicy.none,
      );
      devices.add(api);
      return api;
    }

    test('first-run setup, then sign-in on the admin audience', () async {
      await start(seed: false);
      final api = console();

      expect((await api.admin.setupStatus()).configured, isFalse);
      await expectLater(
        api.admin.setup('short'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            ErrorCode.invalidField,
          ),
        ),
      );
      final session = await api.admin.setup(password);
      expect(session.token, isNotEmpty);
      // The token lasts 12 hours.
      expect(
        session.expiresAt.difference(DateTime.now()),
        allOf(
          greaterThan(const Duration(hours: 11, minutes: 55)),
          lessThan(const Duration(hours: 12, minutes: 5)),
        ),
      );
      expect((await api.admin.config()).serverName, isNotEmpty);

      // Setup is closed once it has been done.
      expect((await console().admin.setupStatus()).configured, isTrue);
      await expectLater(
        console().admin.setup(password),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            ErrorCode.alreadyExists,
          ),
        ),
      );
    });

    test('a wrong password is an answer, not a signed-out session', () async {
      await start();
      final api = console();

      await expectLater(
        api.admin.signIn('not the admin password'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', ErrorCode.invalidCredentials)
              .having((e) => e.status, 'status', 401),
        ),
      );
      await api.admin.signIn(password);
      expect(await api.admin.accounts(), isA<Page<AdminAccount>>());
    });

    test('five wrong passwords lock sign-in, with Retry-After', () async {
      await start();
      final api = console();
      for (var i = 0; i < 5; i++) {
        await expectLater(
          api.admin.signIn('wrong password number $i'),
          throwsA(
            isA<ApiException>().having(
              (e) => e.code,
              'code',
              ErrorCode.invalidCredentials,
            ),
          ),
        );
      }

      // Even the right password is refused while the address is locked.
      await expectLater(
        api.admin.signIn(password),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', ErrorCode.passwordLocked)
              .having(
                (e) => e.retryAfter,
                'retryAfter',
                greaterThanOrEqualTo(const Duration(minutes: 14)),
              ),
        ),
      );
    });

    test('changing the password: a wrong current one keeps the session; '
        'the right one ends the other sessions', () async {
      await start();
      final main = await signedIn();
      final other = await signedIn();

      await expectLater(
        main.admin.changePassword(current: 'not it', next: newPassword),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            ErrorCode.invalidCredentials,
          ),
        ),
      );
      // Still signed in on both: the 401 was a wrong password, not a
      // rejected token.
      expect(main.auth.session, isNotNull);
      await main.admin.config();
      await other.admin.config();

      final fresh = await main.admin.changePassword(
        current: password,
        next: newPassword,
      );
      expect(fresh.token, isNot(other.auth.session!.token));
      await main.admin.config();
      await expectLater(
        other.admin.config(),
        throwsA(isA<SignedOutException>()),
      );

      await expectLater(
        console().admin.signIn(password),
        throwsA(isA<ApiException>()),
      );
      await console().admin.signIn(newPassword);
    });

    test('a device token is not an admin token, and a made-up one signs the '
        'console out', () async {
      await start();
      final alice = await person(aliceNumber);
      final impostor = console(
        session: AdminSession(
          token: alice.bearer,
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        ),
      );

      await expectLater(
        impostor.admin.accounts(),
        throwsA(isA<SignedOutException>()),
      );
      expect(impostor.auth.session, isNull);
    });

    test('accounts: paged, filtered by status and last four digits, '
        'never a full number', () async {
      await start();
      final alice = await person(aliceNumber);
      final bob = await person(bobNumber);
      final api = await signedIn();

      final first = await api.admin.accounts(page: const PageRequest(limit: 1));
      expect(first.items, hasLength(1));
      expect(first.nextCursor, isNotNull);
      final second = await api.admin.accounts(
        page: PageRequest(cursor: first.nextCursor, limit: 1),
      );
      expect(second.items, hasLength(1));
      expect(
        {first.items.single.accountId, second.items.single.accountId},
        {alice.accountId, bob.accountId},
      );

      final byDigits = await api.admin.accounts(query: '0002');
      expect(byDigits.items.map((a) => a.accountId), [bob.accountId]);
      expect(byDigits.items.single.phoneLast4, '0002');

      final everything = await api.admin.accounts();
      final wire = jsonEncode([for (final a in everything.items) a.toJson()]);
      expect(wire, isNot(contains(aliceNumber)));
      expect(wire, isNot(contains(aliceNumber.substring(1))));

      await api.admin.suspend(alice.accountId, reason: 'testing');
      final suspended = await api.admin.accounts(
        status: AccountStatus.suspended,
      );
      expect(suspended.items.map((a) => a.accountId), [alice.accountId]);
      expect(
        (await api.admin.accounts(
          status: AccountStatus.active,
        )).items.map((a) => a.accountId),
        [bob.accountId],
      );
    });

    test('account actions: suspend, resume, device revoke, recovery code, '
        'ban, delete', () async {
      await start();
      final alice = await person(aliceNumber);
      final bob = await person(bobNumber);
      final carol = await person('+8801711000003');
      final api = await signedIn();

      await api.admin.suspend(alice.accountId);
      expect(
        (await api.admin.account(alice.accountId)).account.status,
        AccountStatus.suspended,
      );
      await api.admin.unsuspend(alice.accountId);
      expect(
        (await api.admin.account(alice.accountId)).account.status,
        AccountStatus.active,
      );

      // The recovery code is shown once: the listing and the audit log never
      // carry it.
      final recovery = await api.admin.createRecoveryCode(alice.accountId);
      expect(recovery.recoveryCode, isNotEmpty);
      expect(
        recovery.expiresAt.difference(DateTime.now()),
        allOf(
          greaterThan(const Duration(hours: 47)),
          lessThan(const Duration(hours: 48, minutes: 5)),
        ),
      );

      final detail = await api.admin.account(alice.accountId);
      expect(detail.devices.single.active, isTrue);
      await api.admin.revokeDevice(alice.accountId, alice.id);
      expect(
        (await api.admin.account(alice.accountId)).devices.single.active,
        isFalse,
      );

      await api.admin.ban(bob.accountId, reason: 'abuse');
      await expectLater(
        api.admin.account(bob.accountId),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', ErrorCode.notFound),
        ),
      );
      await api.admin.deleteAccount(carol.accountId);
      expect((await api.admin.accounts()).items.map((a) => a.accountId), [
        alice.accountId,
      ]);

      final audit = await api.admin.audit();
      expect(
        audit.items.map((e) => e.action),
        containsAll([
          'account.suspend',
          'account.unsuspend',
          'recovery_code.issue',
          'device.revoke',
          'account.ban',
          'account.delete',
        ]),
      );
      // Newest first.
      expect(audit.items.first.at.isBefore(audit.items.last.at), isFalse);
      final wire = jsonEncode([for (final e in audit.items) e.toJson()]);
      expect(wire, isNot(contains(recovery.recoveryCode)));
      expect(wire, isNot(contains(password)));
    });

    test('invites: the code is shown once and never listed', () async {
      await start();
      final api = await signedIn();

      final created = await api.admin.createInvite();
      expect(created.inviteCode, isNotEmpty);
      final list = await api.admin.invites();
      expect(list.items.map((i) => i.inviteId), [created.inviteId]);
      expect(list.items.single.status, InviteStatus.open);
      expect(
        jsonEncode(list.items.single.toJson()),
        isNot(contains(created.inviteCode)),
      );

      await api.admin.cancelInvite(created.inviteId);
      expect(
        (await api.admin.invites()).items.single.status,
        InviteStatus.cancelled,
      );
      // Only an open invite can be cancelled.
      await expectLater(
        api.admin.cancelInvite(created.inviteId),
        throwsA(isA<ApiException>()),
      );

      final audit = jsonEncode([
        for (final e in (await api.admin.audit()).items) e.toJson(),
      ]);
      expect(audit, isNot(contains(created.inviteCode)));
    });

    test('reports: filed by people, listed, resolved or dismissed', () async {
      await start();
      final alice = await person(aliceNumber);
      final bob = await person(bobNumber);
      final reporter = deviceApi(bob);
      await reporter.people.report(
        ReportRequest(
          account: alice.accountId,
          category: ReportCategory.spam,
          note: 'sends me spam',
        ),
      );
      await reporter.people.report(
        ReportRequest(account: alice.accountId, category: ReportCategory.abuse),
      );
      final api = await signedIn();

      final open = await api.admin.reports(status: ReportStatus.open);
      expect(open.items, hasLength(2));
      expect(open.items.every((r) => r.subject == alice.accountId), isTrue);
      expect((await api.admin.account(alice.accountId)).openReports, 2);

      final spam = open.items.firstWhere(
        (r) => r.category == ReportCategory.spam,
      );
      final abuse = open.items.firstWhere(
        (r) => r.category == ReportCategory.abuse,
      );
      await api.admin.resolveReport(spam.reportId, ReportStatus.resolved);
      await api.admin.resolveReport(abuse.reportId, ReportStatus.dismissed);

      expect(
        (await api.admin.reports(status: ReportStatus.open)).items,
        isEmpty,
      );
      expect(
        (await api.admin.reports(
          status: ReportStatus.resolved,
        )).items.map((r) => r.reportId),
        [spam.reportId],
      );
      expect((await api.admin.reports()).items, hasLength(2));
      // A report can be decided once.
      await expectLater(
        api.admin.resolveReport(spam.reportId, ReportStatus.dismissed),
        throwsA(isA<ApiException>()),
      );
    });

    test('config, flags and maintenance mode', () async {
      await start();
      final alice = await person(aliceNumber);
      final api = await signedIn();

      var config = await api.admin.updateConfig(
        const AdminConfigPatch(serverName: 'Console Test'),
      );
      expect(config.serverName, 'Console Test');
      expect(config.maintenance, isFalse);
      expect((await api.ops.serverInfo()).name, 'Console Test');

      final flags = (await api.admin.featureFlags()).flags;
      expect(flags.keys, isNotEmpty);
      final name = flags.keys.first;
      await api.admin.setFeatureFlag(name, enabled: !flags[name]!);
      expect((await api.admin.featureFlags()).flags[name], !flags[name]!);
      await expectLater(
        api.admin.setFeatureFlag('not_a_flag', enabled: true),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', ErrorCode.notFound),
        ),
      );

      // Maintenance: people get 503, the console keeps working.
      config = await api.admin.updateConfig(
        const AdminConfigPatch(maintenance: true),
      );
      expect(config.maintenance, isTrue);
      await expectLater(
        deviceApi(alice).identity.account(),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            ErrorCode.maintenance,
          ),
        ),
      );
      expect((await api.admin.config()).maintenance, isTrue);
      await api.admin.updateConfig(const AdminConfigPatch(maintenance: false));
      expect(
        (await deviceApi(alice).identity.account()).accountId,
        alice.accountId,
      );

      config = await api.admin.updateConfig(
        const AdminConfigPatch(federationEnabled: true),
      );
      expect(config.federationEnabled, isTrue);
    });

    test('logs: recent lines, a live stream, redacted', () async {
      await start();
      final api = await signedIn();
      final token = api.auth.session!.token;

      final lines = <String>[];
      final live = Completer<void>();
      final subscription = api.admin.logStream().listen((line) {
        lines.add(line);
        if (line.contains('"event":"http"') && !live.isCompleted) {
          live.complete();
        }
      });
      addTearDown(subscription.cancel);
      // Give the socket a moment to open, then make a request to log.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await api.admin.config();
      await live.future.timeout(const Duration(seconds: 10));

      final recent = await api.admin.logs(limit: 50);
      expect(recent.lines, isNotEmpty);
      for (final line in [...lines, ...recent.lines]) {
        expect(line, isNot(contains(token)));
        expect(line, isNot(contains(password)));
        expect(line.toLowerCase(), isNot(contains('bearer ')));
      }
    });

    test('a refused log stream upgrade surfaces the HTTP error', () async {
      await start();
      final api = console(
        session: AdminSession(
          token: 'not-a-token',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        ),
      );

      await expectLater(
        api.admin.logStream().first,
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 401)),
      );
    });

    test('purge and metrics', () async {
      await start();
      final api = await signedIn();

      final result = await api.admin.purge();
      expect(result.removed.keys, contains('dead_jobs'));
      expect(result.removed.values.every((n) => n >= 0), isTrue);

      final metrics = await api.admin.metrics();
      expect(metrics, contains('helix_ws_open'));
      expect(metrics, contains('helix_http_request_seconds_count'));
      // Dead letters and backlog are cluster-wide gauges.
      expect(metrics, contains('helix_jobs_dead'));
      expect(metrics, contains('helix_mailbox_backlog'));
    });
  });
}
