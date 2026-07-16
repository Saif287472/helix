import 'dart:io';

// Returns true for host strings that are LAN-reachable without WAN relay:
//   IPv4: RFC1918 (10/8, 172.16/12, 192.168/16), link-local (169.254/16), loopback (127/8)
//   IPv6: ULA (fc00::/7), link-local (fe80::/10), loopback (::1)
// Global-unicast IPv6 (2xxx::/4) and WAN IPv4 are rejected.
bool isLanCandidate(String host) {
  // Strip IPv6 zone ID (fe80::1%eth0 → fe80::1)
  final h = host.contains('%') ? host.substring(0, host.indexOf('%')) : host;

  final addr = InternetAddress.tryParse(h);
  if (addr == null) return false;

  if (addr.type == InternetAddressType.IPv4) {
    final parts = addr.address.split('.');
    if (parts.length != 4) return false;
    final b = parts.map((s) => int.tryParse(s) ?? -1).toList();
    if (b.any((x) => x < 0 || x > 255)) return false;

    if (b[0] == 127) return true; // loopback
    if (b[0] == 10) return true; // 10.0.0.0/8
    if (b[0] == 172 && b[1] >= 16 && b[1] <= 31) return true; // 172.16-31.x.x
    if (b[0] == 192 && b[1] == 168) return true; // 192.168.x.x
    if (b[0] == 169 && b[1] == 254) return true; // 169.254.x.x link-local
    return false; // WAN IPv4
  }

  if (addr.type == InternetAddressType.IPv6) {
    if (addr.isLoopback) return true; // ::1
    final raw = addr.rawAddress;
    if (raw.length != 16) return false;
    final first = (raw[0] << 8) | raw[1];
    // ULA: fc00::/7 → first byte 0xFC or 0xFD (bits: 1111 110x)
    if (raw[0] >= 0xFC && raw[0] <= 0xFD) return true;
    // link-local: fe80::/10 → first 10 bits 1111 1110 10
    if ((first & 0xFFC0) == 0xFE80) return true;
    return false; // global unicast, multicast, etc.
  }

  return false;
}
