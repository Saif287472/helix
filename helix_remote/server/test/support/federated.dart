import 'dart:io';

import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/src/modules/federation/module.dart';
import 'package:helix_remote_server/src/modules/ops/module.dart';

import 'harness.dart';

Future<int> freePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

/// A server reachable at its own public URL, federating over plain HTTP on
/// loopback (dev mode only).
Future<Harness> federated({Map<String, String> extra = const {}}) async {
  final port = await freePort();
  return Harness.start(
    extra: {
      'HELIX_PORT': '$port',
      'HELIX_PUBLIC_BASE_URL': 'http://127.0.0.1:$port',
      'HELIX_FEDERATION_ENABLED': 'true',
      'HELIX_FEDERATION_ALLOW_PRIVATE': 'true',
      'HELIX_FEDERATION_HTTP': 'true',
      ...extra,
    },
  );
}

extension FederatedHarness on Harness {
  FederationModule get federation =>
      server.modules.whereType<FederationModule>().single;

  String get domain => federation.config.localDomain;

  Future<void> setFederation(bool on) => env.platform.db.tx(
    (tx) => server.modules.whereType<OpsModule>().single.api.update(
      tx,
      AdminConfigPatch(federationEnabled: on),
    ),
  );

  /// Runs queued jobs (syncs, fan-outs, relays) until none are due.
  Future<void> drain() async {
    for (var i = 0; i < 10; i++) {
      if (await env.platform.jobs.tick() == 0) return;
    }
  }
}

/// Lets queued cross-server work settle on every server.
Future<void> settle(List<Harness> servers) async {
  for (var round = 0; round < 4; round++) {
    for (final h in servers) {
      await h.drain();
    }
  }
}
