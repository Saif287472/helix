import 'package:flutter/widgets.dart';
import 'package:orbit_ui/orbit_ui.dart';

/// The call keys (`prototype/js/screens/calls.js`) on the sample data.

HelixPersonItem _p(String id) => OrbitFakes.people[id]!;

/// `ENDED` in the prototype: what the screen says, and why.
const _ended = {
  'ended': ('Call ended', null),
  'cancelled': ('Call cancelled', null),
  'busy': ('Busy: on another call', 'They are in another call right now.'),
  'noAnswer': ('No answer', 'They did not pick up.'),
  'elsewhere': ('Answered on another device', null),
  'failed': (
    'Call failed',
    'The call could not connect. Check your connection and try again.',
  ),
};

CallModel _call(
  String peer,
  String phase, {
  bool video = false,
  String reason = 'ended',
  String? notice,
  bool weak = false,
  List<CallAudioRoute>? routes,
  CallAudioRoute? route,
  bool theirCameraOff = false,
}) {
  final p = _p(peer);
  final n = p.names;
  final stage = switch (phase) {
    'incoming' => CallStage.incoming,
    'outgoing' || 'ringing' => CallStage.dialing,
    'connecting' => CallStage.connecting,
    'ended' => CallStage.ended,
    _ => CallStage.active,
  };
  final (endText, endDetail) = _ended[reason]!;
  return CallModel(
    callId: '$peer-$phase',
    title: n.display,
    subtitle: n.number ?? (n.helixName != null ? '~${n.helixName}' : null),
    avatar: p.avatar,
    video: video,
    stage: stage,
    statusText: switch (phase) {
      'incoming' => 'Incoming ${video ? 'video' : 'voice'} call',
      'outgoing' => 'Calling…',
      'ringing' => 'Ringing…',
      'connecting' => 'Connecting…',
      'reconnecting' => 'Reconnecting…',
      'ended' => endText,
      _ => '',
    },
    elapsedLabel: '00:12',
    talkTimeLabel: phase == 'ended' && reason == 'ended' ? '04:12' : null,
    endDetail: phase == 'ended' ? endDetail : null,
    endIsProblem: reason == 'failed' || reason == 'busy',
    quality: phase == 'reconnecting'
        ? CallQuality.reconnecting
        : weak
        ? CallQuality.weak
        : CallQuality.good,
    cameraOn: video,
    audioRoute:
        route ?? (video ? CallAudioRoute.speaker : CallAudioRoute.earpiece),
    audioRoutes:
        routes ?? const [CallAudioRoute.earpiece, CallAudioRoute.speaker],
    notice: notice,
    videoLayout:
        video &&
        phase != 'ended' &&
        (phase == 'active' || phase == 'outgoing' || phase == 'ringing'),
    remoteCameraOff: theirCameraOff,
  );
}

/// A call with the preview's own state, so the controls work.
class _PreviewCall extends StatefulWidget {
  const _PreviewCall(this.start);

  final CallModel start;

  @override
  State<_PreviewCall> createState() => _PreviewCallState();
}

class _PreviewCallState extends State<_PreviewCall> {
  late var _m = widget.start;

  CallModel _with({
    bool? muted,
    bool? cameraOn,
    CallAudioRoute? route,
    bool clearNotice = false,
  }) => CallModel(
    callId: _m.callId,
    title: _m.title,
    subtitle: _m.subtitle,
    avatar: _m.avatar,
    video: _m.video,
    stage: _m.stage,
    statusText: _m.statusText,
    elapsedLabel: _m.elapsedLabel,
    talkTimeLabel: _m.talkTimeLabel,
    endDetail: _m.endDetail,
    endIsProblem: _m.endIsProblem,
    quality: _m.quality,
    muted: muted ?? _m.muted,
    cameraOn: cameraOn ?? _m.cameraOn,
    audioRoute: route ?? _m.audioRoute,
    audioRoutes: _m.audioRoutes,
    notice: clearNotice ? null : _m.notice,
    videoLayout: _m.videoLayout,
    remoteCameraOff: _m.remoteCameraOff,
  );

  @override
  Widget build(BuildContext context) => CallScreen(
    model: _m,
    actions: CallActions(
      setMuted: (v) => setState(() => _m = _with(muted: v)),
      setCamera: (v) => setState(() => _m = _with(cameraOn: v)),
      selectAudioRoute: (r) => setState(() => _m = _with(route: r)),
      dismissNotice: () => setState(() => _m = _with(clearNotice: true)),
    ),
  );
}

const _rows = [
  CallDetailRowModel(
    callId: 'a',
    direction: CallLogDirection.incoming,
    label: 'Incoming voice call',
    timeLabel: 'Yesterday, 21:30',
    durationLabel: '32:18',
  ),
  CallDetailRowModel(
    callId: 'b',
    direction: CallLogDirection.missed,
    label: 'Missed voice call',
    timeLabel: 'Yesterday, 19:02',
  ),
  CallDetailRowModel(
    callId: 'c',
    direction: CallLogDirection.outgoing,
    label: 'Outgoing voice call',
    timeLabel: 'Yesterday, 18:55',
    durationLabel: '1:04',
  ),
];

