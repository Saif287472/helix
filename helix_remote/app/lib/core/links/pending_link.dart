import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/links/deep_link.dart';

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
