import 'package:go_router/go_router.dart';
import 'package:helix_remote/features/calls/presentation/call_detail_screen.dart';
import 'package:helix_remote/features/calls/presentation/call_screen.dart';

/// The calls feature's routes.
abstract final class CallRoutes {
  /// The full-screen call (ringing, dialing, live). Pushed by the app's call
  /// host when a call appears; never navigated to by hand.
  static const call = '/call';

  static const _detailBase = '/home/calls';

  /// The call-detail page of [callId]: the person and every call with them.
  /// `helix://call/CALL_ID` links land here.
  static String detail(String callId) =>
      '$_detailBase/${Uri.encodeComponent(callId)}';
}

/// Registered by the router with one line (`...callsRoutes`).
final List<RouteBase> callsRoutes = [
  GoRoute(
    path: CallRoutes.call,
    builder: (context, state) => const CallScreen(),
  ),
  GoRoute(
    path: '${CallRoutes._detailBase}/:callId',
    builder: (context, state) =>
        CallDetailScreen(callId: state.pathParameters['callId'] ?? ''),
  ),
];
