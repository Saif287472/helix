import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'package:helix_remote_calls/helix_remote_calls.dart';

/// A stream that counts what is done to it; nothing else of it is used.
class _Stream implements webrtc.MediaStream {
  _Stream(this.tracks);

  final List<_Track> tracks;
  bool disposed = false;

  @override
  List<webrtc.MediaStreamTrack> getTracks() => tracks;

  @override
  Future<void> dispose() async => disposed = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Track implements webrtc.MediaStreamTrack {
  bool stopped = false;

  @override
  Future<void> stop() async => stopped = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The one camera and microphone of a group call, shared by its links.
void main() {
  late _Stream stream;
  late int opened;
  late bool lastVideo;

  RemoteCallCapture capture({bool video = true, bool fail = false}) {
    return RemoteCallCapture(
      video: video,
      open: (v, limits) async {
        opened++;
        lastVideo = v;
        if (fail) throw StateError('no camera');
        return stream;
      },
    );
  }

  setUp(() {
    stream = _Stream([_Track(), _Track()]);
    opened = 0;
    lastVideo = false;
  });

  test('is opened once, however many links ask', () async {
    final c = capture();
    final a = await c.acquire();
    final b = await c.acquire();
    final d = await c.acquire();
    expect(opened, 1);
    expect(identical(a, b) && identical(b, d), isTrue);
    expect(c.holders, 3);
    expect(lastVideo, isTrue);
  });

  test(
    'stays open until the last link lets go, then stops everything',
    () async {
      final c = capture();
      await c.acquire();
      await c.acquire();
      await c.release();
      expect(stream.tracks.any((t) => t.stopped), isFalse);
      expect(stream.disposed, isFalse);
      await c.release();
      expect(stream.tracks.every((t) => t.stopped), isTrue);
      expect(stream.disposed, isTrue);
      expect(c.holders, 0);
    },
  );

  test(
    'a release with nothing held does nothing, and it opens again after',
    () async {
      final c = capture(video: false);
      await c.release();
      expect(c.holders, 0);
      await c.acquire();
      await c.release();
      await c.acquire();
      expect(opened, 2);
      expect(lastVideo, isFalse);
    },
  );

  test('a camera that will not open leaves nothing held', () async {
    final c = capture(fail: true);
    await expectLater(c.acquire(), throwsStateError);
    expect(c.holders, 0);
  });

  test('a link of a group call is held to a small picture and a bitrate', () {
    const limits = RemoteVideoLimits.group;
    expect(limits.width, 640);
    expect(limits.height, 480);
    expect(limits.frameRate, 15);
    expect(limits.maxBitrateKbps, 400);
    expect(limits.constraints['frameRate'], {'ideal': 15, 'max': 15});
  });
}
