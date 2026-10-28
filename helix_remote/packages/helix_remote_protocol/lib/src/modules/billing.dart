import 'package:helix_remote_protocol/src/json.dart';

// Plans and payments (`/v1/billing/*`, `/v1/admin/payment-requests`,
// `/v1/admin/billing/*`; ADR-035). A payment is made outside the app (bKash
// or Nagad); the app only sends the transaction ID, and the operator
// approves. Nothing here carries a phone number, a password or a key.

/// A plan. `free` is also what an account has when no subscription is
/// running.
enum PlanId implements WireEnum {
  free('free'),
  premium('premium'),
  unknown('unknown');

  const PlanId(this.wire);

  @override
  final String wire;
}

/// How the person paid.
enum PaymentMethod implements WireEnum {
  bkash('bkash'),
  nagad('nagad'),
  unknown('unknown');

  const PaymentMethod(this.wire);

  @override
  final String wire;
}

enum PaymentRequestStatus implements WireEnum {
  /// Waiting for the operator.
  pending('pending'),
  approved('approved'),
  rejected('rejected'),

  /// Nobody answered in [BillingLimits.requestLifetimeDays].
  expired('expired'),
  unknown('unknown');

  const PaymentRequestStatus(this.wire);

  @override
  final String wire;
}

/// Constants both ends share.
abstract final class BillingLimits {
  /// The durations a person may buy, in months.
  static const durations = [1, 6, 12];

  /// A request nobody answers expires after this many days.
  static const requestLifetimeDays = 7;

  /// Premium keeps working this many days after its end date.
  static const graceDays = 3;

  /// A new account's free Premium, once per phone number.
  static const trialDays = 7;

  /// A transaction ID: letters and digits, 6 to 20 of them (bKash IDs are
  /// ten characters, Nagad's are shorter or longer; the operator checks the
  /// real one).
  static const trxMinLength = 6;
  static const trxMaxLength = 20;

  static final RegExp trxPattern = RegExp(r'^[A-Za-z0-9]+$');

  /// What a person typed, as it is stored: trimmed and upper case. Null when
  /// it cannot be a transaction ID.
  static String? normalizeTrxId(String raw) {
    final value = raw.trim().toUpperCase();
    if (value.length < trxMinLength ||
        value.length > trxMaxLength ||
        !trxPattern.hasMatch(value)) {
      return null;
    }
    return value;
  }
}

/// What a plan lets an account do. Sizes are bytes.
final class PlanLimits {
  const PlanLimits({
    required this.maxDevices,
    required this.attachmentQuotaBytes,
    required this.maxAttachmentBytes,
    required this.attachmentRetentionDays,
    required this.backupMaxBytes,
    required this.backupQuotaBytes,
  });

  final int maxDevices;
  final int attachmentQuotaBytes;
  final int maxAttachmentBytes;
  final int attachmentRetentionDays;
  final int backupMaxBytes;
  final int backupQuotaBytes;

  JsonMap toJson() => {
    'max_devices': maxDevices,
    'attachment_quota_bytes': attachmentQuotaBytes,
    'max_attachment_bytes': maxAttachmentBytes,
    'attachment_retention_days': attachmentRetentionDays,
    'backup_max_bytes': backupMaxBytes,
    'backup_quota_bytes': backupQuotaBytes,
  };

  factory PlanLimits.fromJson(JsonReader json) => PlanLimits(
    maxDevices: json.integer('max_devices'),
    attachmentQuotaBytes: json.integer('attachment_quota_bytes'),
    maxAttachmentBytes: json.integer('max_attachment_bytes'),
    attachmentRetentionDays: json.integer('attachment_retention_days'),
    backupMaxBytes: json.integer('backup_max_bytes'),
    backupQuotaBytes: json.integer('backup_quota_bytes'),
  );
}

/// One buyable duration. [listPrice] is [months] times the monthly price;
/// the app crosses it out when it is more than [price].
final class PlanPrice {
  const PlanPrice({
    required this.months,
    required this.price,
    required this.listPrice,
  });

  final int months;

  /// In taka.
  final int price;
  final int listPrice;

  /// Whole percent saved against [listPrice].
  int get savePercent => listPrice <= 0 || price >= listPrice
      ? 0
      : ((listPrice - price) * 100 / listPrice).round();

  JsonMap toJson() => {
    'months': months,
    'price': price,
    'list_price': listPrice,
  };

  factory PlanPrice.fromJson(JsonReader json) => PlanPrice(
    months: json.integer('months'),
    price: json.integer('price'),
    listPrice: json.integer('list_price'),
  );
}

/// Where to send the money.
final class PaymentTarget {
  const PaymentTarget({required this.method, required this.number});

  final PaymentMethod method;
  final String number;

  JsonMap toJson() => {'method': method.wire, 'number': number};

