import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/src/kernel/entitlements.dart';
import 'package:helix_remote_server/src/platform/db/db.dart';

/// A pending payment request and its owner, for the operator's queue.
final class PaymentRequestEntry {
  const PaymentRequestEntry({required this.accountId, required this.info});

  final String accountId;
  final PaymentRequestInfo info;
}

/// What an approval or a grant did, for the audit row.
final class PlanChange {
  const PlanChange({
    required this.accountId,
    required this.months,
    required this.periodEnd,
  });

  final String accountId;
  final int months;
  final DateTime periodEnd;
}

/// The billing module's facade (ADR-026, ADR-035): entitlements for the
/// modules that enforce limits, and the operator's actions for the admin
/// module, which writes the audit rows in the same transaction.
abstract interface class BillingApi implements EntitlementSource {
  /// Whether the operator has switched plans on (`billing_enabled`).
  Future<bool> enabled();

  /// `GET /v1/billing/plan`.
  Future<BillingPlan> planFor(String accountId);

  /// Records a payment request. [ApiError]: `unavailable` (plans off, or no
  /// number set for the method), `invalid_field`, `conflict` (an open request,
  /// or a transaction ID already used).
  Future<PaymentRequestInfo> submitRequest(
    String accountId,
    SubmitPaymentRequest request,
  );

  Future<Page<PaymentRequestInfo>> requestsOf(
    String accountId, {
    required PageRequest page,
  });

  // ------------------------------------------------------------------ admin

  Future<Page<PaymentRequestEntry>> requestsByStatus(
    SqlSession s, {
    required PaymentRequestStatus status,
    required PageRequest page,
  });

  /// Approves a pending request and adds its months. [ApiError]: `not_found`,
  /// `conflict` (not pending).
  Future<PlanChange> approve(Tx tx, String requestId);

  /// Rejects a pending request with a reason the person will read.
  Future<String> reject(Tx tx, String requestId, String reason);

  /// Gives [months] of Premium without a payment. False for an account that
  /// does not exist is the caller's check; billing only holds the plan.
  Future<PlanChange> grant(Tx tx, String accountId, int months);

  /// Ends Premium now (no grace). False when the account had none.
  Future<bool> revoke(Tx tx, String accountId);

  Future<BillingSettings> settings(SqlSession s);

  Future<void> setSettings(Tx tx, BillingSettings settings);
}
