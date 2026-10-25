import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What the app asks for right after a sign-in, before the home tabs.
///
/// Sign-in decides whether the person has just joined an account that may
/// already have a history (password sign-in, linking) and sets
/// [offerRestore]. The router then shows the restore page once; the page
/// clears it, so reaching the tabs by any other road never shows it.
///
/// Taking a number over deliberately does not: the server replaces the
/// identity key and revokes every device, so a backup sealed under the old
/// identity cannot be opened for the new one, and the step would only offer
/// something that fails (AUD-15-5). Do not add the call to `completeSetup`
/// without changing that rule on the server first.
enum PostSignInStep {
  none,

  /// Offer to restore the history backup and any waiting device transfer.
  offerRestore,
}

final postSignInProvider = NotifierProvider<PostSignIn, PostSignInStep>(
  PostSignIn.new,
);

final class PostSignIn extends Notifier<PostSignInStep> {
  @override
  PostSignInStep build() => PostSignInStep.none;

  void offerRestore() => state = PostSignInStep.offerRestore;

  void done() {
    // A deferred call can outlive the container (a test tearing down).
    if (ref.mounted) state = PostSignInStep.none;
  }
}
