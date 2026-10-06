import 'package:helix_remote_api/v2.dart' show ApiException;
import 'package:helix_remote_crypto/v2.dart';
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:test/test.dart';

import 'support/peers.dart';

/// People, profiles, naming, blocks, trust and settings.
void main() {
  late Peers peers;

  setUp(() => peers = Peers());
  tearDown(() => peers.dispose());

  PersonRow person({
    String? phonebook,
    String? nickname,
    String? phone,
    String? helix,
    String? profile,
  }) => PersonRow(
    accountId: '0192a4f0-0000-7000-8000-0000000000aa',
    helixName: helix,
    phoneNumber: phone,
    phonebookName: phonebook,
    nickname: nickname,
    profileName: profile,
    identityVerified: false,
    blocked: false,
    updatedAt: DateTime.utc(2026),
  );

  group('naming', () {
    test('phone-book name, then nickname, then number, then ~Helix name', () {
      expect(
        PersonNaming.displayName(
          person(
            phonebook: 'Mum',
            nickname: 'Mother',
            phone: '+88017',
            helix: 'mum',
          ),
        ),
        'Mum',
      );
      expect(
        PersonNaming.displayName(
          person(nickname: 'Mother', phone: '+88017', helix: 'mum'),
        ),
        'Mother',
      );
      expect(
        PersonNaming.displayName(person(phone: '+88017', helix: 'mum')),
        '+88017',
      );
      expect(PersonNaming.displayName(person(helix: 'mum')), '~mum');
      expect(
        PersonNaming.displayName(person(profile: 'Real Name')),
        'Real Name',
      );
      expect(
        PersonNaming.displayName(person()),
        startsWith('Helix user 0192a4f0'),
      );
      // Blank names are skipped, not shown.
      expect(
        PersonNaming.displayName(person(phonebook: '  ', nickname: 'Nick')),
        'Nick',
      );
    });
  });

  group('discovery', () {
    test(
      'the phone book is matched by hash and stored with its names',
      () async {
        final alice = await peers.register(
          'alice',
          phone: '+8801711000001',
          phoneBook: FakePhoneBook([
            const PhoneBookEntry(name: 'Bobby', numbers: ['+8801711000002']),
            const PhoneBookEntry(
              name: 'Nobody',
              numbers: ['+8801799999999', '+8801711000003'],
            ),
          ]),
        );
        final bob = await peers.register('bob', phone: '+8801711000002');
        final carol = await peers.register('carol', phone: '+8801711000003');

        final result = await alice.engine.people.syncPhoneBook();
        expect(result.checked, 3);
        expect(result.found, 2);
        expect(result.remainingToday, 5000);
        final bobRow = (await alice.engine.people.person(bob.account))!;
        expect(bobRow.phonebookName, 'Bobby');
        expect(bobRow.phoneNumber, '+8801711000002');
        expect(bobRow.phoneHash, peers.server.discoveryHash('+8801711000002'));
        expect(
          (await alice.engine.people.person(carol.account))!.phonebookName,
          'Nobody',
        );
        // Only hashes went over the wire, never numbers.
        final discover = peers.server.calls.where(
          (c) => c.contains('discover'),
        );
        expect(discover, isNotEmpty);
        expect(
          PeopleService.discoveryHash(peers.server.salt, '+8801711000002'),
          peers.server.discoveryHash('+8801711000002'),
        );
        expect(
          (await alice.engine.people.search('bob')).map((p) => p.accountId),
          [bob.account],
        );
        expect(
          (await alice.engine.people.list()).map(
            alice.engine.people.displayName,
          ),
          ['Bobby', 'Nobody'],
        );
      },
    );

    test('one number, one ~name', () async {
      final alice = await peers.register('alice', phone: '+8801711000001');
      final bob = await peers.register('bob', phone: '+8801711000002');
      expect(await alice.engine.people.findByNumber('+8801711000077'), isNull);
      final found = (await alice.engine.people.findByNumber('+8801711000002'))!;
      expect(found.accountId, bob.account);

      await bob.engine.settings.setHelixName('~Bob_The');
      expect(
        (await bob.db.accountDao.current())!.helixName,
        'bob_the',
        reason: 'lower-cased, without the ~',
      );
      final named = (await alice.engine.people.findByHelixName('bob_the'))!;
      expect(named.helixName, 'bob_the');
      expect(await alice.engine.people.findByHelixName('nobody_here'), isNull);
      expect(() => bob.engine.settings.setHelixName('x'), throwsArgumentError);
      await expectLater(
        alice.engine.settings.setHelixName('bob_the'),
        throwsA(isA<ApiException>()),
      );
      await bob.engine.settings.clearHelixName();
      expect((await bob.db.accountDao.current())!.helixName, isNull);
    });
  });

  group('names and blocks', () {
    test('a nickname follows to this account\'s other devices and into '
        'the phone book', () async {
      final book = FakePhoneBook(const []);
      final alice1 = await peers.register(
        'alice1',
        phone: '+8801711000001',
        phoneBook: book,
      );
      final bob = await peers.register('bob', phone: '+8801711000002');
      final alice2 = await peers.link(alice1, 'alice2');
      await alice1.engine.devices.refresh();
      await alice1.engine.people.findByNumber('+8801711000002');

      await alice1.engine.people.setNickname(bob.account, '  Bobby  ');
      await alice1.engine.drainOutbox();
      await alice2.sync();
      expect(
        (await alice1.engine.people.person(bob.account))!.nickname,
        'Bobby',
      );
      expect(
        (await alice2.engine.people.person(bob.account))!.nickname,
        'Bobby',
      );
      expect(book.saved, {'+8801711000002': 'Bobby'});
      // The phone took the name, so it is also the name shown here: the old
      // phone-book name must not outrank the rename.
      expect(
        alice1.engine.people.displayName(
          (await alice1.engine.people.person(bob.account))!,
        ),
        'Bobby',
      );

      await alice1.engine.people.setNickname(bob.account, null);
      await alice1.engine.drainOutbox();
      await alice2.sync();
      expect(
        (await alice2.engine.people.person(bob.account))!.nickname,
        isNull,
      );
    });

    test('blocking is stored on the server and here, and a new device '
        'learns the list', () async {
      final alice1 = await peers.register('alice1', phone: '+8801711000001');
      final bob = await peers.register('bob', phone: '+8801711000002');
      await alice1.engine.people.block(bob.account);
      expect(peers.server.accounts[alice1.account]!.blocked, {bob.account});
      expect((await alice1.engine.people.person(bob.account))!.blocked, isTrue);
      expect(await alice1.engine.people.search('bob'), isEmpty);

      final alice2 = await peers.link(alice1, 'alice2');
      await alice2.engine.people.syncBlocks();
      expect((await alice2.engine.people.person(bob.account))!.blocked, isTrue);

      await alice1.engine.people.unblock(bob.account);
      await alice2.engine.people.syncBlocks();
      expect(
        (await alice2.engine.people.person(bob.account))!.blocked,
        isFalse,
      );
    });
  });

  group('profiles', () {
    test(
      'a profile is encrypted with the key that arrives in messages',
      () async {
        final alice = await peers.register('alice', phone: '+8801711000001');
        final bob = await peers.register('bob', phone: '+8801711000002');
        await alice.engine.people.setOwnProfile(name: 'Alice A.', about: 'hi');
        expect((await alice.db.accountDao.current())!.profileName, 'Alice A.');
        // The server holds ciphertext only.
        final stored = peers.server.profiles[alice.account]!;
        expect(
          String.fromCharCodes(stored.ciphertext),
          isNot(contains('Alice')),
        );
        expect(stored.version, 1);

        // Bob cannot read it before Alice has written to him.
        expect(await bob.engine.people.refreshProfile(alice.account), isNull);
        final chat = await alice.engine.chats.openDirect(bob.account);
        await alice.engine.chats.sendText(chat.id, 'here is my profile key');
        await alice.engine.drainOutbox();
        await bob.sync();
        expect(
          await bob.engine.people.refreshProfile(alice.account),
          'Alice A.',
        );
        expect(
          (await bob.engine.people.person(alice.account))!.profileName,
          'Alice A.',
        );
        expect(await bob.engine.people.aboutOf(alice.account), 'hi');
        // A newer version is picked up, the same one is not fetched again.
        await alice.engine.people.setOwnProfile(name: 'Alice B.');
        expect(
          await bob.engine.people.refreshProfile(alice.account),
          'Alice B.',
        );
        expect(
          (await bob.engine.people.person(alice.account))!.profileVersion,
          2,
        );
        expect(await bob.engine.people.aboutOf(alice.account), isNull);
      },
    );

    test('a report names the account and category and nothing else', () async {
      final alice = await peers.register('alice', phone: '+8801711000001');
      final bob = await peers.register('bob', phone: '+8801711000002');
      await alice.engine.people.report(
        bob.account,
        ReportCategory.spam,
        note: '  sells things  ',
      );
      await alice.engine.people.report(bob.account, ReportCategory.other);
      expect(peers.server.reports.map((r) => (r.account, r.category, r.note)), [
        (bob.account, ReportCategory.spam, 'sells things'),
        (bob.account, ReportCategory.other, null),
      ]);
    });
  });

  group('trust', () {
    test('both sides compute the same safety number; verification resets '
        'on a key change', () async {
      final alice = await peers.register('alice', phone: '+8801711000001');
      final bob = await peers.register('bob', phone: '+8801711000002');
      final chat = await alice.engine.chats.openDirect(bob.account);
      await alice.engine.chats.sendText(chat.id, 'hi');
      await alice.engine.drainOutbox();
      await bob.sync();

      final fromAlice = (await alice.engine.people.safetyNumber(bob.account))!;
      final fromBob = (await bob.engine.people.safetyNumber(alice.account))!;
      expect(fromAlice.digits, fromBob.digits);
      expect(fromAlice.digits, hasLength(60));
      expect(fromAlice.matchesQr(fromBob.qrPayload), isTrue);

      await alice.engine.people.setVerified(bob.account, verified: true);
      expect(
        (await alice.engine.people.person(bob.account))!.identityVerified,
        isTrue,
      );
      // The devices are listed with their trust state.
      final devices = await alice.engine.people.devicesOf(bob.account);
      expect(devices.single.trust, DeviceTrust.trusted);
      expect(devices.single.deviceId, bob.device);
    });

    test('safety numbers need a pinned key', () async {
      final alice = await peers.register('alice', phone: '+8801711000001');
      expect(
        await alice.engine.people.safetyNumber(
          '0192a4f0-0000-7000-8000-0000000000aa',
        ),
        isNull,
      );
    });
  });

  group('settings', () {
    test('typed settings read as defaults, change, stream and reset', () async {
      final alice = await peers.register('alice');
      final settings = alice.engine.settings;
      expect(await settings.get(EngineSettings.sendReadReceipts), isTrue);
      final seen = <bool>[];
      final sub = settings
          .watch(EngineSettings.sendReadReceipts)
          .listen(seen.add);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await settings.set(EngineSettings.sendReadReceipts, false);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(await settings.get(EngineSettings.sendReadReceipts), isFalse);
      await settings.reset(EngineSettings.sendReadReceipts);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await sub.cancel();
      expect(seen, [true, false, true]);
      // A new chat starts without a timer unless a default is set.
      expect(
        await settings.get(EngineSettings.defaultDisappearingSeconds),
        isNull,
      );
    });
  });

  group('chat state', () {
    test('pin, mute, archive and drafts are chat rows; the list orders '
        'pinned first', () async {
      final alice = await peers.register('alice', phone: '+8801711000001');
      final bob = await peers.register('bob', phone: '+8801711000002');
      final carol = await peers.register('carol', phone: '+8801711000003');
      final withBob = await alice.engine.chats.openDirect(bob.account);
      final withCarol = await alice.engine.chats.openDirect(carol.account);
      await alice.engine.chats.sendText(withBob.id, 'older');
      await alice.engine.chats.sendText(withCarol.id, 'newer');
      List<String> order(List<ConversationListItem> items) => [
        for (final i in items) i.conversation.id,
      ];
      expect(order(await alice.engine.chats.watchChats().first), [
        withCarol.id,
        withBob.id,
      ]);
      await alice.engine.chats.setPinned(withBob.id, pinned: true);
      expect(order(await alice.engine.chats.watchChats().first), [
        withBob.id,
        withCarol.id,
      ]);
      await alice.engine.chats.setArchived(withCarol.id, archived: true);
      expect(order(await alice.engine.chats.watchChats().first), [withBob.id]);
      expect(order(await alice.engine.chats.watchChats(archived: true).first), [
        withCarol.id,
      ]);
      await alice.engine.chats.setDraft(withBob.id, 'half written');
      expect(
        (await alice.db.conversationsDao.byId(withBob.id))!.draft,
        'half written',
      );
      // Sending clears the draft.
      await alice.engine.chats.sendText(withBob.id, 'written');
      expect((await alice.db.conversationsDao.byId(withBob.id))!.draft, isNull);

      await alice.engine.chats.deleteChat(withBob.id);
      expect(await alice.db.conversationsDao.byId(withBob.id), isNull);
    });

    test('messages are validated before they are queued', () async {
      final alice = await peers.register('alice', phone: '+8801711000001');
      final bob = await peers.register('bob', phone: '+8801711000002');
      final chat = await alice.engine.chats.openDirect(bob.account);
      expect(
        () => alice.engine.chats.sendText(chat.id, '   '),
        throwsArgumentError,
      );
      expect(
        () => alice.engine.chats.sendText(chat.id, 'x' * 70000),
        throwsArgumentError,
      );
      expect(
        () => alice.engine.chats.sendBody(
          chat.id,
          const ReactionBody(
            target: MessageRef(id: 'a', author: 'b'),
            emoji: 'A',
          ),
        ),
        throwsArgumentError,
      );
      expect(
        () => alice.engine.chats.sendText('channel:abc', 'x'),
        throwsArgumentError,
      );
      // A group this account is not in cannot be sent to.
      expect(
        () => alice.engine.chats.sendText('group:abc', 'x'),
        throwsA(isA<GroupException>()),
      );
      // Nothing was queued.
      expect(await alice.db.outboxDao.failed(), isEmpty);
      expect(await alice.db.outboxDao.nextWakeAt(), isNull);
    });

    test('view-once media is marked opened and the author gets a viewed '
        'receipt', () async {
      final alice = await peers.register('alice', phone: '+8801711000001');
      final bob = await peers.register('bob', phone: '+8801711000002');
      final chat = await alice.engine.chats.openDirect(bob.account);
      final sent = await alice.engine.chats.sendBody(
        chat.id,
        const LocationBody(latE7: 1, lngE7: 2, accuracyM: 3),
        viewOnce: true,
      );
      await alice.engine.drainOutbox();
      await bob.sync();
      final row = (await bob.messages(alice)).single;
      expect(row.viewOnceState, ViewOnceState.unopened);
      await bob.engine.chats.openViewOnce(row.localRowid);
      expect(
        (await bob.db.messagesDao.byRowid(row.localRowid))!.viewOnceState,
        ViewOnceState.opened,
      );
      await bob.engine.drainOutbox();
      await alice.sync();
      expect(
        (await alice.db.messagesDao.byRowid(sent.localRowid))!.status,
        MessageStatus.viewed,
      );
      // Opening twice does nothing more.
      final calls = peers.server.callsTo(Routes.sendMessage);
      await bob.engine.chats.openViewOnce(row.localRowid);
      await bob.engine.drainOutbox();
      expect(peers.server.callsTo(Routes.sendMessage), calls);
    });

    test('search finds text from both sides of a chat', () async {
      final alice = await peers.register('alice', phone: '+8801711000001');
      final bob = await peers.register('bob', phone: '+8801711000002');
      final chat = await alice.engine.chats.openDirect(bob.account);
      await alice.engine.chats.sendText(chat.id, 'lunch at noon');
      await alice.engine.drainOutbox();
      await bob.sync();
      await bob.engine.chats.sendText(
        directConversationId(alice.account),
        'noon works',
      );
      expect((await bob.engine.chats.search('noo')).map((m) => m.body), [
        'noon works',
        'lunch at noon',
      ]);
      expect(await bob.engine.chats.search('nonexistent'), isEmpty);
      expect(
        await bob.engine.chats.search('noon', conversationId: 'direct:other'),
        isEmpty,
      );
      // A deleted message is not found any more.
      await alice.engine.chats.deleteForEveryone(
        (await alice.messages(bob)).first.localRowid,
      );
      await alice.engine.drainOutbox();
      await bob.sync();
      expect((await bob.engine.chats.search('lunch')), isEmpty);
    });
  });

  test('safety numbers use the crypto layer\'s ordering', () {
    final a = SafetyNumber.compute(
      localAccount: '0192a4f0-0000-7000-8000-00000000000a',
      localIdentityKey: Uint8List32.of(1),
      remoteAccount: '0192a4f0-0000-7000-8000-00000000000b',
      remoteIdentityKey: Uint8List32.of(2),
    );
    final b = SafetyNumber.compute(
      localAccount: '0192a4f0-0000-7000-8000-00000000000b',
      localIdentityKey: Uint8List32.of(2),
      remoteAccount: '0192a4f0-0000-7000-8000-00000000000a',
      remoteIdentityKey: Uint8List32.of(1),
    );
    expect(a.digits, b.digits);
  });
}

abstract final class Uint8List32 {
  static List<int> of(int v) => List.filled(32, v);
}
