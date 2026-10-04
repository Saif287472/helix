import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/features/groups/application/group_invites.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// People who used an approval link and wait for an admin: approve lets them
/// in (and hands them the group's key), reject turns them away.
class JoinRequestsScreen extends ConsumerWidget {
  const JoinRequestsScreen({super.key, required this.groupId});

  final String groupId;

  Future<void> _answer(
    BuildContext context,
    WidgetRef ref,
    PersonEntryView request, {
    required bool approve,
  }) async {
    final actions = ref.read(joinRequestActionsProvider);
    final result = approve
        ? await actions.approve(groupId, request.id)
        : await actions.reject(groupId, request.id);
    if (!context.mounted) return;
    showHelixSnackBar(
      context,
      result.message ??
          (approve
              ? '${request.title} joined the group.'
              : '${request.title} was turned away.'),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requests = ref.watch(joinRequestViewsProvider(groupId));
    return Scaffold(
      appBar: AppBar(title: const Text('Join requests')),
      body: switch (requests) {
        AsyncError() => HelixErrorState(
          message:
              'The requests could not be loaded. Only admins can see them.',
          onRetry: () => ref.invalidate(joinRequestsProvider(groupId)),
        ),
        AsyncData(:final value) when value.isEmpty => const HelixEmptyState(
          icon: Icons.how_to_reg_outlined,
          title: 'No one is waiting',
          message:
              'When someone uses an approval link, they show up here for you '
              'to let in.',
        ),
        AsyncData(:final value) => ListView(
          children: [
            for (final request in value)
              ListTile(
                key: ValueKey('request-${request.id}'),
                leading: HelixAvatar(model: request.avatar),
                title: Text(
                  request.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text('Asked ${request.whenLabel}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'Reject ${request.title}',
                      onPressed: () =>
                          _answer(context, ref, request, approve: false),
                    ),
                    IconButton(
                      icon: const Icon(Icons.check),
                      tooltip: 'Approve ${request.title}',
                      onPressed: () =>
                          _answer(context, ref, request, approve: true),
                    ),
                  ],
                ),
              ),
          ],
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}
