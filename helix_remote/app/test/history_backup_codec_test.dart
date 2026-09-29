import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/app/history_backup_codec.dart';

Map<String, dynamic> _message(String id, int ts, String text) => {
  'id': id,
  'conversation_id': 'c1',
  'sender_account_id': 'alice',
  'ts': ts,
  'text': text,
};

void main() {
  test('every device of the account derives the same key', () async {
    final identity = await Ed25519().newKeyPair();
    final seed = await identity.extractPrivateKeyBytes();
    expect(
      await HistoryBackupCodec.deriveKey(seed),
      await HistoryBackupCodec.deriveKey(List.of(seed)),
    );
  });

  test('a backup round-trips and is bound to its identity', () async {
    final key = await HistoryBackupCodec.deriveKey(List.filled(32, 7));
    final snapshot = {
      'v': 1,
      'conversations': {
        'c1': {
          'title': 'Bob',
          'members': ['alice', 'bob'],
        },
      },
      'messages': [_message('m1', 1, 'hello')],
    };
    final blob = await HistoryBackupCodec.encrypt(
      key: key,
      identityPublicKey: 'identity-1',
      snapshot: snapshot,
    );
    expect(blob, isNot(contains('hello')));
    expect(
      await HistoryBackupCodec.decrypt(
        key: key,
        identityPublicKey: 'identity-1',
        blob: blob,
      ),
      snapshot,
    );
    await expectLater(
      HistoryBackupCodec.decrypt(
        key: key,
        identityPublicKey: 'identity-2',
        blob: blob,
      ),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
    await expectLater(
      HistoryBackupCodec.decrypt(
        key: await HistoryBackupCodec.deriveKey(List.filled(32, 8)),
        identityPublicKey: 'identity-1',
        blob: blob,
      ),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
  });

  test('merging keeps both histories and prefers this device', () {
    final merged = HistoryBackupCodec.merge(
      {
        'conversations': {
          'c1': {'title': 'old'},
        },
        'messages': [
          _message('m1', 1, 'from the phone'),
          _message('m2', 2, 'x'),
        ],
      },
      {
        'conversations': {
          'c1': {'title': 'new'},
          'c2': {'title': 'Tablet chat'},
        },
        'messages': [
          _message('m2', 2, 'edited here'),
          _message('m3', 3, 'new'),
        ],
      },
    );
    final messages = (merged['messages'] as List).cast<Map<String, dynamic>>();
    expect(messages.map((m) => m['id']), ['m1', 'm2', 'm3']);
    expect(messages[1]['text'], 'edited here');
    expect((merged['conversations'] as Map).keys, {'c1', 'c2'});
    expect((merged['conversations'] as Map)['c1'], {'title': 'new'});
  });
}
