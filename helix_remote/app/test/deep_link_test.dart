import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/app/deep_link.dart';

void main() {
  test('P6 invite deep link provides code and server for onboarding', () {
    final link = HelixDeepLink.tryParse(
      'helix://invite?code=inv-123&server=https%3A%2F%2Fchat.example',
    );

    expect(link?.kind, HelixDeepLinkKind.invite);
    expect(link?.inviteCode, 'inv-123');
    expect(link?.serverUrl, 'https://chat.example');
  });

  test('P6 call and group join links retain their explicit targets', () {
    final call = HelixDeepLink.tryParse('helix://call/call-42');
    final group = HelixDeepLink.tryParse(
      'helix://group/join?group=team&invite=invite-7',
    );

    expect(call?.callId, 'call-42');
    expect(group?.kind, HelixDeepLinkKind.groupJoin);
    expect(group?.groupId, 'team');
    expect(group?.inviteCode, 'invite-7');
  });
}
