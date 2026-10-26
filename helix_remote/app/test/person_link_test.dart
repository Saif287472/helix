import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/features/people/application/people_gateway.dart';
import 'package:helix_remote/features/people/application/people_search.dart';
import 'package:helix_remote/shared/navigation/conversation_seams.dart';
import 'package:helix_remote_api/v2.dart' show ApiException, NetworkException;
import 'package:helix_remote_db/helix_remote_db.dart' show directConversationId;
import 'package:helix_remote_protocol/helix_remote_protocol.dart'
    show ErrorCode;

import 'support/people_fakes.dart';

/// A `~name` link is the one link whose destination has to be looked up before
/// anything can be opened, so what that lookup says when it cannot answer is
/// the whole of the link's UI.
void main() {
  late FakePeopleGateway gateway;
  late FakeSeams seams;
  late ProviderContainer container;

  setUp(() {
    gateway = FakePeopleGateway();
    seams = FakeSeams();
    container = ProviderContainer(
      overrides: [
        peopleGatewayProvider.overrideWith((ref) async => gateway),
        conversationSeamsProvider.overrideWithValue(seams),
      ],
    );
    addTearDown(container.dispose);
  });

  Future<String?> resolve(String name) =>
      container.read(peopleActionsProvider).openPersonLink(name);

  test('a name that resolves opens the chat and says nothing', () async {
    gateway.byHelixName['anna'] = personRow('acct-1', helix: 'anna');

    expect(await resolve('anna'), isNull);
    expect(seams.opened, [directConversationId('acct-1')]);
    expect(gateway.calls, contains('findByHelixName:anna'));
  });

  test('a name that answers to nobody opens nothing', () async {
    final message = await resolve('ghost');

    expect(seams.opened, isEmpty);
    expect(
      message,
      'No Orbit account is called ~ghost on your server, '
      'or it is not findable by name.',
      reason:
          'one sentence for both reasons, because the server does not say '
          'which one it is',
    );
  });

  test('your own name opens the chat you keep your notes in', () async {
    gateway.byHelixName['me'] = personRow('self-account', helix: 'me');

    expect(await resolve('me'), isNull);
    expect(seams.opened, [directConversationId('self-account')]);
  });

  test('a failed lookup is one plain sentence', () async {
    gateway.lookupError = const ApiException(
      status: 429,
      code: ErrorCode.rateLimited,
    );
    expect(await resolve('anna'), 'Too many lookups. Try again later.');

    gateway.lookupError = const NetworkException();
    expect(await resolve('bella'), 'No connection to your server.');

    // Whatever else went wrong, the reason never reaches the screen: it can
    // name an account or carry a server's own text.
    gateway.lookupError = StateError('secret detail');
    final message = await resolve('carol');
    expect(message, 'That lookup did not work. Try again.');
    expect(message, isNot(contains('secret')));
    expect(seams.opened, isEmpty);
  });
}
