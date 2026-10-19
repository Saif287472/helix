import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/core/platform/chat_platform.dart';
import 'package:helix_remote/core/platform/file_actions.dart';
import 'package:helix_remote/core/platform/video_player.dart';
import 'package:helix_remote/features/conversation/application/media_content.dart';
import 'package:helix_remote/features/conversation/application/media_viewer.dart';
import 'package:helix_remote/features/conversation/presentation/media_viewer_screen.dart';
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:orbit_ui/orbit_ui.dart' show OrbitSpinner;

import '../support/chat_harness.dart';
import '../support/media_fakes.dart';

/// The video in the media viewer: the Orbit viewer over the app's player.
void main() {
  AttachmentRow attachment(
    int position,
    String kind, {
    String? localPath,
    AttachmentTransfer transfer = AttachmentTransfer.ready,
  }) => AttachmentRow(
    id: position + 1,
    messageRowid: 7,
    position: position,
    kind: kind,
    mediaId: 'm$position',
    mediaKey: Uint8List(32),
    digest: Uint8List(32),
    mime: kind == 'video' ? 'video/mp4' : 'image/jpeg',
    size: 3,
    localPath: localPath,
    transfer: transfer,
  );

  /// One video by default; [album] puts a photo that has not downloaded yet
  /// in front of it. What is handed to the share sheet lands in [shared].
  Widget app(
    TestChatGateway gateway,
    FakeVideoPlayers players, {
    bool album = false,
    double textScale = 1,
    List<String>? shared,
  }) => chatApp(
    gateway,
    Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: const MediaViewerScreen(rowid: 7),
      ),
    ),
    overrides: [
      videoPlayersProvider.overrideWithValue(players),
      viewerMetaProvider.overrideWith(
        (ref, rowid) async =>
            const ViewerMeta(senderName: 'Bob', timeLabel: 'Today, 14:30'),
      ),
      messageMediaProvider.overrideWith(
        (ref, rowid) => Stream.value([
          if (album)
            MediaPart(
              attachment(0, 'image', transfer: AttachmentTransfer.remote),
              null,
            ),
          MediaPart(attachment(1, 'video', localPath: '/v.mp4'), null),
        ]),
      ),
      fileActionsProvider.overrideWithValue(_Files(shared ?? <String>[])),
    ],
  );

  Future<void> opened(WidgetTester tester) async {
    await tester.pump(); // the message and its files
    await tester.pump(); // the open future
    await tester.pump();
  }

  chatTest('opens, plays at once, and shows pause with the time', (
    tester,
    gateway,
  ) async {
    final players = FakeVideoPlayers();
    await tester.pumpWidget(app(gateway, players));
    expect(find.byType(OrbitSpinner), findsOneWidget);
    await opened(tester);
    final playback = players.opened.single;
    expect(playback.calls, containsAllInOrder(['init', 'play']));
    expect(find.byKey(const Key('video-surface')), findsOneWidget);
    expect(find.byTooltip('Pause'), findsOneWidget);
    expect(find.text('0:20'), findsOneWidget);

    await tester.tap(find.byTooltip('Pause'));
    await tester.pump();
    expect(playback.calls.last, 'pause');
    expect(find.byTooltip('Play'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    expect(playback.calls.last, 'dispose', reason: 'the decoder is released');
  });

  chatTest('controls hide while playing and a tap brings them back', (
    tester,
    gateway,
  ) async {
    final players = FakeVideoPlayers();
    await tester.pumpWidget(app(gateway, players));
    await opened(tester);
    expect(find.byTooltip('Pause'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    expect(find.byTooltip('Pause'), findsNothing);
    await tester.tapAt(
      tester.getCenter(find.byKey(const Key('video-surface'))),
    );
    await tester.pump();
    expect(find.byTooltip('Pause'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });

  chatTest('seek bar seeks, the speed chip cycles 1x 1.5x 2x', (
    tester,
    gateway,
  ) async {
    final players = FakeVideoPlayers();
    await tester.pumpWidget(app(gateway, players));
    await opened(tester);
    final playback = players.opened.single;

    await tester.tap(find.byTooltip('Pause')); // keep the controls up
    await tester.pump();
    await tester.tapAt(
      tester.getCenter(find.byType(Slider)),
    ); // middle of the bar
    await tester.pump();
    expect(playback.calls.where((c) => c.startsWith('seek')).single, 'seek:10');

    await tester.tap(find.text('1x'));
    await tester.pump();
    expect(find.text('1.5x'), findsOneWidget);
    await tester.tap(find.text('1.5x'));
    await tester.pump();
    expect(find.text('2x'), findsOneWidget);
    await tester.tap(find.text('2x'));
    await tester.pump();
    expect(find.text('1x'), findsOneWidget);
    expect(playback.calls.where((c) => c.startsWith('speed')), [
      'speed:1.5',
      'speed:2.0',
      'speed:1.0',
    ]);
  });

  chatTest('played to the end offers to play again', (tester, gateway) async {
    final players = FakeVideoPlayers();
    await tester.pumpWidget(app(gateway, players));
    await opened(tester);
    final playback = players.opened.single;
    playback.value.value = const VideoPlaybackState(
      duration: Duration(seconds: 20),
      completed: true,
    );
    await tester.pump();
    expect(find.byTooltip('Play again'), findsOneWidget);
    await tester.tap(find.byTooltip('Play again'));
    await tester.pump();
    expect(playback.calls.last, 'play');
    expect(find.byTooltip('Pause'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });

  chatTest('a file the decoder refuses offers the share sheet', (
    tester,
    gateway,
  ) async {
    final shared = <String>[];
    gateway.localPaths[2] = '/v.mp4';
    final players = FakeVideoPlayers(failInit: true);
    await tester.pumpWidget(app(gateway, players, shared: shared));
    await opened(tester);
    expect(find.textContaining('cannot be played'), findsOneWidget);
    await tester.tap(find.text('Open video'));
    expect(shared, ['/v.mp4']);
  });

  chatTest('a platform without a player never opens one', (
    tester,
    gateway,
  ) async {
    final shared = <String>[];
    gateway.localPaths[2] = '/v.mp4';
    final players = FakeVideoPlayers(supported: false);
    await tester.pumpWidget(app(gateway, players, shared: shared));
    await opened(tester);
    expect(players.opened, isEmpty);
    expect(
      find.textContaining('cannot be played inside Helix'),
      findsOneWidget,
    );
    await tester.tap(find.text('Open video'));
    expect(shared, ['/v.mp4']);
  });

  chatTest('a page that is not on screen is only a poster', (
    tester,
    gateway,
  ) async {
    final players = FakeVideoPlayers();
    await tester.pumpWidget(app(gateway, players, album: true));
    await opened(tester);
    // The photo in front has not downloaded; the video beside it has no
    // player until its page is the one on screen.
    expect(find.text('This file is not on your device yet.'), findsOneWidget);
    expect(find.text('Today, 14:30 (1 of 2)'), findsOneWidget);
    expect(players.opened, isEmpty);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await opened(tester);
    expect(find.text('Today, 14:30 (2 of 2)'), findsOneWidget);
    expect(players.opened, hasLength(1));
    expect(find.byKey(const Key('video-surface')), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });

  chatTest('going to the background pauses', (tester, gateway) async {
    final players = FakeVideoPlayers();
    await tester.pumpWidget(app(gateway, players));
    await opened(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    expect(players.opened.single.calls.last, 'pause');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  chatTest('controls fit at 2x text with 48 px targets', (
    tester,
    gateway,
  ) async {
    final players = FakeVideoPlayers();
    await tester.pumpWidget(app(gateway, players, textScale: 2));
    await opened(tester);
    await tester.tap(find.byTooltip('Pause'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    final play = tester.getSize(find.byTooltip('Play'));
    expect(play.width, greaterThanOrEqualTo(48));
    expect(play.height, greaterThanOrEqualTo(48));
    // The speed chip is drawn 30px high; its target reaches 48px, so a tap
    // 8px above it still changes the speed.
    final chip = tester.getRect(find.byTooltip('Playback speed'));
    expect(chip.height, lessThan(48));
    await tester.tapAt(chip.topCenter - Offset(0, (48 - chip.height) / 2 - 1));
    await tester.pump();
    expect(find.text('1.5x'), findsOneWidget);
    // At 2x text the chip itself is wide enough.
    expect(chip.width, greaterThanOrEqualTo(48));
  });
}

/// Records what is handed to the share sheet.
final class _Files implements FileActions {
  _Files(this.shared);

  final List<String> shared;

  @override
  Future<void> shareFile({
    required String path,
    required String name,
    required String mime,
  }) async => shared.add(path);
}
