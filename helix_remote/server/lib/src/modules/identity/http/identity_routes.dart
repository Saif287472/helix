import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/src/modules/identity/application/accounts.dart';
import 'package:helix_remote_server/src/modules/identity/application/registration.dart';
import 'package:helix_remote_server/src/modules/identity/application/sign_in.dart';
import 'package:helix_remote_server/src/modules/identity/application/sign_up.dart';
import 'package:helix_remote_server/src/platform/http/request.dart';
import 'package:helix_remote_server/src/platform/http/routes.dart';
import 'package:helix_remote_server/src/platform/ratelimit/rate_limiter.dart';

/// Per-IP limits for the public identity routes.
abstract final class IdentityLimits {
  static final otp = RateLimitPolicy.per(
    'identity.otp',
    10,
    const Duration(hours: 1),
  );
  static final verify = RateLimitPolicy.per(
    'identity.verify',
    30,
    const Duration(hours: 1),
  );
  static final invite = RateLimitPolicy.per(
    'identity.invite',
    30,
    const Duration(hours: 1),
  );
  static final selfInvite = RateLimitPolicy.per(
    'identity.self_invite',
    3,
    const Duration(hours: 1),
  );
  static final register = RateLimitPolicy.per(
    'identity.register',
    10,
    const Duration(hours: 1),
  );
  static final password = RateLimitPolicy.per(
    'identity.password',
    30,
    const Duration(hours: 1),
  );
  static final link = RateLimitPolicy.per(
    'identity.link',
    20,
    const Duration(hours: 1),
  );
  static final linkPoll = RateLimitPolicy.per(
    'identity.link_poll',
    600,
    const Duration(hours: 1),
  );
  static final addDevice = RateLimitPolicy.per(
    'identity.add_device',
    20,
    const Duration(hours: 1),
  );
  static final challenge = RateLimitPolicy.per(
    'identity.challenge',
    60,
    const Duration(hours: 1),
  );
  static final refresh = RateLimitPolicy.per(
    'identity.refresh',
    600,
    const Duration(hours: 1),
  );
  static final recovery = RateLimitPolicy.per(
    'identity.recovery',
    10,
    const Duration(hours: 1),
  );
}

