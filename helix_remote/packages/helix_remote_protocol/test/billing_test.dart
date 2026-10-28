import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:test/test.dart';

JsonReader _round(JsonMap json) => JsonReader.of(json);

void main() {
  group('transaction IDs', () {
    test('are trimmed and upper case', () {
      expect(BillingLimits.normalizeTrxId(' 8n7a6d5ee7 '), '8N7A6D5EE7');
    });

    test('keep to 6 to 20 letters and digits', () {
      expect(BillingLimits.normalizeTrxId('abc12'), isNull);
      expect(BillingLimits.normalizeTrxId('a' * 21), isNull);
      expect(BillingLimits.normalizeTrxId('ab 123456'), isNull);
      expect(BillingLimits.normalizeTrxId('ab-123456'), isNull);
      expect(BillingLimits.normalizeTrxId('abc123'), 'ABC123');
      expect(BillingLimits.normalizeTrxId('a' * 20), 'A' * 20);
    });
  });

  test('a price knows what it saves', () {
    const six = PlanPrice(months: 6, price: 100, listPrice: 120);
    const twelve = PlanPrice(months: 12, price: 180, listPrice: 240);
    const one = PlanPrice(months: 1, price: 20, listPrice: 20);
    expect(six.savePercent, 17);
    expect(twelve.savePercent, 25);
    expect(one.savePercent, 0);
  });

  test('the plan survives the wire', () {
    final plan = BillingPlan(
      enabled: true,
      plan: PlanId.premium,
      periodEnd: DateTime.utc(2026, 12, 1),
      inGrace: true,
      limits: const PlanLimits(
        maxDevices: 10,
        attachmentQuotaBytes: 1,
        maxAttachmentBytes: 2,
        attachmentRetentionDays: 90,
        backupMaxBytes: 3,
        backupQuotaBytes: 4,
      ),
      premiumLimits: const PlanLimits(
        maxDevices: 10,
        attachmentQuotaBytes: 1,
        maxAttachmentBytes: 2,
        attachmentRetentionDays: 90,
        backupMaxBytes: 3,
        backupQuotaBytes: 4,
      ),
      prices: const [PlanPrice(months: 1, price: 20, listPrice: 20)],
      paymentTargets: const [
        PaymentTarget(method: PaymentMethod.bkash, number: '01700000000'),
      ],
      openRequest: PaymentRequestInfo(
        requestId: 'r',
        months: 1,
        amount: 20,
        method: PaymentMethod.nagad,
        trxId: 'ABC123',
        status: PaymentRequestStatus.pending,
        createdAt: DateTime.utc(2026, 11, 1),
      ),
    );
    final back = BillingPlan.fromJson(_round(plan.toJson()));
    expect(back.enabled, isTrue);
    expect(back.isPremium, isTrue);
    expect(back.inGrace, isTrue);
    expect(back.periodEnd, DateTime.utc(2026, 12, 1));
    expect(back.premiumLimits.attachmentRetentionDays, 90);
    expect(back.paymentTargets.single.method, PaymentMethod.bkash);
    expect(back.openRequest?.trxId, 'ABC123');
    expect(back.lastRequest, isNull);
  });

  test('unknown plans and methods read as unknown, not as an error', () {
    final reader = _round({'method': 'cheque', 'number': '1'});
    expect(PaymentTarget.fromJson(reader).method, PaymentMethod.unknown);
  });

  test('settings keep to sane prices and drop blank numbers', () {
    final ok = BillingSettings.fromJson(
      _round({
        'price_1_month': 20,
        'price_6_months': 100,
        'price_12_months': 180,
        'bkash_number': '  ',
        'nagad_number': '01800000000',
      }),
    );
    expect(ok.bkashNumber, isNull);
    expect(ok.nagadNumber, '01800000000');
    expect(ok.priceFor(6), 100);
    expect(() => ok.priceFor(3), throwsArgumentError);
    expect(
      () => BillingSettings.fromJson(
        _round({
          'price_1_month': 0,
          'price_6_months': 100,
          'price_12_months': 180,
        }),
      ),
      throwsA(isA<ProtocolFormatException>()),
    );
  });

  test('a grant is for 1 to 36 months', () {
    expect(GrantPlanRequest.fromJson(_round({'months': 36})).months, 36);
    expect(
      () => GrantPlanRequest.fromJson(_round({'months': 37})),
      throwsA(isA<ProtocolFormatException>()),
    );
  });

  test('a rejection needs a reason', () {
    expect(
      () => RejectPaymentRequest.fromJson(_round({'reason': ''})),
      throwsA(isA<ProtocolFormatException>()),
    );
  });
}
