import 'dart:convert';
import 'dart:typed_data';

import 'package:helix_remote_crypto/v2.dart';
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart';
import 'package:helix_remote_engine/src/backup/full_backup.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:test/test.dart';

import 'support.dart';

/// The manual full backup (CRYPTO_V2.md §13, F2): envelope v3 with the account
/// identity key inside, sealed under the user's recovery secret.
void main() {
  late BackupWorld world;
  late BackupPeer alice;

  const secret = 'correct horse battery staple';
  const bobId = 'bbbbbbbb-0000-4000-8000-000000000001';

  setUp(() async {
    world = BackupWorld();
    alice = await world.register('alice', phone: '+8801711000001');
    await addHistory(alice, bobId, 8, prefix: 'full');
  });
  tearDown(() => world.dispose());

  Future<BackupException> failureOf(Future<Object?> action) async {
    try {
      await action;
    } on BackupException catch (e) {
      return e;
    }
    fail('expected a BackupException');
  }

  test('create, upload, download and restore on another device', () async {
    final phases = <BackupPhase>[];
    final sub = alice.backup.backupProgress.listen((p) {
      expect(p.full, isTrue);
      phases.add(p.phase);
    });
    final media = ['22222222-2222-4222-8222-222222222222'];
    final result = await alice.backup.createFullBackup(
      recoverySecret: secret,
      mediaIds: media,
    );
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(result.version, 1);
    expect(result.messages, 8);
    expect(
      phases,
      containsAllInOrder([
        BackupPhase.preparing,
        BackupPhase.uploading,
        BackupPhase.done,
      ]),
    );
    final stored = world.remote.fullStored!;
    expect(stored.version, 1);
    expect(stored.mediaIds, media);
    expect((await alice.backup.status()).fullVersion, 1);

    // The envelope is v3, carries no forbidden field at any depth and never
    // the recovery secret, the identity key or the profile key in clear.
    final text = jsonEncode(stored.envelope);
    expect(stored.envelope['format'], 'helix.v2.backup');
    expect(stored.envelope['v'], 3);
    expect(FullBackupJob.carriesForbiddenField(stored.envelope), isFalse);
    expect(text, isNot(contains(secret)));
    final identity = (await alice.db.cryptoDao.identityKeys())!;
    expect(text, isNot(contains(encodeBytes(identity.aikPrivate))));
    expect(
      text,
      isNot(
        contains(
          encodeBytes((await alice.db.accountDao.current())!.profileKey!),
        ),
      ),
    );
    // Both the payload and the wrap are bound to the id and version.
    final envelope = BackupEnvelope.fromJson(JsonReader.of(stored.envelope));
    expect(envelope.backupId, stored.backupId);
    expect(envelope.backupVersion, 1);
    expect(envelope.keyWraps.single.method, BackupKeyWrapMethod.recoverySecret);

    final second = await world.link(alice, 'alice2');
    final restored = await second.backup.restoreFullBackup(
      recoverySecret: secret,
    );
    expect(restored.result.added, 8);
    expect(restored.identityMatches, isTrue);
    expect(restored.secrets!.identityKeySeed, identity.aikPrivate);
    expect(
      restored.secrets!.profileKey,
      (await alice.db.accountDao.current())!.profileKey,
    );
    expect(restored.secrets.toString(), 'ArchiveSecrets(<redacted>)');
    expect(await historyDigest(second), await historyDigest(alice));
  });

  test('a weak recovery secret is refused before anything is sent', () async {
    final e = await failureOf(
      alice.backup.createFullBackup(recoverySecret: 'too short'),
    );
    expect(e.failure, BackupFailure.weakSecret);
    expect(world.remote.fullPuts, 0);
    // Six words are enough.
    await alice.backup.createFullBackup(
      recoverySecret: 'one two three four five six',
    );
    expect(world.remote.fullPuts, 1);
  });

  test('a wrong secret opens nothing and imports nothing', () async {
    await alice.backup.createFullBackup(recoverySecret: secret);
    final second = await world.link(alice, 'alice2');
    final e = await failureOf(
      second.backup.restoreFullBackup(
        recoverySecret: 'a different secret entirely',
      ),
    );
    expect(e.failure, BackupFailure.wrongKey);
    expect(await HistoryStore(second.db).messageCount(), 0);
  });

  test('the platform key opens it too; a wrong one does not', () async {
    final platform = Uint8List(32)..fillRange(0, 32, 3);
    await alice.backup.createFullBackup(
      recoverySecret: secret,
      platformKey: platform,
    );
    final second = await world.link(alice, 'alice2');
    final wrong = await failureOf(
      second.backup.restoreFullBackup(platformKey: Uint8List(32)),
    );
    expect(wrong.failure, BackupFailure.wrongKey);
    final ok = await second.backup.restoreFullBackup(platformKey: platform);
    expect(ok.result.added, 8);
  });

  test('metadata the server cannot change: id, version, ciphertext', () async {
    await alice.backup.createFullBackup(recoverySecret: secret);
    final good = world.remote.fullStored!;
    final second = await world.link(alice, 'alice2');

    FullBackup served({
      String? id,
      int? version,
      Map<String, Object?>? envelope,
    }) => FullBackup(
      backupId: id ?? good.backupId,
      version: version ?? good.version,
      envelope: envelope ?? good.envelope,
      mediaIds: good.mediaIds,
    );

    // The server reports another version or id than the sealed envelope.
    world.remote.fullStored = served(version: 7);
    expect(
      (await failureOf(
        second.backup.restoreFullBackup(recoverySecret: secret),
      )).failure,
      BackupFailure.corrupt,
    );
    world.remote.fullStored = served(
      id: '33333333-3333-4333-8333-333333333333',
    );
    expect(
      (await failureOf(
        second.backup.restoreFullBackup(recoverySecret: secret),
      )).failure,
      BackupFailure.corrupt,
    );
    // The envelope itself is rewritten to say version 7: the AEAD's
    // associated data no longer matches.
    world.remote.fullStored = served(
      version: 7,
      envelope: {...good.envelope, 'version': 7},
    );
    expect(
      (await failureOf(
        second.backup.restoreFullBackup(recoverySecret: secret),
      )).failure,
      BackupFailure.wrongKey,
    );
    // A flipped ciphertext byte.
    final bytes = decodeBytes(good.envelope['ciphertext']! as String)
      ..[10] ^= 1;
    world.remote.fullStored = served(
      envelope: {...good.envelope, 'ciphertext': encodeBytes(bytes)},
    );
    expect(
      (await failureOf(
        second.backup.restoreFullBackup(recoverySecret: secret),
      )).failure,
      BackupFailure.wrongKey,
    );
    // A newer envelope version, and rubbish.
    world.remote.fullStored = served(envelope: {...good.envelope, 'v': 4});
    expect(
      (await failureOf(
        second.backup.restoreFullBackup(recoverySecret: secret),
      )).failure,
      BackupFailure.newerFormat,
    );
    world.remote.fullStored = served(envelope: {'format': 'something else'});
    expect(
      (await failureOf(
        second.backup.restoreFullBackup(recoverySecret: secret),
      )).failure,
      BackupFailure.corrupt,
    );
    expect(await HistoryStore(second.db).messageCount(), 0);
  });

  test('no backup, and a rollback to an older one', () async {
    final none = await failureOf(
      alice.backup.restoreFullBackup(recoverySecret: secret),
    );
    expect(none.failure, BackupFailure.noBackup);
    await alice.backup.createFullBackup(recoverySecret: secret);
    final v1 = world.remote.fullStored!;
    await alice.backup.createFullBackup(recoverySecret: secret);
    expect(world.remote.fullStored!.version, 2);
    world.remote.fullStored = v1;
    expect(
      (await failureOf(
        alice.backup.restoreFullBackup(recoverySecret: secret),
      )).failure,
      BackupFailure.rolledBack,
    );
  });

  test('a second device that is behind takes the next version', () async {
    await alice.backup.createFullBackup(recoverySecret: secret);
    final second = await world.link(alice, 'alice2');
    final result = await second.backup.createFullBackup(recoverySecret: secret);
    expect(result.version, 2);
    expect(world.remote.fullStored!.version, 2);
  });

  test(
    "another account's backup is refused even with the right secret",
    () async {
      final bob = await world.register('bob', phone: '+8801711000002');
      await addHistory(bob, alice.account, 3);
      await bob.backup.createFullBackup(recoverySecret: secret);
      // The same secret opens it, but the archive names Bob's account.
      final second = await world.link(alice, 'alice2');
      final e = await failureOf(
        second.backup.restoreFullBackup(recoverySecret: secret),
      );
      expect(e.failure, BackupFailure.accountMismatch);
      expect(await HistoryStore(second.db).messageCount(), 0);
    },
  );

  test('forbidden fields are found at any depth', () {
    expect(FullBackupJob.carriesForbiddenField({'a': 1}), isFalse);
    expect(FullBackupJob.carriesForbiddenField({'backup_key': 'x'}), isTrue);
    expect(
      FullBackupJob.carriesForbiddenField({
        'wraps': [
          {
            'deep': {'passphrase': 'x'},
          },
        ],
      }),
      isTrue,
    );
    expect(
      FullBackupJob.carriesForbiddenField({
        'x': {'recovery_phrase': 1},
      }),
      isTrue,
    );
  });

  test('delete removes it and forgets the version', () async {
    await alice.backup.createFullBackup(recoverySecret: secret);
    await alice.backup.deleteFullBackup();
    expect(world.remote.fullStored, isNull);
    expect((await alice.backup.status()).fullVersion, isNull);
  });
}