  factory PaymentTarget.fromJson(JsonReader json) => PaymentTarget(
    method: json.enumValue(
      'method',
      PaymentMethod.values,
      orElse: PaymentMethod.unknown,
    ),
    number: json.nonEmpty('number'),
  );
}

/// A payment request as its owner sees it.
final class PaymentRequestInfo {
  const PaymentRequestInfo({
    required this.requestId,
    required this.months,
    required this.amount,
    required this.method,
    required this.trxId,
    required this.status,
    required this.createdAt,
    this.reason,
    this.decidedAt,
  });

  final String requestId;
  final int months;
  final int amount;
  final PaymentMethod method;
  final String trxId;
  final PaymentRequestStatus status;

  /// The operator's short reason on a rejection.
  final String? reason;
  final DateTime createdAt;
  final DateTime? decidedAt;

  JsonMap toJson() => compact({
    'request_id': requestId,
    'months': months,
    'amount': amount,
    'method': method.wire,
    'trx_id': trxId,
    'status': status.wire,
    'reason': reason,
    'created_at': toWireTime(createdAt),
    'decided_at': decidedAt == null ? null : toWireTime(decidedAt!),
  });

  factory PaymentRequestInfo.fromJson(JsonReader json) => PaymentRequestInfo(
    requestId: json.nonEmpty('request_id'),
    months: json.integer('months'),
    amount: json.integer('amount'),
    method: json.enumValue(
      'method',
      PaymentMethod.values,
      orElse: PaymentMethod.unknown,
    ),
    trxId: json.nonEmpty('trx_id'),
    status: json.enumValue(
      'status',
      PaymentRequestStatus.values,
      orElse: PaymentRequestStatus.unknown,
    ),
    reason: json.optString('reason'),
    createdAt: json.time('created_at'),
    decidedAt: json.optTime('decided_at'),
  );
}

/// `GET /v1/billing/plan`.
final class BillingPlan {
  const BillingPlan({
    required this.enabled,
    required this.plan,
    required this.limits,
    required this.premiumLimits,
    required this.prices,
    required this.paymentTargets,
    this.periodEnd,
    this.inGrace = false,
    this.onTrial = false,
    this.openRequest,
    this.lastRequest,
  });

  /// False when the operator has not switched plans on: the app shows no
  /// plan page then.
  final bool enabled;
  final PlanId plan;

  /// When the paid time ends (also while in the grace period).
  final DateTime? periodEnd;

  /// True after [periodEnd] while the grace period keeps Premium running.
  final bool inGrace;

  /// The Premium running now is the free first-week trial.
  final bool onTrial;

  /// What this account may do now.
  final PlanLimits limits;

  /// What Orbit Premium allows, so a Free account can see what it would get.
  final PlanLimits premiumLimits;
  final List<PlanPrice> prices;

  /// Empty until the operator has set a payment number.
  final List<PaymentTarget> paymentTargets;

  /// The one pending request, if any.
  final PaymentRequestInfo? openRequest;

  /// The newest request that is not pending, if any.
  final PaymentRequestInfo? lastRequest;

  bool get isPremium => plan == PlanId.premium;

  JsonMap toJson() => compact({
    'enabled': enabled,
    'plan': plan.wire,
    'period_end': periodEnd == null ? null : toWireTime(periodEnd!),
    'in_grace': inGrace,
    'on_trial': onTrial,
    'limits': limits.toJson(),
    'premium_limits': premiumLimits.toJson(),
    'prices': [for (final p in prices) p.toJson()],
    'payment_targets': [for (final t in paymentTargets) t.toJson()],
    'open_request': openRequest?.toJson(),
    'last_request': lastRequest?.toJson(),
  });

  factory BillingPlan.fromJson(JsonReader json) => BillingPlan(
    enabled: json.boolean('enabled'),
    plan: json.enumValue('plan', PlanId.values, orElse: PlanId.unknown),
    periodEnd: json.optTime('period_end'),
    inGrace: json.flag('in_grace'),
    onTrial: json.flag('on_trial'),
    limits: PlanLimits.fromJson(json.object('limits')),
    premiumLimits: PlanLimits.fromJson(json.object('premium_limits')),
    prices: json.objects('prices', PlanPrice.fromJson),
    paymentTargets: json.objects('payment_targets', PaymentTarget.fromJson),
    openRequest: json.optObject('open_request') == null
        ? null
        : PaymentRequestInfo.fromJson(json.object('open_request')),
    lastRequest: json.optObject('last_request') == null
        ? null
        : PaymentRequestInfo.fromJson(json.object('last_request')),
  );
}

/// `POST /v1/billing/requests`.
final class SubmitPaymentRequest {
  const SubmitPaymentRequest({
    required this.months,
    required this.method,
    required this.trxId,
  });

  final int months;
  final PaymentMethod method;
  final String trxId;

