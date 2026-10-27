part of 'call_screens.dart';

/// Where one other person is in a group call, as a tile says it.
enum GroupTileState { ringing, connecting, connected, left, failed }

/// One person's tile in a group call.
class GroupCallTile {
  const GroupCallTile({
    required this.id,
    required this.name,
    required this.avatar,
    this.state = GroupTileState.connected,
  });

  /// What the app's picture slot is asked for (the person's account).
  final String id;
  final String name;
  final HelixAvatarModel avatar;
  final GroupTileState state;
}

/// What the group call screen draws.
class GroupCallModel {
  const GroupCallModel({
    required this.roomId,
    required this.title,
    required this.stage,
    required this.statusText,
    required this.tiles,
    this.starterName = '',
    this.video = false,
    this.elapsedLabel,
    this.endDetail,
    this.muted = false,
    this.cameraOn = false,
    this.hasLocalVideo = false,
    this.audioRoute = CallAudioRoute.earpiece,
    this.audioRoutes = const [CallAudioRoute.earpiece, CallAudioRoute.speaker],
    this.notice,
    this.busy = false,
  });

  final String roomId;

  /// The group's name.
  final String title;

  /// Incoming, connecting or active; ended shows how it ended.
  final CallStage stage;
  final String statusText;

  /// Everyone but you.
  final List<GroupCallTile> tiles;

  /// Who is calling, for the ringing screen.
  final String starterName;
  final bool video;
  final String? elapsedLabel;
  final String? endDetail;
  final bool muted;
  final bool cameraOn;
  final bool hasLocalVideo;
  final CallAudioRoute audioRoute;
  final List<CallAudioRoute> audioRoutes;
  final String? notice;
  final bool busy;
}

class GroupCallActions {
  const GroupCallActions({
    this.answer,
    this.decline,
    this.hangUp,
    this.setMuted,
    this.setCamera,
    this.flipCamera,
    this.selectAudioRoute,
    this.dismissNotice,
  });

  final VoidCallback? answer;
  final VoidCallback? decline;
  final VoidCallback? hangUp;
  final ValueChanged<bool>? setMuted;
  final ValueChanged<bool>? setCamera;
  final VoidCallback? flipCamera;
  final ValueChanged<CallAudioRoute>? selectAudioRoute;
  final VoidCallback? dismissNotice;
}

/// A person's picture in their tile; [placeholder] is what to draw until
/// frames arrive (their avatar on the gradient).
typedef GroupTileVideoSlot =
    Widget Function(BuildContext context, String id, Widget placeholder);

/// The full-screen group call: a night page on the brand gradient. Ringing,
/// it says which group and who is calling and offers Answer and Decline;
/// live, it shows up to four tiles (you and the others) and the control tray.
class GroupCallScreen extends StatelessWidget {
  const GroupCallScreen({
    super.key,
    required this.model,
    this.actions = const GroupCallActions(),
    this.tileVideo,
    this.localVideo,
  });

  final GroupCallModel model;
  final GroupCallActions actions;
  final GroupTileVideoSlot? tileVideo;
  final CallVideoSlot? localVideo;

