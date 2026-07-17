import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:cryptography/cryptography.dart' as crypto;
import 'package:helix_remote_cli/helix_remote_cli.dart';
import 'package:helix_remote_crypto/helix_remote_crypto.dart';

void main() {
  late File tempDbFile;
  late File tempKeyFile;
  late HelixCliClient client;

  setUp(() {
    tempDbFile = File('test_cli_db.db');
    if (tempDbFile.existsSync()) {
      tempDbFile.deleteSync();
    }
    tempKeyFile = File('test_cli_keys.json');
    if (tempKeyFile.existsSync()) {
      tempKeyFile.deleteSync();
    }
    client = HelixCliClient(dbFile: tempDbFile, keyFile: tempKeyFile);
  });

  tearDown(() {
    client.close();
    if (tempDbFile.existsSync()) {
      tempDbFile.deleteSync();
    }
    if (tempKeyFile.existsSync()) {
      tempKeyFile.deleteSync();
    }
  });

  test('CLI Bootstrapping and Local Identity Creation', () async {
    await client.bootstrap(
      accountId: 'alice_acc_1',
      username: 'alice',
      deviceId: 'device_cli_alice',
      deviceName: 'Alice CLI Client',
    );

    // Verify key persistence in Secure Storage
    final privIdentity = await client.storage.readKey('identity_private');
    final pubIdentity = await client.storage.readKey('identity_public');
    expect(privIdentity, isNotNull);
    expect(pubIdentity, isNotNull);

    final privDevice = await client.storage.readKey('device_private');
    final pubDevice = await client.storage.readKey('device_public');
    expect(privDevice, isNotNull);
    expect(pubDevice, isNotNull);

    final privSpk = await client.storage.readKey('spk_private');
    final pubSpk = await client.storage.readKey('spk_public');
    final sigSpk = await client.storage.readKey('spk_signature');
    expect(privSpk, isNotNull);
    expect(pubSpk, isNotNull);
    expect(sigSpk, isNotNull);

    // Verify record persistence in SQLite Database
    final localAccount = client.db.getAccount('alice_acc_1');
    expect(localAccount, isNotNull);
    expect(localAccount!.username, equals('alice'));
    expect(localAccount.identityPublicKey, equals(pubIdentity));

    final localDevices = client.db.getDevices('alice_acc_1');
    expect(localDevices, isNotEmpty);
    expect(localDevices[0].deviceId, equals('device_cli_alice'));
    expect(localDevices[0].deviceAgreementPublicKey, equals(pubDevice));
  });

  test('Contact Registry CRUD', () async {
    client.initialize();
    client.addContact('bob_acc_1', 'Bob');
    client.addContact('carol_acc_1', 'Carol');

    final contacts = client.listContacts();
    expect(contacts.length, equals(2));
    
    final bob = contacts.firstWhere((c) => c.peerAccountId == 'bob_acc_1');
    expect(bob.nickname, equals('Bob'));
    expect(bob.status, equals('active'));
  });

  test('Double Ratchet Session Persistence and Reconstruction', () async {
    final x25519 = crypto.X25519();
    final bobIdentityKey = await x25519.newKeyPair();
    final bobIdentityPublic = await bobIdentityKey.extractPublicKey();

    final sharedSecret = crypto.SecretKey(List.generate(32, (i) => i));

    // Initialize Alice session and encrypt a message
    final alice = await DoubleRatchetSession.initiate(
      sharedKey: sharedSecret,
      peerPublicKey: bobIdentityPublic,
    );

    final p1 = Uint8List.fromList('Hello Bob!'.codeUnits);
    final c1 = await alice.encrypt(p1);

    // Initialize Bob session and decrypt the message
    final bob = await DoubleRatchetSession.receive(
      sharedKey: sharedSecret,
      localKeyPair: bobIdentityKey,
    );
    final d1 = await bob.decrypt(c1);
    expect(d1, p1);

    // Save Bob's session to the CLI database
    await client.saveSession('session_bob_1', 'conv_1', bob, peerAccountId: 'alice_acc_1');

    // Reconstruct Bob's session from the CLI database
    final bobRestored = await client.loadSession('session_bob_1');
    expect(bobRestored, isNotNull);

    // Alice sends another message, bobRestored must decrypt it
    final p2 = Uint8List.fromList('How are you Alice?'.codeUnits);
    final c2 = await alice.encrypt(p2);
    final d2 = await bobRestored!.decrypt(c2);
    expect(d2, p2);
  });
}
