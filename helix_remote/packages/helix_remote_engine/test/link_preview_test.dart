import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:test/test.dart';

import 'support/peers.dart';

/// A link preview the sender attached arrives with the message.
void main() {
  late Peers peers;
  late Peer alice;
  late Peer bob;

  setUp(() async {
    peers = Peers();
    alice = await peers.register('alice', phone: '+8801711000001');
    bob = await peers.register('bob', phone: '+8801711000002');
  });
  tearDown(() => peers.dispose());

  test('reaches the reader as part of the message', () async {
    final chat = await alice.engine.chats.openDirect(bob.account);
    await alice.engine.chats.sendText(
      chat.id,
      'read this https://example.org/post',
      linkPreview: const LinkPreview(
        url: 'https://example.org/post',
        title: 'A post',
        description: 'About a thing.',
      ),
    );
    await alice.engine.drainOutbox();
    await bob.sync();

    final row = (await bob.messages(alice)).single;
    expect(row.body, 'read this https://example.org/post');
    expect(row.payload, contains('"link_preview"'));
    expect(row.payload, contains('A post'));
    expect(row.payload, contains('About a thing.'));
  });

  test('a message without one has none', () async {
    final chat = await alice.engine.chats.openDirect(bob.account);
    await alice.engine.chats.sendText(chat.id, 'plain https://example.org');
    await alice.engine.drainOutbox();
    await bob.sync();
    expect(
      (await bob.messages(alice)).single.payload ?? '',
      isNot(contains('link_preview')),
    );
  });

  test('a preview for a link that is not in the text is refused', () async {
    final chat = await alice.engine.chats.openDirect(bob.account);
    await expectLater(
      alice.engine.chats.sendText(
        chat.id,
        'hello',
        linkPreview: const LinkPreview(url: 'https://example.org/post'),
      ),
      throwsArgumentError,
    );
    expect(await alice.messages(bob), isEmpty);
  });
}
