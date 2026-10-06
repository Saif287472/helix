import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/core/calls/place_call.dart';
import 'package:helix_remote/features/groups/application/group_models.dart';

import '../support/call_support.dart';

/// The seam every call button reads, and the one secret the group models hold.
void main() {
  test('the conversation header and contact info place calls through '
      'placeCallProvider', () async {
    final port = FakeCallsPort();
    final container = ProviderContainer(overrides: callOverrides(port: port));
    addTearDown(container.dispose);

    final outcome = await container.read(placeCallProvider)(
      'peer-9',
      video: true,
    );

    expect(outcome.started, isTrue);
    expect(port.calls, ['start peer-9 video:true']);
  });

  test(
    'a seam override is how another feature tests its call button',
    () async {
      final calls = <String>[];
      final container = ProviderContainer(
        overrides: [
          placeCallProvider.overrideWithValue((peer, {required video}) async {
            calls.add('$peer $video');
            return const PlaceCallOutcome(PlaceCallStatus.busy, 'busy');
          }),
        ],
      );
      addTearDown(container.dispose);

      final outcome = await container.read(placeCallProvider)(
        'p',
        video: false,
      );
      expect(outcome.started, isFalse);
      expect(outcome.message, 'busy');
      expect(calls, ['p false']);
    },
  );

  test('an invite link never shows up in a log line', () {
    final link = const InviteLinkInfo(
      linkId: 'id1',
      link: 'https://srv.example/open#HLX-GRP-secret.key',
      requiresApproval: false,
    );
    expect('$link', isNot(contains('secret')));
    expect('$link', contains('redacted'));
  });
}
