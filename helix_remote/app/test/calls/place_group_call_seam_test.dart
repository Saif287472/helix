import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/core/calls/call_launcher.dart';
import 'package:helix_remote/features/conversation/application/conversation_header.dart';
import 'package:orbit_ui/models.dart';

import '../support/call_support.dart';

/// The group chat's call button: the launcher the header reads, and when the
/// header offers calls in a group at all.
void main() {
  test(
    'the header launcher starts a group call through the group port',
    () async {
      final groups = FakeGroupCallsPort();
      final container = ProviderContainer(
        overrides: callOverrides(port: FakeCallsPort(), groups: groups),
      );
      addTearDown(container.dispose);

      final said = await container
          .read(callLauncherProvider)
          .startGroup('group:g1', invite: ['peer-1', 'peer-2'], video: true);

      expect(said, isNull);
      expect(groups.calls, hasLength(1));
      expect(groups.calls.single, contains('start'));
      expect(groups.calls.single, contains('group:g1'));
    },
  );

  test('a group offers calls only while someone can be rung', () {
    ConversationHeader group({
      List<HelixPersonItem> callees = const [],
      String? disabled,
    }) => ConversationHeader(
      id: 'group:g1',
      title: 'Friday crew',
      avatar: const HelixAvatarModel(name: 'Friday crew', isGroup: true),
      isGroup: true,
      callees: callees,
      composerDisabledReason: disabled,
    );
    const ada = HelixPersonItem(
      id: 'peer-1',
      names: HelixPersonNames(nickname: 'Ada'),
    );

    expect(group().canCall, isFalse);
    expect(group(callees: const [ada]).canCall, isTrue);
    // Out of the group: nobody to ring from here.
    expect(
      group(callees: const [ada], disabled: 'You can no longer send').canCall,
      isFalse,
    );
    // The callees are part of what changes the header.
    expect(group(callees: const [ada]), isNot(group()));
  });
}
