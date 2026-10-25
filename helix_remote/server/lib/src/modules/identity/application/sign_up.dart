import 'dart:convert';
import 'dart:typed_data';

import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/src/modules/identity/application/context.dart';
import 'package:helix_remote_server/src/modules/identity/config.dart';
import 'package:helix_remote_server/src/modules/identity/domain/secrets.dart';
import 'package:helix_remote_server/src/modules/identity/sms.dart';
import 'package:helix_remote_server/src/platform/db/db.dart';
import 'package:helix_remote_server/src/platform/ratelimit/rate_limiter.dart';

/// Phone verification, invites, registration and recovery.
final class SignUp {
  SignUp(this.c);

  final IdentityContext c;

  static final _perPhone = RateLimitPolicy.per(
    'identity.otp_phone',
    5,
    const Duration(hours: 1),
  );

  /// The cluster's daily text budget (`HELIX_SMS_DAILY_LIMIT`), one bucket
  /// for every number. It is a token bucket that refills over the day, so the
  /// worst case is twice the limit in 24 hours (a full burst at the start of
  /// the window, then the refill); that is the point - it stops a pumping
  /// script from spending the provider's balance, and the bucket is shared by
  /// every node and every purpose (sign-up, recovery, verification).
  RateLimitPolicy get _dailyBudget => RateLimitPolicy.per(
    'identity.sms_daily',
    c.config.smsDailyLimit,
    const Duration(days: 1),
  );

  // ------------------------------------------------------------ phone codes

  /// Whether the number is a Helix user and whether that account has a
  /// password, asked before any code is texted so the app can choose the
  /// right next screen (ADR-032 is the decision to answer an unauthenticated
  /// caller at all). The answer grants nothing: `register`, the recovery
  /// routes and password sign-in still demand what only a code or a key gives
  /// them.
  Future<AccountStatusResponse> accountStatus(AccountStatusRequest req) async {
    final existing = await c.store.accountByPhone(
      c.db,
      c.phoneHash(requireE164(req.phoneNumber)),
    );
    return AccountStatusResponse(
      accountExists: existing != null,
      hasPassword: existing?.hasPassword ?? false,
    );
  }

  Future<PhoneChallengeResponse> requestPhoneChallenge(
    PhoneChallengeRequest req,
  ) async {
    if (!c.config.sms.isConfigured) {
      throw const ApiError(
        ErrorCode.smsUnavailable,
        message: 'This server does not send texts.',
      );
    }
    final e164 = requireE164(req.phoneNumber);
    // Refused before anything is stored or charged, and the answer does not
    // say whether the number is one this server knows: a caller outside the
    // allowed countries learns only that no text will come.
    if (!c.config.allowsCountry(e164)) {
      c.log.info('sms_country_refused', {'purpose': req.purpose.wire});
      throw const ApiError(
        ErrorCode.smsUnavailable,
        message: 'This server does not send texts to that country.',
      );
    }
    final phoneHash = c.phoneHash(e164);
    if (await c.credentials.isBanned(c.db, phoneHash)) {
      throw const ApiError(ErrorCode.phoneBanned);
    }
    final last = await c.credentials.lastChallengeAt(c.db, phoneHash);
    final now = c.clock.now();
    if (last != null && now.difference(last) < c.config.otpResendAfter) {
      throw ApiError(
        ErrorCode.rateLimited,
        retryAfter: c.config.otpResendAfter - now.difference(last),
      );
    }
    await c.limit(_perPhone, encodeBytes(phoneHash));
    // Charged last, after every check that refuses one number, so a banned
    // or throttled number never spends the budget real sign-ups need.
    final budget = await c.rateLimiter.hit(_dailyBudget, 'all');
    if (!budget.allowed) {
      c.log.warn('sms_budget_exhausted', {});
      throw ApiError(
        ErrorCode.rateLimited,
        message: 'Too many codes requested today; try again tomorrow.',
        retryAfter: budget.retryAfter,
      );
    }

    final id = Uuid.v7(now: now);
    final code = sixDigitCode();
    final expires = now.add(IdentityConfig.otpLifetime);
    await c.credentials.insertChallenge(
      c.db,
      id: id,
      phoneHash: phoneHash,
      purpose: req.purpose.wire,
      codeHash: _codeHash(id, code),
      discoveryIndex: await c.discoveryIndexOf(e164),
      last4: e164.substring(e164.length - 4),
      expiresAt: expires,
    );
    try {
      await c.config.sms.send(
        phoneNumber: e164,
        message:
            'Your Helix code is $code. It expires in 10 minutes. Never share it.',
      );
    } on SmsFailed catch (e) {
      c.log.warn('sms_failed', {'reason': e.reason});
      // The text did not leave, so nothing is spent (AUD-2-1): the number
      // may ask again at once and the server's day is not used up by an
      // outage. Charged first so concurrent callers cannot all pass the
      // budget, refunded here.
      await c.credentials.deleteChallenge(c.db, id);
      await c.rateLimiter.refund(_perPhone, encodeBytes(phoneHash));
      await c.rateLimiter.refund(_dailyBudget, 'all');
      throw const ApiError(
        ErrorCode.smsUnavailable,
        message: 'The text could not be sent.',
      );
    }
    return PhoneChallengeResponse(
      challengeId: id,
      expiresAt: expires,
      resendAfter: c.config.otpResendAfter,
    );
  }

