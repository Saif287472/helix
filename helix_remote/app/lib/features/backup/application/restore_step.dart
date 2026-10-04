import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/engine/post_sign_in.dart';

/// Ends the restore step that follows a sign-in on a new device.
///
/// Sign-in sets `postSignInProvider`; the router shows the restore page while
/// it is set. The page calls [finish] when the person restores or skips, and
/// then goes to the home tabs. Whatever they chose, Settings > Backup offers
/// the same restore again later.
final restoreStepProvider = Provider<RestoreStep>(RestoreStep.new);

final class RestoreStep {
  RestoreStep(this._ref);

  final Ref _ref;

  void finish() => _ref.read(postSignInProvider.notifier).done();
}
