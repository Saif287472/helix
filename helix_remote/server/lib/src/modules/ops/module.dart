import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/src/platform/http/request.dart';
import 'package:helix_remote_server/src/platform/http/routes.dart';
import 'package:helix_remote_server/src/platform/module.dart';
import 'package:helix_remote_server/src/platform/ratelimit/rate_limiter.dart';
import 'package:shelf/shelf.dart';

/// Health and readiness (Phase S1). Server info, legal documents, metrics,
/// telemetry and app links join in Phase S6.
final class OpsModule extends ModuleBase {
  OpsModule(super.context);

  static const _probe = RateLimitPolicy(
    'ops.probe',
    capacity: 120,
    perSecond: 2,
  );

  @override
  String get name => 'ops';

  @override
  void routes(RouteRegistry routes) {
    routes
      ..add(name, Routes.live, _live, rateLimit: _probe)
      ..add(name, Routes.ready, _ready, rateLimit: _probe);
  }

  Future<Response> _live(HelixRequest request) async =>
      jsonResponse(LiveResponse(time: context.clock.now()).toJson());

  Future<Response> _ready(HelixRequest request) async {
    final checks = await context.health.run();
    final ready = checks.values.every((ok) => ok);
    return jsonResponse(
      ReadyResponse(ready: ready, checks: checks).toJson(),
      status: ready ? 200 : 503,
    );
  }
}
