import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/helix_remote_server.dart';
import 'package:helix_remote_server/src/modules/identity/module.dart';
import 'package:helix_remote_server/src/modules/identity/sms.dart';

import 'test_client.dart';
import 'test_platform.dart';

const testPepper = 'cGVwcGVyLWZvci10ZXN0cy1vbmx5LTMyLWJ5dGVzLWxvbmc';

/// A running server with every module, a recording SMS provider and a
/// client, on a fresh schema prefix.
final class Harness {
  Harness._(this.env, this.server, this.sms, this.api);

  final TestPlatform env;
  final HelixServer server;
  final RecordingSmsProvider sms;
  final TestApi api;

  IdentityModule get identity =>
      server.modules.whereType<IdentityModule>().single;

  static Future<Harness> start({
    bool global = true,
    Map<String, String> extra = const {},
  }) async {
    final env = await TestPlatform.open(
      extra: {
        'HELIX_PHONE_PEPPER': testPepper,
        'HELIX_GLOBAL_MODE': '$global',
        'HELIX_OTP_RESEND_SECONDS': '0',
        ...extra,
      },
    );
    final sms = RecordingSmsProvider();
    final server = await HelixServer.start(env.platform, allModules(sms: sms));
    return Harness._(env, server, sms, TestApi(server.baseUri));
  }

  Future<void> stop() async {
    api.close();
    await server.stop();
    await env.dispose();
  }

  /// Phone challenge + verify; returns the verification response.
  Future<PhoneVerifyResponse> verifyPhone(
    String number, {
    PhonePurpose purpose = PhonePurpose.register,
  }) async {
    final challenge = await api.call(
      Routes.phoneChallenge,
      body: PhoneChallengeRequest(
        phoneNumber: number,
        purpose: purpose,
      ).toJson(),
    );
    if (challenge.status != 200) {
      throw StateError('challenge failed: $challenge');
    }
    final id = PhoneChallengeResponse.fromJson(challenge.json).challengeId;
    final verify = await api.call(
      Routes.phoneVerify,
      body: PhoneVerifyRequest(
        challengeId: id,
        code: sms.lastCodeFor(number),
      ).toJson(),
    );
    if (verify.status != 200) throw StateError('verify failed: $verify');
    return PhoneVerifyResponse.fromJson(verify.json);
  }

  /// Registers a new account on Helix Global with [number]; returns its
  /// first device (with a session).
  Future<TestDevice> registerGlobal(
    String number, {
    TestAccount? account,
    int oneTime = 25,
  }) async {
    final verified = await verifyPhone(number);
    final acct = account ?? await TestAccount.create();
    final device = await acct.newDevice();
    final response = await api.call(
      Routes.register,
      body: RegisterRequest(
        accountId: acct.id,
        identityKey: acct.publicKey,
        device: await device.registration(),
        prekeys: await device.prekeys(oneTime: oneTime),
        verificationToken: verified.verificationToken,
        termsVersion: '2026-09',
      ).toJson(),
    );
    if (response.status != 201) throw StateError('register failed: $response');
    device.session = RegisterResponse.fromJson(response.json).session;
    return device;
  }
}
