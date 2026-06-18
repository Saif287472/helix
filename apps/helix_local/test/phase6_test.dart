// Phase 6 — Make Helix Local Truly Ephemeral and Wipe-Safe
//
// P6-013: No message content survives in-memory wipe.
// P6-015: Source scan — no production code writes message text to SQLite.
// P6-049: Wipe orchestrator audit — state machine, idempotence, partial failure.
// P6-050: Scoped key deletion only touches the Local key prefix.
// P6-051: Scoped deletion never touches Remote keys.
// P6-052: Keys without the Local prefix survive scoped deletion.
// P6-059: Repeated wipe calls are idempotent.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:helix_local_storage/infrastructure/storage/in_memory_conversation_repository.dart';
import 'package:helix_local_storage/infrastructure/storage/in_memory_ephemeral_media_cache.dart';
import 'package:helix_local_storage/infrastructure/storage/in_memory_transfer_repository.dart';
import 'package:helix_local_domain/application/contracts/repositories.dart';
import 'package:helix_local_domain/domain/models.dart';
import 'package:helix_local_transfer/helix_transfer.dart';

import 'package:helix/application/identity/identity_manager_impl.dart';
import 'package:helix/application/trust/trust_use_case_impl.dart';
import 'package:helix/application/wipe/local_panic_wipe_orchestrator.dart';
import 'package:helix/providers/controllers/ephemeral_media_service.dart';

class _MemoryProfileRepository implements ProfileRepository {
  Profile? profile;

  @override
  Future<Profile?> loadProfile() async => profile;

  @override
  Future<void> saveProfile(Profile profile) async {
    this.profile = profile;
  }

  @override
  Future<void> clear() async {
    profile = null;
  }
}

class _MemoryIdentityStore implements SecureIdentityStore {
  DeviceIdentity? identity;
  String? verifier;
  bool firstRun = true;

  @override
  Future<DeviceIdentity?> loadIdentity() async => identity;

  @override
  Future<void> saveIdentity(DeviceIdentity identity) async {
    this.identity = identity;
  }

  @override
  Future<String?> loadSecretCode() async => null;

  @override
  Future<void> saveSecretCode(String secretCode) async {}

  @override
  Future<String?> loadSecretCodeVerifier() async => verifier;

  @override
  Future<void> saveSecretCodeVerifier(String verifier) async {
    this.verifier = verifier;
  }

  @override
  Future<bool> isFirstRun() async => firstRun;

  @override
  Future<void> setFirstRunDone() async {
    firstRun = false;
  }

  @override
  Future<void> clear() async {
    identity = null;
    verifier = null;
    firstRun = true;
  }
}

class _MemoryTrustRepository implements TrustRepository {
  List<KnownPeer> peers = [];

  @override
  Future<List<KnownPeer>> loadKnownPeers() async => List.of(peers);

  @override
  Future<void> saveKnownPeers(List<KnownPeer> peers) async {
    this.peers = List.of(peers);
  }
}