const _kinds = [
  CallDetailRowModel(
    callId: '1',
    direction: CallLogDirection.incoming,
    label: 'Incoming voice call',
    timeLabel: 'Today, 10:12',
    durationLabel: '4:51',
  ),
  CallDetailRowModel(
    callId: '2',
    direction: CallLogDirection.outgoing,
    label: 'Outgoing video call',
    timeLabel: 'Today, 09:40',
    durationLabel: '12:03',
    video: true,
  ),
  CallDetailRowModel(
    callId: '3',
    direction: CallLogDirection.missed,
    label: 'Missed voice call',
    timeLabel: 'Today, 08:15',
  ),
  CallDetailRowModel(
    callId: '4',
    direction: CallLogDirection.declined,
    label: 'Declined voice call',
    timeLabel: 'Yesterday, 22:01',
  ),
  CallDetailRowModel(
    callId: '5',
    direction: CallLogDirection.failed,
    label: 'Video call failed',
    timeLabel: 'Yesterday, 21:44',
    video: true,
  ),
  CallDetailRowModel(
    callId: '6',
    direction: CallLogDirection.cancelled,
    label: 'Cancelled voice call',
    timeLabel: 'Yesterday, 19:20',
  ),
  CallDetailRowModel(
    callId: '7',
    direction: CallLogDirection.noAnswer,
    label: 'Unanswered voice call',
    timeLabel: 'Yesterday, 19:18',
  ),
];

CallDetailModel _detail(
  String peer, {
  List<CallDetailRowModel> rows = _rows,
  bool blocked = false,
  CallDetailStatus status = CallDetailStatus.ready,
}) {
  final p = _p(peer);
  return CallDetailModel(
    status: status,
    title: p.names.display,
    subtitle: p.names.secondary,
    avatar: p.avatar,
    rows: rows,
    canCall: !blocked,
    blockedReason: blocked
        ? '${p.names.display} has blocked you. You can’t message or call '
              'them.'
        : null,
  );
}

const _mic =
    'Orbit needs the microphone to make calls. Allow it in your phone’s '
    'settings, then try again.';
const _camera =
    'Orbit needs the camera for video calls. Allow it in your phone’s '
    'settings, or answer with voice.';

final Map<String, WidgetBuilder> callPreviews = {
  'call-incoming': (_) => _PreviewCall(_call('nadia', 'incoming')),
  'call-incoming-video': (_) =>
      _PreviewCall(_call('arif', 'incoming', video: true)),
  'call-incoming-notice': (_) =>
      _PreviewCall(_call('nadia', 'incoming', notice: _mic)),
  'call-outgoing': (_) => _PreviewCall(_call('nadia', 'outgoing')),
  'call-ringing': (_) => _PreviewCall(_call('nadia', 'ringing')),
  'call-connecting': (_) => _PreviewCall(_call('nadia', 'connecting')),
  'call-active': (_) => _PreviewCall(_call('nadia', 'active')),
  'call-active-weak': (_) => _PreviewCall(_call('nadia', 'active', weak: true)),
  'call-reconnecting': (_) => _PreviewCall(_call('nadia', 'reconnecting')),
  'call-video': (_) => _PreviewCall(_call('nadia', 'active', video: true)),
  'call-video-dialing': (_) =>
      _PreviewCall(_call('nadia', 'outgoing', video: true)),
  'call-ended': (_) => _PreviewCall(_call('nadia', 'ended')),
  'call-busy': (_) => _PreviewCall(_call('arif', 'ended', reason: 'busy')),
  'call-failed': (_) => _PreviewCall(_call('arif', 'ended', reason: 'failed')),
  'call-cancelled': (_) =>
      _PreviewCall(_call('nadia', 'ended', reason: 'cancelled')),
  'call-no-answer': (_) =>
      _PreviewCall(_call('arif', 'ended', reason: 'noAnswer')),
  'call-elsewhere': (_) =>
      _PreviewCall(_call('nadia', 'ended', reason: 'elsewhere')),
  'call-active-outputs': (_) => _PreviewCall(
    _call(
      'nadia',
      'active',
      routes: const [
        CallAudioRoute.earpiece,
        CallAudioRoute.speaker,
        CallAudioRoute.bluetooth,
      ],
      route: CallAudioRoute.bluetooth,
    ),
  ),
  'call-video-their-camera-off': (_) =>
      _PreviewCall(_call('nadia', 'active', video: true, theirCameraOff: true)),
  'call-camera-refused': (_) =>
      _PreviewCall(_call('arif', 'incoming', video: true, notice: _camera)),
  'call-detail': (_) => CallDetailScreen(model: _detail('ammu')),
  'call-detail-kinds': (_) =>
      CallDetailScreen(model: _detail('arif', rows: _kinds)),
  'call-detail-blocked': (_) =>
      CallDetailScreen(model: _detail('ammu', blocked: true)),
  'call-detail-gone': (_) => CallDetailScreen(
    model: _detail('ammu', status: CallDetailStatus.notFound),
  ),
};
