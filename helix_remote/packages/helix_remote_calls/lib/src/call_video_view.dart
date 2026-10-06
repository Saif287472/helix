import 'package:flutter/widgets.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;

class RemoteCallVideoView extends StatelessWidget {
  const RemoteCallVideoView({
    super.key,
    required this.renderer,
    this.mirror = false,
    this.objectFit = webrtc.RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
  });

  final webrtc.RTCVideoRenderer renderer;
  final bool mirror;
  final webrtc.RTCVideoViewObjectFit objectFit;

  @override
  Widget build(BuildContext context) {
    return webrtc.RTCVideoView(renderer, mirror: mirror, objectFit: objectFit);
  }
}

/// One call video track as something the app can draw without importing the
/// WebRTC plugin: a [Listenable] that fires when frames start or stop, whether
/// any have arrived, and the widget.
class RemoteVideoSource {
  const RemoteVideoSource(this.renderer);

  final webrtc.RTCVideoRenderer renderer;

  /// Fires when the first frame lands or the video size changes.
  Listenable get changes => renderer;

  bool get hasFrames => renderer.renderVideo && renderer.videoWidth > 0;

  Widget build({bool mirror = false}) =>
      RemoteCallVideoView(renderer: renderer, mirror: mirror);
}
