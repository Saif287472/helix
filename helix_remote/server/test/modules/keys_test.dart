import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/src/modules/keys/module.dart';
import 'package:test/test.dart';

import '../support/harness.dart';
import '../support/test_database.dart';

void main() {
  group('keys', skip: databaseTestSkipReason, () {
    late Harness h;

    setUp(() async => h = await Harness.start());
    tearDown(() async => h.stop());

    KeysModule keys() => h.server.modules.whereType<KeysModule>().single;

    test(
      'bundles hand out each one-time prekey once and signal when low',
      () async {
        final alice = await h.registerGlobal('+8801711000001', oneTime: 21);
        // Three requesters: one account gets one one-time prekey per device
        // an hour (server_hardening_test.dart).
        final others = [
          for (final n in ['2', '3', '4'])
            await h.registerGlobal('+880171100000$n'),
        ];
        final low = <(String, int)>[];
        keys().api.onPrekeysLow(
          (device, remaining) async => low.add((device, remaining)),
        );

        final seen = <int>{};
        for (final other in others) {
          final bundle = AccountKeys.fromJson(
            (await h.api.call(
              Routes.accountKeys,
              params: {'account': alice.accountId},
              bearer: other.bearer,
            )).json,
          );
          final device = bundle.devices.single;
          expect(device.deviceId, alice.id);
          expect(device.identityKey, alice.dikPublic);
          expect(device.signingKey, alice.dskPublic);
          expect(
            seen.add(device.oneTimePrekey!.id),
            isTrue,
            reason: 'never handed out twice',
          );
          expect(bundle.identityKey, alice.account.publicKey);
        }
        expect(low, [(alice.id, 19)], reason: 'below 20, signalled once');

        final status = KeyStatus.fromJson(
          (await h.api.call(Routes.keyStatus, bearer: alice.bearer)).json,
        );
        expect(status.oneTimeRemaining, 18);
        expect(status.signedPrekeyId, isNotNull);
      },
    );

    /// A fetch that finds no one-time prekey must not use up the hour's gap:
    /// the next fetch, after the target uploads more, gets one (AUD-2-6).
    test('the one-time gap is spent only when a key was handed out', () async {
      final alice = await h.registerGlobal('+8801711000001', oneTime: 0);
      final bob = await h.registerGlobal('+8801711000002');
      Future<AccountKeys> fetch() async => AccountKeys.fromJson(
        (await h.api.call(
          Routes.accountKeys,
          params: {'account': alice.accountId},
          bearer: bob.bearer,
        )).json,
      );
      expect((await fetch()).devices.single.oneTimePrekey, isNull);
      await h.api.call(
        Routes.addOneTimePrekeys,
        bearer: alice.bearer,
        body: AddOneTimePrekeysRequest(
          keys: await alice.oneTimePrekeys(5),
        ).toJson(),
      );
      expect((await fetch()).devices.single.oneTimePrekey, isNotNull);
      expect(
        (await fetch()).devices.single.oneTimePrekey,
        isNull,
        reason: 'the gap still holds once a key went out',
      );
    });

    test(
      'the certificate in a bundle verifies under the account key',
      () async {
        final alice = await h.registerGlobal('+8801711000001');
        final bob = await h.registerGlobal('+8801711000002');
        final bundle = AccountKeys.fromJson(
          (await h.api.call(
            Routes.accountKeys,
            params: {'account': alice.accountId},
            bearer: bob.bearer,
          )).json,
        );
        final d = bundle.devices.single;
        final reg = await alice.registration(at: d.certificate.createdAt);
        expect(d.certificate.createdAt, isNotNull);
        expect(reg.identityKey, d.identityKey);
      },
    );

    test(
      'signed prekey updates are signature-checked; uploads are capped',
      () async {
        final alice = await h.registerGlobal('+8801711000001');
        final bad = await h.api.call(
          Routes.setSignedPrekey,
          bearer: alice.bearer,
          body: (await alice.signedPrekey(badSignature: true)).toJson(),
        );
        expect(bad.errorCode, 'invalid_field');
        final good = await h.api.call(
          Routes.setSignedPrekey,
          bearer: alice.bearer,
          body: (await alice.signedPrekey(id: 500)).toJson(),
        );
        expect(good.status, 204);
        expect(
          KeyStatus.fromJson(
            (await h.api.call(Routes.keyStatus, bearer: alice.bearer)).json,
          ).signedPrekeyId,
          500,
        );

        final added = await h.api.call(
          Routes.addOneTimePrekeys,
          bearer: alice.bearer,
          body: AddOneTimePrekeysRequest(
            keys: await alice.oneTimePrekeys(100),
          ).toJson(),
        );
        expect(KeyStatus.fromJson(added.json).oneTimeRemaining, 125);

        for (var i = 0; i < 8; i++) {
          await h.api.call(
            Routes.addOneTimePrekeys,
            bearer: alice.bearer,
            body: AddOneTimePrekeysRequest(
              keys: await alice.oneTimePrekeys(100),
            ).toJson(),
          );
        }
        final over = await h.api.call(
          Routes.addOneTimePrekeys,
          bearer: alice.bearer,
          body: AddOneTimePrekeysRequest(
            keys: await alice.oneTimePrekeys(100),
          ).toJson(),
        );
        expect(over.errorCode, 'quota_exceeded');
      },
    );

    test('unknown and federated accounts are not found', () async {
      final bob = await h.registerGlobal('+8801711000002');
      expect(
        (await h.api.call(
          Routes.accountKeys,
          params: {'account': Uuid.v7()},
          bearer: bob.bearer,
        )).status,
        404,
      );
      expect(
        (await h.api.call(
          Routes.accountKeys,
          params: {'account': 'x@other.example'},
          bearer: bob.bearer,
        )).status,
        404,
      );
    });
  });
}
