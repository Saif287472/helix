import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import '../support/flows.dart';
import '../support/harness.dart';
import '../support/test_client.dart';
import '../support/test_database.dart';

const adminPassword = 'correct horse battery staple';

void main() {
  group('ops', skip: databaseTestSkipReason, () {
    late Harness h;

    setUp(
      () async => h = await Harness.start(
        extra: {
          'HELIX_SERVER_NAME': 'Helix Test',
          'HELIX_ANDROID_CERT_SHA256':
              '${List.filled(32, 'ab').join(':')}, not-a-fingerprint',
          'HELIX_ADMIN_PASSWORD': adminPassword,
        },
      ),
    );
    tearDown(() async => h.stop());

    Future<String> adminToken() async => AdminSession.fromJson(
      (await h.api.call(
        Routes.adminSignIn,
        body: const AdminPasswordRequest(password: adminPassword).toJson(),
      )).json,
    ).token;

    test('server info and legal documents describe this server', () async {
      final info = ServerInfo.fromJson(
        (await h.api.call(Routes.serverInfo)).json,
      );
      expect(info.name, 'Helix Test');
      expect(info.registration, RegistrationMode.phone);
      expect(info.termsVersion, HelixLegalDocuments.termsVersion);
      expect(info.federationDomain, isNull);
      expect(info.features, containsPair('crash_reporting_upload', false));

      final legal = LegalDocuments.fromJson(
        (await h.api.call(Routes.legal)).json,
      );
      expect(legal.termsVersion, info.termsVersion);
      expect(legal.terms, HelixLegalDocuments.termsOfService);
    });

    test('app links list only well-formed fingerprints', () async {
      final links = await h.api.call(Routes.assetLinks);
      expect(links.status, 200);
      final body = jsonDecode(links.body) as List;
      final target = (body.single as Map)['target'] as Map;
      expect(target['package_name'], 'com.helix.remote');
      expect(target['sha256_cert_fingerprints'], [
        List.filled(32, 'AB').join(':'),
      ]);

      final page = await h.api.call(Routes.openLink);
      expect(page.status, 200);
      expect(page.headers['content-type'], startsWith('text/html'));
      expect(page.headers['content-security-policy'], contains("'none'"));
      expect(page.body, contains('HLX-(INV|REC|GRP)'));
    });

    test('the landing page cannot be framed', () async {
      final page = await h.api.call(Routes.openLink);
      expect(
        page.headers['content-security-policy'],
        contains("frame-ancestors 'none'"),
      );
      expect(page.headers['x-frame-options'], 'DENY');
    });

    test(
      'the landing page answers /open and /open/ and nothing below',
      () async {
        Future<int> status(String path) async =>
            (await http.get(h.server.baseUri.replace(path: path))).statusCode;
        expect(await status('/open'), 200);
        expect(await status('/open/'), 200);
        expect(await status('/open/x'), 404);
        expect(await status('/open/x/'), 404);
        expect(await status('/openx'), 404);
        expect(await status('/open//'), 404);
      },
    );

    test('crash reports need the flag, and are logged redacted', () async {
      final alice = await h.registerGlobal(aliceNumber);
      final report = const CrashReport(
        name: 'StateError',
        fields: {'screen': 'chat', 'detail': 'call +8801711000001 failed'},
      ).toJson();
      final off = await h.api.call(
        Routes.crashReport,
        bearer: alice.bearer,
        body: report,
      );
      expect(off.errorCode, 'forbidden');

      final token = await adminToken();
      expect(
        (await h.api.call(
          Routes.adminSetFeatureFlag,
          params: {'name': 'crash_reporting_upload'},
          bearer: token,
          body: const SetFeatureFlagRequest(enabled: true).toJson(),
        )).status,
        204,
      );
      final on = await h.api.call(
        Routes.crashReport,
        bearer: alice.bearer,
        body: report,
      );
      expect(on.status, 204);
      final line = h.env.log.lines.lastWhere((l) => l.contains('client_crash'));
      expect(line, isNot(contains('8801711000001')));
      expect(line, contains('chat'));
    });

    test('metrics need an admin token', () async {
      expect((await h.api.call(Routes.metrics)).status, 401);
      final alice = await h.registerGlobal(aliceNumber);
      expect(
        (await h.api.call(Routes.metrics, bearer: alice.bearer)).status,
        401,
        reason: 'a device token is not an admin token',
      );
      final metrics = await h.api.call(
        Routes.metrics,
        bearer: await adminToken(),
      );
      expect(metrics.status, 200);
      expect(metrics.body, contains('helix_http_request_seconds'));
    });

    test(
      'maintenance mode stops device routes but not health or admin',
      () async {
        final alice = await h.registerGlobal(aliceNumber);
        final token = await adminToken();
        final patched = AdminConfig.fromJson(
          (await h.api.call(
            Routes.adminSetConfig,
            bearer: token,
            body: const AdminConfigPatch(maintenance: true).toJson(),
          )).json,
        );
        expect(patched.maintenance, isTrue);

        final blocked = await h.api.call(
          Routes.keyStatus,
          bearer: alice.bearer,
        );
        expect(blocked.status, 503);
        expect(blocked.errorCode, 'maintenance');
        expect((await h.api.call(Routes.live)).status, 200);
        expect(
          (await h.api.call(Routes.adminConfig, bearer: token)).status,
          200,
        );

        await h.api.call(
          Routes.adminSetConfig,
          bearer: token,
          body: const AdminConfigPatch(maintenance: false).toJson(),
        );
        expect(
          (await h.api.call(Routes.keyStatus, bearer: alice.bearer)).status,
          200,
        );
      },
    );
  });

  group('admin', skip: databaseTestSkipReason, () {
    late Harness h;

    setUp(() async => h = await Harness.start());
    tearDown(() async => h.stop());

    Future<String> setUpAdmin() async {
      final response = await h.api.call(
        Routes.adminSetup,
        body: const AdminPasswordRequest(password: adminPassword).toJson(),
      );
      expect(response.status, 201, reason: '$response');
      return AdminSession.fromJson(response.json).token;
    }

    test('first-run setup happens once', () async {
      final status = AdminSetupStatus.fromJson(
        (await h.api.call(Routes.adminSetupStatus)).json,
      );
      expect(status.configured, isFalse);

      final short = await h.api.call(
        Routes.adminSetup,
        body: const AdminPasswordRequest(password: 'short').toJson(),
      );
      expect(short.errorCode, 'invalid_field');

      final token = await setUpAdmin();
      expect(token, isNotEmpty);
      expect(
        AdminSetupStatus.fromJson(
          (await h.api.call(Routes.adminSetupStatus)).json,
        ).configured,
        isTrue,
      );
      final again = await h.api.call(
        Routes.adminSetup,
        body: const AdminPasswordRequest(
          password: 'another long password',
        ).toJson(),
      );
      expect(again.errorCode, 'already_exists');
    });

    test('sign-in locks after repeated failures', () async {
      await setUpAdmin();
      Future<TestResponse> attempt(String password) => h.api.call(
        Routes.adminSignIn,
        body: AdminPasswordRequest(password: password).toJson(),
      );
      for (var i = 0; i < 5; i++) {
        expect(
          (await attempt('wrong password!!')).errorCode,
          'invalid_credentials',
        );
      }
      final locked = await attempt(adminPassword);
      expect(locked.errorCode, 'password_locked');
      expect(locked.headers['retry-after'], isNotNull);
    });

    Future<TestResponse> attemptFrom(String ip, String password) => h.api.call(
      Routes.adminSignIn,
      headers: {'x-forwarded-for': ip},
      body: AdminPasswordRequest(password: password).toJson(),
    );

    test(
      'parallel guesses get no more than five; other addresses can still sign in',
      () async {
        await setUpAdmin();
        final results = await Future.wait([
          for (var i = 0; i < 9; i++)
            attemptFrom('203.0.113.7', 'wrong password!!'),
        ]);
        final codes = results.map((r) => r.errorCode).toList();
        expect(
          codes.where((c) => c == 'invalid_credentials'),
          hasLength(5),
          reason: 'attempts are counted before the password is checked',
        );
        expect(codes.where((c) => c == 'password_locked'), hasLength(4));
        expect(
          (await attemptFrom('203.0.113.7', adminPassword)).errorCode,
          'password_locked',
        );
        expect(
          (await attemptFrom('198.51.100.20', adminPassword)).status,
          200,
          reason: 'the lockout is per address: the operator elsewhere is fine',
        );
      },
    );

    test('a global cap locks sign-in after 100 failures anywhere', () async {
      await setUpAdmin();
      for (var batch = 0; batch < 4; batch++) {
        await Future.wait([
          for (var ip = 0; ip < 5; ip++)
            for (var i = 0; i < 5; i++)
              attemptFrom('192.0.2.${batch * 5 + ip + 1}', 'wrong password!!'),
        ]);
      }
      final capped = await attemptFrom('198.51.100.30', adminPassword);
      expect(capped.errorCode, 'password_locked');
      expect(
        int.parse(capped.headers['retry-after']!),
        lessThanOrEqualTo(15 * 60),
        reason: 'the global lock is short',
      );
    });

    test('changing the password ends other admin sessions', () async {
      final first = await setUpAdmin();
      final second = AdminSession.fromJson(
        (await h.api.call(
          Routes.adminSignIn,
          body: const AdminPasswordRequest(password: adminPassword).toJson(),
        )).json,
      ).token;
      final wrong = await h.api.call(
        Routes.adminPassword,
        bearer: second,
        body: const ChangeAdminPasswordRequest(
          currentPassword: 'not the password',
          newPassword: 'a brand new password',
        ).toJson(),
      );
      expect(wrong.errorCode, 'invalid_credentials');

      await Future<void>.delayed(const Duration(milliseconds: 5));
      final changed = await h.api.call(
        Routes.adminPassword,
        bearer: second,
        body: const ChangeAdminPasswordRequest(
          currentPassword: adminPassword,
          newPassword: 'a brand new password',
        ).toJson(),
      );
      expect(changed.status, 200);
      final fresh = AdminSession.fromJson(changed.json).token;
      expect((await h.api.call(Routes.adminConfig, bearer: first)).status, 401);
      expect((await h.api.call(Routes.adminConfig, bearer: fresh)).status, 200);

      final device = await h.registerGlobal(aliceNumber);
      expect(
        (await h.api.call(Routes.adminAccounts, bearer: device.bearer)).status,
        401,
        reason: 'device tokens never open admin routes',
      );
      expect(
        (await h.api.call(Routes.keyStatus, bearer: fresh)).status,
        401,
        reason: 'admin tokens never open device routes',
      );
    });

    test(
      'accounts: list, filter, detail, suspend, recovery, revoke, ban',
      () async {
        final token = await setUpAdmin();
        final alice = await h.registerGlobal(aliceNumber);
        final bob = await h.registerGlobal(bobNumber);

        final all = Page.fromJson(
          (await h.api.call(Routes.adminAccounts, bearer: token)).json,
          AdminAccount.fromJson,
        );
        expect(all.items.map((a) => a.accountId), [
          bob.account.id,
          alice.account.id,
        ]);
        expect(all.items.first.phoneLast4, '0002');
        expect(
          jsonEncode(all.toJson((a) => a.toJson())),
          isNot(contains('880171')),
        );

        final paged = Page.fromJson(
          (await h.api.call(
            Routes.adminAccounts,
            bearer: token,
            query: {'limit': '1'},
          )).json,
          AdminAccount.fromJson,
        );
        expect(paged.items, hasLength(1));
        final rest = Page.fromJson(
          (await h.api.call(
            Routes.adminAccounts,
            bearer: token,
            query: {'limit': '1', 'cursor': paged.nextCursor!},
          )).json,
          AdminAccount.fromJson,
        );
        expect(rest.items.single.accountId, alice.account.id);
        expect(rest.nextCursor, isNull);

        final byDigits = Page.fromJson(
          (await h.api.call(
            Routes.adminAccounts,
            bearer: token,
            query: {'q': '0001'},
          )).json,
          AdminAccount.fromJson,
        );
        expect(byDigits.items.single.accountId, alice.account.id);

        // Bob reports Alice; the detail view counts it.
        await h.api.call(
          Routes.report,
          bearer: bob.bearer,
          body: ReportRequest(
            account: alice.account.id,
            category: ReportCategory.spam,
          ).toJson(),
        );
        final detail = AdminAccountDetail.fromJson(
          (await h.api.call(
            Routes.adminAccount,
            params: {'account': alice.account.id},
            bearer: token,
          )).json,
        );
        expect(detail.devices.single.deviceId, alice.id);
        expect(detail.devices.single.active, isTrue);
        expect(detail.openReports, 1);
        expect(detail.hasPassword, isFalse);

        // Suspension limits the account to allow-listed routes.
        expect(
          (await h.api.call(
            Routes.adminSuspend,
            params: {'account': alice.account.id},
            bearer: token,
            body: const AdminActionRequest(reason: 'spam wave').toJson(),
          )).status,
          204,
        );
        expect(
          (await h.api.call(Routes.keyStatus, bearer: alice.bearer)).errorCode,
          'account_suspended',
        );
        expect(
          (await h.api.call(
            Routes.adminUnsuspend,
            params: {'account': alice.account.id},
            bearer: token,
          )).status,
          204,
        );
        expect(
          (await h.api.call(Routes.keyStatus, bearer: alice.bearer)).status,
          200,
        );

        // A recovery code is shown once and works for recovery lookup.
        final code = AdminRecoveryCode.fromJson(
          (await h.api.call(
            Routes.adminRecoveryCode,
            params: {'account': alice.account.id},
            bearer: token,
          )).json,
        );
        final lookup = RecoveryLookupResponse.fromJson(
          (await h.api.call(
            Routes.recoveryLookup,
            body: RecoveryLookupRequest(
              recoveryCode: code.recoveryCode,
            ).toJson(),
          )).json,
        );
        expect(lookup.valid, isTrue);

        // Revoking a device ends its session.
        expect(
          (await h.api.call(
            Routes.adminRevokeDevice,
            params: {'account': alice.account.id, 'device_id': alice.id},
            bearer: token,
          )).status,
          204,
        );
        expect(
          (await h.api.call(Routes.keyStatus, bearer: alice.bearer)).status,
          401,
        );
        expect(
          (await h.api.call(
            Routes.adminRevokeDevice,
            params: {'account': alice.account.id, 'device_id': alice.id},
            bearer: token,
          )).errorCode,
          'not_found',
        );

        // A ban deletes the account and keeps the number out.
        expect(
          (await h.api.call(
            Routes.adminBan,
            params: {'account': bob.account.id},
            bearer: token,
          )).status,
          204,
        );
        expect(
          (await h.api.call(
            Routes.adminAccount,
            params: {'account': bob.account.id},
            bearer: token,
          )).errorCode,
          'not_found',
        );
        final challenge = await h.api.call(
          Routes.phoneChallenge,
          body: const PhoneChallengeRequest(
            phoneNumber: bobNumber,
            purpose: PhonePurpose.register,
          ).toJson(),
        );
        expect(challenge.errorCode, 'phone_banned');

        // Delete, and 404 for unknown accounts.
        expect(
          (await h.api.call(
            Routes.adminDeleteAccount,
            params: {'account': alice.account.id},
            bearer: token,
          )).status,
          204,
        );
        expect(
          (await h.api.call(
            Routes.adminSuspend,
            params: {'account': alice.account.id},
            bearer: token,
          )).errorCode,
          'not_found',
        );

        final audit = Page.fromJson(
          (await h.api.call(Routes.adminAudit, bearer: token)).json,
          AuditEntry.fromJson,
        );
        expect(audit.items.map((e) => e.action).toList(), [
          'account.delete',
          'account.ban',
          'device.revoke',
          'recovery_code.issue',
          'account.unsuspend',
          'account.suspend',
          'admin.setup',
        ]);
        final suspend = audit.items.firstWhere(
          (e) => e.action == 'account.suspend',
        );
        expect(suspend.target, alice.account.id);
        expect(suspend.details, {'reason': 'spam wave'});
        expect(
          jsonEncode(audit.toJson((e) => e.toJson())),
          isNot(contains(code.recoveryCode)),
        );
      },
    );

    test('invites: create, list, cancel', () async {
      final token = await setUpAdmin();
      final created = CreatedInvite.fromJson(
        (await h.api.call(Routes.adminCreateInvite, bearer: token)).json,
      );
      Future<AdminInvite> listed() async => Page.fromJson(
        (await h.api.call(Routes.adminInvites, bearer: token)).json,
        AdminInvite.fromJson,
      ).items.single;
      final open = await listed();
      expect(open.inviteId, created.inviteId);
      expect(open.status, InviteStatus.open);
      expect(open.issuer, 'admin');

      final check = InviteLookupResponse.fromJson(
        (await h.api.call(
          Routes.inviteLookup,
          body: InviteLookupRequest(inviteCode: created.inviteCode).toJson(),
        )).json,
      );
      expect(check.valid, isTrue);

      expect(
        (await h.api.call(
          Routes.adminCancelInvite,
          params: {'invite_id': created.inviteId},
          bearer: token,
        )).status,
        204,
      );
      expect((await listed()).status, InviteStatus.cancelled);
      expect(
        (await h.api.call(
          Routes.adminCancelInvite,
          params: {'invite_id': created.inviteId},
          bearer: token,
        )).errorCode,
        'not_found',
      );
    });

    test('reports: list by status and resolve', () async {
      final token = await setUpAdmin();
      final alice = await h.registerGlobal(aliceNumber);
      final bob = await h.registerGlobal(bobNumber);
      await h.api.call(
        Routes.report,
        bearer: alice.bearer,
        body: ReportRequest(
          account: bob.account.id,
          category: ReportCategory.abuse,
          note: 'rude',
        ).toJson(),
      );
      Future<List<AdminReport>> listed(String status) async => Page.fromJson(
        (await h.api.call(
          Routes.adminReports,
          bearer: token,
          query: {'status': status},
        )).json,
        AdminReport.fromJson,
      ).items;
      final report = (await listed('open')).single;
      expect(report.reporter, alice.account.id);
      expect(report.subject, bob.account.id);
      expect(report.note, 'rude');

      final bad = await h.api.call(
        Routes.adminResolveReport,
        params: {'report_id': report.reportId},
        bearer: token,
        body: const ResolveReportRequest(status: ReportStatus.open).toJson(),
      );
      expect(bad.errorCode, 'invalid_field');
      expect(
        (await h.api.call(
          Routes.adminResolveReport,
          params: {'report_id': report.reportId},
          bearer: token,
          body: const ResolveReportRequest(
            status: ReportStatus.resolved,
          ).toJson(),
        )).status,
        204,
      );
      expect(await listed('open'), isEmpty);
      expect((await listed('resolved')).single.reportId, report.reportId);
      expect(
        (await h.api.call(
          Routes.adminReports,
          bearer: token,
          query: {'status': 'bogus'},
        )).errorCode,
        'invalid_field',
      );
    });

    test('config, flags, logs, log stream and purge', () async {
      final token = await setUpAdmin();
      final config = AdminConfig.fromJson(
        (await h.api.call(Routes.adminConfig, bearer: token)).json,
      );
      expect(config.maintenance, isFalse);
      expect(config.registration, RegistrationMode.phone);
      expect(
        (await h.api.call(
          Routes.adminSetConfig,
          bearer: token,
          body: const {},
        )).errorCode,
        'bad_request',
      );
      final renamed = AdminConfig.fromJson(
        (await h.api.call(
          Routes.adminSetConfig,
          bearer: token,
          body: const AdminConfigPatch(
            serverName: 'Renamed',
            federationEnabled: true,
          ).toJson(),
        )).json,
      );
      expect(renamed.serverName, 'Renamed');
      expect(renamed.federationDomain, isNotNull);
      final info = ServerInfo.fromJson(
        (await h.api.call(Routes.serverInfo)).json,
      );
      expect(info.name, 'Renamed');
      expect(info.federationDomain, renamed.federationDomain);

      expect(
        (await h.api.call(
          Routes.adminSetFeatureFlag,
          params: {'name': 'not_a_flag'},
          bearer: token,
          body: const SetFeatureFlagRequest(enabled: true).toJson(),
        )).errorCode,
        'not_found',
      );
      await h.api.call(
        Routes.adminSetFeatureFlag,
        params: {'name': 'group_calls'},
        bearer: token,
        body: const SetFeatureFlagRequest(enabled: true).toJson(),
      );
      final flags = FeatureFlags.fromJson(
        (await h.api.call(Routes.adminFeatureFlags, bearer: token)).json,
      );
      expect(flags.flags['group_calls'], isTrue);
      expect(
        flags.flags.keys,
        containsAll(['crash_reporting_upload', 'minimal_analytics']),
      );

      final logs = AdminLogLines.fromJson(
        (await h.api.call(
          Routes.adminLogs,
          bearer: token,
          query: {'limit': '5'},
        )).json,
      );
      expect(logs.lines, hasLength(5));

      final socket = await WebSocket.connect(
        h.server.baseUri
            .replace(scheme: 'ws', path: Routes.adminLogStream.path)
            .toString(),
        headers: {'authorization': 'Bearer $token'},
      );
      final first = socket.first;
      await h.api.call(Routes.live);
      final line = jsonDecode(
        (await first.timeout(const Duration(seconds: 5))) as String,
      );
      expect((line as Map)['level'], isNotNull);
      await socket.close();

      final purged = PurgeResult.fromJson(
        (await h.api.call(Routes.adminPurge, bearer: token)).json,
      );
      expect(
        purged.removed.keys,
        containsAll(['dead_jobs', 'refresh_tokens', 'invites']),
      );
    });
  });

  group('compliance', skip: databaseTestSkipReason, () {
    late Harness h;

    setUp(() async => h = await Harness.start());
    tearDown(() async => h.stop());

    test('export holds every module section and no secrets', () async {
      final alice = await h.registerGlobal(aliceNumber);
      final bob = await h.registerGlobal(bobNumber);
      await h.api.call(
        Routes.block,
        params: {'account': bob.account.id},
        bearer: alice.bearer,
      );
      final response = await h.api.call(
        Routes.exportData,
        bearer: alice.bearer,
      );
      expect(response.status, 200);
      expect(response.headers['content-disposition'], contains('attachment'));
      final export = AccountExport.fromJson(response.json);
      expect(export.accountId, alice.account.id);
      expect(
        export.sections.keys,
        containsAll([
          'identity',
          'keys',
          'messaging',
          'people',
          'media',
          'backup',
          'groups',
        ]),
      );
      final identity = export.sections['identity']! as Map;
      expect((identity['account'] as Map)['phone_last4'], '0001');
      expect(
        ((identity['devices'] as List).single as Map)['device_id'],
        alice.id,
      );
      final people = export.sections['people']! as Map;
      expect(
        ((people['blocked'] as List).single as Map)['account_id'],
        bob.account.id,
      );
      expect(response.body, isNot(contains('8801711000001')));
      expect(response.body, isNot(contains(alice.bearer)));
    });

    Future<TestResponse> delete(TestDevice who, DeleteAccountRequest body) => h
        .api
        .call(Routes.deleteAccount, bearer: who.bearer, body: body.toJson());

    Future<bool> alive(TestDevice who) async =>
        (await h.api.call(Routes.account, bearer: who.bearer)).status == 200;

    test('deleting the account needs the confirmation and purges it', () async {
      final alice = await h.registerGlobal(aliceNumber);
      expect(
        (await delete(
          alice,
          const DeleteAccountRequest(confirmation: 'delete'),
        )).errorCode,
        'invalid_field',
      );

      final proof = (await h.verifyPhone(
        aliceNumber,
        purpose: PhonePurpose.signIn,
      )).verificationToken;
      expect(
        (await delete(
          alice,
          DeleteAccountRequest(verificationToken: proof),
        )).status,
        204,
      );
      expect(
        (await h.api.call(Routes.account, bearer: alice.bearer)).status,
        401,
      );
      // The number is free again (deletion is not a ban).
      final again = await h.registerGlobal(aliceNumber);
      expect(again.account.id, isNot(alice.account.id));
    });

    test('a session token alone deletes nothing: a number needs a fresh '
        'verification of that number', () async {
      final alice = await h.registerGlobal(aliceNumber);
      final bob = await h.registerGlobal(bobNumber);

      final bare = await delete(alice, const DeleteAccountRequest());
      expect(bare.status, 401);
      expect(bare.errorCode, 'invalid_credentials');
      expect(bare.body, contains('verification_token'));
      expect(await alive(alice), isTrue);

      final bobs = (await h.verifyPhone(
        bobNumber,
        purpose: PhonePurpose.signIn,
      )).verificationToken;
      expect(
        (await delete(
          alice,
          DeleteAccountRequest(verificationToken: bobs),
        )).errorCode,
        'invalid_credentials',
        reason: 'a verification of another number is no proof',
      );
      expect(
        (await delete(
          alice,
          const DeleteAccountRequest(verificationToken: 'vt_not-a-token'),
        )).status,
        400,
      );
      expect(await alive(alice), isTrue);
      expect(await alive(bob), isTrue);

      // A verification is single use.
      final mine = (await h.verifyPhone(
        aliceNumber,
        purpose: PhonePurpose.signIn,
      )).verificationToken;
      final other = await h.registerGlobal('+8801711000004');
      expect(
        (await delete(
          other,
          DeleteAccountRequest(verificationToken: mine),
        )).errorCode,
        'invalid_credentials',
      );
      expect(
        (await delete(
          alice,
          DeleteAccountRequest(verificationToken: mine),
        )).status,
        204,
      );
    });

    test('an account with a password needs its auth key', () async {
      final alice = await h.registerGlobal(aliceNumber);
      final pw = PasswordSetup(
        kdf: const KdfParams(),
        salt: bytes(16),
        authKey: bytes(32, 9),
        wrappedIdentityKey: WrappedKey(nonce: bytes(12), ciphertext: bytes(48)),
      );
      await h.api.call(
        Routes.setPassword,
        bearer: alice.bearer,
        body: SetPasswordRequest(password: pw).toJson(),
      );
      expect(
        (await delete(alice, const DeleteAccountRequest())).errorCode,
        'invalid_credentials',
      );
      expect(
        (await delete(
          alice,
          DeleteAccountRequest(currentAuthKey: bytes(32, 3)),
        )).errorCode,
        'invalid_credentials',
      );
      expect(await alive(alice), isTrue);
      expect(
        (await delete(
          alice,
          DeleteAccountRequest(currentAuthKey: pw.authKey),
        )).status,
        204,
      );
    });
  });

  group('compliance on a personal server', skip: databaseTestSkipReason, () {
    late Harness h;

    setUp(() async => h = await Harness.start(global: false));
    tearDown(() async => h.stop());

    Future<TestDevice> register() async {
      final invite = await h.identity.signUp.issueInvite(h.env.platform.db);
      final acct = await TestAccount.create();
      final device = await acct.newDevice();
      final response = await h.api.call(
        Routes.register,
        body: RegisterRequest(
          accountId: acct.id,
          identityKey: acct.publicKey,
          device: await device.registration(),
          prekeys: await device.prekeys(),
          inviteCode: invite.code,
        ).toJson(),
      );
      device.session = RegisterResponse.fromJson(response.json).session;
      return device;
    }

    Future<DeviceKeyProof> proofBy(
      TestDevice signer, {
      String? asDevice,
      List<int> Function(List<int>) body = deleteAccountSignatureBody,
    }) async {
      final c = DeviceChallengeResponse.fromJson(
        (await h.api.call(
          Routes.deviceChallenge,
          body: DeviceChallengeRequest(
            accountId: signer.accountId,
            deviceId: asDevice ?? signer.id,
          ).toJson(),
        )).json,
      );
      return DeviceKeyProof(
        challengeId: c.challengeId,
        challenge: c.challenge,
        signature: await sign(signer.dsk, body(c.challenge)),
      );
    }

    Future<TestResponse> delete(TestDevice who, DeviceKeyProof? proof) =>
        h.api.call(
          Routes.deleteAccount,
          bearer: who.bearer,
          body: DeleteAccountRequest(deviceProof: proof).toJson(),
        );

    test('an account with no password and no number proves it with its '
        'device key', () async {
      final alice = await register();
      final bare = await delete(alice, null);
      expect(bare.errorCode, 'invalid_credentials');
      expect(bare.body, contains('device_proof'));

      // A sign-in signature (another label) confirms nothing.
      expect(
        (await delete(
          alice,
          await proofBy(alice, body: signInSignatureBody),
        )).errorCode,
        'invalid_credentials',
      );
      // Another device's key does not either.
      final impostor = await (await TestAccount.create()).newDevice();
      expect(
        (await delete(
          alice,
          await proofBy(impostor, asDevice: alice.id),
        )).errorCode,
        'invalid_credentials',
      );
      expect(
        (await h.api.call(Routes.account, bearer: alice.bearer)).status,
        200,
      );

      final proof = await proofBy(alice);
      expect((await delete(alice, proof)).status, 204);
      // A challenge is single use.
      final again = await register();
      expect((await delete(again, proof)).errorCode, 'invalid_credentials');
    });
  });
}
