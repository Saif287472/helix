import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/engine/clock.dart';
import 'package:helix_remote/core/engine/failure_copy.dart';
import 'package:helix_remote/features/plans/application/plan_models.dart';
import 'package:helix_remote/features/plans/application/plans_gateway.dart';
import 'package:helix_remote_api/v2.dart' show ApiException;
import 'package:helix_remote_protocol/helix_remote_protocol.dart'
    show BillingLimits, ErrorCode;

/// The account's plan, prices and open request. Dropped when the page closes,
/// so it is read again the next time it opens.
final billingPlanProvider = FutureProvider.autoDispose<PlanView>(
  (ref) async => PlanView.from(await ref.watch(plansGatewayProvider).plan()),
);

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// "1 Dec 2026", in the person's own time zone.
String planDate(DateTime time) {
  final t = time.toLocal();
  return '${t.day} ${_months[t.month - 1]} ${t.year}';
}

/// The second line of the You page's Orbit Premium row, or null while plans
/// are off (or not yet read): the row is not drawn then.
final premiumLabelProvider = Provider.autoDispose<String?>((ref) {
  final plan = ref.watch(billingPlanProvider).value;
  if (plan == null || !plan.enabled) return null;
  final end = plan.periodEnd;
  if (!plan.isPremium || end == null) {
    return plan.open == null ? 'Free plan' : 'Waiting for approval';
  }
  return plan.inGrace
      ? 'Ended ${planDate(end)}, still on for a few days'
      : 'Premium until ${planDate(end)}';
});

@immutable
final class PlanPurchaseState {
  const PlanPurchaseState({this.busy = false, this.error});

  final bool busy;

  /// A sentence for the person; never an exception.
  final String? error;
}

/// Sending a payment request: one at a time, the answer in plain words.
final planPurchaseProvider =
    NotifierProvider.autoDispose<PlanPurchaseNotifier, PlanPurchaseState>(
      PlanPurchaseNotifier.new,
    );

final class PlanPurchaseNotifier extends Notifier<PlanPurchaseState> {
  @override
  PlanPurchaseState build() => const PlanPurchaseState();

  /// True when the server took the request.
  Future<bool> submit({
    required int months,
    required PayMethod method,
    required String trxId,
  }) async {
    if (state.busy) return false;
    final id = BillingLimits.normalizeTrxId(trxId);
    if (id == null) {
      state = const PlanPurchaseState(
        error:
            'That does not look like a transaction ID. It is 6 to 20 letters '
            'and numbers, from the bKash or Nagad message.',
      );
      return false;
    }
    state = const PlanPurchaseState(busy: true);
    try {
      await ref
          .read(plansGatewayProvider)
          .submit(months: months, method: PlanView.wire(method), trxId: id);
      ref.invalidate(billingPlanProvider);
      state = const PlanPurchaseState();
      return true;
    } on Object catch (error) {
      state = PlanPurchaseState(error: _sentence(error));
      return false;
    }
  }

  String _sentence(Object error) {
    if (error is ApiException) {
      final reason = error.details?['reason'];
      if (error.code == ErrorCode.conflict) {
        return reason == 'trx_id_used'
            ? 'That transaction ID was already used.'
            : 'You already have a request waiting for approval.';
      }
      if (error.code == ErrorCode.invalidField) {
        return 'That did not look right. Check the transaction ID.';
      }
      if (error.code == ErrorCode.unavailable) {
        return 'Paying for Premium is not open yet.';
      }
    }
    return describeFailure(error, now: ref.read(clockProvider)()).message;
  }
}
