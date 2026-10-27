import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/core/chat/chat_gateway.dart';
import 'package:helix_remote/core/people/people_names.dart';
import 'package:helix_remote/core/platform/chat_platform.dart';
import 'package:helix_remote/features/chats/application/chat_actions.dart';
import 'package:helix_remote/features/chats/application/chat_list_provider.dart';
import 'package:orbit_ui/models.dart';

import 'support/chat_harness.dart';

/// A favourite chat: set from the selection menu, kept in the chat's row, and
/// drawn as a flag of the chat list's row.
void main() {
  test('chats are made favourites, and not, and the list says which', () async {
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
    container.listen(chatListProvider, (_, _) {});

    Future<Map<String, bool>> favourites() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final items = await container.read(chatListProvider.future);
      return {for (final HelixChatListItem c in items) c.id: c.favourite};
    }

    expect(await favourites(), {bob: false, cara: false});

    final actions = container.read(chatActionsProvider);
    await actions.favourite([bob, cara], favourite: true);
    expect(await favourites(), {bob: true, cara: true});

    await actions.favourite([bob], favourite: false);
    expect(await favourites(), {bob: false, cara: true});
  });
}
