import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:test/test.dart';

import '../support/flows.dart';
import '../support/harness.dart';
import '../support/test_client.dart';
import '../support/test_database.dart';
import '../support/test_socket.dart';

String discoveryHash(List<int> salt, String number) =>
    crypto.Hmac(crypto.sha256, salt).convert(utf8.encode(number)).toString();

void main() {
  group('people', skip: databaseTestSkipReason, () {
    late Harness h;
    late TestDevice alice;
    late TestDevice bob;

    setUp(() async {
      h = await Harness.start();
      alice = await h.registerGlobal(aliceNumber);
      bob = await h.registerGlobal(bobNumber);
    });

    tearDown(() async => h.stop());

    Future<DiscoverResponse> discover(
      TestDevice who,
      List<String> numbers,
    ) async {
      final salt = DiscoverySalt.fromJson(
        (await h.api.call(Routes.discoverySalt, bearer: who.bearer)).json,
      );
      final response = await h.api.call(
        Routes.discover,
        bearer: who.bearer,
        body: DiscoverRequest(
          phoneHashes: [for (final n in numbers) discoveryHash(salt.salt, n)],
        ).toJson(),
      );
      return DiscoverResponse.fromJson(response.json);
    }

    test(
      'discovery matches client-computed hashes, never yourself, within a daily budget',
      () async {
        final result = await discover(alice, [
          bobNumber,
          aliceNumber,
          '+8801711000099',
        ]);
        expect(result.matches.map((m) => m.account), [bob.accountId]);
        expect(result.remainingToday, 5000 - 3);
      },
    );

    test('opting out of phone discovery and blocking hide you', () async {
      await h.api.call(
        Routes.setPrivacy,
        bearer: bob.bearer,
        body: const PrivacySettings(discoverableByPhone: false).toJson(),
      );
      expect((await discover(alice, [bobNumber])).matches, isEmpty);
      await h.api.call(
        Routes.setPrivacy,
        bearer: bob.bearer,
        body: const PrivacySettings().toJson(),
      );
      await h.api.call(
        Routes.block,
        params: {'account': alice.accountId},
        bearer: bob.bearer,
      );
      expect((await discover(alice, [bobNumber])).matches, isEmpty);
    });

    group('discovery storage', () {
      String identitySchema() => h.env.platform.schemas.of('identity');

      Future<String?> storedIndex(
        TestDevice who,
      ) async => (await h.env.platform.db.queryOne(
        'SELECT discovery_index FROM ${identitySchema()}.accounts WHERE id = @id:uuid',
        {'id': who.accountId},
      ))!.optString('discovery_index');

      test('a database dump holds nothing a phone number can be tested '
          'against without the pepper', () async {
        final salt = DiscoverySalt.fromJson(
          (await h.api.call(Routes.discoverySalt, bearer: alice.bearer)).json,
        ).salt;
        final clientHash = discoveryHash(salt, bobNumber);
        final stored = await storedIndex(bob);
        expect(stored, isNotNull);
        expect(stored, isNot(clientHash));
        // Everything the dump offers (the public salt, the stored values) is
        // not enough to reproduce the index from a number.
        final rows = await h.env.platform.db.query(
          'SELECT discovery_index FROM ${identitySchema()}.accounts '
          'UNION ALL SELECT discovery_index FROM ${identitySchema()}.phone_challenges',
        );
        final everything = rows.map((r) => r.optString('discovery_index'));
        expect(everything, isNot(contains(clientHash)));
        // The index is HMAC(K, client hash) with K derived from the pepper:
        // reproducible with the pepper, not with another one.
        String index(List<int> pepper) => crypto.Hmac(
          crypto.sha256,
          crypto.Hmac(
            crypto.sha256,
            pepper,
          ).convert(utf8.encode('helix.v2.discovery-index')).bytes,
        ).convert(utf8.encode(clientHash)).toString();
        expect(
          index(base64Url.decode(base64Url.normalize(testPepper))),
          stored,
        );
        expect(index(utf8.encode('not-the-pepper')), isNot(stored));
        // And the live lookup still works with the real one.
        expect((await discover(alice, [bobNumber])).matches, hasLength(1));
      });

      test('opting out removes the entry; turning it back on needs your own '
          'number', () async {
        await h.api.call(
          Routes.setPrivacy,
          bearer: bob.bearer,
          body: const PrivacySettings(discoverableByPhone: false).toJson(),
        );
        expect(await storedIndex(bob), isNull);
        expect((await discover(alice, [bobNumber])).matches, isEmpty);

        Future<TestResponse> turnOn(String? number) => h.api.call(
          Routes.setPrivacy,
          bearer: bob.bearer,
          body: PrivacySettings(phoneNumber: number).toJson(),
        );
        expect((await turnOn(null)).errorCode, 'invalid_field');
        expect((await turnOn(aliceNumber)).errorCode, 'invalid_field');
        expect(
          await storedIndex(bob),
          isNull,
          reason: 'a failed request changes nothing',
        );
        expect((await discover(alice, [bobNumber])).matches, isEmpty);

        expect((await turnOn(bobNumber)).status, 204);
        expect(await storedIndex(bob), isNotNull);
        expect((await discover(alice, [bobNumber])).matches, hasLength(1));
        // Already on: saving other settings needs no number.
        expect((await turnOn(null)).status, 204);
      });

      test('an account that never had discovery on keeps no entry', () async {
        await h.api.call(
          Routes.setPrivacy,
          bearer: alice.bearer,
          body: const PrivacySettings(discoverableByPhone: false).toJson(),
        );
        expect(await storedIndex(alice), isNull);
        expect((await discover(bob, [aliceNumber])).matches, isEmpty);
      });
    });

    test('helix name lookup respects discoverability and blocks', () async {
      await h.api.call(
        Routes.setHelixName,
        bearer: bob.bearer,
        body: const SetHelixNameRequest(name: 'bobby').toJson(),
      );
      final found = await h.api.call(
        Routes.findByName,
        params: {'name': '~Bobby'},
        bearer: alice.bearer,
      );
      expect(FindByNameResponse.fromJson(found.json).account, bob.accountId);
      await h.api.call(
        Routes.setPrivacy,
        bearer: bob.bearer,
        body: const PrivacySettings(discoverableByName: false).toJson(),
      );
      expect(
        (await h.api.call(
          Routes.findByName,
          params: {'name': 'bobby'},
          bearer: alice.bearer,
        )).status,
        404,
      );
    });

    test('profiles are opaque ciphertext with increasing versions', () async {
      expect(
        (await h.api.call(
          Routes.setOwnProfile,
          bearer: alice.bearer,
          body: EncryptedProfile(version: 1, ciphertext: bytes(80)).toJson(),
        )).status,
        204,
      );
      final stale = await h.api.call(
        Routes.setOwnProfile,
        bearer: alice.bearer,
        body: EncryptedProfile(version: 1, ciphertext: bytes(80, 2)).toJson(),
      );
      expect(stale.errorCode, 'version_conflict');
      final read = EncryptedProfile.fromJson(
        (await h.api.call(
          Routes.profile,
          params: {'account': alice.accountId},
          bearer: bob.bearer,
        )).json,
      );
      expect(read.ciphertext, bytes(80));
      expect(read.version, 1);
    });

    test('blocks stop messages silently, in the real block policy', () async {
      await h.api.call(
        Routes.block,
        params: {'account': alice.accountId},
        bearer: bob.bearer,
      );
      expect(
        BlockList.fromJson(
          (await h.api.call(Routes.blocks, bearer: bob.bearer)).json,
        ).accounts,
        [alice.accountId],
      );
      final sent = await send(h, alice, {
        bob.accountId: [bob.id],
      });
      expect(sent.status, 200, reason: 'the sender is not told');
      expect(
        (await mailbox(
          h,
          bob,
        )).envelopes.where((e) => e.kind == EnvelopeKind.message),
        isEmpty,
      );
      await h.api.call(
        Routes.unblock,
        params: {'account': alice.accountId},
        bearer: bob.bearer,
      );
      await send(h, alice, {
        bob.accountId: [bob.id],
      });
      expect(
        (await mailbox(
          h,
          bob,
        )).envelopes.where((e) => e.kind == EnvelopeKind.message),
        hasLength(1),
      );
    });

    test('presence follows audiences: everyone, contacts, nobody', () async {
      final socket = await TestSocket.connect(h.server.baseUri, bob.bearer);
      await socket.hello();
      Future<PresenceResponse> look() async => PresenceResponse.fromJson(
        (await h.api.call(
          Routes.presence,
          params: {'account': bob.accountId},
          bearer: alice.bearer,
        )).json,
      );
      expect((await look()).online, isTrue);

      await h.api.call(
        Routes.setPrivacy,
        bearer: bob.bearer,
        body: const PrivacySettings(
          online: Audience.contacts,
          lastSeen: Audience.contacts,
        ).toJson(),
      );
      expect(
        (await look()).online,
        isFalse,
        reason: 'alice is not in bob\'s contacts',
      );
      await h.api.call(
        Routes.setContacts,
        bearer: bob.bearer,
        body: SetContactsRequest(accounts: [alice.accountId]).toJson(),
      );
      expect((await look()).online, isTrue);

      await socket.close();
      late PresenceResponse offline;
      await eventually(() async {
        offline = await look();
        expect(offline.online, isFalse);
        expect(offline.lastSeenAt, isNotNull);
      });
      expect(offline.lastSeenAt!.second, 0, reason: 'minute granularity');

      await h.api.call(
        Routes.setPrivacy,
        bearer: bob.bearer,
        body: const PrivacySettings(
          online: Audience.nobody,
          lastSeen: Audience.nobody,
        ).toJson(),
      );
      expect((await look()).lastSeenAt, isNull);
    });

    test('reports are stored without content', () async {
      final r = await h.api.call(
        Routes.report,
        bearer: alice.bearer,
        body: ReportRequest(
          account: bob.accountId,
          category: ReportCategory.spam,
          note: 'sends links',
        ).toJson(),
      );
      expect(r.status, 201);
      expect(Uuid.isValid(ReportResponse.fromJson(r.json).reportId), isTrue);
    });
  });
}
