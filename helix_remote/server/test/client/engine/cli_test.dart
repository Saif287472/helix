import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:helix_remote_cli/v2.dart';
import 'package:test/test.dart';

import '../../support/flows.dart';
import '../../support/harness.dart';
import '../../support/test_database.dart';
import 'support.dart';

/// The v2 CLI, in-process, against the real server: two homes exchange
/// messages, a second device is linked, and nothing secret is printed.
void main() {
  group('v2 CLI', skip: databaseTestSkipReason, () {
    late Harness h;
    late Directory root;
    final secrets = <String>[];

    setUp(() async {
      h = await Harness.start();
      root = Directory.systemTemp.createTempSync('helix_cli_e2e_');
      secrets.clear();
    });
    tearDown(() async {
      await h.stop();
      for (var i = 0; i < 10; i++) {
        try {
          root.deleteSync(recursive: true);
          return;
        } on FileSystemException {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
    });

    /// One CLI run. Prompts for "code" are answered with the SMS the server
    /// just "sent" to [phone].
    Future<(int, _Io)> run(
      String name,
      List<String> args, {
      String? phone,
      Map<String, String> env = const {},
      List<String> input = const [],
    }) async {
      final io = _Io(h, phone, env: env, input: input);
      final code = await HelixCli(io).run([
        '--home',
        '${root.path}/$name',
        '--server',
        h.server.baseUri.toString(),
        ...args,
      ]);
      return (code, io);
    }

    /// Decodes the last JSON line printed.
    Map<String, Object?> lastJson(_Io io) =>
        jsonDecode(io.stdoutLines.last) as Map<String, Object?>;

    /// The database key of home [name] (read only to prove it is never
    /// printed).
    String keyOf(String name) =>
        File('${root.path}/$name/db.key').readAsStringSync().trim();

    test(
      'two CLI homes exchange messages, one links a second device',
      () async {
        final outputs = <_Io>[];
        Future<_Io> ok(
          String name,
          List<String> args, {
          String? phone,
          Map<String, String> env = const {},
        }) async {
          final (code, io) = await run(name, args, phone: phone, env: env);
          expect(code, 0, reason: '${args.first} failed: ${io.stderrLines}');
          outputs.add(io);
          return io;
        }

        const password = 'a long password for the CLI';
        secrets.add(password);
        await ok(
          'alice',
          ['register', '--phone', aliceNumber, '--password-env', 'PW'],
          phone: aliceNumber,
          env: {'PW': password},
        );
        await ok('bob', ['register', '--phone', bobNumber], phone: bobNumber);
        secrets.addAll([keyOf('alice'), keyOf('bob')]);

        // Alice finds Bob by number, names him, and writes to him by name.
        final found = await ok('alice', [
          '--json',
          'contacts',
          'add',
          bobNumber,
          '--name',
          'Bobby',
        ]);
        expect(lastJson(found)['name'], 'Bobby');
        expect(lastJson(found)['phone'], isNot(bobNumber));
        final sent = await ok('alice', [
          '--json',
          'send',
          'Bobby',
          'hello',
          'from',
          'the',
          'CLI',
        ]);
        expect(lastJson(sent)['status'], anyOf('sent', 'delivered'));

        // Bob downloads it. He has not met Alice by name: she is an id.
        final fetched = await ok('bob', ['--json', 'fetch', '--show']);
        final shown = lastJson(fetched);
        expect(shown['processed'], greaterThan(0));
        expect(
          (shown['messages']! as List).single,
          containsPair('text', 'hello from the CLI'),
        );
        final senderId =
            ((shown['messages']! as List).single
                    as Map<String, Object?>)['sender']!
                as String;

        // Bob answers (resolving Alice by her phone number) and reads.
        await ok('bob', ['send', aliceNumber, 'hi', 'Alice']);
        final read = await ok('bob', [
          '--json',
          'read',
          senderId.substring(0, 10),
        ]);
        final messages = (lastJson(read)['messages']! as List)
            .cast<Map<String, Object?>>();
        expect(messages.map((m) => m['text']), [
          'hello from the CLI',
          'hi Alice',
        ]);
        expect(messages.map((m) => m['from']).last, 'me');

        await ok('alice', ['fetch']);
        final aliceRead = await ok('alice', ['--json', 'read', 'Bobby']);
        expect(
          (lastJson(aliceRead)['messages']! as List)
              .cast<Map<String, Object?>>()
              .map((m) => m['text']),
          ['hello from the CLI', 'hi Alice'],
        );
        final chats = await ok('alice', ['--json', 'chats']);
        expect(
          (lastJson(chats)['chats']! as List).single,
          containsPair('name', 'Bobby'),
        );
        expect(lastJson(chats)['chats'], isNot(contains('unread: 1')));

        // Bob links a second CLI device: it shows a code, Bob approves it.
        final linkIo = _Io(h, null, env: const {});
        final linking = HelixCli(linkIo).run([
          '--home',
          '${root.path}/bob2',
          '--server',
          h.server.baseUri.toString(),
          '--json',
          'link',
          '--device-name',
          'Bob second',
        ]);
        late String code;
        await settle(() async {
          expect(linkIo.stdoutLines, isNotEmpty);
          code =
              (jsonDecode(linkIo.stdoutLines.first)
                      as Map<String, Object?>)['link_code']!
                  as String;
        });
        await ok('bob', ['link-approve', code]);
        expect(await linking.timeout(const Duration(seconds: 30)), 0);
        secrets.add(keyOf('bob2'));

        // Messages now reach both of Bob's devices.
        await ok('alice', ['send', 'Bobby', 'to', 'both', 'devices']);
        for (final home in ['bob', 'bob2']) {
          final io = await ok(home, ['--json', 'fetch', '--show']);
          expect(
            (lastJson(io)['messages']! as List)
                .cast<Map<String, Object?>>()
                .map((m) => m['text']),
            contains('to both devices'),
            reason: home,
          );
        }
        final devices = await ok('bob', ['--json', 'devices']);
        final list = (lastJson(devices)['devices']! as List)
            .cast<Map<String, Object?>>();
        expect(list, hasLength(2));
        final second = list.firstWhere((d) => d['this_device'] == false);
        await ok('bob', [
          'devices',
          'revoke',
          (second['device']! as String).substring(0, 12),
        ]);
        expect(
          (lastJson(await ok('bob', ['--json', 'devices']))['devices']!
              as List),
          hasLength(1),
        );

        // Never printed, anywhere: full phone numbers, the SMS codes, the
        // database keys, the password.
        final everything = outputs.map((o) => o.everything).join('\n');
        for (final secret in [
          aliceNumber,
          bobNumber,
          ...secrets,
          ...outputs.expand((o) => o.codesIssued),
        ]) {
          expect(
            everything,
            isNot(contains(secret)),
            reason: 'leaked a secret',
          );
        }
        // Phone numbers do appear masked.
        expect(everything, contains('+880'));
      },
    );

    test('commands refuse politely when signed out or misused', () async {
      final (code, io) = await run('nobody', ['chats']);
      expect(code, 1);
      expect(io.stderrLines.join(), contains('not signed in'));
      final (usage, _) = await run('nobody', ['frobnicate']);
      expect(usage, 2);
      final (help, helpIo) = await run('nobody', ['help']);
      expect(help, 0);
      expect(helpIo.stdoutLines.join('\n'), contains('register'));
      // A wrong password is reported without echoing anything.
      await run(
        'alice',
        ['register', '--phone', aliceNumber, '--password-env', 'PW'],
        phone: aliceNumber,
        env: {'PW': 'right password right password'},
      );
      final (bad, badIo) = await run(
        'laptop',
        ['login', '--phone', aliceNumber, '--password-env', 'PW'],
        env: {'PW': 'wrong password wrong password'},
      );
      expect(bad, 1);
      expect(badIo.everything, isNot(contains('wrong password')));
      expect(badIo.stderrLines.join(), contains('invalid_credentials'));
    });
  });
}

/// A [BufferIo] that answers the "code" prompt with the SMS code the test
/// server recorded for [phone].
final class _Io extends BufferIo {
  _Io(this._h, this._phone, {super.env, super.input});

  final Harness _h;
  final String? _phone;
  final List<String> codesIssued = [];

  @override
  Future<String?> readLine(String prompt, {bool secret = false}) async {
    if (prompt == 'code' && _phone != null) {
      final code = _h.sms.lastCodeFor(_phone);
      codesIssued.add(code);
      prompts.add('code');
      return code;
    }
    return super.readLine(prompt, secret: secret);
  }
}
