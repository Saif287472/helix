import 'dart:async';
import 'dart:convert';

import 'package:helix_remote_api/v2.dart';
import 'package:helix_remote_cli/src/v2/cli_args.dart';
import 'package:helix_remote_cli/src/v2/cli_home.dart';
import 'package:helix_remote_cli/src/v2/cli_io.dart';
import 'package:helix_remote_crypto/v2.dart' show SecureCryptoRandom;
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// Runs one `helix_v2` command line and returns the exit code (0 success,
/// 1 failure, 2 misuse). All state lives in the home directory; all output
/// goes through [io].
///
/// The CLI is a thin shell over the engine (`helix_remote_engine`): it opens
/// the encrypted database, builds the API client and the engine, runs one
/// command and closes everything. It never prints tokens, keys, codes or
/// full phone numbers; phone numbers are masked (`+8801*****01`) and ids of
/// other people are shortened unless `--json` asks for the full value
/// (account and device ids are not secrets; scripts need them).
Future<int> runHelixCli(List<String> arguments, {CliIo? io}) async {
  final console = io == null ? ConsoleIo() : null;
  final cli = HelixCli(io ?? console!);
  try {
    return await cli.run(arguments);
  } finally {
    await console?.close();
  }
}

final class HelixCli {
  HelixCli(this.io);

  final CliIo io;

  late bool _json;

  static const usage = '''
Helix Remote CLI (v2)

usage: helix_v2 [--home DIR] [--server URL] [--json] <command> [arguments]

Account
  register --phone +E164 [--password-env VAR] [--code-env VAR] [--replace]
                                   Create an account (Helix Global). The SMS
                                   code is read from the variable or a prompt.
  register --invite-env VAR        Create an account on a personal server.
  login --phone +E164 [--password-env VAR] [--device-name NAME]
                                   Add this device with the account password.
  link [--device-name NAME]        Link this device: shows a code to approve
                                   on a signed-in device, then waits.
  link-approve CODE                Approve another device's link code.
  status                           Who and where this CLI is signed in.
  logout                           Sign out and wipe the local database.

People
  contacts add +E164 [--name NAME] Find an account by phone number.
  contacts find ~NAME              Find an account by Helix name.
  contacts list                    People this CLI knows.
  block PEER / unblock PEER

Messages (PEER: +E164, ~name, a contact name or an id prefix)
  chats                            The chat list.
  send PEER TEXT...                Send one message and exit.
  chat PEER                        Interactive: lines you type are sent,
                                   incoming messages are printed. /quit exits.
  read PEER [--limit N]            Show the newest messages and mark them read.
  react PEER MESSAGE_ID EMOJI      React to a message.
  fetch [--show]                   Download and decrypt waiting messages.
  watch [--count N] [--timeout S]  Print incoming messages as they arrive.

Devices
  devices                          List this account's devices.
  devices revoke ID                Revoke a device (an id prefix works).
  devices revoke-others            Revoke every device but this one.

The database key comes from HELIX_DB_KEY (64 hex characters) or the file
db.key in the home directory (created on first use). Nothing prints it.
''';

  Future<int> run(List<String> arguments) async {
    final CliArgs args;
    try {
      args = CliArgs.parse(arguments);
    } on CliUsageError catch (e) {
      io.err('error: ${e.message}');
      return 2;
    }
    _json = args.flag('json');
    if (args.command == null || args.command == 'help' || args.flag('help')) {
      io.out(usage);
      return args.command == null && !args.flag('help') ? 2 : 0;
    }
    try {
      await _dispatch(args);
      return 0;
    } on CliUsageError catch (e) {
      io.err('error: ${e.message}');
      return 2;
    } on Object catch (e) {
      io.err('error: ${describeError(e)}');
      return 1;
    }
  }

  /// A message that is safe to show for [error]: never a request body, a
  /// token or the text of an unexpected exception.
  static String describeError(Object error) {
    return switch (error) {
      CliError() => error.message,
      CliUsageError() => error.message,
      SignedOutException() => 'this device is signed out',
      NetworkException() => 'cannot reach the server',
      ApiException() =>
        'the server answered ${error.code.wire}'
            '${error.lockedUntil == null ? '' : ' (locked)'}',
      EngineException() => error.message,
      DbEncryptionException() => 'the database cannot be opened with this key',
      _ => 'unexpected ${error.runtimeType}',
    };
  }

