import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/core/links/deep_link.dart';
import 'package:helix_remote/core/links/helix_code.dart';

/// The link rules from AGENTS.md and plan §7.
///
/// `helix://` URIs, and `https://helix.agiletechbd.com/open#HLX-…` where the
/// code travels in the **fragment** so a browser never sends it to the server.
/// Both forms must keep working: a broken link fails silently, which is the
/// worst way for it to fail.
void main() {
  group('the shared web link', () {
    test('carries the code in the fragment, so the server never sees it', () {
      const code = 'HLX-REC-abc123';
      final link = HelixDeepLink.tryParse(
        'https://helix.agiletechbd.com/open#$code',
      );

      expect(link, isNotNull);
      expect(link!.kind, HelixDeepLinkKind.serverCode);
      expect(link.setupCode, code);
      expect(
        link.setupCode,
        isNot(contains('invite=')),
        reason: 'the code is not a query parameter',
      );
    });

    test('accepts an invite code the same way', () {
      const code = 'HLX-INV-abc123';
      final link = HelixDeepLink.tryParse(
        'https://helix.agiletechbd.com/open#$code',
      );
      expect(link?.setupCode, code);
    });

    test('is case-insensitive about the prefix', () {
      final link = HelixDeepLink.tryParse(
        'https://helix.agiletechbd.com/open#hlx-rec-abc123',
      );
      expect(link?.setupCode, 'hlx-rec-abc123');
    });

    test('a fragment that is not a Helix code opens nothing', () {
      expect(
        HelixDeepLink.tryParse('https://helix.agiletechbd.com/open#hello'),
        isNull,
      );
    });

    test('a fragment that is percent-encoded is decoded first', () {
      final link = HelixDeepLink.tryParse(
        'https://helix.agiletechbd.com/open#HLX-REC-a%2Fb',
      );
      expect(link?.setupCode, 'HLX-REC-a/b');
    });
  });

  group('the helix:// scheme', () {
    test('carries a code as a query parameter', () {
      final link = HelixDeepLink.tryParse('helix://open?code=HLX-REC-abc123');
      expect(link?.kind, HelixDeepLinkKind.serverCode);
      expect(link?.setupCode, 'HLX-REC-abc123');
    });

    test('an old-style invite is upgraded into an opaque code', () {
      // A link shared by an older build names the server in the clear. It is
      // re-encoded before it reaches sign-in so only one code format reaches
      // the code page.
      final link = HelixDeepLink.tryParse(
        'helix://invite?code=INV-1&server=https%3A%2F%2Fchat.example',
      );

      expect(link?.kind, HelixDeepLinkKind.invite);
      final code = link!.setupCode!;
      expect(code, startsWith(kHelixInvitePrefix));
      expect(
        decodeHelixInviteCode(code),
        isNotNull,
        reason: 'the upgraded code is one the app can decode',
      );
    });

    test('opens a call', () {
      final link = HelixDeepLink.tryParse('helix://call/abc-123');
      expect(link?.kind, HelixDeepLinkKind.call);
      expect(link?.callId, 'abc-123');
    });

    test('opens a group join only when both parts are present', () {
      final good = HelixDeepLink.tryParse(
        'helix://group/join?group=g1&invite=INV-1',
      );
      expect(good?.kind, HelixDeepLinkKind.groupJoin);
      expect(good?.groupId, 'g1');

      // A group with no invite cannot be joined, and an invite with no group
      // names nothing.
      expect(HelixDeepLink.tryParse('helix://group/join?group=g1'), isNull);
      expect(HelixDeepLink.tryParse('helix://group/join?invite=INV-1'), isNull);
    });

    test('a contact link needs every field, and a known version', () {
      final link = HelixDeepLink.tryParse(
        'helix://contact/add?v=1&id=ID&a=ACCOUNT&n=NONCE&e=1700000000&s=SIG',
      );
      expect(link?.kind, HelixDeepLinkKind.contactAdd);
      expect(link?.contactAccountId, 'ACCOUNT');

      // Every part is load-bearing: a link missing any of them is refused
      // rather than half-honoured.
      expect(
        HelixDeepLink.tryParse('helix://contact/add?v=2&id=ID&a=A&n=N&e=1&s=S'),
        isNull,
        reason: 'an unknown version is refused, not guessed at',
      );
      expect(
        HelixDeepLink.tryParse('helix://contact/add?v=1&id=ID&a=A&n=N&e=1'),
        isNull,
        reason: 'no signature',
      );
    });
  });

  group('what is not a link', () {
    test('rejects empty input, whitespace and a bare slash', () {
      for (final input in ['', '   ', '/', 'not a uri at all']) {
        expect(HelixDeepLink.tryParse(input), isNull, reason: input);
      }
    });

    test('rejects an unknown helix host', () {
      expect(
        HelixDeepLink.tryParse('helix://somethingelse?code=HLX-REC-a'),
        isNull,
      );
    });

    test('rejects a web link that is not the /open page', () {
      expect(
        HelixDeepLink.tryParse('https://helix.agiletechbd.com/#HLX-REC-a'),
        isNull,
      );
    });

    test('an invite link with a host but no path segment is a server join', () {
      // `https://server.example/join?invite=CODE` is the shape a personal
      // server's operator shares.
      final link = HelixDeepLink.tryParse(
        'https://server.example/join?invite=INV-1',
      );
      expect(link?.kind, HelixDeepLinkKind.invite);
      expect(link?.serverUrl, 'https://server.example');
      expect(link?.setupCode, startsWith(kHelixInvitePrefix));
    });
  });

  group('the code codecs', () {
    test('an invite round-trips', () {
      final code = encodeHelixInviteCode(
        serverUrl: 'https://chat.example.org',
        inviteCode: 'INV-1',
      );
      expect(code, startsWith(kHelixInvitePrefix));

      final decoded = decodeHelixInviteCode(code);
      expect(decoded, isNotNull);
      expect(decoded!.serverUrl, 'https://chat.example.org');
      expect(decoded.inviteCode, 'INV-1');
    });

    test('a recovery code round-trips', () {
      final code = encodeHelixRecoveryCode(
        serverUrl: 'https://chat.example.org',
        accountId: 'acct-1',
        recoveryCode: 'rec-secret',
      );
      expect(code, startsWith(kHelixRecoveryPrefix));

      final decoded = decodeHelixRecoveryCode(code);
      expect(decoded, isNotNull);
      expect(decoded!.serverUrl, 'https://chat.example.org');
      expect(decoded.accountId, 'acct-1');
      expect(decoded.recoveryCode, 'rec-secret');
    });

    test('a trailing slash in the server URL does not change the code', () {
      final withSlash = encodeHelixInviteCode(
        serverUrl: 'https://chat.example.org/',
        inviteCode: 'INV-1',
      );
      final without = encodeHelixInviteCode(
        serverUrl: 'https://chat.example.org',
        inviteCode: 'INV-1',
      );
      expect(withSlash, without);
    });

    test('the recognisers agree with the prefixes', () {
      expect(isHelixInviteCode('HLX-INV-abc'), isTrue);
      expect(isHelixRecoveryCode('hlx-rec-abc'), isTrue);
      expect(isHelixInviteCode('HLX-REC-abc'), isFalse);
      expect(isHelixRecoveryCode('nonsense'), isFalse);
    });
  });
}
