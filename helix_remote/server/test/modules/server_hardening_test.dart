import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/src/modules/identity/config.dart';
import 'package:helix_remote_server/src/platform/config/server_config.dart';
import 'package:helix_remote_server/src/platform/ratelimit/rate_limiter.dart';
import 'package:test/test.dart';

import '../support/flows.dart';
import '../support/harness.dart';
import '../support/test_client.dart';
import '../support/test_database.dart';
import '../support/test_platform.dart';

const carolNumber = '+8801711000003';
const usNumber = '+12025550123';

/// Server hardening that needs no protocol change (review 2026-10-09,
/// batch 5: A-05, A-06, A-11, A-12; A-04, A-07 and A-08 are in
/// `platform/jobs_test.dart` and `platform/db_test.dart`).
void main() {
  group('HELIX_SMS_DAILY_LIMIT and HELIX_SMS_COUNTRIES', () {
    IdentityConfig identityConfig({String? limit, String? countries}) =>
        IdentityConfig.from(
          ServerConfig.fromEnv({
            'HELIX_DATABASE_URL': 'postgresql://u:p@localhost/db',
            'HELIX_JWT_KEYS': '{"test":"$testJwtKey"}',
            'HELIX_PHONE_PEPPER': testPepper,
            'HELIX_SMS_DAILY_LIMIT': ?limit,
            'HELIX_SMS_COUNTRIES': ?countries,
          }),
        );

    test('500 a day to Bangladesh unless set', () {
      final config = identityConfig();
      expect(config.smsDailyLimit, 500);
      expect(config.smsCountries, {'880'});
      expect(config.allowsCountry(aliceNumber), isTrue);
      expect(config.allowsCountry(usNumber), isFalse);
      expect(identityConfig(countries: ' ').smsCountries, {'880'});
    });

    test('a list of countries, or * for every country', () {
      final some = identityConfig(countries: '880, +971');
      expect(some.smsCountries, {'880', '971'});
      expect(some.allowsCountry('+971501234567'), isTrue);
      expect(some.allowsCountry(usNumber), isFalse);
      final every = identityConfig(countries: '*');
      expect(every.smsCountries, isEmpty);
      expect(every.allowsCountry(usNumber), isTrue);
      expect(identityConfig(limit: '2000').smsDailyLimit, 2000);
    });

    test('bad values stop the server', () {
      for (final bad in ['0', '-1', 'many', '2000000']) {
        expect(
          () => identityConfig(limit: bad),
          throwsA(isA<ConfigError>()),
          reason: bad,
        );
      }
      for (final bad in ['bd', '0880', '1234', ',', '880;971', '*,880']) {
        expect(
          () => identityConfig(countries: bad),
          throwsA(isA<ConfigError>()),
          reason: bad,
        );
      }
    });
  });

  group('server hardening', skip: databaseTestSkipReason, () {
    late Harness h;

    tearDown(() async => h.stop());

    /// Empties [policy]'s bucket for [key]. A charge larger than what is left
    /// is refused without taking anything, so big bites first, then smaller.
    Future<void> drain(RateLimitPolicy policy, String key) async {
      final limiter = h.env.platform.rateLimiter;
      for (var bite = policy.capacity; bite >= 1; bite ~/= 2) {
        while ((await limiter.hit(policy, key, cost: bite)).allowed) {}
      }
    }

    Future<TestResponse> requestCode(String number) => h.api.call(
      Routes.phoneChallenge,
      body: PhoneChallengeRequest(
        phoneNumber: number,
        purpose: PhonePurpose.register,
      ).toJson(),
    );

    test('texts go only to allowed countries, and the daily budget is charged '
        'only for texts that are sent', () async {
      h = await Harness.start(
        extra: {'HELIX_SMS_DAILY_LIMIT': '2', 'HELIX_OTP_RESEND_SECONDS': '30'},
      );
      final abroad = await requestCode(usNumber);
      expect(abroad.status, 503);
      expect(abroad.errorCode, 'sms_unavailable');

      expect((await requestCode(aliceNumber)).status, 200);
      expect(
        (await requestCode(aliceNumber)).errorCode,
        'rate_limited',
        reason: 'the resend gap refuses before the budget is charged',
      );
      expect((await requestCode(bobNumber)).status, 200);
      final over = await requestCode(carolNumber);
      expect(over.errorCode, 'rate_limited', reason: 'two texts a day');
      expect(int.parse(over.headers['retry-after']!), greaterThan(0));
      expect(h.sms.sent.map((s) => s.phoneNumber), [aliceNumber, bobNumber]);
    });

    test('a number without a password answers like one with a password: a '
        '32-byte salt and the same lockout', () async {
      h = await Harness.start();
      // An account without a password, and a number with no account.
      await h.registerGlobal(aliceNumber);
      for (final number in [aliceNumber, bobNumber]) {
        final params = PasswordParamsResponse.fromJson(
          (await h.api.call(
            Routes.passwordParams,
            body: PasswordParamsRequest(phoneNumber: number).toJson(),
          )).json,
        );
        expect(params.salt, hasLength(32), reason: number);
        expect(params.kdf.toJson(), const KdfParams().toJson());
      }

      Future<TestResponse> signIn() => h.api.call(
        Routes.passwordSignIn,
        body: PasswordSignInRequest(
          phoneNumber: bobNumber,
          authKey: bytes(32, 7),
        ).toJson(),
      );
      final codes = [for (var i = 0; i < 6; i++) (await signIn()).errorCode];
      expect(codes.take(4), everyElement('invalid_credentials'));
      expect(
        codes.skip(4),
        everyElement('password_locked'),
        reason: 'a real account locks after five failures too',
      );
      final locked = await signIn();
      expect(
        int.parse(locked.headers['retry-after']!),
        inInclusiveRange(1, 15 * 60),
      );
    });

    test('a few accounts cannot use up the bundle fetches of a victim, and get '
        'one one-time prekey per device an hour', () async {
      h = await Harness.start();
      final victim = await h.registerGlobal(aliceNumber, oneTime: 30);
      final attacker = await h.registerGlobal(bobNumber);
      final other = await h.registerGlobal(carolNumber);
      Future<TestResponse> fetch(TestDevice who) => h.api.call(
        Routes.accountKeys,
        params: {'account': victim.accountId},
        bearer: who.bearer,
      );
      OneTimePrekey? oneTime(TestResponse r) =>
          AccountKeys.fromJson(r.json).devices.single.oneTimePrekey;

      // What the attack used to empty: the per-target bucket every
      // requester shared. Local fetches no longer use it.
      await drain(
        RateLimitPolicy.per(
          'keys.bundle_target',
          600,
          const Duration(hours: 1),
        ),
        victim.accountId,
      );
      final first = await fetch(other);
      expect(first.status, 200);
      expect(oneTime(first), isNotNull);

      final fetched = [for (var i = 0; i < 20; i++) await fetch(attacker)];
      expect(fetched.map((r) => r.status), everyElement(200));
      expect(oneTime(fetched.first), isNotNull);
      expect(
        fetched.skip(1).map(oneTime),
        everyElement(isNull),
        reason: 'one one-time prekey per requesting account an hour',
      );
      expect(
        (await fetch(attacker)).errorCode,
        'rate_limited',
        reason: '20 fetches per (requester, target) an hour',
      );

      final again = await fetch(other);
      expect(again.status, 200, reason: 'other requesters are unaffected');
      expect(oneTime(again), isNull);
      final status = KeyStatus.fromJson(
        (await h.api.call(Routes.keyStatus, bearer: victim.bearer)).json,
      );
      expect(status.oneTimeRemaining, 28, reason: 'one each, not 22');
    });

    test('reading other people is limited per minute and per distinct person a '
        'day; reading yourself is free', () async {
      h = await Harness.start();
      final alice = await h.registerGlobal(aliceNumber);
      final bob = await h.registerGlobal(bobNumber);
      final carol = await h.registerGlobal(carolNumber);
      Future<TestResponse> presence(TestDevice reader, TestDevice target) =>
          h.api.call(
            Routes.presence,
            params: {'account': target.accountId},
            bearer: reader.bearer,
          );
      expect((await presence(alice, bob)).status, 200);
      await drain(
        RateLimitPolicy.per(
          'people.read_targets',
          2000,
          const Duration(days: 1),
        ),
        alice.accountId,
      );
      expect(
        (await presence(alice, bob)).status,
        200,
        reason: 'bob was already seen today',
      );
      expect((await presence(alice, carol)).errorCode, 'rate_limited');
      expect(
        (await h.api.call(
          Routes.profile,
          params: {'account': carol.accountId},
          bearer: alice.bearer,
        )).errorCode,
        'rate_limited',
        reason: 'profiles count too',
      );
      expect(
        await h.env.platform.ephemeral.get(
          'people:seen:${alice.accountId}:${carol.accountId}',
        ),
        isNull,
        reason: 'a refused read does not mark carol as seen',
      );
      expect((await presence(bob, carol)).status, 200);

      // The per-minute budget refills two tokens a second, so drain it
      // right before each try.
      final reads = RateLimitPolicy.per(
        'people.reads',
        120,
        const Duration(minutes: 1),
      );
      TestResponse? refused;
      for (var i = 0; i < 3 && refused == null; i++) {
        await drain(reads, alice.accountId);
        final r = await presence(alice, bob);
        if (r.status == 429) refused = r;
      }
      expect(refused?.errorCode, 'rate_limited');
      expect(
        (await presence(alice, alice)).status,
        200,
        reason: 'your own presence is free',
      );
    });
  });
}
