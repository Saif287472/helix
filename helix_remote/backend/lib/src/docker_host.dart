import 'dart:io';

/// Parses the `Gateway` field of the default route (destination `00000000`)
/// out of the contents of Linux's `/proc/net/route`. The kernel stores it
/// as 4 little-endian hex bytes, e.g. `010012AC` -> bytes `01 00 12 AC` in
/// file order -> address read in reverse -> `172.18.0.1`. Returns null if
/// there's no default route line in the expected format.
String? parseDefaultGatewayFromRouteTable(String routeTableContents) {
  final lines = routeTableContents.split('\n');
  for (final line in lines.skip(1)) {
    final fields = line.trim().split(RegExp(r'\s+'));
    if (fields.length < 3 || fields[1] != '00000000') continue;
    final hex = fields[2];
    if (hex.length != 8 || int.tryParse(hex, radix: 16) == null) continue;
    final octets = [
      int.parse(hex.substring(6, 8), radix: 16),
      int.parse(hex.substring(4, 6), radix: 16),
      int.parse(hex.substring(2, 4), radix: 16),
      int.parse(hex.substring(0, 2), radix: 16),
    ];
    return octets.join('.');
  }
  return null;
}

/// Best-effort detection of "this container's Docker bridge gateway" - the
/// address a connection from the *host's own loopback interface* is
/// rewritten to appear as by the time it reaches a process inside the
/// container (a raw 127.0.0.1 packet can't cross a network-namespace
/// boundary unchanged, so Docker's bridge networking NATs it to the
/// gateway address instead). This only happens for connections genuinely
/// originating from the host loopback via a published port - a real
/// external client, or another container reaching this one over the
/// bridge network directly, keeps its own distinct address. Returns null
/// if the route table can't be read (non-Linux, no default route, not
/// containerized, etc.) - callers must treat that as "can't confirm",
/// never as "is local".
String? dockerHostGatewayAddress() {
  try {
    return parseDefaultGatewayFromRouteTable(
      File('/proc/net/route').readAsStringSync(),
    );
  } catch (_) {
    return null;
  }
}
