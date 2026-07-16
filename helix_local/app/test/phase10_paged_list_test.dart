import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix/ui/components/helix_paged_list.dart';

void main() {
  testWidgets('P10 paged list loads first page and appends more lazily', (
    tester,
  ) async {
    final controller = HelixPagedListController<int>(
      pageSize: 3,
      fetchPage: (cursor, pageSize) async {
        final start = cursor as int? ?? 0;
        final items = List.generate(pageSize, (index) => start + index);
        final next = start + pageSize >= 6 ? null : start + pageSize;
        return (items: items, nextCursor: next);
      },
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          height: 120,
          child: HelixPagedList<int>(
            controller: controller,
            itemBuilder: (context, item, index) =>
                SizedBox(height: 64, child: Text('item $item')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('item 0'), findsOneWidget);
    expect(controller.items.length, equals(3));

    await controller.loadMore();
    await tester.pumpAndSettle();

    expect(controller.items.length, equals(6));
    expect(controller.isDone, isTrue);
  });
}
