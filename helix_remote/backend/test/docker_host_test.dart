// Docker rewrites a connection from the HOST's own loopback interface into
// a container's published port so it appears to originate from the bridge
// gateway address instead of 127.0.0.1 (a raw loopback packet can't cross
// a network-namespace boundary unchanged). parseDefaultGatewayFromRouteTable
// recovers that gateway from /proc/net/route so AdminPairingModule can
// recognize "an operator curled the published port from the VPS itself" the
// same way it would recognize genuine loopback on a non-containerized boot.
//
// The fixture below is the real, unmodified /proc/net/route contents read
// from the production helix-backend container - gateway 172.18.0.1, which
// matches `docker network inspect`'s reported gateway for that deployment.

import 'package:helix_remote_backend/src/docker_host.dart';
import 'package:test/test.dart';

const _realContainerRouteTable =
    'Iface\tDestination\tGateway \tFlags\tRefCnt\tUse\tMetric\tMask\t\tMTU\tWindow\tIRTT'
    '\n'
    'eth0\t00000000\t010012AC\t0003\t0\t0\t0\t00000000\t0\t0\t0'
    '\n'
    'eth0\t000012AC\t00000000\t0001\t0\t0\t0\t0000FFFF\t0\t0\t0'
    '\n';

void main() {
  test('parses the gateway out of a real container route table', () {
    expect(
      parseDefaultGatewayFromRouteTable(_realContainerRouteTable),
      equals('172.18.0.1'),
    );
  });

  test('returns null when there is no default route', () {
    const noDefaultRoute =
        'Iface\tDestination\tGateway \tFlags\tRefCnt\tUse\tMetric\tMask\t\tMTU\tWindow\tIRTT\n'
        'eth0\t000012AC\t00000000\t0001\t0\t0\t0\t0000FFFF\t0\t0\t0\n';
    expect(parseDefaultGatewayFromRouteTable(noDefaultRoute), isNull);
  });

  test('returns null for empty or malformed input', () {
    expect(parseDefaultGatewayFromRouteTable(''), isNull);
    expect(parseDefaultGatewayFromRouteTable('garbage\nmore garbage'), isNull);
  });
}
