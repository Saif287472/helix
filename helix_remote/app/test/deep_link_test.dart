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

  // NOTE: parsing is all these two kinds have. `bootstrap.dart` is the only
  // consumer of a parsed link and it matches HelixDeepLinkKind.invite, so a
  // tapped call or group-join link opens the app and does nothing further.
  // This test passing is not evidence that those links work end to end — it
  // asserts the parser, and the parser is not the missing half.
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
