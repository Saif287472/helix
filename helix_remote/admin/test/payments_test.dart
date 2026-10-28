import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

import 'support/harness.dart';

AdminPaymentRequest request(
  String id, {
  PaymentRequestStatus status = PaymentRequestStatus.pending,
  String trx = 'ABC123XYZ9',
  int months = 6,
  int amount = 100,
  String? reason,
}) => AdminPaymentRequest(
  request: PaymentRequestInfo(
    requestId: id,
    months: months,
    amount: amount,
    method: PaymentMethod.bkash,
    trxId: trx,
    status: status,
    reason: reason,
    createdAt: DateTime.utc(2026, 11, 1, 9),
  ),
  accountId: 'acct-$id',
  accountName: 'Rima',
  accountPhone: '+8801711000001',
);

void main() {
  late AdminHarness h;

  setUp(() => h = AdminHarness());

  group('payments', () {
    setUp(() {
      h.server.paymentRequests = [
        request('req-1'),
        request(
          'req-2',
          status: PaymentRequestStatus.approved,
          trx: 'DONE000001',
        ),
        request(
          'req-3',
          status: PaymentRequestStatus.rejected,
          trx: 'NOPE000001',
          reason: 'not found',
        ),
      ];
    });

    Future<void> openPayments(WidgetTester tester) async {
      await h.startSignedIn(tester);
      await h.goTo(tester, 'Payments');
    }

    testWidgets('shows the waiting requests with who sent them', (
      tester,
    ) async {
      await openPayments(tester);

      expect(find.textContaining('BDT 100 · 6 months · bKash'), findsOneWidget);
      expect(find.text('Rima'), findsOneWidget);
      expect(find.text('+8801711000001'), findsOneWidget);
      expect(find.textContaining('ID ABC123XYZ9'), findsOneWidget);
      // Only the waiting one is listed first.
      expect(find.textContaining('DONE000001'), findsNothing);
    });

    testWidgets('the counts say how many accounts are on what', (tester) async {
      await openPayments(tester);

      expect(find.text('PREMIUM NOW'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('ON THE FREE TRIAL'), findsOneWidget);
      expect(find.text('4 approved, BDT 480'), findsOneWidget);
    });

    testWidgets('the filters show what was decided', (tester) async {
      await openPayments(tester);

      await tapText(tester, 'Approved');
      expect(find.textContaining('DONE000001'), findsOneWidget);
      expect(find.text('APPROVED'), findsOneWidget);
      await tapText(tester, 'Rejected');
      expect(find.textContaining('NOPE000001'), findsOneWidget);
      await tapText(tester, 'Expired');
      expect(find.text('Nothing here'), findsOneWidget);
    });

    testWidgets('approving adds the time and takes it off the queue', (
      tester,
    ) async {
      await openPayments(tester);

      await tapText(tester, 'BDT 100 · 6 months · bKash');
      expect(find.text('LOOK FOR THIS PAYMENT'), findsOneWidget);
      expect(find.text('ABC123XYZ9'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
      await tester.pumpAndSettle();

      expect(
        h.server.requests,
        contains('POST /v1/admin/payment-requests/req-1/approve'),
      );
      expect(find.text('No payments waiting'), findsOneWidget);
      expect(find.textContaining('Approved: 6 months added'), findsOneWidget);
    });

    testWidgets('rejecting needs a reason and sends it', (tester) async {
      await openPayments(tester);

      await tapText(tester, 'BDT 100 · 6 months · bKash');
      await tester.tap(find.widgetWithText(OutlinedButton, 'Reject'));
      await tester.pumpAndSettle();
      // Reject stays off until a reason is typed.
      final dialogReject = find.widgetWithText(FilledButton, 'Reject');
      expect(tester.widget<FilledButton>(dialogReject).onPressed, isNull);
      await tester.enterText(find.byType(TextField), 'transaction not found');
      await tester.pump();
      await tester.tap(dialogReject);
      await tester.pumpAndSettle();

      expect(h.server.bodies['POST /v1/admin/payment-requests/req-1/reject'], [
        {'reason': 'transaction not found'},
      ]);
      expect(find.text('No payments waiting'), findsOneWidget);
    });

    testWidgets('a request already decided elsewhere says so', (tester) async {
      await openPayments(tester);
      h.server.fail(
        'POST /v1/admin/payment-requests/{}/approve',
        ErrorCode.conflict,
      );

      await tapText(tester, 'BDT 100 · 6 months · bKash');
      await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Approved:'), findsNothing);
      // Still in the queue.
      expect(find.text('No payments waiting'), findsNothing);
    });

    testWidgets('prices and numbers are edited and saved', (tester) async {
      await openPayments(tester);

      await tapText(tester, 'Prices and numbers');
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(1), '110');
      await tester.enterText(fields.at(4), '01800000000');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final saved = h.server.billingSettings;
      expect(saved.priceSixMonths, 110);
      expect(saved.nagadNumber, '01800000000');
      expect(saved.bkashNumber, '01700000000');
      expect(find.text('Prices and numbers saved.'), findsOneWidget);
    });

    testWidgets('a price that is not a number cannot be saved', (tester) async {
      await openPayments(tester);

      await tapText(tester, 'Prices and numbers');
      await tester.enterText(find.byType(TextField).first, 'free');
      await tester.pump();
      final save = find.widgetWithText(FilledButton, 'Save');
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
    });
  });
}