  // ---------------------------------------------------------- dispatch

  Future<void> _dispatch(CliArgs args) async {
    final home = CliHome.resolve(args.option('home'), io.env);
    switch (args.command) {
      case 'register':
        return _register(args, home);
      case 'login':
        return _login(args, home);
      case 'link':
        return _link(args, home);
      case 'status':
        return _status(args, home);
      case 'logout':
        return _withEngine(args, home, _logout);
      case 'contacts':
        return _withEngine(args, home, _contacts);
      case 'block' || 'unblock':
        return _withEngine(args, home, _block);
      case 'chats':
        return _withEngine(args, home, _chats);
      case 'send':
        return _withEngine(args, home, _send);
      case 'chat':
        return _withEngine(args, home, _chat, live: true);
      case 'read':
        return _withEngine(args, home, _read);
      case 'react':
        return _withEngine(args, home, _react);
      case 'fetch':
        return _withEngine(args, home, _fetch);
      case 'watch':
        return _withEngine(args, home, _watch, live: true);
      case 'devices':
        return _withEngine(args, home, _devices);
      case 'link-approve':
        return _withEngine(args, home, _linkApprove);
      default:
        throw CliUsageError('unknown command "${args.command}" (try help)');
    }
  }

  // --------------------------------------------------------- the engine

