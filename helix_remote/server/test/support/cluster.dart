import 'dart:io';

import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/helix_remote_server.dart';
import 'package:helix_remote_server/src/platform/push/push.dart';

import 'harness.dart';
import 'test_client.dart';
import 'test_platform.dart';
import 'test_socket.dart';

/// One node of a [Cluster]: a server, a client pointed at it, and the push
/// provider it sends through.
final class Node {
  Node(this.label, this.server, this.api, this.push);

  final String label;
  final HelixServer server;
  final TestApi api;
  final RecordingPushProvider push;

  HelixPlatform get platform => server.platform;

  String get nodeId => platform.config.nodeId;

  /// Connects [device]'s socket here and reads `hello`.
  Future<TestSocket> online(TestDevice device, {int? after}) async {
    final socket = await TestSocket.connect(
      server.baseUri,
      device.bearer,
      after: after,
    );
    await socket.hello();
    return socket;
  }

  Future<TestResponse> send(
    TestDevice from,
    Map<String, List<String>> to, {
    String? id,
    bool ephemeral = false,
    bool urgent = true,
    Map<String, String> headers = const {},
  }) => api.call(
    Routes.sendMessage,
    bearer: from.bearer,
    headers: headers,
    body: SendMessageRequest(
      id: id ?? Uuid.v7(),
      recipients: [
        for (final e in to.entries)
          Recipient(
            account: e.key,
            devices: [
              for (final d in e.value)
                DevicePayload(device: d, payload: bytes(64, d.hashCode)),
            ],
          ),
      ],
      ephemeral: ephemeral,
      urgent: urgent,
    ).toJson(),
  );

  Future<MailboxPage> mailbox(TestDevice device, {int after = 0}) async =>
      MailboxPage.fromJson(
        (await api.call(
          Routes.mailbox,
          bearer: device.bearer,
          query: {'after': '$after'},
        )).json,
      );

  Future<TestResponse> ack(TestDevice device, int seq) => api.call(
    Routes.ackMailbox,
    bearer: device.bearer,
    body: AckRequest(seq: seq).toJson(),
  );

  /// Acks everything stored for [device] (account signals from set-up), so
  /// its next socket starts empty.
  Future<void> clear(TestDevice device) async {
    final page = await mailbox(device);
    if (page.lastSeq > 0) await ack(device, page.lastSeq);
  }
}

/// Two nodes on one schema prefix: one cluster behind a load balancer
/// (ARCHITECTURE_V2_PLAN.md §4.6), not federation. Node [a] is the
/// [Harness] server; node [b] is a second [HelixServer] with the same
/// configuration and its own push provider. They share only Postgres.
final class Cluster {
  Cluster._(this.h, this.a, this.b);

  final Harness h;
  final Node a;
  final Node b;

  List<Node> get nodes => [a, b];

  static Future<Cluster> start({Map<String, String> extra = const {}}) async {
    final h = await Harness.start(extra: extra);
    try {
      final push = RecordingPushProvider();
      final platform = await HelixPlatform.open(
        testConfig(
          prefix: h.env.prefix,
          extra: {
            // The same settings Harness.start gives node A.
            'HELIX_PHONE_PEPPER': testPepper,
            'HELIX_GLOBAL_MODE': 'true',
            'HELIX_OTP_RESEND_SECONDS': '0',
            'HELIX_ADMIN_KDF_MEMORY_KIB': '256',
            ...extra,
          },
        ),
        log: Log(sink: MemorySink()),
        push: push,
      );
      final server = await HelixServer.start(platform, allModules(sms: h.sms));
      return Cluster._(
        h,
        Node('A', h.server, h.api, h.push),
        Node('B', server, TestApi(server.baseUri), push),
      );
    } on Object {
      await h.stop();
      rethrow;
    }
  }

  Future<void> stop() async {
    final dir = b.platform.config.blobs.directory;
    b.api.close();
    await b.server.stop();
    if (dir != null && Directory(dir).existsSync()) {
      Directory(dir).deleteSync(recursive: true);
    }
    await h.stop();
  }

  /// Pushes recorded by either node.
  List<({String token, PushReason reason, String? callId})> get pushes => [
    ...a.push.sent,
    ...b.push.sent,
  ];

  /// Runs due outbox jobs on both nodes at the same time, as their live
  /// runners would.
  Future<void> tickJobs() async {
    for (var i = 0; i < 3; i++) {
      await Future.wait([a.platform.jobs.tick(), b.platform.jobs.tick()]);
    }
  }
}

/// Reads frames until [socket] has been quiet for a moment (drops account
/// signals and roster changes a test does not look at).
Future<void> quiet(TestSocket socket) async {
  while (!await socket.silent(const Duration(milliseconds: 300))) {}
}
