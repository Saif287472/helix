import 'package:helix_admin/src/features/common/feature_controller.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// The payment requests people sent (ADR-035): a transaction ID for a bKash
/// or Nagad payment the operator checks in their own history, then approves or
/// rejects. Nothing here holds a message, a key or a password.
final class PaymentsController extends PagedController<AdminPaymentRequest> {
  PaymentsController(super.ctx, {super.pageSize});

  PaymentRequestStatus _status = PaymentRequestStatus.pending;
  BillingSummary? _summary;
  final Set<String> _deciding = {};

  /// The status filter (pending first: that is the queue).
  PaymentRequestStatus get status => _status;

  bool isDeciding(String requestId) => _deciding.contains(requestId);

  /// Counts for the top of the page; null until read, or when it failed.
  BillingSummary? get summary => _summary;

  /// Reads the counts. A failure leaves the old ones: the queue still works.
  Future<void> loadSummary() async {
    try {
      _summary = await ctx.api.admin.billingSummary();
    } on Object {
      // The queue below is what the operator came for.
    }
    notifyListeners();
  }

  @override
  Future<Page<AdminPaymentRequest>> fetch(PageRequest page) =>
      ctx.api.admin.paymentRequests(status: _status, page: page);

  Future<void> filterByStatus(PaymentRequestStatus status) {
    _status = status;
    return refresh();
  }

  /// Approves a pending request: the months are added to the account.
  /// Returns a problem to show, or null.
  Future<String?> approve(String requestId) =>
      _decide(requestId, () => ctx.api.admin.approvePaymentRequest(requestId));

  /// Rejects it with a short reason the person will read.
  Future<String?> reject(String requestId, String reason) => _decide(
    requestId,
    () => ctx.api.admin.rejectPaymentRequest(requestId, reason),
  );

  Future<String?> _decide(
    String requestId,
    Future<void> Function() action,
  ) async {
    if (!_deciding.add(requestId)) return null;
    notifyListeners();
    final problem = await attempt(action);
    _deciding.remove(requestId);
    if (problem == null && _status == PaymentRequestStatus.pending) {
      removeWhere((r) => r.request.requestId == requestId);
    } else {
      notifyListeners();
    }
    if (problem == null) await loadSummary();
    return problem;
  }

  Future<BillingSettings?> loadSettings(void Function(String) onProblem) async {
    BillingSettings? loaded;
    final problem = await attempt(() async {
      loaded = await ctx.api.admin.billingSettings();
    });
    if (problem != null) onProblem(problem);
    return loaded;
  }

  Future<String?> saveSettings(BillingSettings settings) =>
      attempt(() async => ctx.api.admin.setBillingSettings(settings));
}
