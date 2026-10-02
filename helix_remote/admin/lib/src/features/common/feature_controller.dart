import 'package:flutter/foundation.dart';
import 'package:helix_admin/src/api/error_text.dart';
import 'package:helix_admin/src/session/admin_session_controller.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// Base for the per-feature state classes: plain `ChangeNotifier`s that own
/// one screen's data and talk to the server through [ctx].
abstract class FeatureController extends ChangeNotifier {
  FeatureController(this.ctx);

  final AdminContext ctx;
  bool _disposed = false;

  bool get isDisposed => _disposed;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Runs [action]. A failure goes to the session (a rejected token ends it)
  /// and comes back as operator-facing text; success returns null.
  Future<String?> attempt(Future<void> Function() action) async {
    try {
      await action();
      return null;
    } on Object catch (e) {
      ctx.report(e);
      return describeAdminError(e, now: ctx.now);
    }
  }
}

/// A cursor-paged list: the first page, then "load more". The server only
/// pages forward, so there is no page number.
abstract class PagedController<T> extends FeatureController {
  PagedController(super.ctx, {this.pageSize = 50});

  final int pageSize;

  List<T> _items = const [];
  String? _next;
  bool _loading = false;
  bool _loadingMore = false;
  bool _loaded = false;
  String? _error;
  String? _moreError;

  // A refresh that overtakes an older one (filter changed) wins.
  int _generation = 0;

  /// One page from the server.
  Future<Page<T>> fetch(PageRequest page);

  List<T> get items => _items;

  /// True while the first page of the current filter is loading.
  bool get loading => _loading;
  bool get loadingMore => _loadingMore;

  /// True once a page has arrived for the current filter.
  bool get loaded => _loaded;
  bool get hasMore => _next != null;

  /// The first page failed; [items] is empty.
  String? get error => _error;

  /// Loading more failed; [items] keeps what it had.
  String? get moreError => _moreError;

  /// Loads the first page again.
  Future<void> refresh() async {
    final generation = ++_generation;
    _loading = true;
    _loadingMore = false;
    _error = null;
    _moreError = null;
    notifyListeners();
    try {
      final page = await fetch(PageRequest(limit: pageSize));
      if (generation != _generation || isDisposed) return;
      _items = page.items;
      _next = page.nextCursor;
      _loaded = true;
    } on Object catch (e) {
      if (generation != _generation || isDisposed) return;
      ctx.report(e);
      _items = const [];
      _next = null;
      _loaded = false;
      _error = describeAdminError(e, now: ctx.now);
    }
    _loading = false;
    notifyListeners();
  }

  /// Appends the next page.
  Future<void> loadMore() async {
    final cursor = _next;
    if (cursor == null || _loadingMore || _loading) return;
    final generation = _generation;
    _loadingMore = true;
    _moreError = null;
    notifyListeners();
    try {
      final page = await fetch(PageRequest(cursor: cursor, limit: pageSize));
      if (generation != _generation || isDisposed) return;
      _items = [..._items, ...page.items];
      _next = page.nextCursor;
    } on Object catch (e) {
      if (generation != _generation || isDisposed) return;
      ctx.report(e);
      _moreError = describeAdminError(e, now: ctx.now);
    }
    _loadingMore = false;
    notifyListeners();
  }

  /// Replaces the first item for which [test] is true (after an action).
  void replaceWhere(bool Function(T item) test, T replacement) {
    _items = [for (final i in _items) test(i) ? replacement : i];
    notifyListeners();
  }

  void removeWhere(bool Function(T item) test) {
    _items = [
      for (final i in _items)
        if (!test(i)) i,
    ];
    notifyListeners();
  }
}