  Uri _server(CliArgs args, CliHome home) {
    final text =
        args.option('server') ?? io.env['HELIX_SERVER'] ?? home.savedServer();
    if (text == null) {
      throw CliUsageError('no server: pass --server URL or set HELIX_SERVER');
    }
    final uri = Uri.tryParse(text);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw CliUsageError(
        '--server needs a URL like https://helix.example.org',
      );
    }
    return uri;
  }

  /// Opens the database, the API client and the engine, runs [body] and
  /// closes everything. Commands that start by creating the account pass
  /// [createKey].
  Future<void> _open(
    CliArgs args,
    CliHome home,
    Future<void> Function(Engine engine, CliHome home) body, {
    bool createKey = false,
    bool live = false,
    bool requireAccount = true,
  }) async {
    final server = _server(args, home);
    if (requireAccount && !createKey && !home.databaseFile.existsSync()) {
      throw CliError(
        'not signed in: run register, login or link first (no database yet)',
      );
    }
    home.directory.createSync(recursive: true);
    final db = await HelixDb.open(
      home.databaseFile,
      key: home.key(create: createKey),
    );
    final api = HelixApi(
      baseUrl: server,
      sessions: DbSessionTokenStore(db),
      clientName: 'helix-cli/2',
    );
    final engine = Engine(
      api: api,
      db: db,
      clock: DateTime.now,
      random: SecureCryptoRandom(),
      config: EngineConfig(
        deviceName: args.option('device-name') ?? 'Helix CLI',
        platform: DevicePlatform.cli,
      ),
    );
    try {
      await engine.start(realtime: live, background: live);
      if (requireAccount && engine.status != EngineStatus.running) {
        throw CliError(
          'not signed in: run register, login or link first '
          '(status: ${engine.status.name})',
        );
      }
      await body(engine, home);
      if (engine.status == EngineStatus.running) await engine.drainOutbox();
    } finally {
      await engine.close();
      await api.close();
      await db.close();
    }
  }

  Future<void> _withEngine(
    CliArgs args,
    CliHome home,
    Future<void> Function(Engine engine, CliArgs args) command, {
    bool live = false,
  }) => _open(args, home, (engine, _) => command(engine, args), live: live);

  // ------------------------------------------------------------ account

  Future<String> _secret(
    CliArgs args,
    String envOption,
    String prompt, {
    bool required = true,
  }) async {
    final name = args.option(envOption);
    if (name != null) {
      final value = io.env[name];
      if (value == null || value.isEmpty) {
        throw CliError('the environment variable $name is not set');
      }
      return value;
    }
    final line = await io.readLine(prompt, secret: true);
    if (line == null || (required && line.isEmpty)) {
      throw CliError('no $prompt given');
    }
    return line;
  }

  String _phone(CliArgs args) {
    final phone = args.option('phone');
    if (phone == null || !RegExp(r'^\+[0-9]{8,15}$').hasMatch(phone)) {
      throw CliUsageError('--phone needs a number like +8801711000001');
    }
    return phone;
  }

  Future<void> _register(CliArgs args, CliHome home) async {
    final server = _server(args, home);
    final inviteEnv = args.option('invite-env');
    await _open(
      args,
      home,
      (engine, _) async {
        if (inviteEnv != null) {
          final invite = io.env[inviteEnv];
          if (invite == null || invite.isEmpty) {
            throw CliError('the environment variable $inviteEnv is not set');
          }
          await engine.account.register(
            inviteCode: invite,
            password: args.option('password-env') == null
                ? null
                : await _secret(args, 'password-env', 'password'),
            deviceName: args.option('device-name'),
          );
        } else {
          final phone = _phone(args);
          final challenge = await engine.account.requestPhoneCode(phone);
          io.err('a code was sent to ${maskPhone(phone)}');
          final code = args.option('code-env') != null
              ? await _secret(args, 'code-env', 'code')
              : (await io.readLine('code', secret: true)) ?? '';
          final verified = await engine.account.verifyPhone(
            challenge.challengeId,
            code.trim(),
          );
          if (verified.accountExists && !args.flag('replace')) {
            throw CliError(
              'this number already has an account: use login, or pass '
              "--replace to take it over (this ends the old account's devices)",
            );
          }
          await engine.account.register(
            verificationToken: verified.verificationToken,
            phoneNumber: phone,
            password: args.option('password-env') == null
                ? null
                : await _secret(args, 'password-env', 'password'),
            accountId: verified.accountExists ? verified.accountId : null,
            replaceExisting: verified.accountExists,
            deviceName: args.option('device-name'),
          );
        }
        home.saveServer(server.toString());
        _printIdentity(engine, 'registered');
      },
      createKey: true,
      requireAccount: false,
    );
  }

  Future<void> _login(CliArgs args, CliHome home) async {
    final server = _server(args, home);
    final phone = _phone(args);
    await _open(
      args,
      home,
      (engine, _) async {
        await engine.account.signInWithPassword(
          phoneNumber: phone,
          password: await _secret(args, 'password-env', 'password'),
          deviceName: args.option('device-name'),
        );
        home.saveServer(server.toString());
        _printIdentity(engine, 'signed in');
      },
      createKey: true,
      requireAccount: false,
    );
  }

  Future<void> _link(CliArgs args, CliHome home) async {
    final server = _server(args, home);
    await _open(
      args,
      home,
      (engine, _) async {
        final link = await engine.account.beginLink(
          deviceName: args.option('device-name'),
        );
        // The link code is meant to be shown (as a QR code or text): it holds
        // a one-time public key, not a secret.
        if (_json) {
          io.out(jsonEncode({'link_code': link.code}));
        } else {
          io.out(
            'On a signed-in device run:  helix_v2 link-approve ${link.code}',
          );
          io.err('waiting for approval (10 minutes)...');
        }
        await link.complete();
        home.saveServer(server.toString());
        _printIdentity(engine, 'linked');
      },
      createKey: true,
      requireAccount: false,
    );
  }

  Future<void> _linkApprove(Engine engine, CliArgs args) async {
    if (args.positional.isEmpty) {
      throw CliUsageError('link-approve needs the code the new device shows');
    }
    await engine.devices.approveLink(args.positional.first);
    _print({'approved': true}, 'link approved');
  }

  void _printIdentity(Engine engine, String what) => _print(
    {'result': what, 'account': engine.accountId, 'device': engine.deviceId},
    '$what: account ${shortId(engine.accountId!)}, '
    'device ${shortId(engine.deviceId!)}',
  );

  Future<void> _status(CliArgs args, CliHome home) async {
    final server =
        args.option('server') ?? io.env['HELIX_SERVER'] ?? home.savedServer();
    if (!home.databaseFile.existsSync()) {
      _print({'signed_in': false}, 'not signed in (no database yet)');
      return;
    }
    await _open(args, home, (engine, _) async {
      final account = await engine.account.current();
      _print(
        {
          'signed_in': account != null,
          'server': server,
          'account': account?.accountId,
          'device': account?.deviceId,
          'phone': account?.phoneNumber == null
              ? null
              : maskPhone(account!.phoneNumber!),
          'database': home.databaseFile.path,
        },
        account == null
            ? 'not signed in'
            : 'signed in as ${shortId(account.accountId)} '
                  '(device ${shortId(account.deviceId)}) on $server\n'
                  'database: ${home.databaseFile.path}',
      );
    }, requireAccount: false);
  }

  Future<void> _logout(Engine engine, CliArgs args) async {
    await engine.signOut();
    _print({'signed_out': true}, 'signed out; the local database was wiped');
  }

  // ------------------------------------------------------------- people

  Future<void> _contacts(Engine engine, CliArgs args) async {
    final action = args.positional.isEmpty ? 'list' : args.positional.first;
    final rest = args.positional.skip(1).toList();
    switch (action) {
      case 'add':
        if (rest.isEmpty) throw CliUsageError('contacts add needs a number');
        final person = await engine.people.findByNumber(rest.first);
        if (person == null) {
          throw CliError('no Helix account for ${maskPhone(rest.first)}');
        }
        final name = args.option('name');
        if (name != null) {
          await engine.people.setNickname(person.accountId, name);
        }
        _printPerson((await engine.people.person(person.accountId))!, 'found');
      case 'find':
        if (rest.isEmpty) throw CliUsageError('contacts find needs a ~name');
        final person = await engine.people.findByHelixName(rest.first);
        if (person == null) throw CliError('no account named ${rest.first}');
        _printPerson(person, 'found');
      case 'list':
        final people = await engine.people.list();
        if (_json) {
          io.out(
            jsonEncode({
              'contacts': [for (final p in people) _personJson(p)],
            }),
          );
        } else if (people.isEmpty) {
          io.out('no contacts yet');
        } else {
          for (final p in people) {
            io.out('${shortId(p.accountId)}  ${_name(p)}');
          }
        }
      default:
        throw CliUsageError('contacts: add, find or list');
    }
  }

  Future<void> _block(Engine engine, CliArgs args) async {
    if (args.positional.isEmpty) {
      throw CliUsageError('${args.command} needs a peer');
    }
    final account = await _resolvePeer(engine, args.positional.first);
    if (args.command == 'block') {
      await engine.people.block(account);
    } else {
      await engine.people.unblock(account);
    }
    _print({args.command!: account}, '${args.command}ed ${shortId(account)}');
  }

  // ----------------------------------------------------------- messages

  Future<void> _chats(Engine engine, CliArgs args) async {
    final items = await engine.chats.watchChats().first;
    final rows = <Map<String, Object?>>[];
    for (final item in items) {
      final peer = item.conversation.id.substring('direct:'.length);
      final person = await engine.people.person(peer);
      rows.add({
        'conversation': item.conversation.id,
        'peer': peer,
        'name': person == null ? shortId(peer) : _name(person),
        'unread': item.conversation.unreadCount,
        'last': item.lastMessage?.deletedAt != null
            ? '(deleted)'
            : item.conversation.lastMessagePreview,
      });
    }
    if (_json) {
      io.out(jsonEncode({'chats': rows}));
    } else if (rows.isEmpty) {
      io.out('no chats yet');
    } else {
      for (final r in rows) {
        io.out(
          '${shortId(r['peer']! as String)}  ${r['name']}'
          "${(r['unread']! as int) > 0 ? '  (${r['unread']} unread)' : ''}"
          '  ${r['last'] ?? ''}',
        );
      }
    }
  }

  Future<void> _send(Engine engine, CliArgs args) async {
    if (args.positional.length < 2) throw CliUsageError('send PEER TEXT...');
    final account = await _resolvePeer(engine, args.positional.first);
    final text = args.positional.skip(1).join(' ');
    final chat = await engine.chats.openDirect(account);
    final row = await engine.chats.sendText(chat.id, text);
    await engine.drainOutbox();
    final status = (await engine.chats.message(row.localRowid))!.status;
    _print(
      {'id': row.messageId, 'status': status.name, 'conversation': chat.id},
      status == MessageStatus.pending
          ? 'queued (the server could not be reached; it will go out on the '
                'next run)'
          : 'sent',
    );
  }

  Future<void> _chat(Engine engine, CliArgs args) async {
    if (args.positional.isEmpty) throw CliUsageError('chat needs a peer');
    final account = await _resolvePeer(engine, args.positional.first);
    final chat = await engine.chats.openDirect(account);
    final person = await engine.people.person(account);
    final label = person == null ? shortId(account) : _name(person);
    final subscription = engine.events.listen((event) {
      if (event is IncomingMessageEvent &&
          event.notice.conversationId == chat.id) {
        _printIncoming(label, event.notice.preview, event.notice.sentAt);
        unawaited(engine.chats.markRead(chat.id));
      }
    });
    io.err('chatting with $label; /quit to leave');
    try {
      while (true) {
        final line = await io.readLine('>');
        if (line == null || line.trim() == '/quit') break;
        if (line.trim().isEmpty) continue;
        await engine.chats.sendText(chat.id, line);
      }
    } finally {
      await subscription.cancel();
    }
  }

  void _printIncoming(String from, String text, DateTime at) {
    if (_json) {
      io.out(
        jsonEncode({'from': from, 'text': text, 'at': at.toIso8601String()}),
      );
    } else {
      io.out('$from: $text');
    }
  }

  Future<void> _read(Engine engine, CliArgs args) async {
    if (args.positional.isEmpty) throw CliUsageError('read needs a peer');
    final account = await _resolvePeer(engine, args.positional.first);
    final id = directConversationId(account);
    final limit = int.tryParse(args.option('limit') ?? '') ?? 20;
    final page = await engine.chats.pageOlder(id, limit: limit);
    final person = await engine.people.person(account);
    final label = person == null ? shortId(account) : _name(person);
    final rows = [
      for (final m in page.messages)
        {
          'id': m.messageId,
          'from': m.outgoing ? 'me' : label,
          'sender': m.sender,
          'at': m.sentAt.toIso8601String(),
          'kind': m.kind,
          'text': m.deletedAt != null ? null : m.body,
          'deleted': m.deletedAt != null,
          'edited': m.editedAt != null,
          'status': m.status.name,
        },
    ];
    if (_json) {
      io.out(jsonEncode({'messages': rows}));
    } else if (rows.isEmpty) {
      io.out('no messages');
    } else {
      for (final r in rows) {
        final text = r['deleted'] == true
            ? '(deleted)'
            : (r['text'] ?? '(${r['kind']})');
        io.out(
          '[${r['at']}] ${r['from']}: $text'
          "${r['edited'] == true ? ' (edited)' : ''}",
        );
      }
    }
    await engine.chats.markRead(id);
  }

  Future<void> _react(Engine engine, CliArgs args) async {
    if (args.positional.length < 3) {
      throw CliUsageError('react PEER MESSAGE_ID EMOJI');
    }
    final account = await _resolvePeer(engine, args.positional.first);
    final prefix = args.positional[1];
    final page = await engine.chats.pageOlder(
      directConversationId(account),
      limit: 200,
    );
    final matches = page.messages
        .where((m) => m.messageId.startsWith(prefix))
        .toList();
    if (matches.length != 1) {
      throw CliError(
        matches.isEmpty ? 'no such message' : 'ambiguous message id',
      );
    }
    await engine.chats.react(matches.single.localRowid, args.positional[2]);
    _print({'reacted': matches.single.messageId}, 'reacted');
  }

  Future<void> _fetch(Engine engine, CliArgs args) async {
    final summary = await engine.syncOnce();
    if (_json) {
      io.out(
        jsonEncode({
          'processed': summary.processed,
          'complete': summary.complete,
          if (args.flag('show'))
            'messages': [
              for (final n in summary.notices)
                {
                  'conversation': n.conversationId,
                  'sender': n.sender,
                  'text': n.preview,
                },
            ],
        }),
      );
      return;
    }
    io.out(
      '${summary.processed} new envelope${summary.processed == 1 ? '' : 's'}'
      "${summary.complete ? '' : ' (more waiting)'}",
    );
    if (args.flag('show')) {
      for (final n in summary.notices) {
        final person = await engine.people.person(n.sender);
        _printIncoming(
          person == null ? shortId(n.sender) : _name(person),
          n.preview,
          n.sentAt,
        );
      }
    }
  }

  Future<void> _watch(Engine engine, CliArgs args) async {
    final count = int.tryParse(args.option('count') ?? '');
    final timeout = int.tryParse(args.option('timeout') ?? '');
    final done = Completer<void>();
    var seen = 0;
    final subscription = engine.events.listen((event) async {
      if (event is! IncomingMessageEvent) return;
      final person = await engine.people.person(event.notice.sender);
      _printIncoming(
        person == null ? shortId(event.notice.sender) : _name(person),
        event.notice.preview,
        event.notice.sentAt,
      );
      if (count != null && ++seen >= count && !done.isCompleted) {
        done.complete();
      }
    });
    // Catch up first: whatever arrived while no socket was open.
    await engine.syncOnce();
    try {
      await Future.any([
        done.future,
        io.interrupted,
        if (timeout != null) Future<void>.delayed(Duration(seconds: timeout)),
      ]);
    } finally {
      await subscription.cancel();
    }
  }

  // ------------------------------------------------------------ devices

  Future<void> _devices(Engine engine, CliArgs args) async {
    final action = args.positional.isEmpty ? 'list' : args.positional.first;
    switch (action) {
      case 'list':
        final devices = await engine.devices.refresh();
        if (_json) {
          io.out(
            jsonEncode({
              'devices': [
                for (final d in devices)
                  {
                    'device': d.deviceId,
                    'name': d.name,
                    'platform': d.platform,
                    'this_device': d.isThisDevice,
                  },
              ],
            }),
          );
        } else {
          for (final d in devices) {
            io.out(
              '${shortId(d.deviceId)}  ${d.name ?? '-'}  ${d.platform ?? '-'}'
              "${d.isThisDevice ? '  (this device)' : ''}",
            );
          }
        }
      case 'revoke':
        if (args.positional.length < 2) {
          throw CliUsageError('devices revoke ID');
        }
        final prefix = args.positional[1];
        final matches = [
          for (final d in await engine.devices.list())
            if (d.deviceId.startsWith(prefix)) d,
        ];
        if (matches.length != 1) {
          throw CliError(
            matches.isEmpty ? 'no such device' : 'ambiguous device id',
          );
        }
        await engine.devices.revoke(
          matches.single.deviceId,
          lost: args.flag('lost'),
        );
        _print({'revoked': matches.single.deviceId}, 'revoked');
      case 'revoke-others':
        final n = await engine.devices.revokeOthers();
        _print({'revoked': n}, 'revoked $n device${n == 1 ? '' : 's'}');
      default:
        throw CliUsageError('devices: list, revoke ID or revoke-others');
    }
  }

  // -------------------------------------------------------------- output

  void _print(Map<String, Object?> json, String human) =>
      io.out(_json ? jsonEncode(json) : human);

  void _printPerson(PersonRow person, String what) => _print(
    _personJson(person),
    '$what: ${shortId(person.accountId)}  ${_name(person)}',
  );

  Map<String, Object?> _personJson(PersonRow p) => {
    'account': p.accountId,
    'name': _name(p),
    'phone': p.phoneNumber == null ? null : maskPhone(p.phoneNumber!),
    'helix_name': p.helixName,
    'blocked': p.blocked,
  };

  /// A person's display name with any phone number masked.
  String _name(PersonRow person) {
    final name = PersonNaming.displayName(person);
    return RegExp(r'^\+?[0-9 ]{6,}$').hasMatch(name) ? maskPhone(name) : name;
  }

  /// Turns "+number", "~name", a contact name or an id prefix into an
  /// account id.
  Future<String> _resolvePeer(Engine engine, String spec) async {
    if (Uuid.isValid(spec)) return spec;
    if (RegExp(r'^\+[0-9]{8,15}$').hasMatch(spec)) {
      for (final p in await engine.people.list()) {
        if (p.phoneNumber == spec) return p.accountId;
      }
      final found = await engine.people.findByNumber(spec);
      if (found == null) {
        throw CliError('no Helix account for ${maskPhone(spec)}');
      }
      return found.accountId;
    }
    if (spec.startsWith('~')) {
      final name = spec.substring(1).toLowerCase();
      for (final p in await engine.people.list()) {
        if (p.helixName == name) return p.accountId;
      }
      final found = await engine.people.findByHelixName(spec);
      if (found == null) throw CliError('no account named $spec');
      return found.accountId;
    }
    final people = await engine.people.list();
    final lower = spec.toLowerCase();
    final byId = [
      for (final p in people)
        if (p.accountId.startsWith(lower)) p,
    ];
    if (byId.length == 1) return byId.single.accountId;
    final byName = [
      for (final p in people)
        if (_name(p).toLowerCase() == lower) p,
    ];
    final candidates = byName.isNotEmpty
        ? byName
        : [
            for (final p in people)
              if (_name(p).toLowerCase().contains(lower)) p,
          ];
    if (candidates.length == 1) return candidates.single.accountId;
    throw CliError(
      candidates.isEmpty && byId.isEmpty
          ? 'unknown contact "$spec" (use +number or ~name to look someone up)'
          : 'ambiguous contact "$spec"',
    );
  }
}
