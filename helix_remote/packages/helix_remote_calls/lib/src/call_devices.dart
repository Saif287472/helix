import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;

/// Where a call's sound can come out, as the platform names it.
enum WebRtcAudioOutput { earpiece, speaker, bluetooth, wiredHeadset }

/// The audio outputs the platform offers during a call, and the choice
/// between them (v2 app, Phase A3).
///
/// A thin wrapper over `flutter_webrtc`'s `Helper`, so the app's call code
/// depends on this package and not on the plugin. On Android the plugin
/// reports `earpiece`, `speaker`, `bluetooth` and `wired-headset`; elsewhere
/// the outputs have the platform's own ids and none of them maps here, so
/// [available] is empty and the app hides the route control (a desktop has
/// no earpiece to choose against).
///
/// Every method answers rather than throws: audio routing is a convenience
/// of an ongoing call, never a reason to end it.
class WebRtcAudioOutputs {
  const WebRtcAudioOutputs();

  static const _ids = {
    'earpiece': WebRtcAudioOutput.earpiece,
    'speaker': WebRtcAudioOutput.speaker,
    'bluetooth': WebRtcAudioOutput.bluetooth,
    'wired-headset': WebRtcAudioOutput.wiredHeadset,
  };

  /// The outputs that exist right now. Meaningful only once the call's
  /// microphone is open (the plugin lists devices after `getUserMedia`).
  Future<Set<WebRtcAudioOutput>> available() async {
    try {
      final devices = await webrtc.Helper.audiooutputs;
      return {
        for (final device in devices) ?_ids[device.deviceId],
      };
    } on Object {
      return const {};
    }
  }

  /// Sends the call's sound to [output].
  Future<void> select(WebRtcAudioOutput output) async {
    try {
      if (output == WebRtcAudioOutput.speaker) {
        await webrtc.Helper.setSpeakerphoneOn(true);
      }
      final id = _ids.entries.firstWhere((e) => e.value == output).key;
      await webrtc.Helper.selectAudioOutput(id);
    } on Object {
      // The platform refused (the headset just went away): the app asks
      // [available] again on the next change and picks another.
    }
  }

  /// Fires when an output appears or goes (a headset plugged in, a Bluetooth
  /// device connecting). Single listener: setting it replaces the last one.
  Stream<void> get changes {
    late final StreamController<void> controller;
    controller = StreamController<void>.broadcast(
      onListen: () {
        webrtc.navigator.mediaDevices.ondevicechange = (_) {
          if (!controller.isClosed) controller.add(null);
        };
      },
      onCancel: () {
        webrtc.navigator.mediaDevices.ondevicechange = null;
      },
    );
    return controller.stream;
  }
}

/// What a media-permission request ended with.
enum WebRtcMediaPermission { granted, microphoneDenied, cameraDenied }

/// Asks the platform for the microphone (and the camera) the way a call will
/// use them, so the person meets the permission prompt before a call is placed
/// or answered rather than as a mid-call failure.
///
/// `flutter_webrtc` raises the OS prompt from `getUserMedia`, and offers no
/// way to ask without opening the device; the probe opens it and closes it
/// again at once. A denial (or a device that will not open) is an answer, not
/// an exception.
class WebRtcMediaPermissions {
  const WebRtcMediaPermissions();

  Future<WebRtcMediaPermission> request({required bool video}) async {
    if (!await _probe(audio: true, video: false)) {
      return WebRtcMediaPermission.microphoneDenied;
    }
    if (video && !await _probe(audio: false, video: true)) {
      return WebRtcMediaPermission.cameraDenied;
    }
    return WebRtcMediaPermission.granted;
  }

  Future<bool> _probe({required bool audio, required bool video}) async {
    webrtc.MediaStream? stream;
    try {
      stream = await webrtc.navigator.mediaDevices.getUserMedia({
        'audio': audio,
        'video': video,
      });
      return true;
    } on Object {
      return false;
    } finally {
      if (stream != null) {
        for (final track in stream.getTracks()) {
          try {
            await track.stop();
          } on Object {
            // Already stopped.
          }
        }
        try {
          await stream.dispose();
        } on Object {
          // Nothing left to release.
        }
      }
    }
  }
}
