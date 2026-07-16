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