  static String _stateLabel(GroupTileState s) => switch (s) {
    GroupTileState.ringing => 'Ringing…',
    GroupTileState.connecting => 'Connecting…',
    GroupTileState.connected => '',
    GroupTileState.left => 'Left',
    GroupTileState.failed => 'Could not connect',
  };

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final m = model;
    final incoming = m.stage == CallStage.incoming;
    final ended = m.stage == CallStage.ended;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Material(
        type: MaterialType.transparency,
        child: DecoratedBox(
          decoration: BoxDecoration(gradient: t.brandGradient),
          child: CustomPaint(
            painter: _CallBackdrop(),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 56, 16, 32),
              child: Column(
                children: [
                  _top(t, incoming),
                  const SizedBox(height: 10),
                  Expanded(
                    child: incoming ? _ringing(context, t) : _grid(context, t),
                  ),
                  if (m.notice != null) _notice(t),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: incoming ? _answerRow() : _tray(context, t, ended),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _top(OrbitTokens t, bool incoming) => Column(
    children: [
      OrbitText(
        'ORBIT GROUP ${model.video ? 'VIDEO' : 'VOICE'} CALL',
        style: t.mono.style(
          size: OrbitType.meta,
          color: t.callMuted,
          letterSpacingEm: 0.12,
        ),
      ),
      const SizedBox(height: 6),
      Semantics(
        container: true,
        header: true,
        child: OrbitText(
          model.title,
          textAlign: TextAlign.center,
          style: t.display(size: 22, color: t.callText),
        ),
      ),
      const SizedBox(height: 2),
      Semantics(
        container: true,
        liveRegion: true,
        label: model.elapsedLabel == null
            ? model.statusText
            : 'Call duration ${model.elapsedLabel}',
        excludeSemantics: true,
        child: OrbitText(
          (model.elapsedLabel ?? model.statusText).toUpperCase(),
          style: t.mono.style(
            size: 12.5,
            color: model.elapsedLabel == null ? t.callMuted : t.callLive,
            letterSpacingEm: 0.12,
          ),
        ),
      ),
    ],
  );

  Widget _ringing(BuildContext context, OrbitTokens t) {
    final m = model;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final tile in m.tiles)
                OrbitAvatar(avatar: tile.avatar, size: 64),
            ],
          ),
          const SizedBox(height: 18),
          OrbitText(
            m.starterName.isEmpty
                ? 'Incoming group call'
                : '${m.starterName} is calling the group',
            textAlign: TextAlign.center,
            style: t.font.style(size: OrbitType.body, color: t.callText),
          ),
          const SizedBox(height: 4),
          OrbitText(
            m.tiles.map((x) => x.name).join(', '),
            textAlign: TextAlign.center,
            style: t.font.style(size: OrbitType.small, color: t.callMuted),
          ),
        ],
      ),
    );
  }

  Widget _answerRow() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 32),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _CallButton(
          icon: OrbitIcons.phoneDisconnect,
          label: 'Decline',
          tooltip: 'Decline group call',
          size: 72,
          corner: 26,
          iconSize: 30,
          fill: OrbitNight.callEnd,
          ink: const Color(0xFFFFFFFF),
          onPressed: model.busy ? null : (actions.decline ?? _noop),
        ),
        _CallButton(
          icon: model.video ? OrbitIcons.videoCamera : OrbitIcons.phone,
          label: 'Join',
          tooltip: model.video ? 'Join video call' : 'Join call',
          size: 72,
          corner: 26,
          iconSize: 30,
          fill: OrbitNight.callAccept,
          ink: const Color(0xFFFFFFFF),
          onPressed: model.busy ? null : (actions.answer ?? _noop),
        ),
      ],
    ),
  );

  /// You and the others: two stacked, three or four in a pair of rows.
  Widget _grid(BuildContext context, OrbitTokens t) {
    final m = model;
    final others = [
      for (final tile in m.tiles)
        _tile(
          context,
          t,
          name: tile.name,
          avatar: tile.avatar,
          label: GroupCallScreen._stateLabel(tile.state),
          video: tileVideo?.call(context, tile.id, _gradient(t, tile.avatar)),
          dim:
              tile.state == GroupTileState.left ||
              tile.state == GroupTileState.failed,
        ),
    ];
    final me = _tile(
      context,
      t,
      name: 'You',
      avatar: const HelixAvatarModel(name: 'You'),
      label: m.muted ? 'Muted' : '',
      video: m.cameraOn && m.hasLocalVideo
          ? localVideo?.call(context, _gradient(t, null))
          : null,
      dim: false,
      mirror: true,
    );
    final all = [...others, me];
    Widget rowOf(List<Widget> items) => Expanded(
      child: Row(
        children: [
          for (final (i, w) in items.indexed) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: w),
          ],
        ],
      ),
    );
    final List<Widget> rows;
    if (all.length <= 2) {
      rows = [
        for (final w in all) rowOf([w]),
      ];
    } else {
      rows = [rowOf(all.sublist(0, 2)), rowOf(all.sublist(2))];
    }
    return Column(
      children: [
        for (final (i, r) in rows.indexed) ...[
          if (i > 0) const SizedBox(height: 8),
          r,
        ],
      ],
    );
  }

  Widget _gradient(OrbitTokens t, HelixAvatarModel? avatar) => DecoratedBox(
    decoration: BoxDecoration(gradient: t.brandGradient),
    child: Center(
      child: avatar == null
          ? const SizedBox.shrink()
          : OrbitAvatar(avatar: avatar, size: 56),
    ),
  );

  Widget _tile(
    BuildContext context,
    OrbitTokens t, {
    required String name,
    required HelixAvatarModel avatar,
    required String label,
    required Widget? video,
    required bool dim,
    bool mirror = false,
  }) => Semantics(
    container: true,
    label: label.isEmpty ? name : '$name, $label',
    excludeSemantics: true,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(color: t.callGlass),
            child: video ?? _gradient(t, avatar),
          ),
          if (dim) const ColoredBox(color: Color(0x73000000)),
          Positioned(
            left: 8,
            bottom: 8,
            right: 8,
            child: Row(
              children: [
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0x66000000),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: OrbitText(
                      label.isEmpty ? name : '$name · $label',
                      style: t.font.style(
                        size: OrbitType.caption,
                        color: const Color(0xFFFFFFFF),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

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
            model.notice!,
            style: t.font.style(size: 13, color: t.callText, height: 1.4),
          ),
        ),
        OrbitIconButton(
          icon: OrbitIcons.x,
          tooltip: 'Dismiss',
          color: t.callMuted,
          size: 40,
          onPressed: actions.dismissNotice,
        ),
      ],
    ),
  );

  Widget _tray(BuildContext context, OrbitTokens t, bool ended) {
    final m = model;
    final a = actions;
    final live = !ended;
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
    final window = MediaQuery.sizeOf(context).width >= orbitWindowBreakpoint;
    Widget? speaker;
    if (m.audioRoutes.length > 1 && !window) {
      final on = m.audioRoute == CallAudioRoute.speaker;
      final other = m.audioRoutes.firstWhere(
        (r) => r != m.audioRoute,
        orElse: () => m.audioRoute,
      );
      speaker = b(
        OrbitIcons.speakerHigh,
        'Speaker',
        on ? 'Turn speaker off' : 'Turn speaker on',
        on: on,
        onPressed: () => a.selectAudioRoute?.call(other),
      );
    }
    final controls = [
      b(
        m.muted ? OrbitIcons.microphoneSlash : OrbitIcons.microphone,
        'Mute',
        m.muted ? 'Unmute microphone' : 'Mute microphone',
        on: m.muted,
        onPressed: () => a.setMuted?.call(!m.muted),
      ),
      if (m.video) ...[
        b(
          m.cameraOn ? OrbitIcons.videoCamera : OrbitIcons.videoCameraSlash,
          'Video',
          m.cameraOn ? 'Turn camera off' : 'Turn camera on',
          on: m.cameraOn,
          onPressed: () => a.setCamera?.call(!m.cameraOn),
        ),
        b(
          OrbitIcons.cameraRotate,
          'Flip',
          'Flip camera',
          enabled: m.cameraOn,
          onPressed: a.flipCamera,
        ),
      ],
      ?speaker,
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: t.callGlass,
        border: Border.all(color: t.callLine),
        borderRadius: BorderRadius.circular(32),
      ),
      child: Column(
        children: [
          Row(
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
    );
  }
}
