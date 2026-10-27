import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_ui/orbit_ui.dart';

/// The GIF tray: the GIFs already on the phone.
void main() {
  late OrbitTokens orbit;
  setUpAll(() {
    orbit = OrbitTokens.fromThemeJson(
      jsonDecode(File('assets/themes/orbit.json').readAsStringSync())
          as Map<String, Object?>,
    );
  });

  // A 1x1 transparent PNG: any picture will do for a tile.
  final pixel = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
  );

  Future<void> openChat(WidgetTester tester, ChatActions actions) async {
    tester.view.physicalSize = const Size(412, 866);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: OrbitTheme.of(orbit),
        home: Scaffold(
          body: ChatScreen(
            model: ChatModel(
              conversationId: 'direct:nadia',
              title: 'Nadia Rahman',
              avatar: OrbitFakes.nadia.avatar,
            ),
            actions: actions,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Attach'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'GIF is in the attach sheet only when the app can load and send',
    (tester) async {
      await openChat(tester, ChatActions(onPickFiles: (_) {}));
      expect(find.text('GIF'), findsNothing);
    },
  );

  testWidgets('an empty tray says where GIFs come from', (tester) async {
    await openChat(
      tester,
      ChatActions(
        onPickFiles: (_) {},
        onLoadGifs: () => const [],
        onSendGif: (_) {},
      ),
    );
    await tester.tap(find.text('GIF'));
    await tester.pumpAndSettle();
    expect(find.text('GIFs'), findsWidgets);
    expect(find.textContaining('No GIFs on this phone yet'), findsOneWidget);
  });

  testWidgets('a tile sends its GIF and closes the tray', (tester) async {
    final sent = <String>[];
    await openChat(
      tester,
      ChatActions(
        onPickFiles: (_) {},
        onLoadGifs: () => [
          ChatGifItem(id: '7', image: MemoryImage(Uint8List.fromList(pixel))),
          ChatGifItem(id: '9', image: MemoryImage(Uint8List.fromList(pixel))),
        ],
        onSendGif: sent.add,
      ),
    );
    await tester.tap(find.text('GIF'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Send this GIF'), findsNWidgets(2));
    await tester.tap(find.bySemanticsLabel('Send this GIF').last);
    await tester.pumpAndSettle();
    expect(sent, ['9']);
    expect(find.bySemanticsLabel('Send this GIF'), findsNothing);
  });

  testWidgets('a tray that cannot load says so', (tester) async {
    await openChat(
      tester,
      ChatActions(
        onPickFiles: (_) {},
        onLoadGifs: () => throw StateError('disk'),
        onSendGif: (_) {},
      ),
    );
    await tester.tap(find.text('GIF'));
    await tester.pumpAndSettle();
    expect(find.text('GIFs could not be loaded.'), findsOneWidget);
  });
}
