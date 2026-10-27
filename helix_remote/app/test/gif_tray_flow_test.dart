import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/core/platform/chat_platform.dart';
import 'package:helix_remote/features/conversation/presentation/conversation_screen.dart';
import 'package:helix_remote_db/helix_remote_db.dart';

import 'support/chat_harness.dart';
import 'support/media_fakes.dart';

/// The GIF tray offers the GIFs the person already has and sends one again.
void main() {
  late Directory dir;
  late Directory clean;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('helix_gif');
    clean = Directory('${dir.path}/helix_clean')..createSync();
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<int> gifOnPhone(
    TestChatGateway gateway,
    String chat,
    String name, {
    bool fileExists = true,
    int digest = 1,
  }) async {
    final file = File('${dir.path}/$name');
    if (fileExists) file.writeAsBytesSync([0x47, 0x49, 0x46, 0x38, 0x39, 0x61]);
    final message = await gateway.incoming(chat, 'a gif');
    final id = await gateway.db
        .into(gateway.db.attachments)
        .insert(
          AttachmentsCompanion.insert(
            messageRowid: message.localRowid,
            position: 0,
            kind: 'gif',
            mediaId: 'm$digest',
            mediaKey: Uint8List(32),
            digest: Uint8List.fromList(List.filled(32, digest)),
            mime: 'image/gif',
            size: 6,
            localPath: Value(file.path),
            transfer: AttachmentTransfer.ready,
          ),
        );
    gateway.localPaths[id] = file.path;
    return id;
  }

  chatTest('GIF > a tile sends that GIF as a GIF, from a cleaned copy', (
    tester,
    gateway,
  ) async {
    final chat = (await tester.runAsync(
      () => gateway.chatWith('bob', name: 'Bob'),
    ))!;
    await tester.runAsync(() => gifOnPhone(gateway, chat, 'cat.gif'));
    tester.view.physicalSize = const Size(412, 866);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      chatApp(
        gateway,
        ConversationScreen(conversationId: chat),
        overrides: [
          mediaSanitizerProvider.overrideWithValue(FakeSanitizer(clean)),
          mediaTempProvider.overrideWithValue(tempIn(dir)),
        ],
      ),
    );
    await settle(tester, rounds: 10);

    await tester.tap(find.byTooltip('Attach'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('GIF'));
    await settle(tester, rounds: 10);
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Send this GIF'));
    for (var i = 0; i < 20 && gateway.sentPaths.isEmpty; i++) {
      await settle(tester, rounds: 2);
    }

    expect(gateway.log, contains('sendMedia:$chat:1'));
    expect(gateway.sentPaths.single, contains('helix_clean'));
  });

  chatTest('a GIF whose file is gone is not offered', (tester, gateway) async {
    final chat = (await tester.runAsync(
      () => gateway.chatWith('bob', name: 'Bob'),
    ))!;
    await tester.runAsync(() async {
      await gifOnPhone(gateway, chat, 'there.gif', digest: 1);
      await gifOnPhone(gateway, chat, 'gone.gif', fileExists: false, digest: 2);
    });
    tester.view.physicalSize = const Size(412, 866);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      chatApp(gateway, ConversationScreen(conversationId: chat)),
    );
    await settle(tester, rounds: 10);
    await tester.tap(find.byTooltip('Attach'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('GIF'));
    await settle(tester, rounds: 10);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Send this GIF'), findsOneWidget);
  });
}
