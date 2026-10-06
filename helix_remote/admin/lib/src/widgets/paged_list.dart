import 'package:flutter/material.dart';
import 'package:helix_admin/src/features/common/feature_controller.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// A refreshable, cursor-paged list for any [PagedController]: the first
/// page, a "Load more" button while the server has more, and distinct
/// loading, empty and error states.
class PagedListView<T> extends StatelessWidget {
  const PagedListView({
    super.key,
    required this.controller,
    required this.itemBuilder,
    required this.emptyIcon,
    required this.emptyTitle,
    this.emptyMessage,
    this.header,
  });

  final PagedController<T> controller;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final IconData emptyIcon;
  final String emptyTitle;
  final String? emptyMessage;

  /// Filters, shown above the list and kept while it reloads.
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final Widget body;
        if (controller.loading && controller.items.isEmpty) {
          body = Center(
            child: Semantics(
              label: 'Loading',
              liveRegion: true,
              child: const HelixSkeleton(width: 180, height: 24),
            ),
          );
        } else if (controller.error != null) {
          body = HelixErrorState(
            message: controller.error!,
            onRetry: controller.refresh,
          );
        } else if (controller.items.isEmpty) {
          body = HelixEmptyState(
            icon: emptyIcon,
            title: emptyTitle,
            message: emptyMessage,
          );
        } else {
          body = RefreshIndicator(
            onRefresh: controller.refresh,
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: controller.items.length + 1,
              itemBuilder: (context, index) {
                if (index < controller.items.length) {
                  return itemBuilder(context, controller.items[index]);
                }
                return _Footer(controller: controller);
              },
            ),
          );
        }
        return Column(
          children: [
            ?header,
            Expanded(child: body),
          ],
        );
      },
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.controller});

  final PagedController<dynamic> controller;

  @override
  Widget build(BuildContext context) {
    if (controller.loadingMore) {
      return const Padding(
        padding: EdgeInsets.all(HelixSpace.md),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final problem = controller.moreError;
    if (problem != null || controller.hasMore) {
      return Padding(
        padding: const EdgeInsets.all(HelixSpace.md),
        child: Column(
          children: [
            if (problem != null)
              Padding(
                padding: const EdgeInsets.only(bottom: HelixSpace.xs),
                child: Text(
                  problem,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            OutlinedButton(
              onPressed: controller.loadMore,
              child: Text(problem == null ? 'Load more' : 'Try again'),
            ),
          ],
        ),
      );
    }
    return const SizedBox(height: HelixSpace.lg);
  }
}