  JsonMap toJson() => {
    'months': months,
    'method': method.wire,
    'trx_id': trxId,
  };

  factory SubmitPaymentRequest.fromJson(JsonReader json) =>
      SubmitPaymentRequest(
        months: json.integer('months'),
        method: json.enumValue(
          'method',
          PaymentMethod.values,
          orElse: PaymentMethod.unknown,
        ),
        trxId: json.string('trx_id', maxLength: 64),
      );
}

// ------------------------------------------------------------------ admin

/// One row of `GET /v1/admin/payment-requests`.
///
/// The operator sees the person the way the accounts list shows them (ADR-030):
/// the name they keep, else their `~Helix name`, and the number their app
/// reported (only with `HELIX_PHONE_KEY`). That is what lets the operator
/// match the sender of a bKash or Nagad payment to the account.
final class AdminPaymentRequest {
  const AdminPaymentRequest({
    required this.request,
    required this.accountId,
    this.accountName,
    this.accountPhone,
  });

  final PaymentRequestInfo request;
  final String accountId;
  final String? accountName;
  final String? accountPhone;

  AdminPaymentRequest copyWith({String? accountName, String? accountPhone}) =>
      AdminPaymentRequest(
        request: request,
        accountId: accountId,
        accountName: accountName ?? this.accountName,
        accountPhone: accountPhone ?? this.accountPhone,
      );

  JsonMap toJson() => compact({
    ...request.toJson(),
    'account_id': accountId,
    'account_name': accountName,
    'account_phone': accountPhone,
  });

  factory AdminPaymentRequest.fromJson(JsonReader json) => AdminPaymentRequest(
    request: PaymentRequestInfo.fromJson(json),
    accountId: json.nonEmpty('account_id'),
    accountName: json.optString('account_name'),
    accountPhone: json.optString('account_phone'),
  );
}

/// `POST /v1/admin/payment-requests/{request_id}/reject`.
final class RejectPaymentRequest {
  const RejectPaymentRequest({required this.reason});

  /// Short, shown to the person.
  final String reason;

  static const maxReasonLength = 200;

  JsonMap toJson() => {'reason': reason};

  factory RejectPaymentRequest.fromJson(JsonReader json) =>
      RejectPaymentRequest(
        reason: json.nonEmpty('reason', maxLength: maxReasonLength),
      );
}

/// `PUT /v1/admin/accounts/{account}/plan`: the operator gives Premium time.
final class GrantPlanRequest {
  const GrantPlanRequest({required this.months});

  final int months;

  JsonMap toJson() => {'months': months};

  factory GrantPlanRequest.fromJson(JsonReader json) =>
      GrantPlanRequest(months: json.intIn('months', 1, 36));
}

/// `GET` and `PUT /v1/admin/billing/settings`: prices (in taka) and the
/// numbers people pay to. A null number means that method is not offered.
final class BillingSettings {
  const BillingSettings({
    required this.priceOneMonth,
    required this.priceSixMonths,
    required this.priceTwelveMonths,
    this.bkashNumber,
    this.nagadNumber,
  });

  final int priceOneMonth;
  final int priceSixMonths;
  final int priceTwelveMonths;
  final String? bkashNumber;
  final String? nagadNumber;

  static const maxPrice = 100000;
  static const maxNumberLength = 32;

  /// The price of [months] (one of [BillingLimits.durations]).
  int priceFor(int months) => switch (months) {
    1 => priceOneMonth,
    6 => priceSixMonths,
    12 => priceTwelveMonths,
    _ => throw ArgumentError.value(months, 'months'),
  };

  JsonMap toJson() => compact({
    'price_1_month': priceOneMonth,
    'price_6_months': priceSixMonths,
    'price_12_months': priceTwelveMonths,
    'bkash_number': bkashNumber,
    'nagad_number': nagadNumber,
  });

  factory BillingSettings.fromJson(JsonReader json) => BillingSettings(
    priceOneMonth: json.intIn('price_1_month', 1, maxPrice),
    priceSixMonths: json.intIn('price_6_months', 1, maxPrice),
    priceTwelveMonths: json.intIn('price_12_months', 1, maxPrice),
    bkashNumber: _number(json, 'bkash_number'),
    nagadNumber: _number(json, 'nagad_number'),
  );

  static String? _number(JsonReader json, String key) {
    final value = json.optString(key, maxLength: maxNumberLength)?.trim();
    return value == null || value.isEmpty ? null : value;
  }
}

/// A limit an operator may change for one account (support cases, ADR-035).
/// The wire names are the ones in [PlanLimits].
enum PlanLimitKey implements WireEnum {
  maxDevices('max_devices', 1, 100),
  attachmentQuotaBytes('attachment_quota_bytes', 0, _tebibytes * 16),
  maxAttachmentBytes('max_attachment_bytes', 1, _tebibytes),
  attachmentRetentionDays('attachment_retention_days', 1, 3650),
  backupMaxBytes('backup_max_bytes', 1, _tebibytes),
  backupQuotaBytes('backup_quota_bytes', 0, _tebibytes * 16),
  unknown('unknown', 0, 0);

