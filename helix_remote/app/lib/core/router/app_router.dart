import 'dart:async';

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:helix_remote/core/engine/post_sign_in.dart';
import 'package:helix_remote/core/engine/session_providers.dart';
import 'package:helix_remote/core/engine/runtime_providers.dart';
import 'package:helix_remote/core/links/deep_link.dart';
import 'package:helix_remote/features/backup/backup_routes.dart';
import 'package:helix_remote/features/devices/devices_routes.dart';
import 'package:helix_remote/features/calls/calls_routes.dart';
import 'package:helix_remote/features/groups/groups_routes.dart';
import 'package:helix_remote/features/chats/chats_routes.dart';
import 'package:helix_remote/features/conversation/conversation_routes.dart';
import 'package:helix_remote/features/home/presentation/home_screen.dart';
import 'package:helix_remote/features/people/people_routes.dart';
import 'package:helix_remote/features/profile/profile_routes.dart';
import 'package:helix_remote/features/settings/settings_routes.dart';
import 'package:helix_remote/features/sign_in/presentation/sign_in_screen.dart';
import 'package:orbit_ui/orbit_ui.dart' as orbit;
import 'package:helix_remote/shared/widgets/orbit_you_connector.dart';
import 'package:helix_remote/shared/route_paths.dart';
import 'package:helix_remote/shared/widgets/reset_screen.dart';

// Kept importable from here: the link listener, sign-in and the tests all
// reach the pending link through the router's library.
export 'package:helix_remote/core/links/pending_link.dart';

/// Every route in the app. A1 ships sign-in, the home tabs shell and the two
/// startup screens; A2/A3 add conversations and the settings pages under
/// `/home`.
abstract final class AppRoutes {
  static const signIn = '/sign-in';
  static const home = '/home';
  static const reset = '/reset';
  static const startup = '/startup';

  /// Your profile and settings (the prototype's You), opened from Home.
  static const settings = '/settings';
}

