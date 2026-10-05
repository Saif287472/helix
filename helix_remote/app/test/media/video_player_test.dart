import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/core/platform/chat_platform.dart';
import 'package:helix_remote/core/platform/video_player.dart';
import 'package:helix_remote/features/conversation/presentation/video_player_view.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

import '../support/media_fakes.dart';

void main() {
  Widget app(
    FakeVideoPlayers players, {
    bool active = true,
    VoidCallback? onElsewhere,
    double textScale = 1,
  }) => ProviderScope(
    overrides: [videoPlayersProvider.overrideWithValue(players)],
    child: MaterialApp(
      theme: HelixThemes.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: VideoPlayerView(
          path: '/v.mp4',
          active: active,
          onOpenElsewhere: onElsewhere ?? () {},
        ),
      ),
    ),
  );

  Future<void> opened(WidgetTester tester) async {
    await tester.pump(); // build
    await tester.pump(); // the open future
    await tester.pump();
  }

  testWidgets('opens, plays at once, and shows pause with the time', (
    tester,
  ) async {
    final players = FakeVideoPlayers();
    await tester.pumpWidget(app(players));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
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

  testWidgets('controls hide while playing and a tap brings them back', (
    tester,
  ) async {
    final players = FakeVideoPlayers();
    await tester.pumpWidget(app(players));
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

  testWidgets('seek bar seeks, the speed chip cycles 1x 1.5x 2x', (
    tester,
  ) async {
    final players = FakeVideoPlayers();
    await tester.pumpWidget(app(players));
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

  testWidgets('played to the end offers to play again', (tester) async {
    final players = FakeVideoPlayers();
    await tester.pumpWidget(app(players));
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
  });

  testWidgets('a file the decoder refuses offers the share sheet', (
    tester,
  ) async {
    var opened = 0;
    final players = FakeVideoPlayers(failInit: true);
    await tester.pumpWidget(app(players, onElsewhere: () => opened++));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('cannot be played'), findsOneWidget);
    await tester.tap(find.text('Open video'));
    expect(opened, 1);
  });

  testWidgets('a platform without a player never opens one', (tester) async {
    var opened = 0;
    final players = FakeVideoPlayers(supported: false);
    await tester.pumpWidget(app(players, onElsewhere: () => opened++));
    await tester.pump();
    await tester.pump();
    expect(players.opened, isEmpty);
    expect(
      find.textContaining('cannot be played inside Helix'),
      findsOneWidget,
    );
    await tester.tap(find.text('Open video'));
    expect(opened, 1);
  });

  testWidgets('a page that is not on screen is only a poster', (tester) async {
    final players = FakeVideoPlayers();
    await tester.pumpWidget(app(players, active: false));
    await tester.pump();
    expect(players.opened, isEmpty);
    expect(find.byIcon(Icons.play_circle_outline), findsOneWidget);
  });

  testWidgets('going to the background pauses', (tester) async {
    final players = FakeVideoPlayers();
    await tester.pumpWidget(app(players));
    await opened(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    expect(players.opened.single.calls.last, 'pause');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets('controls fit at 2x text with 48 px targets', (tester) async {
    final players = FakeVideoPlayers();
    await tester.pumpWidget(app(players, textScale: 2));
    await opened(tester);
    await tester.tap(find.byTooltip('Pause'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    for (final target in [
      find.byTooltip('Play'),
      find.byTooltip('Playback speed'),
    ]) {
      final size = tester.getSize(target);
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    }
  });
}
