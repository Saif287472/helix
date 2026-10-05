import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/router/app_router.dart';
import 'package:helix_remote/features/groups/application/group_pending.dart';
import 'package:helix_remote/shared/navigation/group_paths.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// The app-wide banner for "a member was added to one of your groups by the
/// server roster": whichever screen is up, a snackbar says so and offers to
/// review it (the group's info page, where Confirm and Remove are).
///
/// The prompt itself stays on the group's screens until the person answers;
/// this is only the nudge for when they are somewhere else. It names the
/// group and the person (as this phone knows them), never a message.
class UnconfirmedMemberHost extends ConsumerWidget {
  const UnconfirmedMemberHost({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(unconfirmedMemberAlertsProvider, (_, next) {
      final alert = next.value;
      if (alert == null) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger == null) return;
      showHelixSnackBar(
        context,
        alert.message,
        actionLabel: 'Review',
        duration: const Duration(seconds: 8),
        onAction: () =>
            ref.read(appRouterProvider).push(GroupPaths.info(alert.groupId)),
      );
    });
    return child;
  }
}
