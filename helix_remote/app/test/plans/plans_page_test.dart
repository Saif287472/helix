import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/features/plans/application/plans_gateway.dart';
import 'package:helix_remote/features/plans/application/plans_providers.dart';
import 'package:helix_remote/features/plans/presentation/premium_page.dart';
import 'package:helix_remote/shared/widgets/orbit_you_connector.dart';
import 'package:helix_remote_api/v2.dart' show ApiException;
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

import '../settings/settings_pages_test.dart' show orbitField, youTest;
import '../support/a3b_fakes.dart';

const _free = PlanLimits(
  maxDevices: 2,
  attachmentQuotaBytes: 4 * 1024 * 1024 * 1024,
  maxAttachmentBytes: 100 * 1024 * 1024,
  attachmentRetentionDays: 30,
  backupMaxBytes: 100 * 1024 * 1024,
  backupQuotaBytes: 1024 * 1024 * 1024,
);

const _premium = PlanLimits(
  maxDevices: 10,
  attachmentQuotaBytes: 16 * 1024 * 1024 * 1024,
  maxAttachmentBytes: 400 * 1024 * 1024,
  attachmentRetentionDays: 90,
  backupMaxBytes: 400 * 1024 * 1024,
  backupQuotaBytes: 4 * 1024 * 1024 * 1024,
);

const _prices = [
  PlanPrice(months: 1, price: 20, listPrice: 20),
  PlanPrice(months: 6, price: 100, listPrice: 120),
  PlanPrice(months: 12, price: 180, listPrice: 240),
];

BillingPlan aPlan({
  bool enabled = true,
  PlanId plan = PlanId.free,
  DateTime? end,
  bool grace = false,
  bool trial = false,
  List<PaymentTarget> targets = const [
    PaymentTarget(method: PaymentMethod.bkash, number: '01700000000'),
    PaymentTarget(method: PaymentMethod.nagad, number: '01800000000'),
  ],
  PaymentRequestInfo? open,
  PaymentRequestInfo? last,
}) => BillingPlan(
  enabled: enabled,
  plan: plan,
  periodEnd: end,
  inGrace: grace,
  onTrial: trial,
  limits: plan == PlanId.premium ? _premium : _free,
  premiumLimits: _premium,
  prices: _prices,
  paymentTargets: targets,
  openRequest: open,
  lastRequest: last,
);

PaymentRequestInfo req(
  PaymentRequestStatus status, {
  String? reason,
  String trx = 'ABC123XYZ9',
  int months = 6,
}) => PaymentRequestInfo(
  requestId: 'r1',
  months: months,
  amount: 100,
  method: PaymentMethod.bkash,
  trxId: trx,
  status: status,
  reason: reason,
  createdAt: DateTime.utc(2026, 11, 1),
);

final class FakePlansGateway implements PlansGateway {
  FakePlansGateway(this.current);

  BillingPlan current;
  Object? planError;
  Object? submitError;
  final List<({int months, PaymentMethod method, String trxId})> submitted = [];

  @override
  Future<BillingPlan> plan() async {
    if (planError != null) throw planError!;
    return current;
  }

  @override
  Future<PaymentRequestInfo> submit({
    required int months,
    required PaymentMethod method,
    required String trxId,
  }) async {
    if (submitError != null) throw submitError!;
    submitted.add((months: months, method: method, trxId: trxId));
    final made = req(PaymentRequestStatus.pending, trx: trxId, months: months);
    current = aPlan(open: made);
    return made;
  }
}

List<Override> _overrides(FakePlansGateway gateway) => [
  ...a3bOverrides(),
  plansGatewayProvider.overrideWithValue(gateway),
];

