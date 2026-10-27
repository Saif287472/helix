import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:orbit_ui/src/components/avatar.dart';
import 'package:orbit_ui/src/components/bars.dart';
import 'package:orbit_ui/src/components/button.dart';
import 'package:orbit_ui/src/components/icon_button.dart';
import 'package:orbit_ui/src/components/list_rows.dart';
import 'package:orbit_ui/src/components/overlays.dart';
import 'package:orbit_ui/src/components/page_bits.dart';
import 'package:orbit_ui/src/components/page_parts.dart';
import 'package:orbit_ui/src/components/spinner.dart';
import 'package:orbit_ui/src/components/state_kit.dart';
import 'package:orbit_ui/src/components/timeline.dart';
import 'package:orbit_ui/src/icons/orbit_glyph.dart';
import 'package:orbit_ui/src/icons/orbit_icons.dart';
import 'package:orbit_ui/src/models/view_models.dart';
import 'package:orbit_ui/src/theme/effect_shapes.dart';
import 'package:orbit_ui/src/theme/orbit_metrics.dart';
import 'package:orbit_ui/src/theme/orbit_text.dart';
import 'package:orbit_ui/src/theme/orbit_tokens.dart';
import 'package:orbit_ui/src/theme/pattern_painter.dart';
import 'package:orbit_ui/src/window/window_scaffold.dart';

part 'group_call_screen.dart';

/// Where a call is (`contracts/calls.md`). The prototype's `outgoing` and
/// `ringing` are both [dialing], told apart by [CallModel.statusText].
enum CallStage { dialing, incoming, connecting, active, ended }

enum CallQuality { good, weak, reconnecting }

enum CallAudioRoute { earpiece, speaker, bluetooth, wiredHeadset }

void _noop() {}

(OrbitGlyph, String) _route(CallAudioRoute r) => switch (r) {
  CallAudioRoute.earpiece => (OrbitIcons.ear, 'Phone'),
  CallAudioRoute.speaker => (OrbitIcons.speakerHigh, 'Speaker'),
  CallAudioRoute.bluetooth => (OrbitIcons.bluetooth, 'Bluetooth'),
  CallAudioRoute.wiredHeadset => (OrbitIcons.headphones, 'Headset'),
};

/// `CallModel` (`contracts/calls.md`).
class CallModel {
  const CallModel({
    required this.callId,
    required this.title,
    required this.avatar,
    required this.stage,
    required this.statusText,
    this.subtitle,
    this.video = false,
    this.elapsedLabel,
    this.talkTimeLabel,
    this.endDetail,
    this.endIsProblem = false,
    this.quality = CallQuality.good,
    this.muted = false,
    this.cameraOn = false,
    this.audioRoute = CallAudioRoute.earpiece,
    this.audioRoutes = const [CallAudioRoute.earpiece, CallAudioRoute.speaker],
    this.notice,
    this.busy = false,
    this.videoLayout = false,
    this.hasLocalVideo = false,
    this.hasRemoteVideo = false,
    this.remoteCameraOff = false,
    this.screenSharing = false,
    this.peerScreenSharing = false,
    this.canShareScreen = false,
  });

  final String callId;
  final String title;
  final String? subtitle;
  final HelixAvatarModel avatar;
  final bool video;
  final CallStage stage;

  /// "Calling…", "Ringing…", "Incoming voice call", "Call ended", …
  final String statusText;

  /// The running clock on a live call.
  final String? elapsedLabel;

  /// How long an ended call that was answered lasted.
  final String? talkTimeLabel;
  final String? endDetail;
  final bool endIsProblem;
  final CallQuality quality;
  final bool muted;
  final bool cameraOn;
  final CallAudioRoute audioRoute;

  /// The outputs there are now; empty on a window.
  final List<CallAudioRoute> audioRoutes;
  final String? notice;
  final bool busy;

  /// The full-screen video layout (dialing with your camera, or live).
  final bool videoLayout;
  final bool hasLocalVideo;
  final bool hasRemoteVideo;

  /// Their camera is off on a live video call.
  final bool remoteCameraOff;

  /// You are sharing your screen in place of your camera.
  final bool screenSharing;

  /// They are: their picture is a screen, drawn whole instead of cropped.
  final bool peerScreenSharing;

  /// The phone can share its screen (the Share button shows).
  final bool canShareScreen;

  bool get _live =>
      stage == CallStage.dialing ||
      stage == CallStage.connecting ||
      stage == CallStage.active;
}

/// `CallActions` (`contracts/calls.md`).
class CallActions {
  const CallActions({
    this.answer,
    this.decline,
    this.hangUp,
    this.setMuted,
    this.setCamera,
    this.flipCamera,
    this.setScreenSharing,
    this.selectAudioRoute,
    this.dismissNotice,
  });

  final VoidCallback? answer;
  final VoidCallback? decline;
  final VoidCallback? hangUp;
  final ValueChanged<bool>? setMuted;
  final ValueChanged<bool>? setCamera;
  final VoidCallback? flipCamera;

  /// Starts or stops sharing the screen. With it set (and the model's
  /// `canShareScreen`), a live video call shows Share.
  final ValueChanged<bool>? setScreenSharing;
  final ValueChanged<CallAudioRoute>? selectAudioRoute;
  final VoidCallback? dismissNotice;
}