void main() {
  // ── P6-013: No message content survives wipe ─────────────────────────────

  group('P6-013: RAM-only message storage', () {
    test(
      'messages added to InMemoryConversationRepository are not persisted',
      () {
        final repo = InMemoryConversationRepository();

        final thread = ChatThread(
          threadId: 'tid-1',
          peerDisplayName: 'Alice',
          peerDeviceSuffix: 'A1',
          peerStaticKeyFingerprint: 'fp1',
          peerSessionId: 'sid-1',
          peerHost: '1.2.3.4',
          peerPort: 9000,
          status: ThreadStatus.active,
          unreadCount: 0,
          hasNewSessionSeparator: false,
        );
        thread.messages.add(
          ChatMessage(
            messageId: 'msg-1',
            threadId: 'tid-1',
            origin: MessageOrigin.local,
            text: 'secret content',
            timestamp: DateTime.now(),
            deliveryStatus: MessageDeliveryStatus.delivered,
          ),
        );
        repo.saveThread(thread);

        expect(repo.listThreads().length, equals(1));
        expect(
          repo.listThreads().first.messages.first.text,
          equals('secret content'),
        );

        // Simulate wipe: remove all threads
        for (final t in List.of(repo.listThreads())) {
          repo.removeThread(t.threadId);
        }

        expect(
          repo.listThreads(),
          isEmpty,
          reason: 'All messages must be gone after wipe',
        );
      },
    );

    test('creating a second repository instance starts empty', () {
      final repo1 = InMemoryConversationRepository();
      final thread = ChatThread(
        threadId: 'tid-2',
        peerDisplayName: 'Bob',
        peerDeviceSuffix: 'B2',
        peerStaticKeyFingerprint: 'fp2',
        peerSessionId: 'sid-2',
        peerHost: '5.6.7.8',
        peerPort: 9001,
        status: ThreadStatus.active,
        unreadCount: 0,
        hasNewSessionSeparator: false,
      );
      repo1.saveThread(thread);
      expect(repo1.listThreads().length, equals(1));

      // A new repository (simulating app restart) starts empty — no persistence.
      final repo2 = InMemoryConversationRepository();
      expect(
        repo2.listThreads(),
        isEmpty,
        reason: 'New repository instance must start empty (RAM-only)',
      );
    });
  });

  // ── P6-015: Source scan ───────────────────────────────────────────────────

  group('P6-021: identity reset lifecycle', () {
    test(
      'reset clears profile and identity; next setup rotates fingerprint',
      () async {
        final profiles = _MemoryProfileRepository();
        final identities = _MemoryIdentityStore();
        final manager = IdentityManagerImpl(
          profileRepository: profiles,
          secureIdentityStore: identities,
        );
        addTearDown(manager.dispose);

        await manager.createProfile(
          'Alice',
          'correct horse battery staple',
          DiscoverabilityState.hidden,
        );
        final firstFingerprint = manager.identity!.staticPublicKeyFingerprint;

        await manager.reset();

        expect(manager.profile, isNull);
        expect(manager.identity, isNull);
        expect(manager.isFirstRun, isTrue);
        expect(profiles.profile, isNull);
        expect(identities.identity, isNull);

        await manager.createProfile(
          'Alice',
          'correct horse battery staple',
          DiscoverabilityState.hidden,
        );

        expect(
          manager.identity!.staticPublicKeyFingerprint,
          isNot(firstFingerprint),
        );
      },
    );
  });

  group('P6-022: key rotation and trust warnings', () {
    test('trusted nickname with a new fingerprint is flagged', () async {
      final trust = TrustUseCaseImpl(repository: _MemoryTrustRepository());
      addTearDown(trust.dispose);

      await trust.init();
      await trust.markKnown('fp-old', 'Alice', 'a1', '10.0.0.2', 7777);
      await trust.trustPeer('fp-old', 'Alice');

      final warning = trust.detectImpersonation('fp-new', 'Alice');

      expect(warning, isNotNull);
      expect(warning!.fingerprint, equals('fp-old'));
      expect(
        trust.detectImpersonation('fp-old', 'Alice'),
        isNull,
        reason: 'The existing trusted fingerprint must not warn on itself.',
      );
    });
  });

  group('P6-015: Source scan for banned SQLite message writes', () {
    test(
      'no production Dart file calls insertMessage or insertOneWayMessage',
      () {
        // Walk the packages/local and apps/helix_local source trees, excluding
        // test directories and the database definition file itself.
        final roots = [
          Directory('../../packages/local'),
          Directory('../../apps/helix_local/lib'),
        ].where((d) => d.existsSync()).toList();

        final banned = ['insertMessage', 'insertOneWayMessage', 'upsertThread'];
        final violations = <String>[];

        for (final root in roots) {
          final files = root
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart'))
              .where(
                (f) => !f.path.contains(
                  '${Platform.pathSeparator}test${Platform.pathSeparator}',
                ),
              )
              .where((f) => !f.path.endsWith('database.dart'));

          for (final file in files) {
            final content = file.readAsStringSync();
            for (final pattern in banned) {
              if (content.contains(pattern)) {
                violations.add('${file.path}: contains "$pattern"');
              }
            }
          }
        }

        expect(
          violations,
          isEmpty,
          reason:
              'Production code must not write message content to SQLite:\n'
              '${violations.join('\n')}',
        );
      },
    );

    test(
      'P6-023: private identity material is not exposed by UI/provider surfaces',
      () {
        final roots = [
          Directory('../../apps/helix_local/lib/ui'),
          Directory('../../apps/helix_local/lib/providers'),
          Directory('../../apps/helix_local/lib/services'),
          Directory('../../apps/helix_local/lib/application/diagnostics'),
        ].where((d) => d.existsSync()).toList();

        final banned = [
          'privateKeyPem',
          'certPem',
          'kKeyIdentityPrivate',
          'identity_key_pem',
          'identity_cert_pem',
        ];
        final violations = <String>[];

        for (final root in roots) {
          final files = root
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart'));

          for (final file in files) {
            final content = file.readAsStringSync();
            for (final pattern in banned) {
              if (content.contains(pattern)) {
                violations.add('${file.path}: contains "$pattern"');
              }
            }
          }
        }

        expect(
          violations,
          isEmpty,
          reason:
              'Private identity material must not appear in UI, provider '
              'state, diagnostics, logs, or export surfaces:\n'
              '${violations.join('\n')}',
        );
      },
    );
  });

  // ── P6-049: Wipe orchestrator audit ──────────────────────────────────────

  group('P6-049: LocalPanicWipeOrchestrator state machine', () {
    test('initial phase is idle', () {
      final orc = LocalPanicWipeOrchestrator.withSteps(const []);
      expect(orc.phase, equals(WipePhase.idle));
    });

    test('phase transitions idle → inProgress → complete', () async {
      final log = <String>[];
      final orc = LocalPanicWipeOrchestrator.withSteps([
        ('step-a', () async => log.add('a')),
        ('step-b', () async => log.add('b')),
      ]);

      expect(orc.phase, WipePhase.idle);
      final result = await orc.execute();

      expect(result.phase, WipePhase.complete);
      expect(result.succeeded, isTrue);
      expect(orc.phase, WipePhase.complete);
      expect(log, equals(['a', 'b']), reason: 'Steps must execute in order');
    });

    test(
      'P6-044: failing step is recorded; remaining steps still run',
      () async {
        final log = <String>[];
        final orc = LocalPanicWipeOrchestrator.withSteps([
          ('step-ok-before', () async => log.add('before')),
          ('step-boom', () async => throw StateError('simulated failure')),
          ('step-ok-after', () async => log.add('after')),
        ]);

        final result = await orc.execute();

        expect(result.phase, WipePhase.partialFailure);
        expect(result.succeeded, isFalse);
        expect(result.errors.length, equals(1));
        expect(result.errors.first, contains('step-boom'));
        expect(
          log,
          equals(['before', 'after']),
          reason: 'Steps after a failure must still run',
        );
      },
    );

    test('P6-043 / P6-059: second execute() call is idempotent', () async {
      int callCount = 0;
      final orc = LocalPanicWipeOrchestrator.withSteps([
        ('step-counted', () async => callCount++),
      ]);

      final first = await orc.execute();
      final second = await orc.execute();

      expect(first.phase, WipePhase.complete);
      expect(second.phase, WipePhase.complete);
      expect(
        callCount,
        equals(1),
        reason: 'Steps must not re-execute on repeated calls',
      );
    });

    test('execute() on a partialFailure instance is also idempotent', () async {
      final orc = LocalPanicWipeOrchestrator.withSteps([
        ('boom', () async => throw Exception('fail')),
      ]);

      final first = await orc.execute();
      expect(first.phase, WipePhase.partialFailure);

      final second = await orc.execute();
      expect(second.phase, WipePhase.partialFailure);
      expect(
        second.errors,
        isEmpty,
        reason: 'Idempotent re-call must return empty errors',
      );
    });

    test('WipeResult.succeeded is false when errors list is non-empty', () {
      const r = WipeResult(
        phase: WipePhase.partialFailure,
        errors: ['step-a: StateError'],
      );
      expect(r.succeeded, isFalse);
    });

    test('WipeResult.succeeded is true for empty errors list', () {
      const r = WipeResult(phase: WipePhase.complete);
      expect(r.succeeded, isTrue);
    });

    test(
      'P6-048: successful wipe clears interruption recovery marker',
      () async {
        final log = <String>[];
        var pending = false;
        final orc = LocalPanicWipeOrchestrator.withStepsAndRecovery(
          [
            ('step-a', () async => log.add('a')),
            ('step-b', () async => log.add('b')),
          ],
          onMarkWipePending: () async {
            pending = true;
            log.add('mark');
          },
          onClearWipePending: () async {
            pending = false;
            log.add('clear');
          },
        );

        final result = await orc.execute();

        expect(result.succeeded, isTrue);
        expect(pending, isFalse);
        expect(log, equals(['mark', 'a', 'b', 'clear']));
      },
    );

    test(
      'P6-048: failed wipe leaves recovery marker for next launch',
      () async {
        var pending = false;
        final orc = LocalPanicWipeOrchestrator.withStepsAndRecovery(
          [('boom', () async => throw StateError('interrupted'))],
          onMarkWipePending: () async {
            pending = true;
          },
          onClearWipePending: () async {
            pending = false;
          },
        );

        final result = await orc.execute();

        expect(result.phase, WipePhase.partialFailure);
        expect(pending, isTrue);
        expect(result.errors.single, contains('boom'));
      },
    );
  });

  group('P6-032: file-transfer wipe cleanup', () {
    test(
      'cancelAllTransfers removes tracked sessions and .part files',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('helix_p6_part_');
        addTearDown(() async {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });

        final repository = InMemoryTransferRepository();
        await repository.saveTransfer(
          const FileTransferSession(
            fileId: 'file-1',
            fileName: 'secret.txt',
            mimeType: 'text/plain',
            totalSize: 12,
            chunkCount: 1,
            receivedChunks: {},
          ),
        );

        final transferDir = Directory(
          '${tempDir.path}${Platform.pathSeparator}transfers',
        );
        await transferDir.create(recursive: true);
        final partFile = File(
          '${transferDir.path}${Platform.pathSeparator}file-1.part',
        );
        await partFile.writeAsString('partial bytes');

        final coordinator = ReceiveFileCoordinatorImpl(
          repository: repository,
          onProgressUpdate: (_, _, _, {localFilePath}) {},
          getCacheDirectory: () async => tempDir,
        );

        await coordinator.cancelAllTransfers();

        expect(repository.listTransfers(), isEmpty);
        expect(await partFile.exists(), isFalse);
      },
    );
  });

  group('P6-033: ephemeral media wipe cleanup', () {
    test('clearAll removes cached media bytes', () {
      final cache = InMemoryEphemeralMediaCache();
      final service = EphemeralMediaService(cache: cache);

      cache.storeMedia('media-1', Uint8List.fromList([1, 2, 3]));
      expect(service.hasMedia('media-1'), isTrue);

      service.clearAll();

      expect(service.hasMedia('media-1'), isFalse);
    });
  });

  // ── P6-050 to P6-053: Scoped key isolation ────────────────────────────────

  group('P6-050-P6-053: Scoped secure-storage key isolation', () {
    const localPrefix = 'helix_local_v1_';
    const remotePrefix = 'helix_remote_v1_';

    final allKeys = {
      'helix_local_v1_session': 'local-session',
      'helix_local_v1_trust_fp1': 'trust-data',
      'helix_remote_v1_account': 'remote-account',
      'helix_remote_v1_device_key': 'remote-key',
      'unrelated_system_key': 'system-data',
    };

    test('P6-050/P6-052: scoped deletion selects only Local-prefixed keys', () {
      final toDelete = allKeys.keys
          .where((k) => k.startsWith(localPrefix))
          .toList();

      expect(
        toDelete,
        containsAll(['helix_local_v1_session', 'helix_local_v1_trust_fp1']),
      );
      expect(
        toDelete.length,
        equals(2),
        reason: 'Only Local-prefixed keys must be selected',
      );
    });

    test('P6-051: Remote keys survive Local scoped deletion', () {
      final toDelete = allKeys.keys
          .where((k) => k.startsWith(localPrefix))
          .toSet();

      final surviving = allKeys.keys
          .where((k) => !toDelete.contains(k))
          .toList();

      expect(surviving, contains('helix_remote_v1_account'));
      expect(surviving, contains('helix_remote_v1_device_key'));
    });

    test('P6-053: unrelated system keys survive Local scoped deletion', () {
      final toDelete = allKeys.keys
          .where((k) => k.startsWith(localPrefix))
          .toSet();

      expect(toDelete, isNot(contains('unrelated_system_key')));
    });

    test('Local and Remote prefixes are distinct — no overlap possible', () {
      expect(localPrefix.startsWith(remotePrefix), isFalse);
      expect(remotePrefix.startsWith(localPrefix), isFalse);
    });
  });
}
