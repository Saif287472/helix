import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/core/people/people_names.dart';
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart' show PersonNaming;
import 'package:helix_remote_ui/helix_remote_ui.dart';

import 'support/people_fakes.dart';

/// The naming order every screen shares (AGENTS.md): phone-book name, then
/// nickname, then number, then `~Helix name`.
void main() {
  group('the naming order', () {
    const id = '0192a4f0-0000-7000-8000-0000000000aa';

    // Every subset of the four names, against the order the product rule
    // gives. 16 rows, so no permutation is left to chance.
    for (var mask = 0; mask < 16; mask++) {
      final book = mask & 1 != 0 ? 'Mum' : null;
      final nick = mask & 2 != 0 ? 'Mother' : null;
      final number = mask & 4 != 0 ? '+8801711000001' : null;
      final helix = mask & 8 != 0 ? 'mum_b' : null;
      final expected =
          book ??
          nick ??
          number ??
          (helix == null ? 'Helix user 0192a4f0' : '~$helix');
      final label = [
        if (book != null) 'phone book',
        if (nick != null) 'nickname',
        if (number != null) 'number',
        if (helix != null) '~name',
        if (mask == 0) 'nothing',
      ].join(' + ');

      test('$label -> $expected', () {
        final row = personRow(
          id,
          phonebook: book,
          nickname: nick,
          phone: number,
          helix: helix,
        );
        final name = PersonName.fromRow(row);
        expect(name.display, expected);
        // The same string the engine's own helper gives, so a notification
        // built in the engine and a row built here can never disagree.
        expect(name.display, PersonNaming.displayName(row));
        expect(name.source, switch (expected) {
          _ when book != null => HelixNameSource.phoneBook,
          _ when nick != null => HelixNameSource.nickname,
          _ when number != null => HelixNameSource.number,
          _ when helix != null => HelixNameSource.helixName,
          _ => HelixNameSource.unknown,
        });
      });
    }

    test('blank and whitespace-only names are skipped, not shown', () {
      final name = PersonName.fromRow(
        personRow(
          id,
          phonebook: '   ',
          nickname: '',
          phone: ' +8801711000001 ',
        ),
      );
      expect(name.display, '+8801711000001');
      expect(name.names.phoneBookName, isNull);
      expect(name.names.nickname, isNull);
    });

    test('the line under a name is the number, else the ~Helix name', () {
      final named = PersonName.fromRow(
        personRow(id, phonebook: 'Mum', phone: '+8801711000001', helix: 'm'),
      );
      expect(named.names.secondary, '+8801711000001');
      final noNumber = PersonName.fromRow(
        personRow(id, nickname: 'Mum', helix: 'm'),
      );
      expect(noNumber.names.secondary, '~m');
      final numberOnly = PersonName.fromRow(
        personRow(id, phone: '+8801711000001', helix: 'm'),
      );
      expect(numberOnly.names.secondary, '~m');
    });

    test('a person who only has a profile name is shown by it', () {
      final name = PersonName.fromRow(personRow(id, profile: 'Maya R.'));
      expect(name.display, 'Maya R.');
      expect(name.source, HelixNameSource.unknown);
      expect(name.profileName, 'Maya R.');
    });

    test('a stranger is "Helix user" and a short id, never blank', () {
      expect(PersonName.unknown(id).display, 'Helix user 0192a4f0');
      expect(PersonName.unknown('abc').display, 'Helix user abc');
    });

    test('a person on another server carries their server', () {
      const federated = '0192a4f0-1111-7000-8000-000000000001@other.example';
      expect(
        PersonName.unknown(federated).display,
        'Helix user 0192a4f0 (other.example)',
      );
      // A row with no names at all gets the same, so two strangers on
      // different servers are not confused.
      expect(
        PersonName.fromRow(personRow(federated)).display,
        'Helix user 0192a4f0 (other.example)',
      );
      // Once there is a name, the name wins and the id stays out of sight.
      expect(
        PersonName.fromRow(personRow(federated, nickname: 'Sam')).display,
        'Sam',
      );
    });

    test('an avatar image is reused while its bytes are unchanged', () {
      final bytes = Uint8List.fromList(List.filled(64, 7));
      final first = PersonName.fromRow(personRow(id, avatar: bytes));
      final again = PersonName.fromRow(
        personRow(id, avatar: Uint8List.fromList(bytes)),
        previous: first,
      );
      expect(identical(first.image, again.image), isTrue);
      final changed = PersonName.fromRow(
        personRow(id, avatar: Uint8List.fromList(List.filled(64, 9))),
        previous: first,
      );
      expect(identical(first.image, changed.image), isFalse);
    });

    test('the number is masked for anything that could be logged', () {
      final name = PersonName.fromRow(personRow(id, phone: '+8801711000001'));
      expect(name.maskedNumber, isNot(contains('1711000001')));
      expect(name.maskedNumber, startsWith('+880'));
      expect(name.maskedNumber, endsWith('01'));
      expect(PersonName.unknown(id).maskedNumber, isNull);
    });
  });

  group('collisions', () {
    test('two people with one name are told apart; a lone name is not', () {
      final directory = PeopleDirectory.fromRows([
        personRow('a', phonebook: 'Sam', phone: '+8801711000001'),
        personRow('b', phonebook: 'sam', phone: '+8801711000002'),
        personRow('c', nickname: 'Sam', helix: 'sam_c'),
        personRow('d', phonebook: 'Dana'),
      ]);
      expect(directory.collides('a'), isTrue);
      expect(directory.collides('b'), isTrue, reason: 'case does not matter');
      // c is shown by the phone-book-less nickname "Sam" too.
      expect(directory.collides('c'), isTrue);
      expect(directory.collides('d'), isFalse);
      expect(directory.labelOf('a'), 'Sam (…0001)');
      expect(directory.labelOf('b'), 'sam (…0002)');
      expect(directory.labelOf('c'), 'Sam (~sam_c)');
      expect(directory.labelOf('d'), 'Dana');
    });

    test('a stranger is never a collision with a known person', () {
      final directory = PeopleDirectory.fromRows([
        personRow('a', phonebook: 'Sam'),
      ]);
      expect(directory.collides('nobody'), isFalse);
      expect(directory.nameOf('nobody').display, 'Helix user nobody');
    });
  });

  group('the directory', () {
    test('finds the other person in a direct conversation id', () {
      final directory = PeopleDirectory.fromRows([
        personRow('acc', nickname: 'Mum'),
      ]);
      expect(directory.nameOfConversation('direct:acc')!.display, 'Mum');
      expect(
        directory.nameOfConversation('direct:unknown')!.display,
        'Helix user unknown',
      );
      expect(directory.nameOfConversation('group:abc'), isNull);
    });
  });

  group('the providers', () {
    late StreamController<List<PersonRow>> rows;
    late ProviderContainer container;

    setUp(() {
      rows = StreamController<List<PersonRow>>();
      container = ProviderContainer(
        overrides: [peopleRowsProvider.overrideWith((ref) => rows.stream)],
      );
    });
    tearDown(() async {
      container.dispose();
      await rows.close();
    });

    test(
      'a name follows every change: found, nicknamed, phone-booked',
      () async {
        final seen = <String>[];
        container.listen(
          personNameProvider('a'),
          (_, next) => seen.add(next.display),
          fireImmediately: true,
        );
        expect(seen, ['Helix user a'], reason: 'a stranger until a row exists');

        rows.add([personRow('a', phone: '+8801711000001')]);
        await pumpEventQueue();
        rows.add([personRow('a', phone: '+8801711000001', nickname: 'Mum')]);
        await pumpEventQueue();
        rows.add([
          personRow(
            'a',
            phone: '+8801711000001',
            nickname: 'Mum',
            phonebook: 'Mother',
          ),
        ]);
        await pumpEventQueue();
        expect(seen, ['Helix user a', '+8801711000001', 'Mum', 'Mother']);
      },
    );

    test('a person is not rebuilt when somebody else changes', () async {
      var builds = 0;
      container.listen(personNameProvider('a'), (_, _) => builds++);
      rows.add([personRow('a', nickname: 'Mum'), personRow('b')]);
      await pumpEventQueue();
      final afterFirst = builds;
      expect(afterFirst, greaterThan(0));

      rows.add([
        personRow('a', nickname: 'Mum'),
        personRow('b', nickname: 'Bob'),
        personRow('c', nickname: 'Cy'),
      ]);
      await pumpEventQueue();
      expect(builds, afterFirst, reason: 'a did not change');

      rows.add([personRow('a', nickname: 'Mum', blocked: true)]);
      await pumpEventQueue();
      expect(builds, afterFirst + 1);
      expect(container.read(personNameProvider('a')).blocked, isTrue);
    });
  });
}
