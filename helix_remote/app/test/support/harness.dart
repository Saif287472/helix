import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:go_router/go_router.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// A scope, a theme and a router with [home] at `/` and the extra routes
/// beside it: what a screen needs to be pumped on its own. Routes that are
/// only a stub name themselves so a test can see where a tap went.
Widget harness({
  required Widget home,
  List<Override> overrides = const [],
  List<RouteBase> routes = const [],
  ProviderContainer? container,
}) {
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (context, state) => home),
      ...routes,
    ],
  );
  final app = MaterialApp.router(
    theme: HelixThemes.light(),
    routerConfig: router,
  );
  return container == null
      ? ProviderScope(overrides: overrides, child: app)
      : UncontrolledProviderScope(container: container, child: app);
}

/// A route that shows [label] and the `extra` it was opened with, for
/// asserting where a tap or a link went.
GoRoute stubRoute(String path, [String? label]) => GoRoute(
  path: path,
  builder: (context, state) => Scaffold(
    body: Center(
      child: Text(
        '${label ?? path}${state.extra == null ? '' : ' ${state.extra}'}',
      ),
    ),
  ),
);