void registerIdentityRoutes(
  RouteRegistry r, {
  required SignUp signUp,
  required Registration registration,
  required SignIn signIn,
  required Accounts accounts,
}) {
  const m = 'identity';

  // Public.
  r
    ..add(
      m,
      Routes.phoneChallenge,
      rateLimit: IdentityLimits.otp,
      (q) async => jsonResponse(
        (await signUp.requestPhoneChallenge(
          q.json(PhoneChallengeRequest.fromJson),
        )).toJson(),
      ),
    )
    ..add(
      m,
      Routes.phoneVerify,
      rateLimit: IdentityLimits.verify,
      (q) async => jsonResponse(
        (await signUp.verify(q.json(PhoneVerifyRequest.fromJson))).toJson(),
      ),
    )
    ..add(
      m,
      Routes.inviteLookup,
      rateLimit: IdentityLimits.invite,
      (q) async => jsonResponse(
        (await signUp.lookupInvite(
          q.json(InviteLookupRequest.fromJson),
        )).toJson(),
      ),
    )
    ..add(
      m,
      Routes.inviteSelfIssue,
      rateLimit: IdentityLimits.selfInvite,
      (q) async => jsonResponse((await signUp.selfIssueInvite()).toJson()),
    )
    ..add(
      m,
      Routes.register,
      rateLimit: IdentityLimits.register,
      maxBodyBytes: 256 * 1024,
      (q) async => jsonResponse(
        (await registration.register(
          q.json(RegisterRequest.fromJson),
        )).toJson(),
        status: 201,
      ),
    )
    ..add(
      m,
      Routes.passwordParams,
      rateLimit: IdentityLimits.password,
      (q) async => jsonResponse(
        (await signIn.params(q.json(PasswordParamsRequest.fromJson))).toJson(),
      ),
    )
    ..add(
      m,
      Routes.passwordSignIn,
      rateLimit: IdentityLimits.password,
      (q) async => jsonResponse(
        (await signIn.signIn(q.json(PasswordSignInRequest.fromJson))).toJson(),
      ),
    )
    ..add(
      m,
      Routes.linkCreate,
      rateLimit: IdentityLimits.link,
      (q) async => jsonResponse(
        (await signIn.createLink(q.json(LinkCreateRequest.fromJson))).toJson(),
        status: 201,
      ),
    )
    ..add(m, Routes.linkPoll, rateLimit: IdentityLimits.linkPoll, (q) async {
      final header = q.raw.headers[HelixHeaders.authorization];
      final bearer =
          header != null && header.toLowerCase().startsWith('bearer ')
          ? header.substring(7).trim()
          : null;
      final wait = (int.tryParse(q.query('wait_s') ?? '') ?? 0).clamp(0, 30);
      return jsonResponse(
        (await signIn.pollLink(
          q.uuidParam('link_id'),
          bearer,
          Duration(seconds: wait),
        )).toJson(),
      );
    })
    ..add(
      m,
      Routes.addDevice,
      rateLimit: IdentityLimits.addDevice,
      maxBodyBytes: 256 * 1024,
      (q) async => jsonResponse(
        (await signIn.addDevice(q.json(AddDeviceRequest.fromJson))).toJson(),
        status: 201,
      ),
    )
    ..add(
      m,
      Routes.deviceChallenge,
      rateLimit: IdentityLimits.challenge,
      (q) async => jsonResponse(
        (await signIn.challenge(
          q.json(DeviceChallengeRequest.fromJson),
        )).toJson(),
      ),
    )
    ..add(
      m,
      Routes.deviceSignIn,
      rateLimit: IdentityLimits.challenge,
      (q) async => jsonResponse(
        (await signIn.deviceSignIn(
          q.json(DeviceSignInRequest.fromJson),
        )).toJson(),
      ),
    )
    ..add(
      m,
      Routes.refreshSession,
      rateLimit: IdentityLimits.refresh,
      (q) async => jsonResponse(
        (await signIn.c.sessions.refresh(
          signIn.c.db,
          signIn.c.store,
          q.json(RefreshRequest.fromJson).refreshToken,
        )).toJson(),
      ),
    )
    ..add(
      m,
      Routes.recoveryLookup,
      rateLimit: IdentityLimits.recovery,
      (q) async => jsonResponse(
        (await registration.lookup(
          q.json(RecoveryLookupRequest.fromJson),
        )).toJson(),
      ),
    )
    ..add(
      m,
      Routes.recoveryRedeem,
      rateLimit: IdentityLimits.recovery,
      maxBodyBytes: 256 * 1024,
      (q) async => jsonResponse(
        (await registration.redeem(
          q.json(RecoveryRedeemRequest.fromJson),
        )).toJson(),
      ),
    );

  // Signed in.
  r
    ..add(m, Routes.signOut, allowSuspended: true, (q) async {
      await accounts.signOut(q.device);
      return noContent();
    })
    ..add(
      m,
      Routes.account,
      allowSuspended: true,
      (q) async => jsonResponse((await accounts.info(q.device)).toJson()),
    )
    ..add(m, Routes.setPassword, (q) async {
      await accounts.setPassword(q.device, q.json(SetPasswordRequest.fromJson));
      return noContent();
    })
    ..add(m, Routes.setHelixName, (q) async {
      await accounts.setHelixName(
        q.device,
        q.json(SetHelixNameRequest.fromJson),
      );
      return noContent();
    })
    ..add(m, Routes.clearHelixName, (q) async {
      await accounts.clearHelixName(q.device);
      return noContent();
    })
    ..add(m, Routes.securityEvents, allowSuspended: true, (q) async {
      final page = await accounts.events(
        q.device,
        PageRequest.fromQuery(q.raw.url.queryParameters),
      );
      return jsonResponse(page.toJson((e) => e.toJson()));
    })
    ..add(
      m,
      Routes.devices,
      allowSuspended: true,
      (q) async => jsonResponse((await accounts.devices(q.device)).toJson()),
    )
    ..add(m, Routes.renameDevice, (q) async {
      await accounts.rename(
        q.device,
        q.uuidParam('device_id'),
        q.json(RenameDeviceRequest.fromJson),
      );
      return noContent();
    })
    ..add(m, Routes.revokeDevice, allowSuspended: true, (q) async {
      await accounts.revoke(
        q.device,
        q.uuidParam('device_id'),
        lost: q.query('reason') == 'lost',
      );
      return noContent();
    })
    ..add(
      m,
      Routes.revokeOtherDevices,
      allowSuspended: true,
      (q) async => jsonResponse(
        RevokeOthersResponse(
          revoked: await accounts.revokeOthers(q.device),
        ).toJson(),
      ),
    )
    ..add(m, Routes.approveLink, (q) async {
      await signIn.approveLink(
        q.device,
        q.uuidParam('link_id'),
        q.json(LinkApproveRequest.fromJson),
      );
      return noContent();
    })
    ..add(m, Routes.setPushToken, allowSuspended: true, (q) async {
      await accounts.setPushToken(q.device, q.json(PushTokenRequest.fromJson));
      return noContent();
    })
    ..add(m, Routes.clearPushToken, allowSuspended: true, (q) async {
      await accounts.clearPushToken(q.device);
      return noContent();
    });
}
