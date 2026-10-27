import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;

/// How hard a group call may push the relay: every person in a room is a
/// separate connection through the same TURN server (ADR-034), so a link gets
/// a smaller picture, fewer frames and a bitrate cap than a 1:1 call.
final class RemoteVideoLimits {
  const RemoteVideoLimits({
    this.width = 640,
    this.height = 480,
    this.frameRate = 15,
    this.maxBitrateKbps = 400,
  });

  /// What a link of a group call uses.
  static const group = RemoteVideoLimits();

  final int width;
  final int height;
  final int frameRate;

  /// The video encoder's ceiling for one link, in kbit/s.
  final int maxBitrateKbps;

  Map<String, Object> get constraints => {
    'width': {'ideal': width, 'max': width},
    'height': {'ideal': height, 'max': height},
    'frameRate': {'ideal': frameRate, 'max': frameRate},
  };
}

/// One microphone and camera shared by every peer connection of a group call.
///
/// A phone opens its camera once; a mesh of four people has three connections
/// that all send the same tracks. Each connection [acquire]s the capture and
/// [release]s it when it ends; the tracks stop when the last one lets go.
/// Opening is injectable so a test needs no camera.
final class RemoteCallCapture {
  RemoteCallCapture({
    this.video = false,
    this.limits = RemoteVideoLimits.group,
    Future<webrtc.MediaStream> Function(bool video, RemoteVideoLimits limits)?
    open,
  }) : _open = open ?? _openDevices;

  /// The room carries video (the camera is opened).
  final bool video;
  final RemoteVideoLimits limits;
  final Future<webrtc.MediaStream> Function(
    bool video,
    RemoteVideoLimits limits,
  )
  _open;

  Future<webrtc.MediaStream>? _stream;
  int _holders = 0;

  /// Connections holding the capture now.
  int get holders => _holders;

  /// The shared stream, opened on the first call.
  Future<webrtc.MediaStream> acquire() {
    _holders++;
    return _stream ??= _open(video, limits).catchError((Object error) {
      _holders--;
      _stream = null;
      throw error;
    });
  }

  /// One connection is done. The last one stops the microphone and camera.
  Future<void> release() async {
    if (_holders == 0) return;
    _holders--;
    if (_holders > 0) return;
    final opening = _stream;
    _stream = null;
    if (opening == null) return;
    try {
      final stream = await opening;
      for (final track in stream.getTracks()) {
        await track.stop();
      }
      await stream.dispose();
    } on Object {
      // Releasing the devices is best effort: the call is already over.
    }
  }

  static Future<webrtc.MediaStream> _openDevices(
    bool video,
    RemoteVideoLimits limits,
  ) => webrtc.navigator.mediaDevices.getUserMedia({
    'audio': {
      'echoCancellation': true,
      'noiseSuppression': true,
      'autoGainControl': true,
    },
    'video': video ? limits.constraints : false,
  });
}
