import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/core/chat/chat_gateway.dart';
import 'package:helix_remote/core/platform/audio_player.dart';
import 'package:helix_remote/core/platform/chat_platform.dart';
import 'package:helix_remote/features/conversation/application/audio_playback.dart';

import '../support/chat_harness.dart';
import '../support/media_fakes.dart';

void main() {
  ProviderContainer container(
    TestChatGateway gateway,
    FakeAudioPlayer Function() make,
  ) {
    final c = ProviderContainer(
      overrides: [
        chatGatewayProvider.overrideWith((ref) => gateway),
        audioPlayerFactoryProvider.overrideWithValue(make),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  Future<void> pump() => Future<void>.delayed(const Duration(milliseconds: 5));

  testWidgets('plays one voice note at a time, with speed and seek', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final gateway = await TestChatGateway.create();
      gateway.localPaths[1] = '/a.m4a';
      gateway.localPaths[2] = '/b.m4a';
      final players = <FakeAudioPlayer>[];
      final c = container(gateway, () {
        final p = FakeAudioPlayer();
        players.add(p);
        return p;
      });
      final notifier = c.read(playbackProvider.notifier);

      await notifier.toggle(10, 1);
      await pump();
      var s = c.read(playbackProvider);
      expect(s.messageRowid, 10);
      expect(s.playing, isTrue);

      // Another note takes over on the same player: never two sounds.
      await notifier.toggle(11, 2);
      await pump();
      expect(players, hasLength(1));
      expect(players.single.loaded, ['/a.m4a', '/b.m4a']);
      expect(c.read(playbackProvider).messageRowid, 11);

      // A second tap pauses, a third resumes.
      await notifier.toggle(11, 2);
      await pump();
      expect(c.read(playbackProvider).playing, isFalse);
      await notifier.toggle(11, 2);
      await pump();
      expect(c.read(playbackProvider).playing, isTrue);

      await notifier.cycleSpeed();
      expect(c.read(playbackProvider).speed, 1.5);
      expect(players.single.calls, contains('speed:1.5'));
      await notifier.seek(11, 0.5);
      expect(players.single.calls, contains('seek:0:00:05.000000'));
      await notifier.seek(10, 0.5); // not the one playing: ignored
      expect(
        players.single.calls.where((c) => c.startsWith('seek')),
        hasLength(1),
      );

      // Played to the end: marked played, nothing is current any more.
      players.single.controller.add(
        const AudioPlayback(duration: Duration(seconds: 10), completed: true),
      );
      await pump();
      s = c.read(playbackProvider);
      expect(s.messageRowid, isNull);
      expect(s.played, contains(11));

      await notifier.stop();
      await gateway.close();
    });
  });

  testWidgets('a note that is not downloaded, or cannot be played, says so', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final gateway = await TestChatGateway.create();
      final player = FakeAudioPlayer();
      final c = container(gateway, () => player);
      final notifier = c.read(playbackProvider.notifier);

      await notifier.toggle(1, 7); // no local file
      expect(c.read(playbackProvider).notice, contains('Downloading'));
      expect(gateway.log, contains('download:7'));
      expect(c.read(playbackProvider).messageRowid, isNull);

      gateway.localPaths[7] = '/x';
      player.failLoad = true;
      await notifier.toggle(1, 7);
      expect(c.read(playbackProvider).notice, contains('not available'));
      expect(c.read(playbackProvider).messageRowid, isNull);

      player.failLoad = false;
      await notifier.toggle(1, 7);
      await pump();
      player.controller.add(const AudioPlayback(failed: true));
      await pump();
      expect(c.read(playbackProvider).notice, contains('could not be played'));
      expect(c.read(playbackProvider).messageRowid, isNull);
      await gateway.close();
    });
  });
}
