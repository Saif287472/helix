import 'package:helix_local_discovery/lan_candidate.dart';
import 'package:test/test.dart';

void main() {
  group('isLanCandidate — IPv4', () {
    test('accepts loopback', () {
      expect(isLanCandidate('127.0.0.1'), isTrue);
      expect(isLanCandidate('127.255.255.255'), isTrue);
    });

    test('accepts RFC1918 10/8', () {
      expect(isLanCandidate('10.0.0.1'), isTrue);
      expect(isLanCandidate('10.255.255.254'), isTrue);
    });

    test('accepts RFC1918 172.16-31.x.x', () {
      expect(isLanCandidate('172.16.0.1'), isTrue);
      expect(isLanCandidate('172.31.255.254'), isTrue);
    });

    test('rejects 172.15.x.x and 172.32.x.x (outside RFC1918 range)', () {
      expect(isLanCandidate('172.15.0.1'), isFalse);
      expect(isLanCandidate('172.32.0.1'), isFalse);
    });

    test('accepts RFC1918 192.168.x.x', () {
      expect(isLanCandidate('192.168.0.1'), isTrue);
      expect(isLanCandidate('192.168.255.254'), isTrue);
    });

    test('accepts IPv4 link-local 169.254.x.x', () {
      expect(isLanCandidate('169.254.1.1'), isTrue);
    });

    test('rejects WAN IPv4', () {
      expect(isLanCandidate('8.8.8.8'), isFalse);
      expect(isLanCandidate('1.1.1.1'), isFalse);
      expect(isLanCandidate('203.0.113.1'), isFalse);
      expect(isLanCandidate('192.169.0.1'), isFalse); // not 192.168
    });
  });

  group('isLanCandidate — IPv6', () {
    test('accepts loopback ::1', () {
      expect(isLanCandidate('::1'), isTrue);
    });

    test('accepts ULA fc00::/7 range', () {
      expect(isLanCandidate('fc00::1'), isTrue);
      expect(isLanCandidate('fd12:3456:789a::1'), isTrue);
      expect(isLanCandidate('fdff:ffff:ffff:ffff:ffff:ffff:ffff:ffff'), isTrue);
    });

    test('accepts IPv6 link-local fe80::/10', () {
      expect(isLanCandidate('fe80::1'), isTrue);
      expect(isLanCandidate('fe80::dead:beef'), isTrue);
      expect(isLanCandidate('febf::1'), isTrue);
    });

    test('strips zone ID from link-local before parsing', () {
      expect(isLanCandidate('fe80::1%eth0'), isTrue);
      expect(isLanCandidate('fe80::dead:beef%wlan0'), isTrue);
    });

    test('rejects global unicast IPv6', () {
      expect(isLanCandidate('2001:db8::1'), isFalse);
      expect(isLanCandidate('2606:4700:4700::1111'), isFalse); // Cloudflare DNS
    });

    test('rejects fec0::/10 (deprecated site-local)', () {
      // fec0 starts with 1111 1110 11 — not link-local (fe80::/10)
      // and not ULA (fc00::/7). These should be rejected.
      expect(isLanCandidate('fec0::1'), isFalse);
    });

    test('rejects multicast', () {
      expect(isLanCandidate('ff02::1'), isFalse);
    });
  });

  group('isLanCandidate — invalid input', () {
    test('returns false for non-IP strings', () {
      expect(isLanCandidate(''), isFalse);
      expect(isLanCandidate('not-an-ip'), isFalse);
      expect(isLanCandidate('hostname.local'), isFalse);
    });
  });
}
