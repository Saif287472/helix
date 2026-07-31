import 'dart:io';
import 'package:helix_remote_cli/helix_remote_cli.dart';

void main(List<String> args) async {
  if (args.isEmpty ||
      args[0] == 'help' ||
      args[0] == '--help' ||
      args[0] == '-h') {
    _printHelp();
    return;
  }

  final command = args[0];
  final dbFile = File('helix_cli.db');
  final keyFile = File('.helix_cli_keys.json');

  final client = HelixCliClient(dbFile: dbFile, keyFile: keyFile);

  try {
    switch (command) {
      case 'bootstrap':
        if (args.length < 3) {
          print('Usage: bootstrap <accountId> <phoneHash> [deviceId]');
          exit(1);
        }
        final accountId = args[1];
        final phoneHash = args[2];
        final deviceId = args.length > 3 ? args[3] : 'cli_device';
        print('Bootstrapping client identity for Account: $accountId...');
        await client.bootstrap(
          accountId: accountId,
          phoneHash: phoneHash,
          deviceId: deviceId,
          deviceName: 'CLI Terminal Client',
        );
        print('Success! Client identity bootstrapped.');
        break;

      case 'contacts':
        if (args.length < 2) {
          print('Usage: contacts <add|list> [peerAccountId] [nickname]');
          exit(1);
        }
        final action = args[1];
        if (action == 'add') {
          if (args.length < 4) {
            print('Usage: contacts add <peerAccountId> <nickname>');
            exit(1);
          }
          final peerId = args[2];
          final nick = args[3];
          client.addContact(peerId, nick);
          print('Contact added: $nick ($peerId).');
        } else if (action == 'list') {
          final list = client.listContacts();
          if (list.isEmpty) {
            print('No contacts found.');
          } else {
            print('Contacts Registry:');
            for (final c in list) {
              print('  - ${c.nickname} (${c.peerAccountId}) [${c.status}]');
            }
          }
        } else {
          print('Unknown contacts action: $action');
          exit(1);
        }
        break;

      case 'status':
        client.initialize();
        final identityPub = await client.storage.readKey('identity_public');
        if (identityPub == null) {
          print('Status: Client not bootstrapped.');
        } else {
          final accountId = await client.storage.readKey('account_id');
          final phoneHash = await client.storage.readKey('phone_hash');
          final deviceId = await client.storage.readKey('device_id');
          print('Helix CLI Client Status:');
          print('  Account ID: $accountId');
          print('  Phone hash: $phoneHash');
          print('  Device ID:  $deviceId');
          print('  Identity Public Key: $identityPub');
          print('  Database Path:       ${dbFile.absolute.path}');
        }
        break;

      default:
        print('Unknown command: $command');
        _printHelp();
        exit(1);
    }
  } catch (e) {
    print('Error executing command: $e');
    exit(1);
  }
}

void _printHelp() {
  print('Helix Remote CLI Client');
  print('Usage: main.dart <command> [arguments]');
  print('');
  print('Available commands:');
  print(
    '  bootstrap <accountId> <phoneHash> [deviceId]  Bootstrap local client identity & generate keypairs',
  );
  print(
    '  contacts add <peerAccountId> <nickname>       Add a new contact to registry',
  );
  print(
    '  contacts list                                 List all contacts in registry',
  );
  print(
    '  status                                        Display current bootstrap & account details',
  );
  print(
    '  help                                          Show this help manual',
  );
}