/// A picture from the platform: the other person's video or your camera.
/// [placeholder] is what the screen draws while there is no picture (their
/// picture on the gradient, smaller in the tile); the app shows it until
/// frames arrive. The preview passes no slot and the screen draws the
/// prototype's stand-in gradients.
typedef CallVideoSlot =
    Widget Function(BuildContext context, Widget placeholder);

/// The other person's picture. [screen] says it is a shared screen, which the
/// app draws whole (letterboxed) instead of cropping it to fill.
typedef CallRemoteVideoSlot =
    Widget Function(
      BuildContext context,
      Widget placeholder, {
      required bool screen,
    });

/// `call` (`js/screens/calls.js`): the full-screen call, a night page on the
/// brand gradient. The header says what kind of call and that it is
/// encrypted; the middle has the picture (with pulsing rings while it
/// rings), the name, the number and the status; the bottom has Answer and
/// Decline, or the control tray with End. A video call that has a picture
/// shows it full screen with your camera in a tile.
class CallScreen extends StatefulWidget {
  const CallScreen({
    super.key,
    required this.model,
    this.actions = const CallActions(),
    this.remoteVideo,
    this.localVideo,
  });

  final CallModel model;
  final CallActions actions;
  final CallRemoteVideoSlot? remoteVideo;
  final CallVideoSlot? localVideo;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );
  var _controlsOff = false;
  var _swapped = false;
  Offset? _tile;

  @override
  void didUpdateWidget(CallScreen old) {
    super.didUpdateWidget(old);
    if (old.model.callId != widget.model.callId) {
      _controlsOff = false;
      _swapped = false;
      _tile = null;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  bool get _ringing =>
      widget.model.stage == CallStage.incoming ||
      widget.model.stage == CallStage.dialing ||
      widget.model.stage == CallStage.connecting;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    if (_ringing && !still) {
      if (!_pulse.isAnimating) _pulse.repeat();
    } else {
      _pulse.stop();
    }
    final m = widget.model;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Material(
        type: MaterialType.transparency,
        child: m.videoLayout ? _videoLayout(context) : _plain(context),
      ),
    );
  }

  // ---------------------------------------------------------------- plain

  Widget _plain(BuildContext context) {
    final t = OrbitTokens.of(context);
    final m = widget.model;
    final incoming = m.stage == CallStage.incoming;
    return DecoratedBox(
      decoration: BoxDecoration(gradient: t.brandGradient),
      child: CustomPaint(
        painter: _CallBackdrop(),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 64, 24, 40),
          child: Column(
            children: [
              _header(t, m.video),
              Expanded(child: _middle(t)),
              if (m.notice != null) _notice(t),
              // A window keeps the controls to a phone's reach (440px).
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: incoming
                    ? _incoming(t)
                    : _tray(t, ended: m.stage == CallStage.ended),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// `.c-top`: "Orbit voice call" over "End-to-end encrypted" with its lock,
  /// at least 48px tall and centred in it. On a video call its 52px top
  /// padding already passes the 48 (`border-box`), so it is only as tall as
  /// its text.
  Widget _header(OrbitTokens t, bool video, {double minHeight = 48}) =>
      ConstrainedBox(
        constraints: BoxConstraints(minHeight: minHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            OrbitText(
              'ORBIT ${video ? 'VIDEO' : 'VOICE'} CALL',
              textAlign: TextAlign.center,
              style: t.mono.style(
                size: OrbitType.meta,
                color: t.callMuted,
                letterSpacingEm: 0.12,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OrbitIcon(
                  OrbitIcons.lockSimple,
                  weight: OrbitIconWeight.fill,
                  size: 13,
                  color: t.callLive,
                ),
                const SizedBox(width: 6),
                OrbitText(
                  'END-TO-END ENCRYPTED',
                  style: t.mono.style(
                    size: 10.5,
                    color: t.callMuted,
                    letterSpacingEm: 0.1,
                  ),
                ),
              ],
            ),
          ],
        ),
      );

  Widget _middle(OrbitTokens t) {
    final m = widget.model;
    final ended = m.stage == CallStage.ended;
    final sub = m.subtitle ?? '';
    final status = t.mono.style(
      size: 13,
      color: ended && m.endIsProblem ? const Color(0xFFFFD3D5) : t.callMuted,
      letterSpacingEm: 0.12,
    );
    // The status is a live region a screen reader announces as it changes.
    Widget said(String text, Widget child) => Semantics(
      container: true,
      liveRegion: true,
      label: text,
      excludeSemantics: true,
      child: child,
    );
    final parts = <Widget>[
      _orb(t, rings: _ringing),
      Semantics(
        container: true,
        header: true,
        child: OrbitText(
          m.title,
          textAlign: TextAlign.center,
          style: t.display(size: 28, color: t.callText),
        ),
      ),
      if (sub.isNotEmpty)
        Transform.translate(
          offset: const Offset(0, -10),
          child: OrbitText(
            sub,
            style: t.mono.style(size: 12.5, color: t.callMuted),
          ),
        ),
    ];
    if (m.stage == CallStage.incoming) {
      parts.add(
        said(
          m.statusText,
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OrbitIcon(
                m.video ? OrbitIcons.videoCamera : OrbitIcons.phone,
                weight: OrbitIconWeight.fill,
                size: 13,
                color: t.callMuted,
              ),
              const SizedBox(width: 8),
              OrbitText(m.statusText.toUpperCase(), style: status),
            ],
          ),
        ),
      );
    } else if (ended) {
      parts.add(
        said(
          m.statusText,
          OrbitText(m.statusText.toUpperCase(), style: status),
        ),
      );
      final talk = m.talkTimeLabel;
      // `style="margin-top:0"` on this `.c-sub`: the full 18px gap.
      if (talk != null) {
        parts.add(
          OrbitText(talk, style: t.mono.style(size: 12.5, color: t.callMuted)),
        );
      }
      final detail = m.endDetail;
      // A notice says more than the reason, so the reason steps aside.
      if (detail != null && m.notice == null) parts.add(_detail(t, detail));
    } else if (m.stage == CallStage.active &&
        m.quality != CallQuality.reconnecting) {
      // "Connected" until the clock's first tick.
      final clock = m.elapsedLabel;
      parts.add(
        clock == null
            ? said(
                m.statusText,
                OrbitText(m.statusText.toUpperCase(), style: status),
              )
            : said(
                'Call duration $clock',
                OrbitText(clock, style: status.copyWith(color: t.callLive)),
              ),
      );
      if (m.quality == CallQuality.weak) {
        parts.add(said('Poor connection', _weakChip(t)));
      }
      if (m.muted) parts.add(_detail(t, 'Your microphone is off'));
    } else if (m.quality == CallQuality.reconnecting) {
      parts.add(
        said(
          m.statusText,
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OrbitSpinner(size: 13, color: t.callMuted),
              const SizedBox(width: 8),
              OrbitText(m.statusText.toUpperCase(), style: status),
            ],
          ),
        ),
      );
    } else {
      parts.add(
        said(
          m.statusText,
          OrbitText(m.statusText.toUpperCase(), style: status),
        ),
      );
    }
    // `.c-mid`: centred, 18px between parts; `.c-sub` pulls itself 10px up,
    // which the translate above does without changing the gap that follows,
    // so the parts after it move up too.
    return Center(
      child: SingleChildScrollView(child: _Stack18(children: parts)),
    );
  }

  Widget _detail(OrbitTokens t, String text) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 270),
    child: OrbitText(
      text,
      textAlign: TextAlign.center,
      style: t.font.style(size: 13, color: t.callMuted, height: 1.5),
    ),
  );

  Widget _weakChip(OrbitTokens t) => Container(
    height: 28,
    padding: const EdgeInsets.symmetric(horizontal: 10),
    decoration: BoxDecoration(
      color: const Color(0x33FFD68C),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const OrbitIcon(
          OrbitIcons.cellSignalLow,
          weight: OrbitIconWeight.fill,
          size: 12,
          color: Color(0xFFFFE3A8),
        ),
        const SizedBox(width: 6),
        Text(
          'Poor connection',
          style: t.font.style(
            size: 12,
            weight: 560,
            color: const Color(0xFFFFE3A8),
          ),
        ),
      ],
    ),
  );

  /// `.c-orb`: the 112px picture at a 34% corner with a white ring and a
  /// deep shadow, in a 132px box; while it rings, three rings grow out of
  /// it, 0.8 s apart (still, they sit on the box's edge).
  Widget _orb(OrbitTokens t, {required bool rings}) {
    final m = widget.model;
    Widget halo(Color c, double delay) => AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        var scale = 1.0;
        var opacity = 1.0;
        if (_pulse.isAnimating) {
          final p = (_pulse.value - delay) % 1.0;
          scale = 0.9 + 0.8 * Curves.easeInOut.transform(p);
          opacity = p < 0.3 ? p / 0.3 : 1 - (p - 0.3) / 0.7;
        }
        return Opacity(
          opacity: opacity.clamp(0, 1),
          child: Transform.scale(
            scale: scale,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: c, width: 1.5),
                borderRadius: BorderRadius.circular(132 * 0.36),
              ),
            ),
          ),
        );
      },
    );
    return Semantics(
      container: true,
      image: true,
      label: 'Picture of ${m.title}',
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: 132,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            if (rings) ...[
              Positioned.fill(child: halo(const Color(0x99FFFFFF), 0)),
              Positioned.fill(child: halo(const Color(0x998CF0FF), 1 / 3)),
              Positioned.fill(child: halo(const Color(0x99FFFFFF), 2 / 3)),
            ],
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(112 * 0.34),
                // CSS's first shadow is on top; Flutter's last is.
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x8C08143C),
                    offset: Offset(0, 18),
                    blurRadius: 40,
                    spreadRadius: -12,
                  ),
                  BoxShadow(color: Color(0x38FFFFFF), spreadRadius: 4),
                ],
              ),
              child: OrbitAvatar(avatar: m.avatar, size: 112, cornerPct: 34),
            ),
          ],
        ),
      ),
    );
  }

  /// `.c-noticebar`: an amber sentence over the controls, with ×.
  Widget _notice(OrbitTokens t) => Container(
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
    decoration: BoxDecoration(
      color: const Color(0x2EFFD68C),
      border: Border.all(color: const Color(0x73FFD68C)),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      children: [
        const OrbitIcon(
          OrbitIcons.warningCircle,
          weight: OrbitIconWeight.fill,
          size: 20,
          color: Color(0xFFFFE3A8),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OrbitText(
            widget.model.notice!,
            style: t.font.style(size: 13, color: t.callText, height: 1.4),
          ),
        ),
        const SizedBox(width: 10),
        OrbitIconButton(
          icon: OrbitIcons.x,
          tooltip: 'Dismiss',
          color: t.callMuted,
          size: 40,
          onPressed: widget.actions.dismissNotice,
        ),
      ],
    ),
  );

  /// `.c-incoming`: Decline and Answer, 72px, around the width.
  Widget _incoming(OrbitTokens t) {
    final m = widget.model;
    final a = widget.actions;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _CallButton(
            icon: OrbitIcons.phoneDisconnect,
            label: 'Decline',
            tooltip: 'Decline call',
            size: 72,
            corner: 26,
            iconSize: 30,
            fill: OrbitNight.callEnd,
            ink: const Color(0xFFFFFFFF),
            onPressed: m.busy ? null : (a.decline ?? _noop),
          ),
          _CallButton(
            icon: m.video ? OrbitIcons.videoCamera : OrbitIcons.phone,
            label: 'Answer',
            tooltip: m.video ? 'Answer video call' : 'Answer call',
            size: 72,
            corner: 26,
            iconSize: 30,
            fill: OrbitNight.callAccept,
            ink: const Color(0xFFFFFFFF),
            onPressed: m.busy ? null : (a.answer ?? _noop),
          ),
        ],
      ),
    );
  }

  /// `.c-panel`: the glass tray. A voice call: Speaker (or the output),
  /// Video (never on a voice call), Mute; a video call: Flip, Camera, Mute,
  /// Speaker. End spans the second row.
  Widget _tray(OrbitTokens t, {required bool ended}) {
    final m = widget.model;
    final a = widget.actions;
    final live = m._live && !ended;
    Widget b(
      OrbitGlyph icon,
      String label,
      String tip, {
      bool on = false,
      bool enabled = true,
      VoidCallback? onPressed,
    }) => _CallButton(
      icon: icon,
      label: label,
      tooltip: tip,
      on: on,
      onPressed: live && enabled ? (onPressed ?? _noop) : null,
    );
    final many = m.audioRoutes.length > 2;
    // A window has no output control: Windows picks its own output.
    final window = MediaQuery.sizeOf(context).width >= orbitWindowBreakpoint;
    Widget? speaker;
    if (m.audioRoutes.isNotEmpty && !window) {
      if (many) {
        final (ic, label) = _route(m.audioRoute);
        speaker = b(
          ic,
          label,
          'Audio output: $label',
          on: m.audioRoute != CallAudioRoute.earpiece,
          onPressed: () => _chooseRoute(context),
        );
      } else {
        // Two outputs: a tap picks the other one; one output is no choice.
        final on = m.audioRoute == CallAudioRoute.speaker;
        final other = m.audioRoutes.firstWhere(
          (r) => r != m.audioRoute,
          orElse: () => m.audioRoute,
        );
        final phoneAndSpeaker =
            m.audioRoutes.length < 2 ||
            m.audioRoutes.toSet().containsAll(const {
              CallAudioRoute.earpiece,
              CallAudioRoute.speaker,
            });
        speaker = b(
          OrbitIcons.speakerHigh,
          'Speaker',
          phoneAndSpeaker
              ? (on ? 'Turn speaker off' : 'Turn speaker on')
              : 'Audio output: ${_route(m.audioRoute).$2}',
          on: on,
          enabled: m.audioRoutes.length > 1,
          onPressed: () => a.selectAudioRoute?.call(other),
        );
      }
    }
    final mute = b(
      m.muted ? OrbitIcons.microphoneSlash : OrbitIcons.microphone,
      'Mute',
      m.muted ? 'Unmute microphone' : 'Mute microphone',
      on: m.muted,
      onPressed: () => a.setMuted?.call(!m.muted),
    );
    final controls = m.video
        ? [
            b(
              OrbitIcons.cameraRotate,
              'Flip',
              'Flip camera',
              enabled: m.cameraOn,
              onPressed: a.flipCamera,
            ),
            b(
              m.cameraOn ? OrbitIcons.videoCamera : OrbitIcons.videoCameraSlash,
              'Video',
              m.cameraOn ? 'Turn camera off' : 'Turn camera on',
              on: m.cameraOn,
              // The app's rule: from connecting on (the prototype: active).
              enabled:
                  m.stage == CallStage.active ||
                  m.stage == CallStage.connecting,
              onPressed: () => a.setCamera?.call(!m.cameraOn),
            ),
            if (m.canShareScreen && a.setScreenSharing != null)
              b(
                OrbitIcons.monitor,
                'Share',
                m.screenSharing
                    ? 'Stop sharing your screen'
                    : 'Share your screen',
                on: m.screenSharing,
                enabled: m.stage == CallStage.active,
                onPressed: () => a.setScreenSharing?.call(!m.screenSharing),
              ),
            mute,
            ?speaker,
          ]
        : [
            ?speaker,
            b(
              OrbitIcons.videoCameraSlash,
              'Video',
              'Video is not available on a voice call',
              enabled: false,
            ),
            mute,
          ];
    return CustomPaint(
      painter: const OrbitOuterShadow(
        radius: BorderRadius.all(Radius.circular(32)),
        shadows: [
          BoxShadow(
            color: Color(0x8008143C),
            offset: Offset(0, 20),
            blurRadius: 40,
            spreadRadius: -20,
          ),
        ],
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
        decoration: BoxDecoration(
          color: t.callGlass,
          border: Border.all(color: t.callLine),
          borderRadius: BorderRadius.circular(32),
        ),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (i, c) in controls.indexed) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Expanded(child: c),
                ],
              ],
            ),
            const SizedBox(height: 12),
            _EndButton(onPressed: live ? (a.hangUp ?? _noop) : null),
          ],
        ),
      ),
    );
  }

  void _chooseRoute(BuildContext context) {
    final m = widget.model;
    showOrbitSheet(
      context,
      title: 'Audio output',
      items: [
        for (final r in m.audioRoutes)
          OrbitMenuItem(
            icon: _route(r).$1,
            label: _route(r).$2,
            on: r == m.audioRoute,
            onTap: () => widget.actions.selectAudioRoute?.call(r),
          ),
      ],
    );
  }

  // ---------------------------------------------------------------- video

  Widget _videoLayout(BuildContext context) {
    final t = OrbitTokens.of(context);
    final m = widget.model;
    final dialing = m.stage != CallStage.active;
    final size = MediaQuery.sizeOf(context);
    Widget stand(String swatch) =>
        DecoratedBox(decoration: BoxDecoration(gradient: orbitSwatch(swatch)));
    // What the app's pictures show until frames arrive: their picture on the
    // gradient, or a small one in the tile.
    Widget waiting({required bool small}) => DecoratedBox(
      decoration: BoxDecoration(gradient: t.brandGradient),
      child: Center(
        child: OrbitAvatar(avatar: m.avatar, size: small ? 48 : 120),
      ),
    );
    Widget remote({required bool small}) =>
        widget.remoteVideo?.call(
          context,
          waiting(small: small),
          screen: m.peerScreenSharing,
        ) ??
        stand('ph-e');
    Widget local({bool small = false}) =>
        widget.localVideo?.call(context, waiting(small: small)) ??
        stand('ph-c');
    Widget theirs({bool small = false}) => m.remoteCameraOff && !dialing
        ? DecoratedBox(
            decoration: BoxDecoration(gradient: t.brandGradient),
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -0.2),
                  radius: 0.75,
                  colors: [Color(0x24FFFFFF), Color(0x00FFFFFF)],
                  stops: [0, 0.55],
                ),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(
                          120 * t.avatarR / 100,
                        ),
                        boxShadow: const [
                          BoxShadow(color: Color(0x38FFFFFF), spreadRadius: 4),
                        ],
                      ),
                      child: OrbitAvatar(avatar: m.avatar, size: 120),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        OrbitIcon(
                          OrbitIcons.videoCameraSlash,
                          size: 12,
                          color: t.callMuted,
                        ),
                        const SizedBox(width: 6),
                        OrbitText(
                          'CAMERA OFF',
                          style: t.mono.style(
                            size: 12,
                            color: t.callMuted,
                            letterSpacingEm: 0.08,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          )
        : dialing
        ? local()
        : remote(small: small);
    // The app's tile needs your camera's picture; the preview's is drawn.
    final showTile =
        !dialing &&
        m.cameraOn &&
        (widget.localVideo == null || m.hasLocalVideo);
    final big = _swapped && showTile ? local() : theirs();
    final small = _swapped ? theirs(small: true) : local(small: true);
    final hide = _controlsOff;
    Widget hideable(Widget w) => IgnorePointer(
      ignoring: hide,
      child: AnimatedOpacity(
        opacity: hide ? 0 : 1,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 180),
        // Hidden controls leave the screen reader's tree too.
        child: ExcludeSemantics(excluding: hide, child: w),
      ),
    );
    // The tile starts at the top end and stays inside the safe area.
    final pad = MediaQuery.paddingOf(context);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    Offset inside(Offset at) => Offset(
      at.dx.clamp(
        pad.left + 12,
        (size.width - pad.right - 12 - 104).clamp(
          pad.left + 12,
          double.infinity,
        ),
      ),
      at.dy.clamp(
        pad.top + 12,
        (size.height - pad.bottom - 12 - 150).clamp(
          pad.top + 12,
          double.infinity,
        ),
      ),
    );
    final tile = inside(_tile ?? Offset(rtl ? 16 : size.width - 16 - 104, 132));
    final bigLabel = dialing || (_swapped && showTile)
        ? 'Your camera'
        : 'Video from ${m.title}';
    return ColoredBox(
      color: const Color(0xFF000000),
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _controlsOff = !_controlsOff),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Semantics(
                    container: true,
                    label: bigLabel,
                    excludeSemantics: true,
                    child: big,
                  ),
                  const IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color(0x80000000),
                            Color(0x00000000),
                            Color(0x00000000),
                            Color(0xA6000000),
                          ],
                          stops: [0, 0.22, 0.62, 1],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: hideable(
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(28, 100, 28, 0),
                    child: _header(t, true, minHeight: 0),
                  ),
                  // `.c-who`: the name at 22px and the clock, left, 4px 24px.
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 4,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        OrbitText(
                          m.title,
                          style: t.display(size: 22, color: t.callText),
                        ),
                        Semantics(
                          container: true,
                          liveRegion: true,
                          label: dialing || m.elapsedLabel == null
                              ? m.statusText
                              : 'Call duration ${m.elapsedLabel}',
                          excludeSemantics: true,
                          child: OrbitText(
                            dialing || m.elapsedLabel == null
                                ? m.statusText.toUpperCase()
                                : m.elapsedLabel!,
                            style: t.mono.style(
                              size: 13,
                              color: dialing || m.elapsedLabel == null
                                  ? t.callMuted
                                  : t.callLive,
                              letterSpacingEm: 0.12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!dialing && (m.screenSharing || m.peerScreenSharing))
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: ConstrainedBox(
                          // Clear of your camera's tile, which sits at the end.
                          constraints: BoxConstraints(
                            maxWidth: (size.width - 24 - 24 - 116).clamp(
                              160.0,
                              600.0,
                            ),
                          ),
                          child: _ShareBanner(
                            text: m.screenSharing
                                ? 'You are sharing your screen'
                                : '${m.title} is sharing their screen',
                            onStop:
                                m.screenSharing &&
                                    widget.actions.setScreenSharing != null
                                ? () => widget.actions.setScreenSharing!(false)
                                : null,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (showTile)
            Positioned(
              left: tile.dx,
              top: tile.dy,
              child: GestureDetector(
                onPanUpdate: (d) =>
                    setState(() => _tile = inside(tile + d.delta)),
                onTap: () => setState(() => _swapped = !_swapped),
                child: Tooltip(
                  message: _swapped
                      ? 'Show ${m.title} full screen'
                      : 'Show your camera full screen',
                  excludeFromSemantics: true,
                  child: Semantics(
                    container: true,
                    button: true,
                    excludeSemantics: true,
                    label: _swapped
                        ? 'Show ${m.title} full screen'
                        : 'Show your camera full screen',
                    child: MouseRegion(
                      cursor: SystemMouseCursors.move,
                      child: Container(
                        width: 104,
                        height: 150,
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x66000000),
                              offset: Offset(0, 10),
                              blurRadius: 30,
                            ),
                            BoxShadow(
                              color: Color(0x2EFFFFFF),
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: small,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          // `left: 14px; right: 14px`, but a window's 440px width wins, so
          // the tray sits at the left.
          Positioned(
            left: 14,
            bottom: 30,
            width: (size.width - 28).clamp(0.0, 440.0),
            child: hideable(
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (m.notice != null) _notice(t),
                  _tray(t, ended: false),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// `.c-mid`'s column: 18px between parts, centred.
/// "You are sharing your screen" with Stop, or "Sam is sharing their screen".
class _ShareBanner extends StatelessWidget {
  const _ShareBanner({required this.text, this.onStop});

  final String text;
  final VoidCallback? onStop;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 6, 6, 6),
      decoration: BoxDecoration(
        color: t.callGlass,
        border: Border.all(color: t.callLine),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          OrbitIcon(OrbitIcons.monitor, size: 14, color: t.callText),
          const SizedBox(width: 8),
          Flexible(
            child: OrbitText(
              text,
              style: t.font.style(size: OrbitType.small, color: t.callText),
            ),
          ),
          if (onStop != null) ...[
            const SizedBox(width: 6),
            OrbitTapArea(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onStop,
                child: Semantics(
                  container: true,
                  button: true,
                  label: 'Stop sharing your screen',
                  excludeSemantics: true,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: OrbitNight.callEnd,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: OrbitText(
                      'Stop',
                      style: t.font.style(
                        size: OrbitType.small,
                        weight: 600,
                        color: const Color(0xFFFFFFFF),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Stack18 extends StatelessWidget {
  const _Stack18({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final (i, c) in children.indexed) ...[
        if (i > 0) SizedBox(height: c is Transform ? 8 : 18),
        if (c is Transform) c.child! else c,
      ],
    ],
  );
}

/// The call screen's backdrop over `--brand-gradient`: an 18px grid of
/// faint dots and a soft white glow at 50% 36% that fades out by 46%.
class _CallBackdrop extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final dot = Paint()..color = const Color(0x17FFFFFF);
    for (var y = 9.0; y < size.height; y += 18) {
      for (var x = 9.0; x < size.width; x += 18) {
        canvas.drawCircle(Offset(x, y), 1.1, dot);
      }
    }
    final c = Offset(size.width / 2, size.height * 0.36);
    // `circle` with the default size: the farthest corner.
    final far = [
      Offset.zero,
      Offset(size.width, 0),
      Offset(0, size.height),
      Offset(size.width, size.height),
    ].map((p) => (p - c).distance).reduce((a, b) => a > b ? a : b);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0x2EFFFFFF), Color(0x00FFFFFF)],
          stops: [0, 0.46],
        ).createShader(Rect.fromCircle(center: c, radius: far)),
    );
  }

  @override
  bool shouldRepaint(_CallBackdrop old) => false;
}

/// `.cbtn`: a 58px glass tile (corner 22) over its 11.5px label, 7px apart;
/// on, the tile turns `--glass-bg` with a filled `--glass-accent` icon;
/// disabled, the whole button is at 38%.
class _CallButton extends StatelessWidget {
  const _CallButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onPressed,
    this.on = false,
    this.size = 58,
    this.corner = 22,
    this.iconSize = 25,
    this.fill,
    this.ink,
  });

  final OrbitGlyph icon;
  final String label;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool on;
  final double size;
  final double corner;
  final double iconSize;
  final Color? fill;
  final Color? ink;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final enabled = onPressed != null;
    return Opacity(
      opacity: enabled ? 1 : 0.38,
      child: Tooltip(
        message: tooltip,
        excludeFromSemantics: true,
        child: Semantics(
          button: true,
          enabled: enabled,
          toggled: on,
          label: tooltip,
          excludeSemantics: true,
          child: GestureDetector(
            onTap: onPressed,
            behavior: HitTestBehavior.opaque,
            // A `<button>` keeps the browser's 1px of padding above and below.
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      color: fill ?? (on ? t.glassBg : t.callGlass),
                      borderRadius: BorderRadius.circular(corner),
                    ),
                    child: Center(
                      child: OrbitIcon(
                        icon,
                        weight: on || fill != null
                            ? OrbitIconWeight.fill
                            : null,
                        size: iconSize,
                        color: ink ?? (on ? t.glassAccent : t.callText),
                      ),
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    label,
                    style: t.font.style(size: 11.5, color: t.callText),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `.cbtn.end`: the red pill across the tray's second row, up to 240px.
class _EndButton extends StatelessWidget {
  const _EndButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: onPressed == null ? 0.38 : 1,
    child: Tooltip(
      message: 'End call',
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        enabled: onPressed != null,
        label: 'End call',
        child: GestureDetector(
          onTap: onPressed,
          child: Container(
            height: 56,
            margin: const EdgeInsets.symmetric(vertical: 1),
            constraints: const BoxConstraints(maxWidth: 240),
            decoration: BoxDecoration(
              color: OrbitNight.callEnd,
              borderRadius: BorderRadius.circular(28),
            ),
            child: const Center(
              child: OrbitIcon(
                OrbitIcons.phoneDisconnect,
                weight: OrbitIconWeight.fill,
                size: 26,
                color: Color(0xFFFFFFFF),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------- call detail

enum CallDetailStatus { loading, ready, notFound, error }

enum CallLogDirection {
  incoming,
  outgoing,
  missed,
  declined,
  failed,
  cancelled,
  noAnswer,
}

class CallDetailRowModel {
  const CallDetailRowModel({
    required this.callId,
    required this.direction,
    required this.label,
    required this.timeLabel,
    this.durationLabel,
    this.spokenDuration,
    this.video = false,
  });

  final String callId;
  final CallLogDirection direction;

  /// "Incoming voice call".
  final String label;
  final String timeLabel;
  final String? durationLabel;
  final String? spokenDuration;
  final bool video;

  bool get isProblem =>
      direction == CallLogDirection.missed ||
      direction == CallLogDirection.failed;
}

class CallDetailModel {
  const CallDetailModel({
    required this.title,
    required this.avatar,
    this.status = CallDetailStatus.ready,
    this.subtitle,
    this.rows = const [],
    this.canCall = true,
    this.blockedReason,
  });

  final CallDetailStatus status;
  final String title;
  final String? subtitle;
  final HelixAvatarModel avatar;
  final List<CallDetailRowModel> rows;
  final bool canCall;

  /// "Nadia has blocked you. You can’t message or call them."
  final String? blockedReason;
}

class CallDetailActions {
  const CallDetailActions({
    this.voiceCall,
    this.videoCall,
    this.openContact,
    this.deleteAll,
    this.retry,
  });

  /// Places the call; the sentence to show when it could not start (null
  /// when it started: the call screen opens by itself).
  final Future<String?> Function()? voiceCall;
  final Future<String?> Function()? videoCall;
  final VoidCallback? openContact;
  final VoidCallback? deleteAll;
  final VoidCallback? retry;
}

/// `call-detail`: one person's calls. Their picture and name, Voice call,
/// Video call and Contact, and every call with them, newest first.
class CallDetailScreen extends StatefulWidget {
  const CallDetailScreen({
    super.key,
    required this.model,
    this.actions = const CallDetailActions(),
  });

  final CallDetailModel model;
  final CallDetailActions actions;

  @override
  State<CallDetailScreen> createState() => _CallDetailScreenState();
}

class _CallDetailScreenState extends State<CallDetailScreen> {
  /// The call being placed: its button spins.
  bool? _placing;

  Future<void> _call({required bool video}) async {
    final place = video ? widget.actions.videoCall : widget.actions.voiceCall;
    if (place == null || _placing != null) return;
    setState(() => _placing = video);
    final String? refusal;
    try {
      refusal = await place();
    } finally {
      if (mounted) setState(() => _placing = null);
    }
    if (refusal != null && mounted) {
      showOrbitToast(context, refusal, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final m = widget.model;
    final a = widget.actions;
    final top = MediaQuery.paddingOf(context).top;
    final n = m.rows.length;
    final Widget body = switch (m.status) {
      CallDetailStatus.loading => const Center(child: OrbitPageLoading()),
      CallDetailStatus.error => ListView(
        children: [
          OrbitLoadFailed(
            title: 'This call could not be loaded.',
            onRetry: a.retry,
          ),
        ],
      ),
      CallDetailStatus.notFound => ListView(
        children: const [
          OrbitEmptyState(
            icon: OrbitIcons.phoneX,
            title: 'Call not found',
            text: 'This call is no longer in your call history.',
          ),
        ],
      ),
      CallDetailStatus.ready => ListView(
        padding: const EdgeInsets.only(bottom: 30),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
            child: Column(
              children: [
                Semantics(
                  container: true,
                  image: true,
                  label: 'Picture of ${m.title}',
                  excludeSemantics: true,
                  child: OrbitAvatar(avatar: m.avatar, size: 72),
                ),
                const SizedBox(height: 12),
                Semantics(
                  container: true,
                  header: true,
                  child: OrbitText(
                    m.title,
                    textAlign: TextAlign.center,
                    style: t.font.style(
                      size: 22,
                      weight: 640,
                      color: t.ink,
                      letterSpacingEm: -0.02,
                    ),
                  ),
                ),
                if ((m.subtitle ?? '').isNotEmpty) ...[
                  const SizedBox(height: 6),
                  OrbitText(
                    m.subtitle!,
                    textAlign: TextAlign.center,
                    style: t.mono.style(size: 12, color: t.ink3),
                  ),
                ],
              ],
            ),
          ),
          if (!m.canCall && m.blockedReason != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 8, 32, 0),
              child: OrbitText.rich(
                TextSpan(
                  children: [
                    WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: OrbitIcon(
                        OrbitIcons.prohibit,
                        size: 12,
                        color: t.ink3,
                      ),
                    ),
                    TextSpan(text: ' ${m.blockedReason}'),
                  ],
                ),
                textAlign: TextAlign.center,
                style: t.font.style(
                  size: OrbitType.caption,
                  color: t.ink3,
                  height: 1.5,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (m.canCall) ...[
                  _Round(
                    OrbitIcons.phone,
                    'Voice call',
                    () => _call(video: false),
                    busy: _placing == false,
                  ),
                  const SizedBox(width: 18),
                  _Round(
                    OrbitIcons.videoCamera,
                    'Video call',
                    () => _call(video: true),
                    busy: _placing == true,
                  ),
                  const SizedBox(width: 18),
                ],
                _Round(OrbitIcons.userCircle, 'Contact', a.openContact),
              ],
            ),
          ),
          OrbitSection(
            title: 'Calls',
            rows: [for (final r in m.rows) _row(t, r)],
          ),
        ],
      ),
    };
    return OrbitPageBackground(
      child: Padding(
        padding: EdgeInsets.only(top: top),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OrbitAppBar(
              title: 'Call details',
              onLead: () => Navigator.maybePop(context),
              actions: [
                if (m.status == CallDetailStatus.ready)
                  OrbitIconButton(
                    icon: OrbitIcons.trash,
                    tooltip: 'Delete from call history',
                    onPressed: () => showOrbitDialog(
                      context,
                      title: 'Delete from call history?',
                      text: n > 1
                          ? 'These $n calls with ${m.title} will be removed '
                                'from your call history.'
                          : 'This call with ${m.title} will be removed from '
                                'your call history.',
                      actions: [
                        const OrbitDialogAction('Cancel'),
                        OrbitDialogAction(
                          'Delete',
                          kind: OrbitButtonKind.danger,
                          onPressed: a.deleteAll,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }

  Widget _row(OrbitTokens t, CallDetailRowModel r) {
    final (icon, ink) = switch (r.direction) {
      CallLogDirection.incoming => (OrbitIcons.arrowDownLeft, t.success),
      CallLogDirection.outgoing => (OrbitIcons.arrowUpRight, t.success),
      CallLogDirection.missed => (OrbitIcons.arrowDownLeft, t.danger),
      CallLogDirection.declined => (OrbitIcons.phoneDisconnect, t.ink3),
      CallLogDirection.failed => (OrbitIcons.warningCircle, t.danger),
      CallLogDirection.cancelled => (OrbitIcons.arrowUpRight, t.ink3),
      CallLogDirection.noAnswer => (OrbitIcons.arrowUpRight, t.ink3),
    };
    return Semantics(
      label: [r.label, r.timeLabel, ?r.spokenDuration].join(', '),
      excludeSemantics: true,
      child: OrbitListRow(
        icon: icon,
        iconWeight: OrbitIconWeight.bold,
        iconInk: ink,
        title: r.label,
        titleInk: r.isProblem ? t.danger : null,
        sub: '${r.video ? 'Video · ' : ''}${r.timeLabel}',
        subMono: true,
        value: r.durationLabel ?? '',
      ),
    );
  }
}

/// `.quick-item`: a 56px tile (corner 20) on `--surface` with an
/// `--accent` icon, its label under it.
class _Round extends StatelessWidget {
  const _Round(this.icon, this.label, this.onPressed, {this.busy = false});

  final OrbitGlyph icon;
  final String label;
  final VoidCallback? onPressed;

  /// Waiting for its action: a spinner in place of the icon.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: GestureDetector(
          onTap: onPressed,
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: 64,
            // A `<button>`'s 1px of padding above and below.
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Column(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: t.surface,
                    border: Border.all(color: t.line),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Center(
                    child: busy
                        ? OrbitSpinner(size: 23, color: t.accent)
                        : OrbitIcon(icon, size: 23, color: t.accent),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.font.style(size: 12, weight: 520, color: t.ink2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
