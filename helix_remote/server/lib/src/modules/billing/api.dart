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

/// What a call may do with the relay (ADR-036).
final class CallGrant {
  const CallGrant({
    required this.metered,
    required this.expiresAt,
    required this.pool,
  });

  /// The call spends the starter's call time.
  final bool metered;

  /// When the relay stops carrying it: the end of the time reserved for a
  /// metered call, else a long lifetime.
  final DateTime expiresAt;

  /// The pool the call runs in. For the answering side this is the starter's,
  /// whatever it asked for, so both ends use the same relay.
  final CallPool pool;
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

  /// The account's plan as the operator sees it, with overrides.
  Future<AdminAccountPlan> accountPlan(SqlSession s, String accountId);

  /// Changes one limit for one account until [expiresAt] (or until cleared).
  Future<void> setOverride(
    Tx tx,
    String accountId, {
    required PlanLimitKey key,
    required int value,
    required String reason,
    DateTime? expiresAt,
  });

  /// False when the account had no such override.
  Future<bool> clearOverride(Tx tx, String accountId, PlanLimitKey key);

  Future<BillingSummary> summary(SqlSession s);

  Future<BillingSettings> settings(SqlSession s);

  Future<void> setSettings(Tx tx, BillingSettings settings);

  // -------------------------------------------------------------- call time

  /// The account's call time: its pools, or unlimited.
  Future<CallTime> callTime(String accountId);

  /// The operator gives [voice] and [video] minutes (three days, outside the
  /// daily caps), inside the caller's transaction.
  Future<void> grantCallTime(
    Tx tx,
    String accountId, {
    required int voice,
    required int video,
  });

  /// Takes today's minutes (Dhaka day). `conflict` (`details.reason:
  /// already_claimed`) when they were taken.
  Future<CallTime> claimCallTime(String accountId);

  /// Decides what the relay may carry for one call and sets the time aside
  /// (ADR-036). [role] caller: the account starts the call, or joins a group
  /// call's [roomId]; a Free caller's time is reserved and `quota_exceeded`
  /// (`details.reason: call_time`) says there is none. [role] callee: the
  /// answering side; it runs under the caller's reservation. [callerIsRemote]
  /// says the caller is on another server, whose own server meters it.
  Future<CallGrant> grantCall({
    required String accountId,
    required String callId,
    required CallRole role,
    required CallPool pool,
    String? roomId,
    bool callerIsRemote = false,
  });

  /// A call (or one leg of a room) ended: settles a one-to-one call at once
  /// and a room a minute after its last leg.
  Future<void> callEnded(String callId);
}
