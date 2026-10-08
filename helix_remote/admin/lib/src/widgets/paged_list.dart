import 'package:flutter/material.dart';
import 'package:helix_admin/src/features/common/feature_controller.dart';
import 'package:helix_admin/src/widgets/console_kit.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// A refreshable, cursor-paged list for any [PagedController]: the first
/// page, a "Load more" button while the server has more, and distinct
/// loading, empty and error states. The header (title, search, filters)
/// scrolls with the list and stays while it reloads.
class PagedListView<T> extends StatelessWidget {
  const PagedListView({
    super.key,
    required this.controller,
    required this.itemBuilder,
    required this.emptyIcon,
    required this.emptyTitle,
    this.emptyMessage,
    this.header,
    this.shown,
    this.gap = 10,
    this.padding = const EdgeInsets.all(16),
  });

  final PagedController<T> controller;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final IconData emptyIcon;
  final String emptyTitle;
  final String? emptyMessage;

  /// A title and filters, shown above the list and kept while it reloads.
  final Widget? header;

  /// Narrows what is listed (a client-side filter over the loaded pages);
  /// null lists everything the controller has.
  final List<T>? shown;

  /// Space between two items.
  final double gap;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final items = shown ?? controller.items;
        final hasHeader = header != null;
        final Widget? state;
        if (controller.loading && controller.items.isEmpty) {
          state = const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: ConsoleLoading(),
          );
        } else if (controller.error != null) {
          state = ConsoleBanner(
            title: 'Something went wrong',
            message: controller.error!,
            onRetry: controller.refresh,
          );
        } else if (items.isEmpty) {
          state = ConsoleEmpty(
            icon: emptyIcon,
            title: emptyTitle,
            message: emptyMessage,
          );
        } else {
          state = null;
        }
        final lead = hasHeader ? 1 : 0;
        final count = state != null ? lead + 1 : lead + items.length + 1;
        return RefreshIndicator(
          onRefresh: controller.refresh,
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: padding,
            itemCount: count,
            itemBuilder: (context, index) {
              if (hasHeader && index == 0) {
                return Padding(
                  padding: EdgeInsets.only(bottom: gap + 6),
                  child: header,
                );
              }
              if (state != null) return state;
              final i = index - lead;
              if (i < items.length) {
                return Padding(
                  padding: EdgeInsets.only(bottom: gap),
                  child: itemBuilder(context, items[i]),
                );
              }
              return _Footer(controller: controller);
            },
          ),
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
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final problem = controller.moreError;
    if (problem != null || controller.hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            if (problem != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  problem,
                  style: const TextStyle(color: HelixConsoleColors.danger),
                ),
              ),
            OutlinedButton(
              onPressed: controller.loadMore,
              style: ConsoleButtons.outlined,
              child: Text(problem == null ? 'Load more' : 'Try again'),
            ),
          ],
        ),
      );
    }
    return const SizedBox(height: 24);
  }
}