  const PlanLimitKey(this.wire, this.min, this.max);

  @override
  final String wire;

  /// The smallest and largest value an override may set.
  final int min;
  final int max;

  static const _tebibytes = 1024 * 1024 * 1024 * 1024;
}

/// One limit an operator changed for an account.
final class PlanOverride {
  const PlanOverride({
    required this.key,
    required this.value,
    required this.reason,
    this.expiresAt,
  });

  final PlanLimitKey key;
  final int value;

  /// Why, for the next operator. Never shown to the person.
  final String reason;

  /// Null: until an operator removes it.
  final DateTime? expiresAt;

  JsonMap toJson() => compact({
    'key': key.wire,
    'value': value,
    'reason': reason,
    'expires_at': expiresAt == null ? null : toWireTime(expiresAt!),
  });

  factory PlanOverride.fromJson(JsonReader json) => PlanOverride(
    key: json.enumValue(
      'key',
      PlanLimitKey.values,
      orElse: PlanLimitKey.unknown,
    ),
    value: json.integer('value'),
    reason: json.string('reason'),
    expiresAt: json.optTime('expires_at'),
  );
}

/// `GET /v1/admin/accounts/{account}/plan`: what the account has, what it may
/// do now (with overrides applied) and the overrides.
final class AdminAccountPlan {
  const AdminAccountPlan({
    required this.plan,
    required this.limits,
    required this.overrides,
    this.periodEnd,
    this.source,
    this.inGrace = false,
  });

  final PlanId plan;
  final DateTime? periodEnd;

  /// `payment`, `admin` or `trial`; null without a subscription.
  final String? source;
  final bool inGrace;
  final PlanLimits limits;
  final List<PlanOverride> overrides;

  JsonMap toJson() => compact({
    'plan': plan.wire,
    'period_end': periodEnd == null ? null : toWireTime(periodEnd!),
    'source': source,
    'in_grace': inGrace,
    'limits': limits.toJson(),
    'overrides': [for (final o in overrides) o.toJson()],
  });

  factory AdminAccountPlan.fromJson(JsonReader json) => AdminAccountPlan(
    plan: json.enumValue('plan', PlanId.values, orElse: PlanId.unknown),
    periodEnd: json.optTime('period_end'),
    source: json.optString('source'),
    inGrace: json.flag('in_grace'),
    limits: PlanLimits.fromJson(json.object('limits')),
    overrides: json.objects('overrides', PlanOverride.fromJson),
  );
}

/// `PUT /v1/admin/accounts/{account}/plan/overrides/{key}`.
final class SetPlanOverrideRequest {
  const SetPlanOverrideRequest({
    required this.value,
    required this.reason,
    this.days,
  });

  final int value;
  final String reason;

  /// Days the override lasts; null keeps it until it is removed.
  final int? days;

  static const maxReasonLength = 200;

  JsonMap toJson() => compact({'value': value, 'reason': reason, 'days': days});

  factory SetPlanOverrideRequest.fromJson(JsonReader json) =>
      SetPlanOverrideRequest(
        value: json.integer('value'),
        reason: json.nonEmpty('reason', maxLength: maxReasonLength),
        days: json.optIntIn('days', 1, 366),
      );
}

/// `GET /v1/admin/billing/summary`: counts for the Payments page.
final class BillingSummary {
  const BillingSummary({
    required this.premium,
    required this.inGrace,
    required this.onTrial,
    required this.pendingRequests,
    required this.approvedLast30Days,
    required this.takenLast30Days,
  });

  /// Accounts with Premium running (trials included).
  final int premium;

  /// Premium accounts past their end date, inside the grace period.
  final int inGrace;
  final int onTrial;
  final int pendingRequests;

  /// Requests approved in the last 30 days and the taka they were for.
  final int approvedLast30Days;
  final int takenLast30Days;

  JsonMap toJson() => {
    'premium': premium,
    'in_grace': inGrace,
    'on_trial': onTrial,
    'pending_requests': pendingRequests,
    'approved_last_30_days': approvedLast30Days,
    'taken_last_30_days': takenLast30Days,
  };

  factory BillingSummary.fromJson(JsonReader json) => BillingSummary(
    premium: json.integer('premium'),
    inGrace: json.integer('in_grace'),
    onTrial: json.integer('on_trial'),
    pendingRequests: json.integer('pending_requests'),
    approvedLast30Days: json.integer('approved_last_30_days'),
    takenLast30Days: json.integer('taken_last_30_days'),
  );
}
