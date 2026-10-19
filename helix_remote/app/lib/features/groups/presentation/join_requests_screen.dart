import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/features/groups/application/group_invites.dart';
import 'package:orbit_ui/orbit_ui.dart' as orbit;

/// Connector: people who used an approval link and wait for an admin,
/// drawn by `orbit_ui`'s Join requests. Approve lets them in (and hands them
/// the group's key), reject turns them away.
class JoinRequestsScreen extends ConsumerWidget {
  const JoinRequestsScreen({super.key, required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requests = ref.watch(joinRequestViewsProvider(groupId));
    final list = requests.value ?? const <PersonEntryView>[];
    final actions = ref.read(joinRequestActionsProvider);

    Future<String?> answer(String account, {required bool approve}) async {
      final request = list.where((r) => r.account == account).firstOrNull;
      if (request == null) return null;
      final result = approve
          ? await actions.approve(groupId, request.id)
          : await actions.reject(groupId, request.id);
      return result.message ??
          (approve
              ? '${request.title} joined the group.'
              : '${request.title} was turned away.');
    }

    return orbit.JoinRequestsScreen(
      model: orbit.JoinRequestsModel(
        requests: [
          for (final r in list)
            orbit.PersonEntryView(
              account: r.account,
              title: r.title,
              whenLabel: 'Asked ${r.whenLabel}',
              avatar: r.avatar,
            ),
        ],
        loading: requests.isLoading && !requests.hasValue,
        loadFailed: requests.hasError && !requests.hasValue,
      ),
      actions: orbit.JoinRequestsActions(
        onApprove: (account) => answer(account, approve: true),
        onReject: (account) => answer(account, approve: false),
        onRetry: () => ref.invalidate(joinRequestsProvider(groupId)),
      ),
    );
  }
}
