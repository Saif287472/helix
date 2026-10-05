import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/core/platform/audio_player.dart';
import 'package:helix_remote/core/platform/device_audio_player.dart';
import 'package:helix_remote/core/platform/device_voice_recorder.dart';
import 'package:helix_remote/core/platform/flutter_media_processor.dart';
import 'package:helix_remote/core/platform/media_temp.dart';
import 'package:helix_remote/core/platform/pixel_decoder.dart';
import 'package:helix_remote/core/platform/thumbnail_encoder.dart';
import 'package:helix_remote/core/platform/video_frames.dart';
import 'package:helix_remote/core/platform/voice_recorder.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart'
    show MediaItemKind;
import 'package:image/image.dart' as img;

import '../support/media_fakes.dart';

final class _Decoder implements PixelDecoder {
  _Decoder(this.pixels);

  final DecodedPixels? pixels;
  final sides = <int>[];

  @override
  Future<DecodedPixels?> decode(
    Uint8List encoded, {
    required int maxSide,
  }) async {
    sides.add(maxSide);
    return pixels;
  }
}

final class _Frames implements VideoFrameSource {
  _Frames(this.jpeg);

  final Uint8List? jpeg;
  Duration? askedAt;

  @override
  Future<Uint8List?> frame(
    String path, {
    required int maxSide,
    Duration? at,
  }) async {
    askedAt = at;
    return jpeg;
  }
}

