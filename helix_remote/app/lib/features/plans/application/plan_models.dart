import 'package:flutter/foundation.dart' show immutable;
import 'package:helix_remote_protocol/helix_remote_protocol.dart' as proto;

/// How a person pays: the two mobile wallets the operator can take.
enum PayMethod {
  bkash('bKash'),
  nagad('Nagad');

  const PayMethod(this.label);

  final String label;
}

/// A request's state, for the notice at the top of the page.
enum RequestState { pending, approved, rejected, expired }

/// What a plan allows, in the units the page shows.
@immutable
final class PlanLimitsView {
  const PlanLimitsView({
    required this.maxDevices,
    required this.attachmentQuotaBytes,
    required this.maxAttachmentBytes,
    required this.attachmentRetentionDays,
    required this.backupQuotaBytes,
  });

  final int maxDevices;
  final int attachmentQuotaBytes;
  final int maxAttachmentBytes;
  final int attachmentRetentionDays;
  final int backupQuotaBytes;

  factory PlanLimitsView.from(proto.PlanLimits l) => PlanLimitsView(
    maxDevices: l.maxDevices,
    attachmentQuotaBytes: l.attachmentQuotaBytes,
    maxAttachmentBytes: l.maxAttachmentBytes,
    attachmentRetentionDays: l.attachmentRetentionDays,
    backupQuotaBytes: l.backupQuotaBytes,
  );
}

/// One buyable length of time. [listPrice] is crossed out when it is more
/// than [price].
@immutable
final class PriceView {
  const PriceView({
    required this.months,
    required this.price,
    required this.listPrice,
    required this.savePercent,
  });

  final int months;
  final int price;
  final int listPrice;
  final int savePercent;
}

@immutable
final class PayTarget {
  const PayTarget({required this.method, required this.number});

  final PayMethod method;
  final String number;
}

/// A payment request as the person sees it.
@immutable
final class RequestView {
  const RequestView({
    required this.months,
    required this.trxId,
    required this.state,
    this.reason,
  });

  final int months;
  final String trxId;
  final RequestState state;
  final String? reason;
}

/// Everything the Orbit Premium page draws.
@immutable
final class PlanView {
  const PlanView({
    required this.enabled,
    required this.isPremium,
    required this.inGrace,
    required this.onTrial,
    required this.limits,
    required this.premiumLimits,
    required this.prices,
    required this.targets,
    this.periodEnd,
    this.open,
    this.last,
  });

  final bool enabled;
  final bool isPremium;

  /// After the end date, while the grace period keeps Premium on.
  final bool inGrace;

  /// The Premium running is the free first week.
  final bool onTrial;
  final DateTime? periodEnd;

  /// What the account may do now, and what Premium allows.
  final PlanLimitsView limits;
  final PlanLimitsView premiumLimits;
  final List<PriceView> prices;

  /// Empty until the operator has set a number.
  final List<PayTarget> targets;

  /// The request waiting for the operator, and the newest decided one.
  final RequestView? open;
  final RequestView? last;

  static PayMethod? _method(proto.PaymentMethod m) => switch (m) {
    proto.PaymentMethod.bkash => PayMethod.bkash,
    proto.PaymentMethod.nagad => PayMethod.nagad,
    proto.PaymentMethod.unknown => null,
  };

  static RequestView _request(proto.PaymentRequestInfo r) => RequestView(
    months: r.months,
    trxId: r.trxId,
    reason: r.reason,
    state: switch (r.status) {
      proto.PaymentRequestStatus.pending => RequestState.pending,
      proto.PaymentRequestStatus.approved => RequestState.approved,
      proto.PaymentRequestStatus.rejected => RequestState.rejected,
      _ => RequestState.expired,
    },
  );

  factory PlanView.from(proto.BillingPlan p) {
    final open = p.openRequest;
    final last = p.lastRequest;
    return PlanView(
      enabled: p.enabled,
      isPremium: p.isPremium,
      inGrace: p.inGrace,
      onTrial: p.onTrial,
      periodEnd: p.periodEnd,
      limits: PlanLimitsView.from(p.limits),
      premiumLimits: PlanLimitsView.from(p.premiumLimits),
      prices: [
        for (final x in p.prices)
          PriceView(
            months: x.months,
            price: x.price,
            listPrice: x.listPrice,
            savePercent: x.savePercent,
          ),
      ],
      targets: [
        for (final t in p.paymentTargets)
          if (_method(t.method) case final m?)
            PayTarget(method: m, number: t.number),
      ],
      open: open == null ? null : _request(open),
      last: last == null ? null : _request(last),
    );
  }

  /// The method to start from: the first the operator offers.
  PayMethod? get firstMethod => targets.isEmpty ? null : targets.first.method;

  static proto.PaymentMethod wire(PayMethod m) => switch (m) {
    PayMethod.bkash => proto.PaymentMethod.bkash,
    PayMethod.nagad => proto.PaymentMethod.nagad,
  };
}

/// One pool of free call minutes, as the page shows it.
@immutable
final class CallPoolView {
  const CallPoolView({
    required this.minutes,
    required this.dailyMinutes,
    required this.capMinutes,
  });

  final int minutes;
  final int dailyMinutes;
  final int capMinutes;
}

/// The Free plan's call time (ADR-036). Null pools mean the server did not
/// send them (an unlimited account).
@immutable
final class CallTimeView {
  const CallTimeView({
    required this.unlimited,
    required this.canClaim,
    this.voice,
    this.video,
    this.nextClaimAt,
  });

  final bool unlimited;
  final bool canClaim;
  final CallPoolView? voice;
  final CallPoolView? video;
  final DateTime? nextClaimAt;

  factory CallTimeView.from(proto.CallTime t) {
    CallPoolView? pool(proto.CallPool media) {
      final p = t.pool(media);
      return p == null
          ? null
          : CallPoolView(
              minutes: p.minutes,
              dailyMinutes: p.dailyMinutes,
              capMinutes: p.capMinutes,
            );
    }

    return CallTimeView(
      unlimited: t.unlimited,
      canClaim: t.canClaim,
      voice: pool(proto.CallPool.voice),
      video: pool(proto.CallPool.video),
      nextClaimAt: t.nextClaimAt,
    );
  }
}

/// What a Free account gets each day (the numbers the server enforces).
abstract final class FreeCallTime {
  static const voiceDaily = proto.CallTimeLimits.voiceDaily;
  static const videoDaily = proto.CallTimeLimits.videoDaily;
}