void main() {
  group('Orbit Premium page', () {
    youTest('says plans are not open while the operator has not switched '
        'them on', (tester) async {
      final gateway = FakePlansGateway(aPlan(enabled: false));
      await pumpPage(
        tester,
        const PremiumPage(),
        overrides: _overrides(gateway),
      );
      await settle(tester);

      expect(find.text('Plans are not open yet'), findsOneWidget);
      expect(find.text('Send for approval'), findsNothing);
    });

    youTest('shows the Free plan, what Premium adds and the prices', (
      tester,
    ) async {
      useTallWindow(tester);
      final gateway = FakePlansGateway(aPlan());
      await pumpPage(
        tester,
        const PremiumPage(),
        overrides: _overrides(gateway),
      );
      await settle(tester);

      expect(find.text('You are on the Free plan'), findsOneWidget);
      // Premium's numbers, with today's beside them.
      expect(find.text('Linked devices'), findsOneWidget);
      expect(find.text('Now: 2'), findsOneWidget);
      expect(find.text('16.0 GB'), findsWidgets);
      expect(find.text('90 days'), findsOneWidget);
      // The three prices, the crossed-out one and what it saves.
      expect(find.text('BDT 20'), findsOneWidget);
      expect(find.text('BDT 100'), findsOneWidget);
      expect(find.text('BDT 120'), findsOneWidget);
      expect(find.text('Save 17%'), findsOneWidget);
      expect(find.text('Save 25%'), findsOneWidget);
      final crossed = tester.widget<Text>(find.text('BDT 120'));
      expect(crossed.style?.decoration, TextDecoration.lineThrough);
      // Where to pay.
      expect(find.text('bKash'), findsOneWidget);
      expect(find.text('01700000000'), findsOneWidget);
      expect(find.text('Nagad'), findsOneWidget);
    });

    youTest('sends the transaction ID with the chosen time and method', (
      tester,
    ) async {
      useTallWindow(tester);
      final gateway = FakePlansGateway(aPlan());
      await pumpPage(
        tester,
        const PremiumPage(),
        overrides: _overrides(gateway),
      );
      await settle(tester);

      await tester.tap(find.text('12 months'));
      await tester.pump();
      await tester.tap(find.text('Nagad'));
      await tester.pump();
      await tester.enterText(
        orbitField('Step 2: transaction ID'),
        ' 8n7a6d5ee7 ',
      );
      await tester.pump();
      await tester.tap(find.text('Send for approval'));
      await settle(tester);

      expect(gateway.submitted, [
        (months: 12, method: PaymentMethod.nagad, trxId: '8N7A6D5EE7'),
      ]);
      // The page now waits for the operator.
      expect(find.textContaining('waiting for approval'), findsOneWidget);
      expect(find.text('Send for approval'), findsNothing);
    });

    youTest('refuses an ID that cannot be one, without asking the server', (
      tester,
    ) async {
      useTallWindow(tester);
      final gateway = FakePlansGateway(aPlan());
      await pumpPage(
        tester,
        const PremiumPage(),
        overrides: _overrides(gateway),
      );
      await settle(tester);

      await tester.enterText(orbitField('Step 2: transaction ID'), 'ab');
      await tester.pump();
      await tester.tap(find.text('Send for approval'));
      await settle(tester);

      expect(gateway.submitted, isEmpty);
      expect(
        find.textContaining('does not look like a transaction ID'),
        findsOneWidget,
      );
    });

    youTest('says plainly when the ID was already used', (tester) async {
      useTallWindow(tester);
      final gateway = FakePlansGateway(aPlan())
        ..submitError = const ApiException(
          status: 409,
          code: ErrorCode.conflict,
          details: {'reason': 'trx_id_used'},
        );
      await pumpPage(
        tester,
        const PremiumPage(),
        overrides: _overrides(gateway),
      );
      await settle(tester);

      await tester.enterText(
        orbitField('Step 2: transaction ID'),
        'ABC123XYZ9',
      );
      await tester.pump();
      await tester.tap(find.text('Send for approval'));
      await settle(tester);

      expect(
        find.text('That transaction ID was already used.'),
        findsOneWidget,
      );
    });

    youTest('shows a waiting request and no way to send another', (
      tester,
    ) async {
      useTallWindow(tester);
      final gateway = FakePlansGateway(
        aPlan(open: req(PaymentRequestStatus.pending)),
      );
      await pumpPage(
        tester,
        const PremiumPage(),
        overrides: _overrides(gateway),
      );
      await settle(tester);

      expect(find.textContaining('ABC123XYZ9'), findsOneWidget);
      expect(find.textContaining('waiting for approval'), findsOneWidget);
      expect(find.text('Send for approval'), findsNothing);
    });

    youTest('tells a rejected person why, and lets them send again', (
      tester,
    ) async {
      useTallWindow(tester);
      final gateway = FakePlansGateway(
        aPlan(
          last: req(
            PaymentRequestStatus.rejected,
            reason: 'transaction not found',
          ),
        ),
      );
      await pumpPage(
        tester,
        const PremiumPage(),
        overrides: _overrides(gateway),
      );
      await settle(tester);

      expect(find.textContaining('transaction not found'), findsOneWidget);
      expect(find.text('Send for approval'), findsOneWidget);
    });

    youTest('shows Premium until its end date and lets the person add time', (
      tester,
    ) async {
      useTallWindow(tester);
      final gateway = FakePlansGateway(
        aPlan(plan: PlanId.premium, end: DateTime.utc(2026, 12, 15, 12)),
      );
      await pumpPage(
        tester,
        const PremiumPage(),
        overrides: _overrides(gateway),
      );
      await settle(tester);

      expect(find.text('You have Orbit Premium'), findsOneWidget);
      expect(find.text('Until 15 Dec 2026.'), findsOneWidget);
      expect(find.text('ADD TIME'), findsOneWidget);
      // Nothing to compare with: the person already has them.
      expect(find.textContaining('Now:'), findsNothing);
    });

    youTest('says it is the free trial, with the day it ends', (tester) async {
      useTallWindow(tester);
      final gateway = FakePlansGateway(
        aPlan(
          plan: PlanId.premium,
          trial: true,
          end: DateTime.utc(2026, 11, 8, 12),
        ),
      );
      await pumpPage(
        tester,
        const PremiumPage(),
        overrides: _overrides(gateway),
      );
      await settle(tester);

      expect(find.text('You are on the free trial'), findsOneWidget);
      expect(find.textContaining('until 8 Nov 2026'), findsOneWidget);
      expect(find.text('You have Orbit Premium'), findsNothing);
    });

    youTest('says so when the plan cannot be read, and tries again', (
      tester,
    ) async {
      final gateway = FakePlansGateway(aPlan())..planError = Exception('x');
      await pumpPage(
        tester,
        const PremiumPage(),
        overrides: _overrides(gateway),
      );
      await settle(tester);
      expect(find.text('Premium could not be loaded.'), findsOneWidget);

      gateway.planError = null;
      await tester.tap(find.text('Try again'));
      await settle(tester);
      expect(find.text('You are on the Free plan'), findsOneWidget);
    });
  });

  group('the You page row', () {
    youTest('is drawn only when plans are on, and says where the person is', (
      tester,
    ) async {
      useTallWindow(tester);
      final off = FakePlansGateway(aPlan(enabled: false));
      await pumpPage(
        tester,
        const OrbitYouConnector(),
        overrides: [
          ...a3bOverrides(settingsGateway: FakeSettingsGateway()),
          plansGatewayProvider.overrideWithValue(off),
        ],
      );
      await settle(tester);
      expect(find.text('Orbit Premium'), findsNothing);

      final on = FakePlansGateway(aPlan());
      await pumpPage(
        tester,
        const OrbitYouConnector(),
        overrides: [
          ...a3bOverrides(settingsGateway: FakeSettingsGateway()),
          plansGatewayProvider.overrideWithValue(on),
        ],
      );
      await settle(tester);
      expect(find.text('Orbit Premium'), findsOneWidget);
      expect(find.text('Free plan'), findsOneWidget);
    });

    test('the label tells a lapsed plan from a running one', () async {
      Future<String?> label(BillingPlan p) async {
        final container = ProviderContainer(
          overrides: [
            plansGatewayProvider.overrideWithValue(FakePlansGateway(p)),
          ],
        );
        addTearDown(container.dispose);
        container.listen(premiumLabelProvider, (_, _) {});
        await container.read(billingPlanProvider.future);
        return container.read(premiumLabelProvider);
      }

      expect(await label(aPlan(enabled: false)), isNull);
      expect(await label(aPlan()), 'Free plan');
      expect(
        await label(aPlan(open: req(PaymentRequestStatus.pending))),
        'Waiting for approval',
      );
      expect(
        await label(
          aPlan(plan: PlanId.premium, end: DateTime.utc(2026, 12, 15, 12)),
        ),
        'Premium until 15 Dec 2026',
      );
      expect(
        await label(
          aPlan(
            plan: PlanId.premium,
            end: DateTime.utc(2026, 11, 8, 12),
            trial: true,
          ),
        ),
        'Free trial until 8 Nov 2026',
      );
      expect(
        await label(
          aPlan(
            plan: PlanId.premium,
            end: DateTime.utc(2026, 12, 15, 12),
            grace: true,
          ),
        ),
        'Ended 15 Dec 2026, still on for a few days',
      );
    });
  });
}
