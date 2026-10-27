import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/core/chat/chat_gateway.dart';
import 'package:helix_remote/core/people/people_names.dart';
import 'package:helix_remote/core/platform/chat_platform.dart';
import 'package:helix_remote/features/chats/application/chat_actions.dart';
import 'package:helix_remote/features/chats/application/chat_list_provider.dart';

import 'support/chat_harness.dart';

/// The person's own lists: made through the chat actions, kept in the
/// database, and read back as the chips and the rows' memberships.
void main() {
  test('a list is made holding chats, renamed, emptied and deleted', () async {
    final gateway = await TestChatGateway.create();
    addTearDown(gateway.close);
    final bob = await gateway.chatWith('bob', name: 'Bob');
    final cara = await gateway.chatWith('cara', name: 'Cara');
    final container = ProviderContainer(
      overrides: [
        chatGatewayProvider.overrideWith((ref) => gateway),
        peopleRowsProvider.overrideWith(
          (ref) => gateway.engine.people.watchAll(),
        ),
        clockProvider.overrideWithValue(() => testNow),
      ],
    );
    addTearDown(container.dispose);
    container.listen(chatListsProvider, (_, _) {});
    container.listen(chatListMembershipProvider, (_, _) {});
    Future<void> tick() =>
        Future<void>.delayed(const Duration(milliseconds: 100));

    final actions = container.read(chatActionsProvider);
    expect(await actions.createList('Work', {bob}), isNull);
    await tick();
    final lists = await container.read(chatListsProvider.future);
    expect(lists.map((l) => l.name), ['Work']);
    final work = lists.single.id;
    expect(await container.read(chatListMembershipProvider.future), {
      bob: [work],
    });

    await actions.setOnList({cara}, work, member: true);
    await actions.setOnList({bob}, work, member: false);
    await tick();
    expect(await container.read(chatListMembershipProvider.future), {
      cara: [work],
    });

    expect(await actions.renameList(work, 'Office'), isNull);
    await tick();
    expect(
      (await container.read(chatListsProvider.future)).single.name,
      'Office',
    );

    await actions.deleteList(work);
    await tick();
    expect(await container.read(chatListsProvider.future), isEmpty);
    expect(await container.read(chatListMembershipProvider.future), isEmpty);
  });

  test(
    'a bad or taken name is refused with a sentence, not an error',
    () async {
      final gateway = await TestChatGateway.create();
      addTearDown(gateway.close);
      final container = ProviderContainer(
        overrides: [
          chatGatewayProvider.overrideWith((ref) => gateway),
          clockProvider.overrideWithValue(() => testNow),
        ],
      );
      addTearDown(container.dispose);
      final actions = container.read(chatActionsProvider);
      expect(await actions.createList('Work', {}), isNull);
      expect(await actions.createList('work', {}), contains('already'));
      expect(await actions.createList('   ', {}), contains('1 to 24'));
      expect(await actions.createList('x' * 25, {}), contains('1 to 24'));
    },
  );
}
