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

  // ------------------------------------------------------------ phone codes

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

    final id = Uuid.v7(now: now);
    final code = sixDigitCode();
    final expires = now.add(IdentityConfig.otpLifetime);
    await c.credentials.insertChallenge(
      c.db,
      id: id,
      phoneHash: phoneHash,
      purpose: req.purpose.wire,
      codeHash: _codeHash(id, code),
      discoveryHash: await c.discoveryHash(e164),
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
        discoveryHash: row.string('discovery_hash'),
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