/// The app's router.
///
/// One [GoRouter] for the whole app, created once (Riverpod providers that
/// build a router must not, or the back stack resets on every rebuild).
/// The redirect is the only thing that decides between sign-in and home.
final appRouterProvider = Provider<GoRouter>((ref) {
  // `redirect` only runs on navigation, so a change of state that should move
  // the person (signed in, signed out, the restore step set or cleared) has to
  // ask for it. This is what takes sign-in to the home tabs once the engine
  // reports a session.
  final refresh = ValueNotifier<int>(0);
  void poke() => refresh.value++;
  late final GoRouter router;
  ref.listen(authStateProvider, (was, now) {
    poke();
    // Signing out (here or on another device) leaves at once, whatever page
    // is on top: a redirect alone does not clear pages pushed over home.
    // (A cold start, which has no earlier state, is the redirect's to place.)
    final before = was?.value;
    final after = now.value;
    if (before != null &&
        before != after &&
        (after == AppAuthState.signedOut || after == AppAuthState.revoked)) {
      router.go(AppRoutes.signIn);
    }
  });
  // Switching accounts closes whatever the last one had open: the pages
  // pushed over home belong to it.
  ref.listen(activeAccountProvider, (was, now) {
    if (was != null && now != null && was.id != now.id) {
      router.go(AppRoutes.home);
    }
  });
  ref.listen(postSignInProvider, (_, _) => poke());
  ref.listen(sessionRestoreProvider, (_, _) => poke());
  ref.onDispose(refresh.dispose);

  // Once the app has left the "Opening Orbit…" screen it never goes back to
  // it, even when a later action (a personal-server sign-in) rebuilds the
  // runtime and authState briefly reports "starting" again.
  var startupDone = false;

  router = GoRouter(
    initialLocation: AppRoutes.signIn,
    // The launcher's intent URL reaches Flutter as the platform's default
    // route name. Without this go_router would start on it, so a crafted
    // `https://…/anything` link could pick the first screen. Links are parsed
    // by [HelixDeepLink] and applied through [pendingLinkProvider] instead.
    overridePlatformDefaultLocation: true,
    refreshListenable: refresh,
    // A [Ref], not a [WidgetRef]: the redirect runs outside the widget tree.
    redirect: (context, state) => _redirectFor(
      ref,
      state.matchedLocation,
      startupDone,
      (v) => startupDone = v,
    ),
    routes: [
      GoRoute(
        path: AppRoutes.startup,
        builder: (context, state) => const orbit.OrbitStartup(),
      ),
      GoRoute(
        path: AppRoutes.signIn,
        builder: (context, state) => const SignInScreen(),
      ),
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.settings,
        builder: (context, state) => const OrbitYouConnector(),
      ),
      ...chatsRoutes,
      ...conversationRoutes,
      ...callsRoutes,
      ...groupsRoutes,
      ...settingsRoutes,
      ...profileRoutes,
      ...devicesRoutes,
      ...backupRoutes,
      GoRoute(
        path: AppRoutes.reset,
        builder: (context, state) => const ResetScreen(),
      ),
      ...peopleRoutes,
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

/// The routes the restore step owns, while it is pending: the step itself and
/// the recovery page it offers ("I have a recovery secret"). Anything else is
/// still redirected to the step, which is what keeps it from being skipped.
const _restoreStepRoutes = {
  RoutePaths.restoreAfterSignIn,
  RoutePaths.backupRecovery,
};

/// Where the user belongs, given where they are.
///
/// The states that mean "wait" return null so the current screen stays up
/// rather than flashing. A revoked device is forced off the home tabs, because
/// its data has been wiped and there is nothing left there to see.
String? _redirectFor(
  Ref ref,
  String location,
  bool startupDone,
  void Function(bool) setStartupDone,
) {
  final auth = ref.read(authStateProvider);
  final at = location;

  // The reset screen is where a database that cannot be opened sends the
  // user; nothing redirects out of it except itself.
  if (at == AppRoutes.reset) return auth.hasError ? null : AppRoutes.signIn;

  if (auth.hasError) return AppRoutes.reset;
  final state = auth.value;
  // A cold start shows "Opening Orbit…" until the remembered server has been
  // read and the database has opened, so a signed-in device never flashes
  // sign-in. Once the app has left it, it never comes back (a personal-server
  // sign-in rebuilds the runtime and reports "starting" again).
  if (!startupDone) {
    final restoring =
        ref.read(sessionRestoreProvider) == SessionRestore.pending &&
        state != AppAuthState.ready;
    if (state == null || state == AppAuthState.starting || restoring) {
      return at == AppRoutes.startup ? null : AppRoutes.startup;
    }
    setStartupDone(true);
  }
  // Still opening the database, or the engine of an account just switched
  // to is still deciding: the screen stays.
  if (state == null || state == AppAuthState.starting) return null;
  if (state == AppAuthState.ready) {
    // The step after signing in on a new device comes before the tabs, once.
    final step = ref.read(postSignInProvider);
    if (step == PostSignInStep.offerRestore) {
      // It holds the person on its own step, and on the pages that step opens -
      // "I have a recovery secret" is one of them, and redirecting them off it
      // made the recovery-secret route after sign-in unreachable.
      return _restoreStepRoutes.contains(at)
          ? null
          : RoutePaths.restoreAfterSignIn;
    }
    if (at == AppRoutes.startup) return AppRoutes.home;
    if (at == RoutePaths.restoreAfterSignIn) return AppRoutes.home;
    if (at == RoutePaths.linkThisDevice) return AppRoutes.home;
    return at == AppRoutes.signIn ? AppRoutes.home : null;
  }
  // signedOut or revoked. Linking this device shows a QR code while signed
  // out, so it is the one other place a signed-out device may be.
  if (at == AppRoutes.startup) return AppRoutes.signIn;
  if (at == RoutePaths.linkThisDevice) return null;
  return at == AppRoutes.signIn ? null : AppRoutes.signIn;
}

/// Navigates for a link that arrived from outside the app.
///
/// A setup code belongs to sign-in; everything else is a route. A link that
/// arrives while somebody is already signed in is refused in the UI, not
/// here, so the person sees why.
void routeDeepLink(GoRouter router, HelixDeepLink link) {
  final code = link.setupCode;
  if (code != null && code.isNotEmpty) {
    // The code itself stays in [pendingLinkProvider]: a route's location is
    // kept in history and logs, and an invite or recovery code is a secret.
    router.go(AppRoutes.signIn);
    return;
  }
  switch (link.kind) {
    case HelixDeepLinkKind.call:
      unawaited(router.push(CallRoutes.detail(link.callId ?? '')));
    case HelixDeepLinkKind.groupLink:
      // The preview and an explicit Join button: opening a link never joins.
      unawaited(router.push(GroupRoutes.join, extra: link.code));
    case HelixDeepLinkKind.groupJoin:
      unawaited(router.push(GroupRoutes.join, extra: link.inviteCode));
    case HelixDeepLinkKind.contactAdd:
      router.go('${AppRoutes.home}/people');
    case HelixDeepLinkKind.invite || HelixDeepLinkKind.serverCode:
      break;
  }
}
