import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:helix_remote_server/src/platform/db/migrations.dart';
import 'package:helix_remote_server/src/platform/http/pipeline.dart';
import 'package:helix_remote_server/src/platform/http/request.dart';
import 'package:helix_remote_server/src/platform/http/routes.dart';
import 'package:helix_remote_server/src/platform/module.dart';
import 'package:helix_remote_server/src/platform/platform.dart';
import 'package:helix_remote_server/src/platform/platform_migrations.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

/// Creates a module from the shared context (and, through closures, from
/// other modules' facades).
typedef ModuleFactory = HelixModule Function(ModuleContext context);

/// One running server node: platform + modules + HTTP.
final class HelixServer {
  HelixServer._(this.platform, this.modules, this.routes, this._http);

  final HelixPlatform platform;
  final List<HelixModule> modules;

  /// The routes this node serves (route-parity tests read it).
  final RouteRegistry routes;
  final HttpServer _http;

  int get port => _http.port;

  Uri get baseUri => Uri.parse('http://${_http.address.host}:$port');

  /// Migrates, starts every module, then listens. [factories] run in order,
  /// so a module can be handed the facades of modules created before it.
  static Future<HelixServer> start(
    HelixPlatform platform,
    List<ModuleFactory> factories, {
    Authenticator? authenticator,
  }) async {
    final context = platform.moduleContext();
    final modules = [for (final create in factories) create(context)];
    final names = <String>{};
    for (final m in modules) {
      if (!names.add(m.name)) throw StateError('module ${m.name} added twice');
    }

    await MigrationRunner(platform.db, platform.schemas).run([
      platformMigrations,
      for (final m in modules)
        MigrationSet(module: m.name, migrations: m.migrations),
    ]);

    final routes = RouteRegistry();
    for (final module in modules) {
      module.routes(routes);
      module.jobs.forEach(platform.jobs.register);
      module.periodic.forEach(platform.periodic.register);
    }
    platform.housekeeping.forEach(platform.periodic.register);

    for (final module in modules) {
      await module.start();
    }

    final maintenance = modules.whereType<ProvidesMaintenance>().firstOrNull;
    final handler = platform
        .httpPipeline(maintenance: maintenance?.maintenanceActive)
        .wrap(
          routes.build(
            authenticator: authenticator ?? _authenticatorFrom(modules),
            rateLimiter: platform.rateLimiter,
            idempotency: platform.idempotency,
          ),
        );

    final http = await shelf_io.serve(
      handler,
      platform.config.host,
      platform.config.port,
      poweredByHeader: null,
    );
    http.autoCompress = false;
    await platform.bus.ready;
    platform.jobs.start();
    await platform.periodic.start();
    platform.log.info('server_started', {
      'node': platform.config.nodeId,
      'port': http.port,
      'modules': [for (final m in modules) m.name],
    });
    return HelixServer._(platform, modules, routes, http);
  }

  /// Stops accepting requests, lets in-flight ones finish (up to [grace]),
  /// stops jobs and modules, and closes the platform.
  Future<void> stop({Duration grace = const Duration(seconds: 10)}) async {
    final force = Timer(grace, () => _http.close(force: true));
    await _http.close();
    force.cancel();
    await platform.periodic.stop();
    await platform.jobs.stop();
    for (final module in modules.reversed) {
      await module.stop();
    }
    platform.log.info('server_stopped', {'node': platform.config.nodeId});
    await platform.close();
  }
}

extension on HelixPlatform {
  HttpPipeline httpPipeline({Future<bool> Function()? maintenance}) =>
      HttpPipeline(
        log: log,
        metrics: metrics,
        rateLimiter: rateLimiter,
        trustedProxies: config.trustedProxies,
        maintenance: maintenance,
      );
}

Authenticator _authenticatorFrom(List<HelixModule> modules) {
  final providers = modules.whereType<ProvidesAuthentication>().toList();
  if (providers.isEmpty) return const DenyAllAuthenticator();
  return _CompositeAuthenticator([for (final p in providers) p.authenticator]);
}

/// Asks each provider in turn; the first answer wins.
final class _CompositeAuthenticator implements Authenticator {
  _CompositeAuthenticator(this._delegates);

  final List<Authenticator> _delegates;

  @override
  Future<DevicePrincipal?> device(String bearerToken) async {
    for (final d in _delegates) {
      final p = await d.device(bearerToken);
      if (p != null) return p;
    }
    return null;
  }

  @override
  Future<AdminPrincipal?> admin(String bearerToken) async {
    for (final d in _delegates) {
      final p = await d.admin(bearerToken);
      if (p != null) return p;
    }
    return null;
  }

  @override
  Future<ServerPrincipal?> server(Request request, Uint8List body) async {
    for (final d in _delegates) {
      final p = await d.server(request, body);
      if (p != null) return p;
    }
    return null;
  }
}
