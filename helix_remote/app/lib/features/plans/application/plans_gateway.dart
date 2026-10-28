import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/engine/runtime_providers.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart'
    show
        BillingPlan,
        CallTime,
        PaymentMethod,
        PaymentRequestInfo,
        SubmitPaymentRequest;

/// What the plan page asks the server (ADR-035). An interface so the page and
/// its notifiers are tested against a fake; [ApiPlansGateway] is the one
/// implementation that touches the API. Failures are whatever the API
/// throws; the notifiers turn them into sentences.
abstract interface class PlansGateway {
  Future<BillingPlan> plan();

  /// The Free plan's call minutes (ADR-036) and today's Claim.
  Future<CallTime> callTime();

  /// Takes today's minutes; throws `conflict` when already taken.
  Future<CallTime> claimCallTime();

  /// Sends the transaction ID of a payment the person made outside the app.
  Future<PaymentRequestInfo> submit({
    required int months,
    required PaymentMethod method,
    required String trxId,
  });
}

/// Rebuilt when the active account changes, so a plan is never read for the
/// wrong account (the same rule every gateway keeps).
final plansGatewayProvider = Provider<PlansGateway>((ref) {
  ref.watch(activeAccountProvider);
  return ApiPlansGateway(ref);
});

final class ApiPlansGateway implements PlansGateway {
  ApiPlansGateway(this._ref);

  final Ref _ref;

  @override
  Future<BillingPlan> plan() async =>
      (await _ref.read(runtimeProvider.future)).api.billing.plan();

  @override
  Future<CallTime> callTime() async =>
      (await _ref.read(runtimeProvider.future)).api.billing.callTime();

  @override
  Future<CallTime> claimCallTime() async =>
      (await _ref.read(runtimeProvider.future)).api.billing.claimCallTime();

  @override
  Future<PaymentRequestInfo> submit({
    required int months,
    required PaymentMethod method,
    required String trxId,
  }) async =>
      (await _ref.read(runtimeProvider.future)).api.billing.submitRequest(
        SubmitPaymentRequest(months: months, method: method, trxId: trxId),
      );
}
