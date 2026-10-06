import 'package:helix_remote_protocol/src/json.dart';

/// Cursor paging for list endpoints. Cursors are opaque strings issued by the
/// server; clients never build or parse them. There is no offset paging in v2.
final class PageRequest {
  const PageRequest({this.cursor, this.limit = defaultLimit});

  static const defaultLimit = 50;
  static const maxLimit = 200;

  final String? cursor;
  final int limit;

  /// Query parameters for the request URL.
  Map<String, String> toQuery() => {'cursor': ?cursor, 'limit': '$limit'};

  /// Parses query parameters, clamping `limit` into `1..maxLimit`.
  factory PageRequest.fromQuery(Map<String, String> query) {
    final parsed = int.tryParse(query['limit'] ?? '');
    return PageRequest(
      cursor: (query['cursor']?.isEmpty ?? true) ? null : query['cursor'],
      limit: parsed == null ? defaultLimit : parsed.clamp(1, maxLimit),
    );
  }
}

/// One page of results. [nextCursor] is null on the last page.
final class Page<T> {
  const Page({required this.items, this.nextCursor});

  final List<T> items;
  final String? nextCursor;

  bool get isLast => nextCursor == null;

  JsonMap toJson(JsonMap Function(T item) encode) => compact({
    'items': [for (final item in items) encode(item)],
    'next_cursor': nextCursor,
  });

  static Page<T> fromJson<T>(
    JsonReader json,
    T Function(JsonReader item) decode,
  ) => Page(
    items: json.objects('items', decode),
    nextCursor: json.optString('next_cursor'),
  );
}
