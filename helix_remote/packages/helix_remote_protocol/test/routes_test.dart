import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:test/test.dart';

/// Every route that needs no session. Adding or removing one must be a
/// deliberate change to this list (AGENTS.md security invariants): the
/// server gives each one a rate limit.
const publicRouteSnapshot = [
  'POST /v1/auth/phone/challenges',
  'POST /v1/auth/phone/verify',
  'POST /v1/auth/invites/lookup',
  'POST /v1/auth/invites/self-issue',
  'POST /v1/auth/register',
  'POST /v1/auth/password/params',
  'POST /v1/auth/password/sign-in',
  'POST /v1/auth/links',
  'GET /v1/auth/links/{link_id}',
  'POST /v1/auth/devices',
  'POST /v1/auth/challenges',
  'POST /v1/auth/sessions',
  'POST /v1/auth/sessions/refresh',
  'POST /v1/auth/recovery/lookup',
  'POST /v1/auth/recovery/redeem',
  'GET /v1/health/live',
  'GET /v1/health/ready',
  'GET /v1/server',
  'GET /v1/server/legal',
  'GET /.well-known/assetlinks.json',
  'GET /open',
  'GET /.well-known/helix-server',
  'GET /v1/admin/setup',
  'POST /v1/admin/setup',
  'POST /v1/admin/sessions',
];

const knownModules = {
  'identity',
  'keys',
  'messaging',
  'realtime',
  'people',
  'groups',
  'calls',
  'media',
  'backup',
  'federation',
  'ops',
  'admin',
  'compliance',
};

void main() {
  test('public routes match the reviewed snapshot', () {
    final public = [
      for (final r in Routes.all)
        if (r.access == RouteAccess.public) r.toString(),
    ];
    expect(public, publicRouteSnapshot);
  });

  test('method and path pairs are unique', () {
    final seen = <String>{};
    for (final route in Routes.all) {
      expect(seen.add(route.toString()), isTrue, reason: 'duplicate $route');
    }
  });

  test('templates do not collide (same method, same shape)', () {
    final shapes = <String, ApiRoute>{};
    for (final route in Routes.all) {
      final shape =
          '${route.method} ${route.path.replaceAll(RegExp(r'\{[a-z_]+\}'), '{}')}';
      final other = shapes[shape];
      expect(other, isNull, reason: '$route collides with $other');
      shapes[shape] = route;
    }
  });

  test('paths are versioned and modules are known', () {
    for (final route in Routes.all) {
      expect(
        route.path.startsWith('/v1/') ||
            route.path.startsWith('/.well-known/') ||
            route.path == '/open',
        isTrue,
        reason: '$route',
      );
      expect(knownModules, contains(route.module), reason: '$route');
      if (route.path.startsWith('/v1/s2s/')) {
        expect(route.access, RouteAccess.s2s, reason: '$route');
      }
      if (route.module == 'admin' && route.access != RouteAccess.public) {
        expect(route.access, RouteAccess.admin, reason: '$route');
      }
    }
  });

  test('every declared route constant is in Routes.all', () {
    // Spot-check the ones most likely to be forgotten.
    expect(
      Routes.all,
      containsAll([
        Routes.websocket,
        Routes.sendGroupMessage,
        Routes.adminPurge,
        Routes.s2sCallSignals,
        Routes.openLink,
      ]),
    );
  });

  test('expand fills and encodes parameters', () {
    expect(
      Routes.setGroupRole.expand({'group_id': 'g 1', 'account': 'a@b.c'}),
      '/v1/groups/g%201/members/a%40b.c/role',
    );
    expect(Routes.removeGroupMember.parameters, ['group_id', 'account']);
    expect(() => Routes.group.expand(), throwsArgumentError);
  });
}
