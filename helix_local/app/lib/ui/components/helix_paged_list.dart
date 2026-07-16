// lib/ui/components/helix_paged_list.dart
//
// P10-03 — Paginated/virtualized list infrastructure.
//
// Provides a generic [HelixPagedListController] and [HelixPagedList] widget
// that load pages of data lazily as the user scrolls. The controller owns
// page-cursor state and calls a caller-supplied fetch function when more
// data is needed. All expensive DB reads should go through this path so that
// the UI isolate never decrypts/searches hundreds of rows in one shot.

import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Controller
// ---------------------------------------------------------------------------

enum _PagedState { idle, loading, loadingMore, done, error }

class HelixPagedListController<T> extends ChangeNotifier {
  HelixPagedListController({required this.fetchPage, this.pageSize = 30});

  /// Caller-supplied function: given the current cursor (null on first page),
  /// return the next page of items and the next cursor (null when exhausted).
  final Future<({List<T> items, dynamic nextCursor})> Function(
    dynamic cursor,
    int pageSize,
  )
  fetchPage;

  final int pageSize;

  final List<T> _items = [];
  List<T> get items => List.unmodifiable(_items);

  dynamic _cursor;
  _PagedState _state = _PagedState.idle;
  Object? _error;

  bool get isLoading => _state == _PagedState.loading;
  bool get isLoadingMore => _state == _PagedState.loadingMore;
  bool get isDone => _state == _PagedState.done;
  bool get hasError => _state == _PagedState.error;
  Object? get error => _error;

  bool get _canLoadMore =>
      _state != _PagedState.loading &&
      _state != _PagedState.loadingMore &&
      _state != _PagedState.done;

  Future<void> loadFirst() async {
    if (_state == _PagedState.loading) return;
    _items.clear();
    _cursor = null;
    _error = null;
    _state = _PagedState.loading;
    notifyListeners();
    await _doFetch();
  }

  Future<void> loadMore() async {
    if (!_canLoadMore) return;
    _state = _PagedState.loadingMore;
    notifyListeners();
    await _doFetch();
  }

  Future<void> _doFetch() async {
    try {
      final result = await fetchPage(_cursor, pageSize);
      _items.addAll(result.items);
      _cursor = result.nextCursor;
      _state = result.nextCursor == null ? _PagedState.done : _PagedState.idle;
    } catch (e) {
      _error = e;
      _state = _PagedState.error;
    }
    notifyListeners();
  }

  void refresh() => loadFirst();
}

// ---------------------------------------------------------------------------
// Widget
// ---------------------------------------------------------------------------

class HelixPagedList<T> extends StatefulWidget {
  const HelixPagedList({
    super.key,
    required this.controller,
    required this.itemBuilder,
    this.separatorBuilder,
    this.emptyBuilder,
    this.errorBuilder,
    this.loadingBuilder,
    this.padding,
    this.reverse = false,
    this.physics,
    this.scrollController,
    // Fraction of viewport remaining before the next page load is triggered.
    this.loadMoreThreshold = 0.2,
  });

  final HelixPagedListController<T> controller;
  final Widget Function(BuildContext context, T item, int index) itemBuilder;
  final Widget Function(BuildContext context, int index)? separatorBuilder;
  final WidgetBuilder? emptyBuilder;
  final Widget Function(BuildContext context, Object error)? errorBuilder;
  final WidgetBuilder? loadingBuilder;
  final EdgeInsetsGeometry? padding;
  final bool reverse;
  final ScrollPhysics? physics;
  final ScrollController? scrollController;
  final double loadMoreThreshold;

  @override
  State<HelixPagedList<T>> createState() => _HelixPagedListState<T>();
}

class _HelixPagedListState<T> extends State<HelixPagedList<T>> {
  late final ScrollController _scrollController;
  bool _ownsScrollController = false;

