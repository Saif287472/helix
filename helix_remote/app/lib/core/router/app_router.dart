import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:helix_remote/core/engine/session_providers.dart';
import 'package:helix_remote/core/links/deep_link.dart';
import 'package:helix_remote/features/home/presentation/home_screen.dart';
import 'package:helix_remote/features/people/people_routes.dart';
import 'package:helix_remote/features/sign_in/presentation/sign_in_screen.dart';
import 'package:helix_remote/shared/widgets/reset_screen.dart';

/// Every route in the app. A1 ships sign-in, the home tabs shell and the two
/// startup screens; A2/A3 add conversations and the settings pages under
/// `/home`.
abstract final class AppRoutes {
  static const signIn = '/sign-in';
  static const home = '/home';
  static const reset = '/reset';
}

/// The external link the app was opened with, if any.
///
/// Warm-start links arrive on `HelixLinkChannel`; a cold start arrives as the
/// process argument. Both end here, and [AppLinkListener] turns a change into
/// a navigation. This is deliberately not go_router's own deep-link handling:
/// the documented link forms (`helix://open?code=…`, and
/// `https://helix.agiletechbd.com/open#HLX-…` where the code travels in the
/// fragment so a browser never sends it to the server) are parsed by
/// [HelixDeepLink], and the Android manifest keeps Flutter's deeplinking off.
final pendingLinkProvider = NotifierProvider<PendingLink, HelixDeepLink?>(
  PendingLink.new,
);

final class PendingLink extends Notifier<HelixDeepLink?> {
  @override
  HelixDeepLink? build() => null;

  void set(HelixDeepLink? link) => state = link;

  /// Takes the link and clears it, so it is handled once.
  HelixDeepLink? take() {
    final link = state;
    state = null;
    return link;
  }
}

/// The app's router.
///
/// One [GoRouter] for the whole app, created once (Riverpod providers that
/// build a router must not, or the back stack resets on every rebuild).
/// The redirect is the only thing that decides between sign-in and home.
final appRouterProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: AppRoutes.signIn,
    // A [Ref], not a [WidgetRef]: the redirect runs outside the widget tree.
    redirect: (context, state) => _redirectFor(ref, state.matchedLocation),
    routes: [
      GoRoute(
        path: AppRoutes.signIn,
        builder: (context, state) => const SignInScreen(),
      ),
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const HomeScreen(),
      ),
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

/// Where the user belongs, given where they are.
///
/// The states that mean "wait" return null so the current screen stays up
/// rather than flashing. A revoked device is forced off the home tabs, because
/// its data has been wiped and there is nothing left there to see.
String? _redirectFor(Ref ref, String location) {
  final auth = ref.read(authStateProvider);
  final at = location;

  // The reset screen is where a database that cannot be opened sends the
  // user; nothing redirects out of it except itself.
  if (at == AppRoutes.reset) return auth.hasError ? null : AppRoutes.signIn;

  if (auth.hasError) return AppRoutes.reset;
  final state = auth.value;
  if (state == null) return null; // Still opening the database.
  if (state == AppAuthState.ready) {
    return at == AppRoutes.signIn ? AppRoutes.home : null;
  }
  // signedOut or revoked.
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
    router.go('${AppRoutes.signIn}?code=${Uri.encodeComponent(code)}');
    return;
  }
  switch (link.kind) {
    case HelixDeepLinkKind.call:
      router.go('${AppRoutes.home}/calls/${link.callId}');
    case HelixDeepLinkKind.groupJoin:
      router.go('${AppRoutes.home}/groups/${link.groupId}');
    case HelixDeepLinkKind.contactAdd:
      router.go('${AppRoutes.home}/people');
    case HelixDeepLinkKind.invite || HelixDeepLinkKind.serverCode:
      break;
  }
}