  Uint8List _codeHash(String challengeId, String code) =>
      hmacSha256(c.config.phonePepper, utf8.encode('otp:$challengeId:$code'));

  /// Checks a code (at most [IdentityConfig.otpMaxAttempts] tries) and
  /// returns a single-use verification token. The request carries no phone
  /// number: the challenge row has its hashes.
  Future<PhoneVerifyResponse> verify(PhoneVerifyRequest req) async {
    if (!Uuid.isValid(req.challengeId)) {
      throw const ApiError(ErrorCode.invalidCode);
    }
    final verified = await c.db.tx<VerifiedPhone?>((tx) async {
      final row = await c.credentials.challengeForUpdate(tx, req.challengeId);
      if (row == null ||
          !row.isNull('consumed_at') ||
          !row.time('expires_at').isAfter(c.clock.now()) ||
          row.integer('attempts') >= IdentityConfig.otpMaxAttempts) {
        return null;
      }
      final match = constantTimeEquals(
        row.bytes('code_hash'),
        _codeHash(req.challengeId, req.code),
      );
      await c.credentials.challengeAttempt(
        tx,
        req.challengeId,
        consumed: match,
      );
      if (!match) return null;
      return VerifiedPhone(
        phoneHash: row.bytes('phone_hash'),
        discoveryIndex: row.string('discovery_index'),
        last4: row.string('last4'),
        purpose: PhonePurpose.values.firstWhere(
          (p) => p.wire == row.string('purpose'),
          orElse: () => PhonePurpose.signIn,
        ),
      );
    });
    if (verified == null) throw const ApiError(ErrorCode.invalidCode);

    final existing = await c.store.accountByPhone(c.db, verified.phoneHash);
    final token = newToken('vt');
    await c.ephemeral.put(
      '${IdentityContext.verificationPrefix}${tokenKey(token)}',
      verified.encode(),
      IdentityConfig.verificationLifetime,
    );
    return PhoneVerifyResponse(
      verificationToken: token,
      expiresAt: c.clock.now().add(IdentityConfig.verificationLifetime),
      accountExists: existing != null,
      hasPassword: existing?.hasPassword ?? false,
      accountId: existing?.id,
    );
  }

  // ----------------------------------------------------------------- invites

  Future<InviteLookupResponse> lookupInvite(InviteLookupRequest req) async {
    final row = await c.credentials.inviteByHash(
      c.db,
      hashToken(req.inviteCode),
    );
    InviteInvalidReason? reason;
    if (row == null) {
      reason = InviteInvalidReason.notFound;
    } else if (!row.isNull('cancelled_at')) {
      reason = InviteInvalidReason.cancelled;
    } else if (!row.isNull('redeemed_at')) {
      reason = InviteInvalidReason.used;
    } else if (!row.time('expires_at').isAfter(c.clock.now())) {
      reason = InviteInvalidReason.expired;
    }
    return InviteLookupResponse(valid: reason == null, reason: reason);
  }

  /// Creates an invite and returns its code (shown once). Admin console
  /// (Phase S6) and Helix Global self-issue use this.
  Future<({String id, String code, DateTime expiresAt})> issueInvite(
    SqlSession db, {
    String issuer = 'admin',
  }) async {
    final code = newToken('inv');
    final id = Uuid.v7();
    final expires = c.clock.now().add(IdentityConfig.inviteLifetime);
    await c.credentials.insertInvite(
      db,
      id: id,
      codeHash: hashToken(code),
      issuer: issuer,
      expiresAt: expires,
    );
    return (id: id, code: code, expiresAt: expires);
  }

  Future<InviteSelfIssueResponse> selfIssueInvite() async {
    if (!c.config.globalMode) {
      throw const ApiError(
        ErrorCode.forbidden,
        message: 'Invites are issued by the operator.',
      );
    }
    final invite = await issueInvite(c.db, issuer: 'self');
    return InviteSelfIssueResponse(
      inviteCode: invite.code,
      expiresAt: invite.expiresAt,
    );
  }
}
