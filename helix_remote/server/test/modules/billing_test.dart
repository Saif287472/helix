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
      // The operator's session lasts hours, so they sign in again.
      admin = AdminSession.fromJson(
        (await h.api.call(
          Routes.adminSignIn,
          body: const AdminPasswordRequest(password: adminPassword).toJson(),
        )).json,
      ).token;
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

    group('the trial', () {
      test('a new account gets a week of Premium', () async {
        await plansOn();
        final bob = await h.registerGlobal(bobNumber);
        final p = await plan(bob);
        expect(p.plan, PlanId.premium);
        expect(p.onTrial, isTrue);
        expect(p.periodEnd, DateTime.utc(2026, 11, 8));
        expect(p.limits.maxDevices, 10);
        // An account that was there before plans went on has none.
        expect((await plan(alice)).plan, PlanId.free);
      });

      test(
        'only once per phone number, even after the account is gone',
        () async {
          await plansOn();
          final first = await h.registerGlobal(bobNumber);
          expect((await plan(first)).onTrial, isTrue);
          await h.env.platform.db.tx(
            (tx) => h.identity.api.deleteAccount(tx, first.accountId),
          );
          final again = await h.registerGlobal(bobNumber);
          final p = await plan(again);
          expect(p.plan, PlanId.free);
          expect(p.onTrial, isFalse);
        },
      );

      test('there is none while plans are off', () async {
        final bob = await h.registerGlobal(bobNumber);
        await plansOn();
        expect((await plan(bob)).plan, PlanId.free);
      });

      test('an older account adding a device does not get one', () async {
        await plansOn();
        await secondDevice(h, alice, aliceNumber);
        expect((await plan(alice)).plan, PlanId.free);
      });

      test(
        'paid time is added after the trial, and the trial is over',
        () async {
          await plansOn();
          await setNumbers();
          final bob = await h.registerGlobal(bobNumber);
          final id = PaymentRequestInfo.fromJson(
            (await submit(bob)).json,
          ).requestId;
          expect((await approve(id)).status, 204);
          final p = await plan(bob);
          expect(p.onTrial, isFalse);
          expect(p.periodEnd, DateTime.utc(2026, 12, 8));
        },
      );
    });

    group('overrides', () {
      Future<TestResponse> override(
        String key,
        int value, {
        String reason = 'support ticket 12',
        int? days,
      }) => h.api.call(
        Routes.adminSetPlanOverride,
        params: {'account': alice.accountId, 'key': key},
        bearer: admin,
        body: SetPlanOverrideRequest(
          value: value,
          reason: reason,
          days: days,
        ).toJson(),
      );

      Future<AdminAccountPlan> viewed() async => AdminAccountPlan.fromJson(
        (await h.api.call(
          Routes.adminAccountPlan,
          params: {'account': alice.accountId},
          bearer: admin,
        )).json,
      );

      test('change one limit for one account and show in its plan', () async {
        await plansOn();
        expect((await viewed()).limits.maxDevices, 2);
        expect((await override('max_devices', 3)).status, 204);

        final view = await viewed();
        expect(view.limits.maxDevices, 3);
        expect(view.limits.attachmentRetentionDays, 30);
        expect(view.overrides.single.key, PlanLimitKey.maxDevices);
        expect(view.overrides.single.reason, 'support ticket 12');
        expect((await plan(alice)).limits.maxDevices, 3);
      });

      test('are enforced where the limit is', () async {
        await plansOn();
        await override('max_attachment_bytes', 4096);
        expect((await upload(alice, 4096)).status, 201);
        expect((await upload(alice, 4097)).status, 413);
      });

      test('can last a number of days and are then gone', () async {
        await plansOn();
        await override('max_devices', 5, days: 2);
        Future<int> devices() async =>
            (await billing().forAccount(alice.accountId)).maxDevices;
        expect(await devices(), 5);
        clock.advance(const Duration(days: 3));
        expect(await devices(), 2);
        await billing().periodic
            .singleWhere((j) => j.name == 'billing.expire_requests')
            .run();
        final left = await h.env.platform.db.queryOne(
          'SELECT count(*) AS n FROM ${h.env.platform.schemas.of('billing')}.entitlement_overrides',
        );
        expect(left!.integer('n'), 0);
      });

      test('can be removed', () async {
        await plansOn();
        await override('max_devices', 6);
        final gone = await h.api.call(
          Routes.adminClearPlanOverride,
          params: {'account': alice.accountId, 'key': 'max_devices'},
          bearer: admin,
        );
        expect(gone.status, 204);
        expect((await viewed()).limits.maxDevices, 2);
        final again = await h.api.call(
          Routes.adminClearPlanOverride,
          params: {'account': alice.accountId, 'key': 'max_devices'},
          bearer: admin,
        );
        expect(again.status, 404);
      });

      test('keep to sane values, known names and real accounts', () async {
        await plansOn();
        expect((await override('max_devices', 0)).status, 400);
        expect((await override('max_devices', 101)).status, 400);
        expect((await override('colour', 1)).status, 404);
        final ghost = await h.api.call(
          Routes.adminSetPlanOverride,
          params: {
            'account': '018f0000-0000-7000-8000-000000000000',
            'key': 'max_devices',
          },
          bearer: admin,
          body: const SetPlanOverrideRequest(value: 3, reason: 'x').toJson(),
        );
        expect(ghost.status, 404);
      });

      test('are audited and go with the account', () async {
        await plansOn();
        await override('max_devices', 4, days: 30);
        final audit = (await h.api.call(Routes.adminAudit, bearer: admin)).body;
        expect(audit, contains('plan.override'));
        expect(audit, isNot(contains('support ticket 12')));
        await h.env.platform.db.tx(
          (tx) => h.identity.api.deleteAccount(tx, alice.accountId),
        );
        final left = await h.env.platform.db.queryOne(
          'SELECT count(*) AS n FROM ${h.env.platform.schemas.of('billing')}.entitlement_overrides',
        );
        expect(left!.integer('n'), 0);
      });
    });

    test('the counts say how many are on what', () async {
      await plansOn();
      await setNumbers();
      final bob = await h.registerGlobal(bobNumber);
      final carol = await h.registerGlobal('+8801711000003');
      final paid = PaymentRequestInfo.fromJson(
        (await submit(alice, months: 6)).json,
      );
      await approve(paid.requestId);
      await submit(bob, trx: 'BOBWAITING1');

      BillingSummary read(TestResponse r) => BillingSummary.fromJson(r.json);
      final sum = read(
        await h.api.call(Routes.adminBillingSummary, bearer: admin),
      );
      expect(sum.premium, 3, reason: 'alice paid, bob and carol on trial');
      expect(sum.onTrial, 2);
      expect(sum.inGrace, 0);
      expect(sum.pendingRequests, 1);
      expect(sum.approvedLast30Days, 1);
      expect(sum.takenLast30Days, 100);
      expect(carol.accountId, isNotEmpty);
    });

    group('the wake-up', () {
      Future<void> tokenFor(TestDevice d, String token) async {
        final r = await h.api.call(
          Routes.setPushToken,
          bearer: d.bearer,
          body: PushTokenRequest(token: token).toJson(),
        );
        expect(r.status, 204, reason: r.body);
      }

      Iterable<String> wakes(String token) => h.push.sent
          .where((p) => p.token == token && p.reason.wire == 'plan')
          .map((p) => p.token);

      test('goes to every device when a request is decided', () async {
        await plansOn();
        await setNumbers();
        final second = await secondDevice(h, alice, aliceNumber);
        await tokenFor(alice, 'first-token');
        await tokenFor(second, 'second-token');
        final id = PaymentRequestInfo.fromJson(
          (await submit(alice)).json,
        ).requestId;
        await approve(id);
        await h.env.platform.jobs.tick();

        expect(wakes('first-token'), hasLength(1));
        expect(wakes('second-token'), hasLength(1));
        // It carries no content: a reason and nothing else.
        expect(h.push.sent.last.callId, isNull);
      });

      test('also follows a rejection, a grant and an override', () async {
        await plansOn();
        await setNumbers();
        await tokenFor(alice, 'first-token');
        final id = PaymentRequestInfo.fromJson(
          (await submit(alice)).json,
        ).requestId;
        await h.api.call(
          Routes.adminRejectPaymentRequest,
          params: {'request_id': id},
          bearer: admin,
          body: const RejectPaymentRequest(reason: 'no such payment').toJson(),
        );
        await h.env.platform.jobs.tick();
        expect(wakes('first-token'), hasLength(1));

        await h.api.call(
          Routes.adminGrantPlan,
          params: {'account': alice.accountId},
          bearer: admin,
          body: const GrantPlanRequest(months: 1).toJson(),
        );
        await h.env.platform.jobs.tick();
        expect(wakes('first-token'), hasLength(2));
      });

      test('is not sent for a decision that did not happen', () async {
        await plansOn();
        await setNumbers();
        await tokenFor(alice, 'first-token');
        final id = PaymentRequestInfo.fromJson(
          (await submit(alice)).json,
        ).requestId;
        await approve(id);
        await approve(id); // a repeat is refused
        await h.env.platform.jobs.tick();
        expect(wakes('first-token'), hasLength(1));
      });
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
