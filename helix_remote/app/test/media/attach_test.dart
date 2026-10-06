import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/core/chat/chat_gateway.dart';
import 'package:helix_remote/core/platform/attachment_picker.dart';
import 'package:helix_remote/core/platform/chat_platform.dart';
import 'package:helix_remote/features/conversation/application/composer_notifier.dart';
import 'package:helix_remote/features/conversation/presentation/send_files_screen.dart';

import '../support/chat_harness.dart';
import '../support/media_fakes.dart';

void main() {
  late Directory dir;
  late Directory captures;
  late Directory clean;
  late FakePicker picker;
  late FakeSanitizer sanitizer;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('helix_attach');
    captures = Directory('${dir.path}/helix_capture')..createSync();
    clean = Directory('${dir.path}/helix_clean')..createSync();
    picker = FakePicker();
    sanitizer = FakeSanitizer(clean);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  PickedFile capture(String name, {PickedKind kind = PickedKind.image}) {
    final file = File('${captures.path}/$name')..writeAsBytesSync([1, 2, 3]);
    return PickedFile(
      path: file.path,
      name: name,
      mime: kind == PickedKind.image ? 'image/jpeg' : 'video/mp4',
      size: 3,
      kind: kind,
      temporary: true,
    );
  }

  List<Override> overrides() => [
    attachmentPickerProvider.overrideWithValue(picker),
    mediaSanitizerProvider.overrideWithValue(sanitizer),
    mediaTempProvider.overrideWithValue(tempIn(dir)),
  ];

  ProviderContainer container(TestChatGateway gateway) {
    final c = ProviderContainer(
      overrides: [
        chatGatewayProvider.overrideWith((ref) => gateway),
        ...overrides(),
      ],
    );
    addTearDown(c.dispose);
    c.listen(composerProvider('c1'), (_, _) {});
    return c;
  }

  /// Real file work runs outside the fake clock; two rounds let a chain of
  /// file calls finish, with a frame between so their results are delivered.
  Future<void> real(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 250)),
      );
      await tester.pump();
    }
  }

  testWidgets('the camera gives a photo or a video, or says why not', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final gateway = await TestChatGateway.create();
      final c = container(gateway);
      final composer = c.read(composerProvider('c1').notifier);

      picker.photo = capture('a.jpg');
      picker.video = capture('b.mp4', kind: PickedKind.video);
      expect(
        (await composer.pick(AttachmentSource.cameraPhoto)).single.name,
        'a.jpg',
      );
      expect(
        (await composer.pick(AttachmentSource.cameraVideo)).single.kind,
        DraftKind.video,
      );

      // Backing out of the camera is "nothing", with no message.
      picker.photo = null;
      expect(await composer.pick(AttachmentSource.cameraPhoto), isEmpty);
      expect(c.read(composerProvider('c1')).notice, isNull);

      picker.denied = true;
      expect(await composer.pick(AttachmentSource.cameraPhoto), isEmpty);
      expect(
        c.read(composerProvider('c1')).notice,
        contains('Allow camera access'),
      );

      picker.camera = false;
      picker.denied = false;
      await composer.pick(AttachmentSource.cameraVideo);
      expect(
        c.read(composerProvider('c1')).notice,
        contains('camera is not available'),
      );
      await gateway.close();
    });
  });

  testWidgets('a captured photo is cleaned, sent, and every copy deleted', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final gateway = await TestChatGateway.create();
      final c = container(gateway);
      final composer = c.read(composerProvider('c1').notifier);
      final shot = capture('a.jpg');
      final theirs = File('${dir.path}/holiday.jpg')..writeAsBytesSync([9]);
      final own = PickedFile(
        path: theirs.path,
        name: 'holiday.jpg',
        mime: 'image/jpeg',
        size: 1,
        kind: PickedKind.image,
      );

      final ok = await composer.sendFiles([
        AttachmentDraft(shot),
        AttachmentDraft(own),
      ]);
      expect(ok, isTrue);
      // The engine was handed the cleaned copies, never the originals.
      expect(gateway.sentPaths, hasLength(2));
      expect(gateway.sentPaths, everyElement(contains('helix_clean')));
      expect(File(shot.path).existsSync(), isFalse, reason: 'camera file');
      expect(clean.listSync(), isEmpty, reason: 'cleaned copies');
      expect(theirs.existsSync(), isTrue, reason: 'their own file stays');
      await gateway.close();
    });
  });

  testWidgets('a failed send keeps the capture for a retry, not the copy', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final gateway = await TestChatGateway.create()
        ..failMedia = true;
      final c = container(gateway);
      final composer = c.read(composerProvider('c1').notifier);
      final shot = capture('a.jpg');
      expect(await composer.sendFiles([AttachmentDraft(shot)]), isFalse);
      expect(
        c.read(composerProvider('c1')).notice,
        contains('could not be sent'),
      );
      expect(File(shot.path).existsSync(), isTrue);
      expect(clean.listSync(), isEmpty);
      await gateway.close();
    });
  });

  testWidgets('a photo whose location cannot be removed is never sent', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final gateway = await TestChatGateway.create();
      final c = container(gateway);
      final composer = c.read(composerProvider('c1').notifier);
      sanitizer.refuse.add('bad.heic');
      final good = capture('good.jpg');
      final bad = capture('bad.heic');

      // Alone: nothing is sent.
      expect(await composer.sendFiles([AttachmentDraft(bad)]), isFalse);
      expect(gateway.log.where((l) => l.startsWith('sendMedia')), isEmpty);
      expect(
        c.read(composerProvider('c1')).notice,
        contains('nothing was sent'),
      );

      // With another: the rest goes, and the person is told.
      expect(
        await composer.sendFiles([AttachmentDraft(bad), AttachmentDraft(good)]),
        isTrue,
      );
      expect(gateway.sentPaths, hasLength(1));
      expect(c.read(composerProvider('c1')).notice, contains('was not sent'));
      await gateway.close();
    });
  });

  testWidgets('a document is sent as it is and left alone', (tester) async {
    await tester.runAsync(() async {
      final gateway = await TestChatGateway.create();
      final c = container(gateway);
      final composer = c.read(composerProvider('c1').notifier);
      final pdf = File('${dir.path}/a.pdf')..writeAsBytesSync([1]);
      await composer.sendFiles([
        AttachmentDraft(
          PickedFile(
            path: pdf.path,
            name: 'a.pdf',
            mime: 'application/pdf',
            size: 1,
            kind: PickedKind.document,
          ),
        ),
      ]);
      expect(gateway.sentPaths.single, pdf.path);
      expect(pdf.existsSync(), isTrue);
      await gateway.close();
    });
  });

  chatTest('leaving the preview deletes the camera file and nothing else', (
    tester,
    gateway,
  ) async {
    // Videos, so no picture preview keeps the files open (Windows refuses to
    // delete a file that is open).
    final shot = capture('a.mp4', kind: PickedKind.video);
    final second = capture('second.mp4', kind: PickedKind.video);
    final theirs = File('${dir.path}/mine.mp4')..writeAsBytesSync([5]);
    await tester.pumpWidget(
      chatApp(
        gateway,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const SendFilesScreen(conversationId: 'c1'),
              ),
            ),
            child: const Text('open'),
          ),
        ),
        overrides: overrides(),
      ),
    );
    final scope = ProviderScope.containerOf(tester.element(find.text('open')));
    scope.read(pendingAttachmentsProvider('c1').notifier).set([
      AttachmentDraft(second),
      AttachmentDraft(shot),
      AttachmentDraft(
        PickedFile(
          path: theirs.path,
          name: 'mine.mp4',
          mime: 'video/mp4',
          size: 1,
          kind: PickedKind.video,
        ),
      ),
    ]);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Send 3 files'), findsOneWidget);

    // Removing the camera's file deletes it at once.
    await tester.tap(find.byTooltip('Remove second.mp4'));
    await tester.pump();
    await real(tester);
    expect(File(second.path).existsSync(), isFalse);
    expect(File(shot.path).existsSync(), isTrue);

    // Back without sending.
    await tester.pageBack();
    await tester.pumpAndSettle();
    await real(tester);
    expect(File(shot.path).existsSync(), isFalse);
    expect(theirs.existsSync(), isTrue);
    await tester.pump();
    expect(scope.read(pendingAttachmentsProvider('c1')), isEmpty);
  });
}