DecodedPixels _pixels(int w, int h) => DecodedPixels(
  rgba: Uint8List.fromList(
    List.generate(w * h * 4, (i) => i % 4 == 3 ? 255 : 120),
  ),
  width: w,
  height: h,
);

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('helix_adapt'));
  tearDown(() => dir.deleteSync(recursive: true));

  group('FlutterMediaProcessor', () {
    FlutterMediaProcessor make({
      PixelDecoder? decoder,
      VideoFrameSource? frames,
    }) => FlutterMediaProcessor(
      decoder: decoder ?? _Decoder(_pixels(20, 10)),
      frames: frames ?? _Frames(null),
      encoder: const InlineThumbnailEncoder(),
    );

    test('a photo: real size from the header, thumbnail and hash', () async {
      final file = File('${dir.path}/a.jpg')
        ..writeAsBytesSync(
          img.encodeJpg(img.Image(width: 400, height: 200), quality: 70),
        );
      final out = await make().process(
        path: file.path,
        kind: MediaItemKind.image,
        mime: 'image/jpeg',
      );
      expect((out.width, out.height), (400, 200));
      expect(out.thumbnail, isNotEmpty);
      expect(out.blurhash, isNotEmpty);
      expect(img.decodeJpg(out.thumbnail!), isNotNull);
    });

    test('a photo that cannot be decoded still reports its size', () async {
      final file = File('${dir.path}/a.jpg')
        ..writeAsBytesSync(
          img.encodeJpg(img.Image(width: 64, height: 32), quality: 70),
        );
      final out = await make(
        decoder: _Decoder(null),
      ).process(path: file.path, kind: MediaItemKind.image, mime: 'image/jpeg');
      expect((out.width, out.height), (64, 32));
      expect(out.thumbnail, isNull);
    });

    test('a missing file is no previews, not an error', () async {
      final out = await make().process(
        path: '${dir.path}/none.jpg',
        kind: MediaItemKind.image,
        mime: 'image/jpeg',
      );
      expect(out.thumbnail, isNull);
      expect(out.width, isNull);
    });

    test(
      'a video: length and size from the file, frame as thumbnail',
      () async {
        final file = File('${dir.path}/v.mp4')..writeAsBytesSync(testMp4());
        final jpeg = Uint8List.fromList(
          img.encodeJpg(img.Image(width: 32, height: 18)),
        );
        final frames = _Frames(jpeg);
        final out = await make(frames: frames).process(
          path: file.path,
          kind: MediaItemKind.video,
          mime: 'video/mp4',
        );
        expect(out.durationMs, 5000);
        expect((out.width, out.height), (1080, 1920));
        expect(out.thumbnail, jpeg);
        expect(out.blurhash, isNotEmpty);
        // A frame a second in, not the usually black first one.
        expect(frames.askedAt, const Duration(seconds: 1));
      },
    );

    test(
      'a video without a frame extractor is sent with size and length only',
      () async {
        final file = File('${dir.path}/v.mp4')..writeAsBytesSync(testMp4());
        final out = await make().process(
          path: file.path,
          kind: MediaItemKind.video,
          mime: 'video/mp4',
        );
        expect(out.thumbnail, isNull);
        expect(out.durationMs, 5000);
      },
    );

    test('voice notes and documents are left to the caller', () async {
      final out = await make().process(
        path: '${dir.path}/x',
        kind: MediaItemKind.voiceNote,
        mime: 'audio/mp4',
      );
      expect(out.thumbnail, isNull);
      expect(out.durationMs, isNull);
    });
  });

  group('MediaTemp', () {
    test('deletes only what it owns and sweeps stale files', () async {
      final temp = tempIn(dir);
      final mine = await temp.newPath(MediaTemp.captures, extension: 'jpg');
      File(mine).writeAsBytesSync([1]);
      final theirs = File('${dir.path}/photo.jpg')..writeAsBytesSync([1]);
      expect(await temp.owns(mine), isTrue);
      expect(await temp.owns(theirs.path), isFalse);
      await temp.deleteAll([mine, theirs.path, '${dir.path}/never-existed']);
      expect(File(mine).existsSync(), isFalse);
      expect(theirs.existsSync(), isTrue, reason: 'a person\'s own file stays');

      final old = File('${dir.path}/helix_voice/old.m4a')
        ..createSync(recursive: true);
      old.setLastModifiedSync(DateTime.now().subtract(const Duration(days: 2)));
      final fresh = File('${dir.path}/helix_voice/new.m4a')..createSync();
      await tempIn(dir).folder(MediaTemp.voice);
      expect(old.existsSync(), isFalse);
      expect(fresh.existsSync(), isTrue);
    });
  });

  group('VoiceWaveform', () {
    test('merges by peak, scales, and is empty for no readings', () {
      expect(VoiceWaveform.fromDecibels(const []), isEmpty);
      final w = VoiceWaveform.fromDecibels([-60, 0, -30, -60], samples: 2);
      expect(w.length, 2);
      expect(w[0], 255, reason: 'the loud reading wins its group');
      expect(w[1], greaterThan(0));
      expect(VoiceWaveform.fromDecibels([-90.0]).single, 0);
      expect(
        VoiceWaveform.fromDecibels(List.filled(1000, -10.0)).length,
        VoiceWaveform.maxSamples,
      );
    });
  });

  group('DeviceVoiceRecorder', () {
    late FakeRecordBackend backend;
    late DateTime now;
    late DeviceVoiceRecorder recorder;

    setUp(() {
      backend = FakeRecordBackend();
      now = DateTime(2026, 1, 1);
      recorder = DeviceVoiceRecorder(
        backend: backend,
        temp: tempIn(dir),
        clock: () => now,
        available: true,
      );
    });

    test(
      'records, counts time without the pauses, returns the waveform',
      () async {
        await recorder.start();
        backend.amps
          ..add(-40)
          ..add(-5);
        await Future<void>.delayed(Duration.zero);
        now = now.add(const Duration(seconds: 2));
        await recorder.pause();
        now = now.add(const Duration(seconds: 30)); // paused: not counted
        await recorder.resume();
        now = now.add(const Duration(seconds: 1));
        final voice = (await recorder.stop())!;
        expect(voice.durationMs, 3000);
        expect(voice.mime, 'audio/mp4');
        expect(voice.waveform.length, 2);
        expect(voice.waveform[1], greaterThan(voice.waveform[0]));
        expect(File(voice.path).existsSync(), isTrue);
        expect(voice.path, endsWith('.m4a'));
      },
    );

    test(
      'a call that pauses the microphone stops the clock and is reported',
      () async {
        final seen = <VoicePhase>[];
        recorder.phases.listen(seen.add);
        await recorder.start();
        now = now.add(const Duration(seconds: 1));
        backend.states.add(VoicePhase.paused); // the system
        await Future<void>.delayed(Duration.zero);
        now = now.add(const Duration(seconds: 60));
        backend.states.add(VoicePhase.recording);
        await Future<void>.delayed(Duration.zero);
        now = now.add(const Duration(seconds: 1));
        final voice = (await recorder.stop())!;
        expect(voice.durationMs, 2000);
        expect(seen, [
          VoicePhase.recording,
          VoicePhase.paused,
          VoicePhase.recording,
          VoicePhase.idle,
        ]);
      },
    );

    test('a refused permission starts nothing and creates no file', () async {
      backend.permission = false;
      await expectLater(
        recorder.start(),
        throwsA(isA<VoiceRecorderPermissionDenied>()),
      );
      expect(backend.calls, isEmpty);
      expect(Directory('${dir.path}/helix_voice').existsSync(), isFalse);
    });

    test('a recorder that fails to start leaves nothing behind', () async {
      backend.startError = StateError('mic busy');
      await expectLater(
        recorder.start(),
        throwsA(isA<VoiceRecorderUnavailable>()),
      );
      expect(Directory('${dir.path}/helix_voice').listSync(), isEmpty);
      // And it can be tried again.
      backend.startError = null;
      await recorder.start();
      expect(await recorder.stop(), isNotNull);
    });

    test('cancel deletes the file; an empty result is no recording', () async {
      await recorder.start();
      final path = backend.path!;
      await recorder.cancel();
      expect(File(path).existsSync(), isFalse);
      expect(backend.calls, contains('cancel'));

      backend.writeFile = false;
      await recorder.start();
      expect(await recorder.stop(), isNull);
    });

    test('a device without a recorder says so', () async {
      final none = DeviceVoiceRecorder(
        backend: backend,
        temp: tempIn(dir),
        available: false,
      );
      expect(none.isAvailable, isFalse);
      await expectLater(none.start(), throwsA(isA<VoiceRecorderUnavailable>()));
    });
  });

  group('DeviceAudioPlayer', () {
    test('load, play, report position, finish back at the start', () async {
      final backend = FakeAudioBackend();
      final player = DeviceAudioPlayer(backend: backend);
      final states = <AudioPlayback>[];
      player.states.listen(states.add);
      await player.setSpeed(1.5);
      await player.load('/x.m4a');
      expect(backend.calls, containsAllInOrder(['stop', 'source', 'rate:1.5']));
      await player.play();
      backend.playingCtl.add(true);
      backend.pos.add(const Duration(seconds: 3));
      await Future<void>.delayed(Duration.zero);
      expect(states.last.playing, isTrue);
      expect(states.last.position, const Duration(seconds: 3));
      expect(states.last.duration, const Duration(seconds: 8));
      backend.done.add(null);
      await Future<void>.delayed(Duration.zero);
      expect(states.last.completed, isTrue);
      expect(states.last.playing, isFalse);
      expect(states.last.position, Duration.zero);
      await player.dispose();
    });

    test(
      'seek is kept inside the file; speed changes reach the backend',
      () async {
        final backend = FakeAudioBackend();
        final player = DeviceAudioPlayer(backend: backend);
        await player.load('/x.m4a');
        await player.seek(const Duration(seconds: 99));
        await player.seek(const Duration(seconds: -4));
        await player.setSpeed(2);
        expect(
          backend.calls,
          containsAll([
            'seek:0:00:08.000000',
            'seek:0:00:00.000000',
            'rate:2.0',
          ]),
        );
        await player.dispose();
      },
    );

    test(
      'a file that cannot be loaded is AudioUnavailable and plays nothing',
      () async {
        final backend = FakeAudioBackend()..failSource = true;
        final player = DeviceAudioPlayer(backend: backend);
        await expectLater(
          player.load('/bad'),
          throwsA(isA<AudioUnavailable>()),
        );
        await player.play();
        expect(backend.calls, isNot(contains('play')));
        await player.dispose();
      },
    );

    test('a failure after it started is reported', () async {
      final backend = FakeAudioBackend();
      final player = DeviceAudioPlayer(backend: backend);
      final states = <AudioPlayback>[];
      player.states.listen(states.add);
      await player.load('/x');
      backend.err.add(StateError('output gone'));
      await Future<void>.delayed(Duration.zero);
      expect(states.last.failed, isTrue);
      await player.dispose();
    });
  });
}
