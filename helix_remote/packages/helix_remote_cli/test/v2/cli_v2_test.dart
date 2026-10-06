import 'dart:io';

import 'package:helix_remote_api/v2.dart';
import 'package:helix_remote_cli/v2.dart';
import 'package:helix_remote_db/helix_remote_db.dart'
    show DbEncryptionException;
import 'package:helix_remote_engine/helix_remote_engine.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:test/test.dart';

/// The v2 CLI without a server: argument handling, the database key and the
/// rule that nothing secret is printed. The flows against a real server are
/// in `server/test/client/engine/cli_test.dart`.
void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('helix_cli_v2_'));
  tearDown(() {
    for (var i = 0; i < 5; i++) {
      try {
        dir.deleteSync(recursive: true);
        return;
      } on FileSystemException {
        sleep(const Duration(milliseconds: 100));
      }
    }
  });

  group('CliArgs', () {
    test('options, flags and positionals can mix', () {
      final args = CliArgs.parse([
        '--server',
        'https://h.example',
        'send',
        '--json',
        'Bobby',
        '--home=/tmp/x',
        'hello',
        'there',
      ]);
      expect(args.command, 'send');
      expect(args.positional, ['Bobby', 'hello', 'there']);
      expect(args.option('server'), 'https://h.example');
      expect(args.option('home'), '/tmp/x');
      expect(args.flag('json'), isTrue);
      expect(args.flag('replace'), isFalse);
    });

    test('a missing value and a lone -h', () {
      expect(() => CliArgs.parse(['--server']), throwsA(isA<CliUsageError>()));
      expect(CliArgs.parse(['-h']).flag('help'), isTrue);
      expect(CliArgs.parse(const []).command, isNull);
    });
  });

  group('CliHome', () {
    final hex = 'ab' * 32;

    test('the key comes from the environment first, then db.key', () {
      final home = CliHome(dir, env: {CliHome.keyEnvName: hex});
      expect(home.key(create: false).bytes, hasLength(32));
      expect(home.keyFile.existsSync(), isFalse);
      final fileOnly = CliHome(dir);
      expect(() => fileOnly.key(create: false), throwsA(isA<CliError>()));
      final created = fileOnly.key(create: true);
      expect(fileOnly.keyFile.readAsStringSync(), hasLength(64));
      expect(fileOnly.key(create: false), created);
    });

    test('a bad key is refused without echoing it', () {
      final home = CliHome(dir, env: {CliHome.keyEnvName: 'not-hex-at-all'});
      try {
        home.key(create: false);
        fail('expected an error');
      } on CliError catch (e) {
        expect(e.message, isNot(contains('not-hex-at-all')));
      }
    });

    test('the server address is remembered', () {
      final home = CliHome(dir);
      expect(home.savedServer(), isNull);
      home.saveServer('https://h.example');
      expect(home.savedServer(), 'https://h.example');
      expect(
        CliHome.resolve(null, {'HELIX_CLI_HOME': dir.path}).directory.path,
        dir.path,
      );
    });
  });

  group('running commands', () {
    Future<(int, BufferIo)> run(
      List<String> args, {
      Map<String, String> env = const {},
    }) async {
      final io = BufferIo(env: env);
      final code = await HelixCli(io).run(args);
      return (code, io);
    }

    test('help lists the commands; no command is a usage error', () async {
      final (code, io) = await run(['help']);
      expect(code, 0);
      final text = io.stdoutLines.join('\n');
      for (final word in [
        'register',
        'login',
        'link',
        'chats',
        'send',
        'read',
        'fetch',
        'watch',
        'devices',
        'HELIX_DB_KEY',
      ]) {
        expect(text, contains(word));
      }
      expect((await run(const [])).$1, 2);
      expect((await run(['--help'])).$1, 0);
    });

    test(
      'unknown commands and a missing server are usage errors (2)',
      () async {
        final home = ['--home', dir.path];
        expect(
          (await run([...home, '--server', 'https://x.test', 'nope'])).$1,
          2,
        );
        final (code, io) = await run([...home, 'chats']);
        expect(code, 2);
        expect(io.stderrLines.join(), contains('--server'));
        final (bad, badIo) = await run([
          ...home,
          '--server',
          'not a url',
          'chats',
        ]);
        expect(bad, 2);
        expect(badIo.stderrLines.join(), contains('URL'));
      },
    );

    test('commands that need an account say so', () async {
      final (code, io) = await run([
        '--home',
        dir.path,
        '--server',
        'https://x.test',
        'chats',
      ]);
      expect(code, 1);
      expect(io.stderrLines.join(), contains('not signed in'));
      // No database or key file was created by a command that only reads.
      expect(File('${dir.path}/helix.db').existsSync(), isFalse);
      expect(File('${dir.path}/db.key').existsSync(), isFalse);
    });

    test('status works without an account', () async {
      final (code, io) = await run([
        '--home',
        dir.path,
        '--server',
        'https://x.test',
        '--json',
        'status',
      ]);
      expect(code, 0);
      expect(io.stdoutLines.single, contains('"signed_in":false'));
    });

    test('registering needs a plausible phone number', () async {
      final (code, io) = await run([
        '--home',
        dir.path,
        '--server',
        'https://x.test',
        'register',
        '--phone',
        '0171',
      ]);
      expect(code, 2);
      expect(io.stderrLines.join(), contains('--phone'));
    });
  });

  group('error messages are safe to print', () {
    test('only codes, never bodies or exception text', () {
      expect(
        HelixCli.describeError(CliError('plain message')),
        'plain message',
      );
      expect(
        HelixCli.describeError(
          const ApiException(
            status: 429,
            code: ErrorCode.passwordLocked,
            message: 'secret detail',
            details: {'locked_until': 1},
          ),
        ),
        'the server answered password_locked (locked)',
      );
      expect(
        HelixCli.describeError(const NetworkException()),
        'cannot reach the server',
      );
      expect(
        HelixCli.describeError(
          const SignedOutException(SignedOutReason.noSession),
        ),
        'this device is signed out',
      );
      expect(
        HelixCli.describeError(const NotSignedInException()),
        'this device is not signed in',
      );
      expect(
        HelixCli.describeError(StateError('password hunter2 token abc')),
        'unexpected StateError',
      );
      expect(
        HelixCli.describeError(const DbEncryptionException('wrong key abc')),
        isNot(contains('abc')),
      );
    });
  });
}
