import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/engine/session_providers.dart';
import 'package:helix_remote/core/links/deep_link.dart';
import 'package:helix_remote/core/links/link_channel.dart';
import 'package:helix_remote/core/router/app_router.dart';
import 'package:helix_remote/features/people/application/people_search.dart';
import 'package:helix_remote/shared/widgets/orbit_app_toast.dart';

/// Turns links that arrive from outside the app into navigation.
///
/// Two sources, one [HelixDeepLink] type: a cold start (the launcher handed us
/// a `helix://` or `https://…/open#HLX-…` URI, parsed in `main`) and a warm
/// start ([HelixLinkChannel], which the Android activity calls when a new
/// intent arrives while the app is already running).
///
/// The link is parked in [pendingLinkProvider] first, because sign-in reads it
/// to pre-fill a code: navigating and pre-filling are the same event, and the
/// screen must be able to ask what it was sent.
class AppLinkListener extends ConsumerStatefulWidget {
  const AppLinkListener({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppLinkListener> createState() => _AppLinkListenerState();
}

class _AppLinkListenerState extends ConsumerState<AppLinkListener> {
  StreamSubscription<HelixDeepLink>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = HelixLinkChannel.instance.links.listen(_onLink);
    // A link that arrived before the first frame is already in the provider.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final pending = ref.read(pendingLinkProvider);
      if (pending != null) _onLink(pending);
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _onLink(HelixDeepLink link) {
    final pending = ref.read(pendingLinkProvider.notifier);
    if (_needsAccount(link)) {
      // A link that needs an account waits (parked in the provider) until the
      // person is signed in, and is handled then.
      pending.set(link);
      if (!_signedIn) return;
      if (link.kind == HelixDeepLinkKind.personLink) {
        // Nothing to navigate to yet: the name has to be looked up first, and
        // the chat it resolves to is the destination.
        pending.take();
        unawaited(
          ref.read(peopleActionsProvider).openPersonLink(link.helixName!).then((
            failure,
          ) {
            if (failure != null && mounted) _toast(failure);
          }),
        );
        return;
      }
      routeDeepLink(ref.read(appRouterProvider), link);
      pending.take();
      return;
    }
    if (link.setupCode != null) {
      // An invite or recovery code belongs to sign-in. A phone that already
      // has an account has no use for one, and a code left parked would be
      // applied by the next sign-in after a sign-out: drop it.
      if (_signedIn) {
        pending.set(null);
        _toast(
          "You're already signed in. Invite and recovery links are "
          "for setting up a new device.",
        );
        return;
      }
      // Parked, and applied by the sign-in screen once the device is known to
      // be signed out. Applying it only asks the person about the server; it
      // sends nothing.
      pending.set(link);
      routeDeepLink(ref.read(appRouterProvider), link);
      return;
    }
    routeDeepLink(ref.read(appRouterProvider), link);
    pending.set(null);
  }

  /// The listener sits above the navigator, so a message goes into the
  /// navigator's overlay.
  void _toast(String message) => showAppToast(ref, message);

  static bool _needsAccount(HelixDeepLink link) =>
      link.kind == HelixDeepLinkKind.groupLink ||
      link.kind == HelixDeepLinkKind.groupJoin ||
      link.kind == HelixDeepLinkKind.personLink;

  bool get _signedIn => ref.read(authStateProvider).value == AppAuthState.ready;

  @override
  Widget build(BuildContext context) {
    ref.listen(authStateProvider, (_, next) {
      if (next.value != AppAuthState.ready) return;
      final pending = ref.read(pendingLinkProvider);
      if (pending != null && _needsAccount(pending)) _onLink(pending);
    });
    return widget.child;
  }
}
