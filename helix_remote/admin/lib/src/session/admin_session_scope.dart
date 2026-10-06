import 'package:flutter/widgets.dart';
import 'package:helix_admin/src/session/admin_session_controller.dart';

/// Makes the session available to every screen below it.
class AdminSessionScope extends InheritedNotifier<AdminSessionController> {
  const AdminSessionScope({
    super.key,
    required AdminSessionController controller,
    required super.child,
  }) : super(notifier: controller);

  /// The session; screens read `session.context` for the API.
  static AdminSessionController of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<AdminSessionScope>();
    assert(scope != null, 'no AdminSessionScope above this widget');
    return scope!.notifier!;
  }

  /// Like [of] but does not rebuild when the session changes.
  static AdminSessionController read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<AdminSessionScope>();
    assert(scope != null, 'no AdminSessionScope above this widget');
    return scope!.notifier!;
  }
}
