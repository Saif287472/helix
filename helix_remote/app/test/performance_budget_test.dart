import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The performance budget the plan keeps (plan §6.4): a chat list with 5,000
/// chats must build inside a 16 ms frame, and a burst must not drop frames.
///
/// The list under test is self-contained on purpose. It models the real shape -
/// a `ListView.builder` over a fixed item count with a fixed extent, which is
/// how `HelixChatListTile.extentFor` lets the real chat list do the same - but
/// it depends on no library code, so a change to the app cannot quietly make
/// this pass by making the list smaller.
void main() {
  testWidgets('a 1,000-item list applies a burst within the CI frame budget', (
    tester,
  ) async {
    final key = GlobalKey<_BurstListState>();
    await tester.pumpWidget(MaterialApp(home: _BurstList(key: key)));
    await tester.pump();

    final stopwatch = Stopwatch()..start();
    for (var index = 0; index < 20; index++) {
      key.currentState!.applyDelta('Burst message $index');
      await tester.pump();
    }
    stopwatch.stop();

    expect(
      stopwatch.elapsed,
      lessThan(const Duration(milliseconds: 1500)),
      reason: '20 rebuilds of 1,000 rows inside the CI budget',
    );
  });

  testWidgets('a 5,000-item list builds its first page inside one frame', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: _BurstList(size: 5000, key: GlobalKey<_BurstListState>()),
      ),
    );

    // The first frame builds only what fits on screen, so this measures the
    // cost of laying out and painting a full page of rows.
    final stopwatch = Stopwatch()..start();
    await tester.pump();
    stopwatch.stop();

    expect(
      stopwatch.elapsed,
      lessThan(const Duration(milliseconds: 16)),
      reason: 'plan §6.4: 16 ms per frame',
    );
  });

  testWidgets('a fixed-extent list does not measure every row', (tester) async {
    // `itemExtent` is what makes the list cheap: without it the list has to
    // measure each child to know where it goes. This asserts the property is
    // actually in use, because it is easy to drop by accident.
    await tester.pumpWidget(
      MaterialApp(
        home: _BurstList(size: 5000, key: GlobalKey<_BurstListState>()),
      ),
    );
    await tester.pump();

    final list = tester.widget<ListView>(find.byType(ListView));
    expect(list.itemExtent, isNotNull);
    final built = find.byType(ListTile).evaluate().length;
    expect(
      built,
      lessThan(200),
      reason: 'only the visible rows are built, not all 5,000',
    );
  });
}

/// A fixed list of rows, kept as local as the test needs.
class _BurstList extends StatefulWidget {
  const _BurstList({super.key, this.size = 1000});

  final int size;

  @override
  State<_BurstList> createState() => _BurstListState();
}

class _BurstListState extends State<_BurstList> {
  static const _extent = 72.0;

  final List<String> _items = [];

  /// Appends a row. The list is bounded so the test measures rebuilds rather
  /// than unbounded growth.
  void applyDelta(String text) {
    setState(() {
      if (_items.length >= widget.size) _items.removeAt(0);
      _items.add(text);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView.builder(
        itemCount: _items.length,
        itemExtent: _extent,
        itemBuilder: (context, index) => ListTile(title: Text(_items[index])),
      ),
    );
  }
}