  @override
  void initState() {
    super.initState();
    if (widget.scrollController != null) {
      _scrollController = widget.scrollController!;
    } else {
      _scrollController = ScrollController();
      _ownsScrollController = true;
    }
    _scrollController.addListener(_onScroll);
    widget.controller.addListener(_rebuild);
    widget.controller.loadFirst();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    if (_ownsScrollController) _scrollController.dispose();
    widget.controller.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() => setState(() {});

  void _onScroll() {
    final pos = _scrollController.position;
    final trigger = pos.maxScrollExtent * (1 - widget.loadMoreThreshold);
    if (pos.pixels >= trigger) {
      widget.controller.loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.controller;

    if (ctrl.isLoading) {
      return widget.loadingBuilder?.call(context) ??
          const Center(child: CircularProgressIndicator());
    }

    if (ctrl.hasError && ctrl.items.isEmpty) {
      return widget.errorBuilder?.call(context, ctrl.error!) ??
          Center(child: Text('Error: ${ctrl.error}'));
    }

    if (ctrl.items.isEmpty && ctrl.isDone) {
      return widget.emptyBuilder?.call(context) ??
          const Center(child: Text('No items.'));
    }

    // Total item count: data items + optional footer (spinner or done indicator).
    final hasFooter =
        ctrl.isLoadingMore || (ctrl.isDone && ctrl.items.isNotEmpty);
    final footerCount = hasFooter ? 1 : 0;
    final itemCount = ctrl.items.length + footerCount;

    final separator = widget.separatorBuilder;
    if (separator != null) {
      return ListView.separated(
        controller: _scrollController,
        padding: widget.padding,
        reverse: widget.reverse,
        physics: widget.physics,
        itemCount: itemCount,
        separatorBuilder: (ctx, i) {
          if (i >= ctrl.items.length - 1) return const SizedBox.shrink();
          return separator(ctx, i);
        },
        itemBuilder: (ctx, i) => _buildItem(ctx, i, ctrl),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: widget.padding,
      reverse: widget.reverse,
      physics: widget.physics,
      itemCount: itemCount,
      itemBuilder: (ctx, i) => _buildItem(ctx, i, ctrl),
    );
  }

  Widget _buildItem(BuildContext ctx, int i, HelixPagedListController<T> ctrl) {
    if (i < ctrl.items.length) {
      return widget.itemBuilder(ctx, ctrl.items[i], i);
    }
    // Footer slot.
    if (ctrl.isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return const SizedBox.shrink();
  }
}

// ---------------------------------------------------------------------------
// Bidirectional paged list (for chat history: load older messages upward)
// ---------------------------------------------------------------------------

class HelixBidirectionalPagedList<T> extends StatefulWidget {
  const HelixBidirectionalPagedList({
    super.key,
    required this.controller,
    required this.itemBuilder,
    this.separatorBuilder,
    this.emptyBuilder,
    this.padding,
    this.physics,
  });

  final HelixPagedListController<T> controller;
  final Widget Function(BuildContext context, T item, int index) itemBuilder;
  final Widget Function(BuildContext context, int index)? separatorBuilder;
  final WidgetBuilder? emptyBuilder;
  final EdgeInsetsGeometry? padding;
  final ScrollPhysics? physics;

  @override
  State<HelixBidirectionalPagedList<T>> createState() =>
      _HelixBidirectionalPagedListState<T>();
}

class _HelixBidirectionalPagedListState<T>
    extends State<HelixBidirectionalPagedList<T>> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    widget.controller.addListener(_rebuild);
    widget.controller.loadFirst();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    widget.controller.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() => setState(() {});

  void _onScroll() {
    // In reverse mode, scrolling toward the beginning triggers older-page load.
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent * 0.8) {
      widget.controller.loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.controller;

    if (ctrl.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (ctrl.items.isEmpty) {
      return widget.emptyBuilder?.call(context) ??
          const Center(child: Text('No messages.'));
    }

    final hasHeader = ctrl.isLoadingMore;
    final headerCount = hasHeader ? 1 : 0;
    final itemCount = ctrl.items.length + headerCount;

    return ListView.builder(
      controller: _scrollController,
      padding: widget.padding,
      physics: widget.physics,
      reverse: true,
      itemCount: itemCount,
      itemBuilder: (ctx, i) {
        if (i == itemCount - 1 && hasHeader) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return widget.itemBuilder(ctx, ctrl.items[i], i);
      },
    );
  }
}
