import 'dart:convert';

import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/src/kernel/entitlements.dart';
import 'package:helix_remote_server/src/modules/billing/module.dart';
import 'package:helix_remote_server/src/platform/clock.dart';
import 'package:test/test.dart';

import '../support/flows.dart';
import '../support/harness.dart';
import '../support/test_client.dart';
import '../support/test_database.dart';

const adminPassword = 'correct horse battery staple';

void main() {
  group('billing', skip: databaseTestSkipReason, () {
    late Harness h;
    late ManualClock clock;
    late TestDevice alice;
    late String admin;

    // Free file size 2 KiB, so Premium's 8 KiB is easy to cross in a test.
    setUp(() async {
      clock = ManualClock(DateTime.utc(2026, 11, 1));
      h = await Harness.start(
        clock: clock,
        extra: {
          'HELIX_ADMIN_PASSWORD': adminPassword,
          'HELIX_MAX_ATTACHMENT_BYTES': '2048',
        },
      );
      alice = await h.registerGlobal(aliceNumber);
      admin = AdminSession.fromJson(
        (await h.api.call(
          Routes.adminSignIn,
          body: const AdminPasswordRequest(password: adminPassword).toJson(),
        )).json,
      ).token;
    });
    tearDown(() async => h.stop());

    BillingModule billing() =>
        h.server.modules.whereType<BillingModule>().single;

    Future<void> plansOn([bool on = true]) async {
      final r = await h.api.call(
        Routes.adminSetFeatureFlag,
        params: {'name': 'billing_enabled'},
        bearer: admin,
        body: SetFeatureFlagRequest(enabled: on).toJson(),
      );
      expect(r.status, 204, reason: r.body);
    }

    Future<void> setNumbers({
      String? bkash = '01700000000',
      String? nagad,
    }) async {
      final r = await h.api.call(
        Routes.adminSetBillingSettings,
        bearer: admin,
        body: BillingSettings(
          priceOneMonth: 20,
          priceSixMonths: 100,
          priceTwelveMonths: 180,
          bkashNumber: bkash,
          nagadNumber: nagad,
        ).toJson(),
      );
      expect(r.status, 200, reason: r.body);
    }

    Future<BillingPlan> plan(TestDevice d) async {
      final r = await h.api.call(Routes.billingPlan, bearer: d.bearer);
      expect(r.status, 200, reason: r.body);
      return BillingPlan.fromJson(r.json);
    }

    Future<TestResponse> submit(
      TestDevice d, {
      int months = 1,
      PaymentMethod method = PaymentMethod.bkash,
      String trx = '8N7A6D5EE7',
    }) => h.api.call(
      Routes.submitPaymentRequest,
      bearer: d.bearer,
      body: SubmitPaymentRequest(
        months: months,
        method: method,
        trxId: trx,
      ).toJson(),
    );

    Future<TestResponse> approve(String id) => h.api.call(
      Routes.adminApprovePaymentRequest,
      params: {'request_id': id},
      bearer: admin,
    );

    Future<TestResponse> upload(TestDevice d, int size) => h.api.call(
      Routes.createUpload,
      bearer: d.bearer,
      body: CreateUploadRequest(
        size: size,
        kind: MediaKind.attachment,
      ).toJson(),
    );

    test('with plans off nothing changes and nothing can be bought', () async {
      final p = await plan(alice);
      expect(p.enabled, isFalse);
      expect(p.limits.maxDevices, 10);
      expect(p.limits.maxAttachmentBytes, 2048);
      expect(p.limits.attachmentRetentionDays, 30);
      expect(p.paymentTargets, isEmpty);
      await setNumbers();
      expect((await submit(alice)).status, 503);
      expect((await upload(alice, 2048)).status, 201);
      expect((await upload(alice, 2049)).status, 413);
    });

    test('Free is two devices and today\'s sizes once plans are on', () async {
      await plansOn();
      final p = await plan(alice);
      expect(p.enabled, isTrue);
      expect(p.plan, PlanId.free);
      expect(p.limits.maxDevices, 2);
      expect(p.limits.attachmentQuotaBytes, 4 * 1024 * 1024 * 1024);
      expect(p.limits.attachmentRetentionDays, 30);
      expect(p.limits.backupMaxBytes, 100 * 1024 * 1024);
      expect(p.prices.map((e) => e.months), [1, 6, 12]);
      expect(p.prices[1].listPrice, 120);
      expect(p.prices[1].price, 100);
      expect(p.prices[1].savePercent, 17);
      expect(p.prices[2].savePercent, 25);
    });

    test('a third device is refused on Free and allowed on Premium', () async {
      await plansOn();
      await setNumbers();
      final second = await secondDevice(h, alice, aliceNumber);
      expect(second.session, isNotNull);
      // A third sign-in, through the same password.
      Future<TestResponse> third() async {
        final step1 = PasswordSignInResponse.fromJson(
          (await h.api.call(
            Routes.passwordSignIn,
            body: PasswordSignInRequest(
              phoneNumber: aliceNumber,
              authKey: bytes(32, 9),
            ).toJson(),
          )).json,
        );
        final device = await alice.account.newDevice(name: 'Third');
        return h.api.call(
          Routes.addDevice,
          body: AddDeviceRequest(
            device: await device.registration(),
            prekeys: await device.prekeys(),
            signInToken: step1.signInToken,
          ).toJson(),
        );
      }

      final refused = await third();
      expect(refused.status, 422, reason: refused.body);
      expect(refused.errorCode, 'quota_exceeded');

      final id = PaymentRequestInfo.fromJson(
        (await submit(alice)).json,
      ).requestId;
      expect((await approve(id)).status, 204);
      expect((await third()).status, 201);
    });

    test('a payment request needs a number, a good ID and is unique', () async {
      await plansOn();
      final bob = await h.registerGlobal(bobNumber);
      // No number set yet.
      expect((await submit(alice)).status, 503);
      await setNumbers(nagad: '01800000000');
      expect((await submit(alice, trx: 'abc')).status, 400);
      expect((await submit(alice, trx: 'has space1')).status, 400);
      expect((await submit(alice, months: 3)).status, 400);

      final made = await submit(alice, trx: ' 8n7a6d5ee7 ');
      expect(made.status, 201, reason: made.body);
      final info = PaymentRequestInfo.fromJson(made.json);
      expect(info.trxId, '8N7A6D5EE7');
      expect(info.amount, 20);
      expect(info.status, PaymentRequestStatus.pending);

      // One open request per account, one use per ID.
      expect((await submit(alice, trx: 'ZZZZZZ1111')).status, 409);
      expect((await submit(bob, trx: '8N7A6D5EE7')).status, 409);
      expect((await submit(bob, trx: 'QQQQQQ2222', months: 12)).status, 201);

      final shown = await plan(alice);
      expect(shown.openRequest?.requestId, info.requestId);
      expect(shown.paymentTargets.map((t) => t.method), [
        PaymentMethod.bkash,
        PaymentMethod.nagad,
      ]);
    });

    test('approving adds time, stacks, and lifts Premium limits', () async {
      await plansOn();
      await setNumbers();
      final first = PaymentRequestInfo.fromJson((await submit(alice)).json);
      // The queue shows it with its owner.
      final queue = Page.fromJson(
        (await h.api.call(Routes.adminPaymentRequests, bearer: admin)).json,
        AdminPaymentRequest.fromJson,
      );
      expect(queue.items.single.request.requestId, first.requestId);
      expect(queue.items.single.accountId, alice.accountId);

      expect((await upload(alice, 5000)).status, 413);
      expect((await approve(first.requestId)).status, 204);
      expect((await approve(first.requestId)).status, 409);

      var p = await plan(alice);
      expect(p.plan, PlanId.premium);
      expect(p.limits.maxAttachmentBytes, 8192);
      expect(p.limits.attachmentQuotaBytes, 16 * 1024 * 1024 * 1024);
      expect(p.limits.attachmentRetentionDays, 90);
      expect(p.limits.backupMaxBytes, 400 * 1024 * 1024);
      expect(p.limits.backupQuotaBytes, 4 * 1024 * 1024 * 1024);
      expect(p.limits.maxDevices, 10);
      expect(p.periodEnd, DateTime.utc(2026, 12, 1));
      expect(p.lastRequest?.status, PaymentRequestStatus.approved);
      expect((await upload(alice, 5000)).status, 201);

      // Six more months are added after the current end, not from today.
      final second = PaymentRequestInfo.fromJson(
        (await submit(alice, months: 6, trx: 'SECOND0001')).json,
      );
      expect((await approve(second.requestId)).status, 204);
      p = await plan(alice);
      expect(p.periodEnd, DateTime.utc(2027, 6, 1));
    });

    test('a rejection says why and the ID can be sent again', () async {
      await plansOn();
      await setNumbers();
      final first = PaymentRequestInfo.fromJson((await submit(alice)).json);
      final no = await h.api.call(
        Routes.adminRejectPaymentRequest,
        params: {'request_id': first.requestId},
        bearer: admin,
        body: const RejectPaymentRequest(
          reason: 'transaction not found',
        ).toJson(),
      );
      expect(no.status, 204, reason: no.body);
      final p = await plan(alice);
      expect(p.plan, PlanId.free);
      expect(p.openRequest, isNull);
      expect(p.lastRequest?.status, PaymentRequestStatus.rejected);
      expect(p.lastRequest?.reason, 'transaction not found');
      expect((await approve(first.requestId)).status, 409);
      // A corrected resend of the same ID is allowed once it was rejected.
      expect((await submit(alice)).status, 201);
    });

    test('Premium runs on for three days after its end, then stops', () async {
      await plansOn();
      await setNumbers();
      final id = PaymentRequestInfo.fromJson(
        (await submit(alice)).json,
      ).requestId;
      await approve(id);
      Future<Entitlements> now() => billing().forAccount(alice.accountId);

      clock.set(DateTime.utc(2026, 11, 30));
      expect((await now()).plan, PlanId.premium);
      clock.set(DateTime.utc(2026, 12, 3, 23));
      expect((await now()).plan, PlanId.premium);
      clock.set(DateTime.utc(2026, 12, 4, 1));
      final after = await now();
      expect(after.plan, PlanId.free);
      expect(after.maxDevices, 2);
      expect(after.attachmentRetention, const Duration(days: 30));
    });

    test('an unanswered request expires and an old one is purged', () async {
      await plansOn();
      await setNumbers();
      final bob = await h.registerGlobal(bobNumber);
      final mine = PaymentRequestInfo.fromJson((await submit(alice)).json);
      final his = PaymentRequestInfo.fromJson(
        (await submit(bob, trx: 'BOBSTRX001')).json,
      );
      final job = billing().periodic.singleWhere(
        (j) => j.name == 'billing.expire_requests',
      );
      Future<String> statusOf(
        String id,
      ) async => (await h.env.platform.db.queryOne(
        'SELECT status FROM ${h.env.platform.schemas.of('billing')}.payment_requests '
        'WHERE id = @id:uuid',
        {'id': id},
      ))!.string('status');

      // Inside the week nothing expires and the operator can still approve.
      clock.advance(const Duration(days: 6));
      await job.run();
      expect(await statusOf(mine.requestId), 'pending');
      expect((await approve(mine.requestId)).status, 204);

      // A week and a day after it was sent, bob's request has lapsed.
      clock.advance(const Duration(days: 2));
      await job.run();
      expect(await statusOf(his.requestId), 'expired');
      await expectLater(
        h.env.platform.db.tx((tx) => billing().approve(tx, his.requestId)),
        throwsA(
          isA<ApiError>().having((e) => e.code, 'code', ErrorCode.conflict),
        ),
      );

      // Decided requests go after a year.
      clock.advance(const Duration(days: 366));
      await job.run();
      final left = await h.env.platform.db.queryOne(
        'SELECT count(*) AS n FROM ${h.env.platform.schemas.of('billing')}.payment_requests',
      );
      expect(left!.integer('n'), 0);
    });

    test('the operator can grant and end Premium, and it is audited', () async {
      await plansOn();
      expect(
        (await h.api.call(
          Routes.adminGrantPlan,
          params: {'account': alice.accountId},
          bearer: admin,
          body: const GrantPlanRequest(months: 2).toJson(),
        )).status,
        204,
      );
      expect((await plan(alice)).periodEnd, DateTime.utc(2027, 1, 1));
      expect(
        (await h.api.call(
          Routes.adminGrantPlan,
          params: {'account': '018f0000-0000-7000-8000-000000000000'},
          bearer: admin,
          body: const GrantPlanRequest(months: 1).toJson(),
        )).status,
        404,
      );
      expect(
        (await h.api.call(
          Routes.adminRevokePlan,
          params: {'account': alice.accountId},
          bearer: admin,
        )).status,
        204,
      );
      expect((await plan(alice)).plan, PlanId.free);
      expect(
        (await h.api.call(
          Routes.adminRevokePlan,
          params: {'account': alice.accountId},
          bearer: admin,
        )).status,
        404,
      );
      final audit = (await h.api.call(Routes.adminAudit, bearer: admin)).body;
      expect(audit, contains('plan.grant'));
      expect(audit, contains('plan.revoke'));
    });

    test('settings are audited without the numbers', () async {
      await setNumbers(bkash: '01711112222');
      final got = BillingSettings.fromJson(
        (await h.api.call(Routes.adminBillingSettings, bearer: admin)).json,
      );
      expect(got.bkashNumber, '01711112222');
      expect(got.priceSixMonths, 100);
      final audit = (await h.api.call(Routes.adminAudit, bearer: admin)).body;
      expect(audit, contains('billing.settings'));
      expect(audit, isNot(contains('01711112222')));
    });

    test('plan routes are for the signed-in account only', () async {
      expect((await h.api.call(Routes.billingPlan)).status, 401);
      expect(
        (await h.api.call(
          Routes.adminPaymentRequests,
          bearer: alice.bearer,
        )).status,
        401,
      );
    });

    test(
      'the export lists billing and deleting the account purges it',
      () async {
        await plansOn();
        await setNumbers();
        final id = PaymentRequestInfo.fromJson(
          (await submit(alice)).json,
        ).requestId;
        await approve(id);
        final export = await h.api.call(
          Routes.exportData,
          bearer: alice.bearer,
        );
        expect(export.status, 200);
        final section =
            ((jsonDecode(export.body) as Map)['sections'] as Map)['billing']
                as Map<String, Object?>;
        expect((section['subscription'] as Map)['plan'], 'premium');
        expect(section['payment_requests'], hasLength(1));

        await h.env.platform.db.tx(
          (tx) => h.identity.api.deleteAccount(tx, alice.accountId),
        );
        final schema = h.env.platform.schemas.of('billing');
        final left = await h.env.platform.db.queryOne(
          'SELECT (SELECT count(*) FROM $schema.subscriptions) AS s, '
          '(SELECT count(*) FROM $schema.payment_requests) AS r',
        );
        expect(left!.integer('s'), 0);
        expect(left.integer('r'), 0);
      },
    );
  });
}
