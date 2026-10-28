import 'package:helix_remote_api/src/v2/transport/transport.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// The `billing` module: the plan, and payment requests (ADR-035). A payment
/// is made outside the app; the app sends only the transaction ID.
final class BillingClient {
  const BillingClient(this._t);

  final HelixTransport _t;

  Future<BillingPlan> plan() =>
      _t.call(Routes.billingPlan, BillingPlan.fromJson);

  /// `conflict` when a request is already open or the ID was already used,
  /// `unavailable` when plans are off.
  Future<PaymentRequestInfo> submitRequest(SubmitPaymentRequest request) =>
      _t.call(
        Routes.submitPaymentRequest,
        PaymentRequestInfo.fromJson,
        json: request.toJson(),
      );

  /// This account's own requests, newest first.
  Future<Page<PaymentRequestInfo>> requests({
    PageRequest page = const PageRequest(),
  }) => _t.call(
    Routes.paymentRequests,
    (json) => Page.fromJson(json, PaymentRequestInfo.fromJson),
    query: page.toQuery(),
  );
}
