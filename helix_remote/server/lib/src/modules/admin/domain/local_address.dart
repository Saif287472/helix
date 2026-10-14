import 'dart:io';

/// Whether [ip] (the request's client address, after the trusted-proxy
/// rules) is this machine or the local network: IPv4 loopback, private and
/// link-local ranges, IPv6 loopback, unique-local and link-local, and an
/// IPv4 one of those inside an IPv4-mapped IPv6 address.
///
/// Carrier-grade NAT (100.64.0.0/10) is *not* local: other customers of the
/// provider share it.
///
/// Admin sign-in exempts these addresses from its global failure cap, so an
/// attacker on the internet cannot lock the operator at home out (review
/// B-08). If `HELIX_TRUSTED_PROXIES` misses the proxy, every request looks
/// local; the per-address lock still applies then.
bool isLocalNetworkAddress(String ip) {
  final address = InternetAddress.tryParse(ip);
  if (address == null) return false;
  var bytes = address.rawAddress;
  if (address.type == InternetAddressType.IPv6) {
    final mapped =
        bytes.sublist(0, 10).every((b) => b == 0) &&
        bytes[10] == 0xff &&
        bytes[11] == 0xff;
    if (!mapped) {
      return address.isLoopback ||
          // fc00::/7 unique local, fe80::/10 link-local.
          (bytes[0] & 0xfe) == 0xfc ||
          (bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80);
    }
    bytes = bytes.sublist(12, 16);
  }
  return bytes[0] == 127 ||
      bytes[0] == 10 ||
      (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
      (bytes[0] == 192 && bytes[1] == 168) ||
      (bytes[0] == 169 && bytes[1] == 254);
}
