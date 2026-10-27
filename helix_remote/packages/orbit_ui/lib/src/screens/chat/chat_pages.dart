import 'dart:async';
import 'dart:ui' show ImageFilter;

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
import 'package:orbit_ui/src/components/pages.dart';
import 'package:orbit_ui/src/components/spinner.dart';
import 'package:orbit_ui/src/components/state_kit.dart';
import 'package:orbit_ui/src/components/wallpaper.dart';
import 'package:orbit_ui/src/components/timeline.dart';
import 'package:orbit_ui/src/icons/orbit_glyph.dart';
import 'package:orbit_ui/src/icons/orbit_icons.dart';
import 'package:orbit_ui/src/models/view_models.dart';
import 'package:orbit_ui/src/theme/orbit_metrics.dart';
import 'package:orbit_ui/src/theme/orbit_text.dart';
import 'package:orbit_ui/src/theme/orbit_tokens.dart';
import 'package:orbit_ui/src/theme/pattern_painter.dart';
import 'package:orbit_ui/src/window/window_scaffold.dart';

/// Whether a list has loaded (`contracts/conversation.md`).
enum LoadState { loading, error, ready }

/// A whole page that is loading or could not load, under its bar.
Widget _loadBody(LoadState s, String failed, VoidCallback? retry) =>
    switch (s) {
      LoadState.loading => const Center(child: OrbitPageLoading()),
      _ => ListView(
        children: [OrbitLoadFailed(title: failed, onRetry: retry)],
      ),
    };

// ------------------------------------------------------------------ forward

/// A chat or person a message can be forwarded to.
class ForwardTargetItem {
  const ForwardTargetItem({
    required this.id,
    required this.title,
    required this.avatar,
    this.isNewChat = false,
  });

  final String id;
  final String title;
  final HelixAvatarModel avatar;
  final bool isNewChat;
}

class ForwardModel {
  const ForwardModel({
    required this.messageCount,
    this.loadState = LoadState.ready,
    this.targets = const [],
  });

  final int messageCount;
  final LoadState loadState;
  final List<ForwardTargetItem> targets;
}

class ForwardActions {
  const ForwardActions({this.onSend, this.onRetry});

  /// Sends to the picked chats; the screen closes when it finishes.
  final Future<void> Function(Set<String> targetIds)? onSend;
  final VoidCallback? onRetry;
}

/// `forward` (`js/screens/chat_pages.js`): pick chats to forward to. A
/// search over the chats, 64px rows ending in a square tick, and "Send to N
/// chats" in a bottom bar once something is picked.
class ForwardScreen extends StatefulWidget {
  const ForwardScreen({
    super.key,
    required this.model,
    this.actions = const ForwardActions(),
    this.initialPicked = const {},
  });

  final ForwardModel model;
  final ForwardActions actions;

  /// Preview start state (`forward-picked`).
  final Set<String> initialPicked;

  @override
  State<ForwardScreen> createState() => _ForwardScreenState();
}

class _ForwardScreenState extends State<ForwardScreen> {
  late final Set<String> _picked = {...widget.initialPicked};
  var _q = '';
  var _busy = false;

  Future<void> _send() async {
    setState(() => _busy = true);
    await widget.actions.onSend?.call({..._picked});
    if (!mounted) return;
    setState(() => _busy = false);
    Navigator.maybePop(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final m = widget.model;
    final q = _q.trim().toLowerCase();
    final rows = [
      for (final c in m.targets)
        if (c.title.toLowerCase().contains(q)) c,
    ];
    final n = _picked.length;
    return _PageFrame(
      title: m.messageCount > 1
          ? 'Forward ${m.messageCount} messages'
          : 'Forward message',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            OrbitSpace.gutter,
            10,
            OrbitSpace.gutter,
            6,
          ),
          child: SizedBox(
            height: 46,
            child: OrbitSearchField(
              hint: 'Search chats and people',
              onChanged: (v) => setState(() => _q = v),
            ),
          ),
        ),
        Expanded(
          child: m.loadState != LoadState.ready
              ? _loadBody(
                  m.loadState,
                  'Your chats could not be loaded.',
                  widget.actions.onRetry,
                )
              : rows.isEmpty
              ? ListView(
                  children: [
                    // The prototype's search empty state
                    // (`conversation.js`), with what was typed.
                    OrbitEmptyState(
                      icon: OrbitIcons.magnifyingGlass,
                      title: 'No results',
                      text: q.isEmpty ? '' : 'Nothing matches “${_q.trim()}”.',
                    ),
                  ],
                )
              : ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    for (final c in rows)
                      InkWell(
                        onTap: () => setState(
                          () => _picked.contains(c.id)
                              ? _picked.remove(c.id)
                              : _picked.add(c.id),
                        ),
                        hoverColor: t.hover,
                        splashFactory: NoSplash.splashFactory,
                        child: SizedBox(
                          height: 64,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: OrbitSpace.gutter,
                            ),
                            child: Row(
                              children: [
                                OrbitAvatar(avatar: c.avatar, size: 44),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: OrbitText(
                                    c.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: t.font.style(
                                      size: OrbitType.headline,
                                      weight: 600,
                                      color: t.ink,
                                      letterSpacingEm: -0.01,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                OrbitPick(
                                  on: _picked.contains(c.id),
                                  corner: 7,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
        if (n > 0)
          OrbitBottomBar(
            children: [
              Expanded(
                child: OrbitButton(
                  label: 'Send to ${n == 1 ? '1 chat' : '$n chats'}',
                  icon: OrbitIcons.paperPlaneTilt,
                  iconWeight: OrbitIconWeight.fill,
                  busy: _busy,
                  block: true,
                  onPressed: _busy ? null : _send,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

/// A page with an app bar and its own column under it (the prototype's
/// `UI.appbar(...)` followed by its parts, without `Kit.page`'s scroll).
class _PageFrame extends StatelessWidget {
  const _PageFrame({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return OrbitPageBackground(
      child: Padding(
        padding: EdgeInsets.only(top: top),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OrbitAppBar(
              title: title,
              onLead: () => Navigator.maybePop(context),
            ),
            ...children,
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------- message info

enum MessageInfoState { loading, error, notFound, ready }

/// One recipient's receipt: "Read Sunday, 18:41", "Delivered …", or
/// "Not delivered yet".
class ReceiptItem {
  const ReceiptItem({
    required this.name,
    required this.avatar,
    this.readLabel,
    this.deliveredLabel,
  });

  final String name;
  final HelixAvatarModel avatar;
  final String? readLabel;
  final String? deliveredLabel;
}

/// One version of an edited message: what it said and when that was.
class MessageEditItem {
  const MessageEditItem({
    required this.text,
    required this.whenLabel,
    this.current = false,
  });

  final String text;
  final String whenLabel;

  /// The version the bubble shows now.
  final bool current;
}

class MessageInfoModel {
  const MessageInfoModel({
    this.loadState = MessageInfoState.ready,
    this.message,
    this.sentLabel = '',
    this.isGroup = false,
    this.recipients = const [],
    this.edits = const [],
  });

  /// Every version of an edited message, the current one first; empty when it
  /// was never edited.
  final List<MessageEditItem> edits;

  final MessageInfoState loadState;
  final HelixMessage? message;
  final String sentLabel;
  final bool isGroup;
  final List<ReceiptItem> recipients;
}

class MessageInfoActions {
  const MessageInfoActions({this.onRetry});

  final VoidCallback? onRetry;
}

/// `message-info`: your message as sent, when it was sent, and who has it.
class MessageInfoScreen extends StatelessWidget {
  const MessageInfoScreen({
    super.key,
    required this.model,
    this.actions = const MessageInfoActions(),
  });

  final MessageInfoModel model;
  final MessageInfoActions actions;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final m = model;
    final msg = m.message;
    return OrbitPage(
      title: 'Message info',
      children: switch (m.loadState) {
        MessageInfoState.loading => const [
          SizedBox(height: 120),
          OrbitPageLoading(),
        ],
        MessageInfoState.error => [
          OrbitLoadFailed(
            title: 'The details could not be loaded.',
            onRetry: actions.onRetry,
          ),
        ],
        MessageInfoState.notFound => const [
          OrbitEmptyState(
            icon: OrbitIcons.chatCircleSlash,
            title: 'Message not found',
            text: 'It may have been deleted.',
          ),
        ],
        MessageInfoState.ready => [
          if (msg != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
              decoration: BoxDecoration(
                color: t.chatBg,
                border: Border(bottom: BorderSide(color: t.line2)),
              ),
              child: OrbitPatternBackground(
                pattern: t.chatPattern,
                color: t.chatBg,
                child: OrbitMessageBubble(message: msg),
              ),
            ),
          OrbitSection(
            rows: [
              OrbitListRow(
                icon: OrbitIcons.paperPlaneTilt,
                iconColor: 0,
                title: 'Sent',
                sub: m.sentLabel,
              ),
            ],
          ),
          if (m.edits.isNotEmpty)
            OrbitSection(
              title: 'Edit history',
              rows: [
                for (final e in m.edits)
                  OrbitListRow(
                    icon: e.current ? OrbitIcons.pencilSimple : null,
                    iconColor: 5,
                    title: e.text,
                    sub: e.current ? 'Now \u00b7 ${e.whenLabel}' : e.whenLabel,
                    minHeight: 52,
                  ),
              ],
            ),
          if (m.recipients.isNotEmpty)
            OrbitSection(
              title: m.isGroup ? 'Recipients' : '',
              rows: [for (final r in m.recipients) _receipt(t, r)],
            ),
        ],
      },
    );
  }

  Widget _receipt(OrbitTokens t, ReceiptItem r) {
    final read = r.readLabel;
    final delivered = r.deliveredLabel;
    return OrbitListRow(
      leading: OrbitAvatar(avatar: r.avatar, size: 40),
      title: r.name,
      sub: read ?? delivered ?? 'Not delivered yet',
      subLeading: read != null
          ? OrbitIcon(
              OrbitIcons.checks,
              weight: OrbitIconWeight.bold,
              size: 13,
              color: t.readTick,
            )
          : delivered != null
          ? OrbitIcon(OrbitIcons.checks, size: 13, color: t.ink3)
          : null,
    );
  }
}

// ------------------------------------------------------------- media viewer

enum ViewerState {
  loading,
  nothingToShow,
  cannotShow,
  viewOnceOpened,
  viewOnceMine,

  /// The message has no photo or video (the app's "There is nothing to show
  /// here.").
  empty,
  ready,
}

/// One picture or video in the viewer. [swatch] is the preview's stand-in.
class ViewerItem {
  const ViewerItem({
    this.isVideo = false,
    this.image,
    this.swatch,
    this.onDevice = true,
  });

  final bool isVideo;

  /// The photo, or a video's still.
  final ImageProvider? image;
  final String? swatch;

  /// False: its page says "This file is not on your device yet."
  final bool onDevice;
}

enum VideoPhase { opening, ready, failed }

/// The video under the current page (`VideoView` in the contract).
class VideoView {
  const VideoView({
    this.phase = VideoPhase.ready,
    this.playing = false,
    this.buffering = false,
    this.completed = false,
    this.fraction = 0,
    this.positionLabel = '0:00',
    this.durationLabel = '0:00',
    this.speed = '1x',
    this.surface,
    this.message,
  });

  final VideoPhase phase;
  final bool playing;
  final bool buffering;
  final bool completed;
  final double fraction;
  final String positionLabel;
  final String durationLabel;
  final String speed;

  /// The app's player (the `videoSurface` slot); null draws the still.
  final Widget? surface;

  /// Why it cannot be played; null is the prototype's sentence.
  final String? message;
}

class MediaViewerModel {
  const MediaViewerModel({
    this.state = ViewerState.ready,
    this.title = '',
    this.timeLabel = '',
    this.caption = '',
    this.items = const [],
    this.initialIndex = 0,
    this.canShare = true,
    this.video,
  });

  final ViewerState state;
  final String title;
  final String timeLabel;
  final String caption;
  final List<ViewerItem> items;
  final int initialIndex;
  final bool canShare;
  final VideoView? video;
}

class MediaViewerActions {
  const MediaViewerActions({
    this.onPageChanged,
    this.onShare,
    this.onOpenVideoElsewhere,
    this.onVideoToggle,
    this.onVideoSeek,
    this.onVideoSpeed,
  });

  final ValueChanged<int>? onPageChanged;
  final ValueChanged<int>? onShare;
  final ValueChanged<int>? onOpenVideoElsewhere;
  final VoidCallback? onVideoToggle;
  final ValueChanged<double>? onVideoSeek;
  final VoidCallback? onVideoSpeed;
}

/// `media-viewer`: a night page. Black, the sender and "(n of m)" in the
/// bar with Share, the picture at 4:3 across the middle, dots for the pages,
/// and the caption under the first. A video adds the 76px play button and
/// the control strip; tapping the video shows or hides them, and they hide
/// 3 seconds after it starts playing.
///
/// The pages follow the finger, and ← and → turn them. A real photo is shown
/// whole and zooms and pans; the preview's stand-ins are the prototype's 4:3.
class MediaViewerScreen extends StatefulWidget {
  const MediaViewerScreen({
    super.key,
    required this.model,
    this.actions = const MediaViewerActions(),
  });

  final MediaViewerModel model;
  final MediaViewerActions actions;

  @override
  State<MediaViewerScreen> createState() => _MediaViewerScreenState();
}

class _MediaViewerScreenState extends State<MediaViewerScreen> {
  late int _i = widget.model.initialIndex;
  late final PageController _pages = PageController(
    initialPage: widget.model.initialIndex,
  );
  var _controls = true;
  Timer? _hide;

  /// While the seek bar is dragged it follows the finger, not the video.
  double? _drag;

  static const _hideAfter = Duration(seconds: 3);

  bool get _playing => widget.model.video?.playing ?? false;

  @override
  void initState() {
    super.initState();
    if (_playing) _scheduleHide();
  }

  @override
  void didUpdateWidget(MediaViewerScreen old) {
    super.didUpdateWidget(old);
    final was = old.model.video?.playing ?? false;
    if (_playing && !was && _controls) _scheduleHide();
    if (!_playing) _hide?.cancel();
  }

  @override
  void dispose() {
    _hide?.cancel();
    _pages.dispose();
    super.dispose();
  }

  void _scheduleHide() {
    _hide?.cancel();
    _hide = Timer(_hideAfter, () {
      if (mounted && _playing) setState(() => _controls = false);
    });
  }

  void _toggleControls() {
    _hide?.cancel();
    setState(() => _controls = !_controls);
    if (_controls && _playing) _scheduleHide();
  }

  void _step(int d) {
    final n = widget.model.items.length;
    if (n == 0) return;
    final i = (_i + d).clamp(0, n - 1);
    if (i == _i) return;
    if (_pages.hasClients) _pages.jumpToPage(i);
    _turned(i);
  }

  void _turned(int i) {
    if (i == _i) return;
    _hide?.cancel();
    setState(() {
      _i = i;
      _controls = true;
      _drag = null;
    });
    widget.actions.onPageChanged?.call(i);
  }

  KeyEventResult _key(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (e.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _step(-1);
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.arrowRight) {
      _step(1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _say(String text) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 260),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: OrbitTokens.of(context).font.style(
          size: OrbitType.body,
          color: OrbitNight.viewerText,
          height: 1.5,
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final m = widget.model;
    final a = widget.actions;
    final top = MediaQuery.paddingOf(context).top;
    final n = m.items.length;
    if (n > 0 && _i >= n) _i = n - 1;
    final message = switch (m.state) {
      ViewerState.nothingToShow => 'This file is not on your device yet.',
      ViewerState.cannotShow => 'This picture cannot be shown.',
      ViewerState.viewOnceOpened =>
        'This view-once message has already been opened.',
      ViewerState.viewOnceMine =>
        'You cannot open a view-once message you sent.',
      ViewerState.empty => 'There is nothing to show here.',
      _ => null,
    };
    final ready = m.state == ViewerState.ready && n > 0;
    final paged =
        m.state == ViewerState.ready || m.state == ViewerState.cannotShow;
    // One picture has no "(1 of 1)".
    final sub = !paged || n == 0
        ? ''
        : n == 1
        ? m.timeLabel
        : '${m.timeLabel} (${_i + 1} of $n)';
    final share =
        paged && m.canShare && (n == 0 || m.items[_i.clamp(0, n - 1)].onDevice);
    Widget body;
    if (message != null) {
      body = Expanded(child: _say(message));
    } else if (m.state == ViewerState.loading || !ready) {
      body = const Expanded(
        child: Center(child: OrbitSpinner(size: 34, color: OrbitNight.text)),
      );
    } else {
      body = Expanded(child: _stage(m, a));
    }
    // `.page.night` outranks `.viewer-page`, so the page is `--night`, not
    // the `#000` that `.viewer-page` asks for.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Focus(
        autofocus: true,
        onKeyEvent: _key,
        child: ColoredBox(
          color: OrbitNight.night,
          child: Padding(
            padding: EdgeInsets.only(top: top),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _bar(
                  context,
                  m.title,
                  sub,
                  share ? () => a.onShare?.call(_i) : null,
                ),
                body,
                if (ready && _i == 0 && m.caption.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 34),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Color(0x99000000), Color(0x00000000)],
                      ),
                    ),
                    child: OrbitText(
                      m.caption,
                      style: OrbitTokens.of(context).font.style(
                        size: 14,
                        color: OrbitNight.caption,
                        height: 1.5,
                      ),
                    ),
                  )
                else if (ready)
                  const SizedBox(height: 34),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _bar(
    BuildContext context,
    String title,
    String sub,
    VoidCallback? share,
  ) {
    final t = OrbitTokens.of(context);
    // 60px, taller only when large text needs it.
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 60),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(
          children: [
            OrbitIconButton(
              icon: OrbitIcons.arrowLeft,
              tooltip: 'Back',
              color: OrbitNight.text,
              onPressed: () => Navigator.maybePop(context),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    OrbitText(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.display(
                        size: 16,
                        color: const Color(0xFFFFFFFF),
                      ),
                    ),
                    if (sub.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: OrbitText(
                          sub,
                          style: t.mono.style(
                            size: OrbitType.meta,
                            color: OrbitNight.viewerSub,
                            letterSpacingEm: 0.04,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (share != null)
              OrbitIconButton(
                icon: OrbitIcons.shareNetwork,
                tooltip: 'Share',
                color: OrbitNight.text,
                onPressed: share,
              ),
          ],
        ),
      ),
    );
  }

  /// `.vp-big`: the 76px round button over a video.
  Widget _big(Widget child, {required String label, VoidCallback? onTap}) {
    Widget disc = Container(
      width: 76,
      height: 76,
      decoration: const BoxDecoration(
        color: Color(0x29FFFFFF),
        shape: BoxShape.circle,
      ),
      child: Center(child: child),
    );
    if (onTap != null) {
      disc = Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: GestureDetector(onTap: onTap, child: disc),
      );
    }
    return Semantics(button: onTap != null, label: label, child: disc);
  }

  /// `.mv-img`: the preview's stand-in fills the width at 4:3, cut by the
  /// stage when taller; a real picture is shown whole.
  Widget _picture(ViewerItem it, {bool zoom = false}) {
    final image = it.image;
    if (image == null) {
      return Center(
        child: LayoutBuilder(
          builder: (context, c) => OverflowBox(
            maxHeight: double.infinity,
            child: SizedBox(
              width: c.maxWidth,
              height: c.maxWidth * 3 / 4,
              child: DecoratedBox(
                decoration: BoxDecoration(gradient: orbitSwatch(it.swatch)),
              ),
            ),
          ),
        ),
      );
    }
    final picture = Center(
      child: Image(
        image: image,
        fit: BoxFit.contain,
        semanticLabel: it.isVideo ? null : 'Photo',
        excludeFromSemantics: it.isVideo,
        errorBuilder: (_, _, _) => it.isVideo
            ? const SizedBox.shrink()
            : _say('This picture cannot be shown.'),
      ),
    );
    return zoom ? InteractiveViewer(maxScale: 6, child: picture) : picture;
  }

  /// One page: a photo, or a video with its controls when it is the current
  /// page (a video beside it is only its still).
  Widget _page(MediaViewerModel m, MediaViewerActions a, int j) {
    final t = OrbitTokens.of(context);
    final it = m.items[j];
    if (!it.onDevice) return _say('This file is not on your device yet.');
    if (!it.isVideo) return _picture(it, zoom: it.image != null);
    final v = j == _i ? m.video : null;
    const white = Color(0xFFFFFFFF);
    final stage = <Widget>[];
    if (v == null) {
      stage
        ..add(_picture(it))
        ..add(
          Center(
            child: _big(
              const OrbitIcon(
                OrbitIcons.play,
                weight: OrbitIconWeight.fill,
                size: 34,
                color: white,
              ),
              label: 'Video',
            ),
          ),
        );
    } else if (v.phase == VideoPhase.failed) {
      stage.add(
        Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const OrbitIcon(
                  OrbitIcons.warningCircle,
                  size: 22,
                  color: OrbitNight.viewerText,
                ),
                const SizedBox(height: 14),
                Text(
                  v.message ?? 'This video cannot be played.',
                  textAlign: TextAlign.center,
                  style: t.font.style(
                    size: OrbitType.body,
                    color: OrbitNight.viewerText,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 14),
                _NightButton(
                  label: 'Open video',
                  onPressed: () => a.onOpenVideoElsewhere?.call(j),
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      final surface = v.phase == VideoPhase.ready ? v.surface : null;
      stage.add(
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggleControls,
            child: surface == null ? _picture(it) : Center(child: surface),
          ),
        ),
      );
      if (v.buffering || v.phase == VideoPhase.opening) {
        stage.add(
          Center(
            child: _big(
              const OrbitSpinner(size: 34, color: white),
              label: 'Loading the video',
            ),
          ),
        );
      } else if (v.completed) {
        stage.add(
          Center(
            child: _big(
              const OrbitIcon(
                OrbitIcons.arrowCounterClockwise,
                weight: OrbitIconWeight.bold,
                size: 34,
                color: white,
              ),
              label: 'Play again',
              onTap: a.onVideoToggle,
            ),
          ),
        );
      } else if (_controls) {
        stage
          ..add(
            Center(
              child: _big(
                OrbitIcon(
                  v.playing ? OrbitIcons.pause : OrbitIcons.play,
                  weight: OrbitIconWeight.fill,
                  size: 34,
                  color: white,
                ),
                label: v.playing ? 'Pause' : 'Play',
                onTap: a.onVideoToggle,
              ),
            ),
          )
          ..add(
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _VideoControls(
                video: v,
                actions: a,
                drag: _drag,
                onDrag: (x) => setState(() => _drag = x),
                onDragEnd: (x) {
                  setState(() => _drag = null);
                  a.onVideoSeek?.call(x);
                },
              ),
            ),
          );
      }
    }
    return Stack(fit: StackFit.expand, children: stage);
  }

  Widget _stage(MediaViewerModel m, MediaViewerActions a) {
    final t = OrbitTokens.of(context);
    final n = m.items.length;
    final stage = <Widget>[
      PageView.builder(
        controller: _pages,
        itemCount: n,
        onPageChanged: _turned,
        itemBuilder: (context, j) => _page(m, a, j),
      ),
    ];
    // A window has no swipe: Previous and Next sit at the sides (`.mv-nav`).
    if (MediaQuery.sizeOf(context).width >= orbitWindowBreakpoint) {
      Widget nav(bool next) => OrbitIconButton(
        icon: next ? OrbitIcons.caretRight : OrbitIcons.caretLeft,
        tooltip: next ? 'Next' : 'Previous',
        size: 52,
        iconSize: 24,
        color: OrbitNight.text,
        onPressed: () => _step(next ? 1 : -1),
      );
      Widget disc(Widget b) => ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: ColoredBox(color: t.scrim, child: b),
        ),
      );
      if (_i > 0) {
        stage.add(
          Positioned(
            left: 20,
            top: 0,
            bottom: 0,
            child: Center(child: disc(nav(false))),
          ),
        );
      }
      if (_i < n - 1) {
        stage.add(
          Positioned(
            right: 20,
            top: 0,
            bottom: 0,
            child: Center(child: disc(nav(true))),
          ),
        );
      }
    }
    if (n > 1) {
      stage.add(
        Positioned(
          left: 0,
          right: 0,
          bottom: 14,
          child: IgnorePointer(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var j = 0; j < n; j++) ...[
                  if (j > 0) const SizedBox(width: 6),
                  Container(
                    width: j == _i ? 16 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: j == _i
                          ? const Color(0xFFFFFFFF)
                          : const Color(0x59FFFFFF),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }
    return ClipRect(
      child: Stack(fit: StackFit.expand, children: stage),
    );
  }
}

/// `.vp-ctrl`: the time, the seek bar, the length and the speed, mono 12px
/// white over a fade to black, 12px 14px 30px in.
class _VideoControls extends StatelessWidget {
  const _VideoControls({
    required this.video,
    required this.actions,
    required this.drag,
    required this.onDrag,
    required this.onDragEnd,
  });

  final VideoView video;
  final MediaViewerActions actions;
  final double? drag;
  final ValueChanged<double> onDrag;
  final ValueChanged<double> onDragEnd;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final mono = t.mono.style(size: 12, color: const Color(0xFFFFFFFF));
    // `12px 14px 30px` around a 30px row, drawn as a 48px row with 9px
    // less above and below, so the speed chip's 48px target is inside it;
    // the right-hand 14px is in the row for the same reason.
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 3, 0, 21),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0xB3000000), Color(0x00000000)],
        ),
      ),
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            Text(video.positionLabel, style: mono),
            const SizedBox(width: 10),
            Expanded(
              child: SliderTheme(
                data: const SliderThemeData(
                  trackHeight: 4,
                  activeTrackColor: Color(0xFFFFFFFF),
                  inactiveTrackColor: Color(0x59FFFFFF),
                  thumbColor: Color(0xFFFFFFFF),
                  overlayShape: RoundSliderOverlayShape(overlayRadius: 0),
                  thumbShape: RoundSliderThumbShape(enabledThumbRadius: 8),
                ),
                child: Slider(
                  value: (drag ?? video.fraction).clamp(0.0, 1.0),
                  onChanged: actions.onVideoSeek == null ? null : onDrag,
                  onChangeEnd: onDragEnd,
                  semanticFormatterCallback: (_) =>
                      '${video.positionLabel} of ${video.durationLabel}',
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(video.durationLabel, style: mono),
            const SizedBox(width: 10),
            // Outermost, so a touch just outside the chip reaches it.
            OrbitTapArea(
              child: Tooltip(
                message: 'Playback speed',
                excludeFromSemantics: true,
                child: Semantics(
                  button: true,
                  label: 'Playback speed ${video.speed}',
                  child: GestureDetector(
                    onTap: actions.onVideoSpeed,
                    child: Container(
                      height: 30,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0x66FFFFFF)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(video.speed, style: mono),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
          ],
        ),
      ),
    );
  }
}

/// The secondary button as the viewer draws it: `--night-3` with a lighter
/// edge and white text.
class _NightButton extends StatelessWidget {
  const _NightButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    return Material(
      color: OrbitNight.buttonBg,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: OrbitNight.buttonLine),
        borderRadius: BorderRadius.circular(t.rMd),
      ),
      child: InkWell(
        onTap: onPressed,
        splashFactory: NoSplash.splashFactory,
        customBorder: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(t.rMd),
        ),
        child: SizedBox(
          height: 48,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Center(
              widthFactor: 1,
              child: Text(
                label,
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
    );
  }
}

// --------------------------------------------------------------- send files

enum SendFileKind { image, video, audio, document }

class SendFileItem {
  const SendFileItem({
    required this.id,
    required this.name,
    required this.sizeLabel,
    required this.kind,
    this.preview,
    this.swatch,
  });

  final String id;
  final String name;
  final String sizeLabel;
  final SendFileKind kind;
  final ImageProvider? preview;

  /// The preview's stand-in picture.
  final String? swatch;
}

class SendFilesModel {
  const SendFilesModel({this.files = const []});

  final List<SendFileItem> files;

  bool get showViewOnce => files.any(
    (f) => f.kind == SendFileKind.image || f.kind == SendFileKind.video,
  );
}

class SendFilesActions {
  const SendFilesActions({this.onRemove, this.onSend});

  final ValueChanged<String>? onRemove;

  /// True when sent: the screen goes back to the chat.
  final Future<bool> Function({
    required String caption,
    required bool viewOnce,
  })?
  onSend;
}

/// `send-files`: what is about to be sent. A card of files (48px thumbnails,
/// the name and the size in mono, × to drop one), the View once switch for
/// photos and videos, the note about location details, and the caption
/// field with Send in the bottom bar.
class SendFilesScreen extends StatefulWidget {
  const SendFilesScreen({
    super.key,
    required this.model,
    this.actions = const SendFilesActions(),
  });

  final SendFilesModel model;
  final SendFilesActions actions;

  @override
  State<SendFilesScreen> createState() => _SendFilesScreenState();
}

class _SendFilesScreenState extends State<SendFilesScreen> {
  final _caption = TextEditingController();
  var _viewOnce = false;
  var _busy = false;

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() => _busy = true);
    final ok =
        await widget.actions.onSend?.call(
          caption: _caption.text,
          viewOnce: _viewOnce,
        ) ??
        true;
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.maybePop(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final m = widget.model;
    final n = m.files.length;
    if (n == 0) {
      return const OrbitPage(
        title: 'Send file',
        children: [
          OrbitEmptyState(
            icon: OrbitIcons.paperclip,
            title: 'Nothing to send',
            text: 'Go back and pick a file.',
          ),
        ],
      );
    }
    return _PageFrame(
      title: n == 1 ? 'Send file' : 'Send $n files',
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(top: 14, bottom: 16),
            children: [
              OrbitCard(children: [for (final f in m.files) _file(t, f)]),
              if (m.showViewOnce)
                OrbitSection(
                  rows: [
                    OrbitListRow(
                      icon: OrbitIcons.numberCircleOne,
                      iconColor: 0,
                      title: 'View once',
                      sub: 'Photos and videos disappear after they are opened.',
                      end: OrbitRowEnd.toggle,
                      on: _viewOnce,
                      onChanged: (v) => setState(() => _viewOnce = v),
                    ),
                  ],
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // `.sec-foot` as a row: the 12px shield on the first
                    // line, 6px before the text.
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: OrbitIcon(
                        OrbitIcons.shieldCheck,
                        size: 12,
                        color: t.ink3,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: OrbitText(
                        'Location details are removed from photos and videos '
                        'before they are sent.',
                        style: t.font.style(
                          size: OrbitType.caption,
                          color: t.ink3,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        OrbitBottomBar(
          children: [
            Expanded(
              child: Container(
                constraints: const BoxConstraints(minHeight: 48),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(
                  color: t.field,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: TextField(
                  controller: _caption,
                  minLines: 1,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  style: t.font.style(size: 15, color: t.ink),
                  decoration: InputDecoration.collapsed(
                    hintText: 'Add a caption',
                    hintStyle: t.font.style(size: 15, color: t.ink4),
                  ),
                ),
              ),
            ),
            Tooltip(
              message: 'Send',
              excludeFromSemantics: true,
              child: Semantics(
                button: true,
                label: 'Send',
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: t.glow,
                  ),
                  child: Material(
                    color: t.accent,
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: _busy ? null : _send,
                      splashFactory: NoSplash.splashFactory,
                      child: Center(
                        child: _busy
                            ? OrbitSpinner(size: 21, color: t.onAccent)
                            : OrbitIcon(
                                OrbitIcons.paperPlaneTilt,
                                weight: OrbitIconWeight.fill,
                                size: 21,
                                color: t.onAccent,
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _file(OrbitTokens t, SendFileItem f) {
    final photo = f.kind == SendFileKind.image || f.kind == SendFileKind.video;
    final (docBg, docInk) = OrbitAvatar.palette(t, 3);
    final thumb = Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: photo ? null : docBg,
        gradient: photo && f.preview == null ? orbitSwatch(f.swatch) : null,
        image: f.preview == null
            ? null
            : DecorationImage(image: f.preview!, fit: BoxFit.cover),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Center(
        child: f.kind == SendFileKind.video
            ? const OrbitIcon(
                OrbitIcons.play,
                weight: OrbitIconWeight.fill,
                size: 19,
                color: Color(0xFFFFFFFF),
              )
            : photo
            ? null
            : OrbitIcon(
                f.kind == SendFileKind.audio
                    ? OrbitIcons.headphones
                    : OrbitIcons.filePdf,
                weight: OrbitIconWeight.fill,
                size: 19,
                color: docInk,
              ),
      ),
    );
    return OrbitListRow(
      leading: thumb,
      title: f.name,
      sub: f.sizeLabel,
      subMono: true,
      trailing: OrbitIconButton(
        icon: OrbitIcons.x,
        tooltip: 'Remove ${f.name}',
        onPressed: () => widget.actions.onRemove?.call(f.id),
      ),
    );
  }
}

// ------------------------------------------------------------- shared media

enum SharedTab { media, docs, links }

class SharedTileItem {
  const SharedTileItem({
    this.thumbnail,
    this.swatch,
    this.isVideo = false,
    this.durationLabel = '',
    this.label = '',
  });

  final ImageProvider? thumbnail;
  final String? swatch;
  final bool isVideo;
  final String durationLabel;

  /// For screen readers: "Photo, today".
  final String label;
}

class SharedDocItem {
  const SharedDocItem({required this.name, required this.detail});

  final String name;

  /// "4.2 MB · PDF · Yesterday".
  final String detail;
}

class SharedLinkItem {
  const SharedLinkItem({
    required this.url,
    required this.detail,
    this.messageId = '',
  });

  final String url;

  /// "helix.agiletechbd.com, today".
  final String detail;
  final String messageId;
}

class SharedMediaModel {
  const SharedMediaModel({
    required this.title,
    this.initialTab = SharedTab.media,
    this.filesState = LoadState.ready,
    this.linksState = LoadState.ready,
    this.media = const [],
    this.documents = const [],
    this.links = const [],
  });

  final String title;
  final SharedTab initialTab;
  final LoadState filesState;
  final LoadState linksState;
  final List<SharedTileItem> media;
  final List<SharedDocItem> documents;
  final List<SharedLinkItem> links;
}

class SharedMediaActions {
  const SharedMediaActions({
    this.onOpenMedia,
    this.onOpenDocument,
    this.onOpenLink,
    this.onShowInChat,
    this.onRetry,
  });

  final ValueChanged<int>? onOpenMedia;
  final ValueChanged<int>? onOpenDocument;
  final ValueChanged<String>? onOpenLink;
  final ValueChanged<String>? onShowInChat;
  final VoidCallback? onRetry;
}

/// `shared`: Media, Docs and Links tabs for one chat, each with its own
/// empty state.
class SharedMediaScreen extends StatefulWidget {
  const SharedMediaScreen({
    super.key,
    required this.model,
    this.actions = const SharedMediaActions(),
  });

  final SharedMediaModel model;
  final SharedMediaActions actions;

  @override
  State<SharedMediaScreen> createState() => _SharedMediaScreenState();
}

class _SharedMediaScreenState extends State<SharedMediaScreen> {
  late var _tab = widget.model.initialTab;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final m = widget.model;
    final a = widget.actions;
    final state = _tab == SharedTab.links ? m.linksState : m.filesState;
    Widget body;
    if (state != LoadState.ready) {
      body = _loadBody(state, 'This could not be loaded.', a.onRetry);
    } else {
      body = switch (_tab) {
        SharedTab.media when m.media.isEmpty => _empty(
          OrbitIcons.images,
          'No media yet',
          'Photos and videos you share in this chat show up here.',
        ),
        SharedTab.docs when m.documents.isEmpty => _empty(
          OrbitIcons.fileText,
          'No documents yet',
          'Files you share in this chat show up here.',
        ),
        SharedTab.links when m.links.isEmpty => _empty(
          OrbitIcons.linkSimple,
          'No links yet',
          'Web links sent in this chat show up here.',
        ),
        SharedTab.media => GridView.count(
          crossAxisCount: 3,
          mainAxisSpacing: 3,
          crossAxisSpacing: 3,
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
          children: [for (final (i, it) in m.media.indexed) _tile(t, i, it)],
        ),
        SharedTab.docs => ListView(
          padding: const EdgeInsets.only(top: 12),
          children: [
            OrbitCard(
              children: [
                for (final (i, d) in m.documents.indexed)
                  OrbitListRow(
                    icon: OrbitIcons.fileText,
                    iconColor: 3,
                    iconWeight: OrbitIconWeight.fill,
                    title: d.name,
                    sub: d.detail,
                    onTap: () => a.onOpenDocument?.call(i),
                  ),
              ],
            ),
          ],
        ),
        SharedTab.links => ListView(
          padding: const EdgeInsets.only(top: 12),
          children: [
            OrbitCard(
              children: [
                for (final l in m.links)
                  OrbitListRow(
                    icon: OrbitIcons.linkSimple,
                    iconColor: 1,
                    title: l.url,
                    titleWidget: OrbitText(
                      l.url,
                      style: t.mono.style(
                        size: 12.5,
                        color: t.ink,
                        height: 1.4,
                      ),
                    ),
                    sub: l.detail,
                    onTap: () => a.onOpenLink?.call(l.url),
                    trailing: OrbitIconButton(
                      icon: OrbitIcons.chatCircle,
                      tooltip: 'Show in chat',
                      onPressed: () => a.onShowInChat?.call(l.messageId),
                    ),
                  ),
              ],
            ),
          ],
        ),
      };
    }
    return _PageFrame(
      title: m.title,
      children: [
        OrbitTabs(
          labels: const ['Media', 'Docs', 'Links'],
          index: _tab.index,
          onChanged: (i) => setState(() => _tab = SharedTab.values[i]),
        ),
        Expanded(child: body),
      ],
    );
  }

  Widget _empty(OrbitGlyph icon, String title, String text) => ListView(
    children: [OrbitEmptyState(icon: icon, title: title, text: text)],
  );

  Widget _tile(OrbitTokens t, int i, SharedTileItem it) => Semantics(
    button: true,
    label: it.label.isEmpty ? null : it.label,
    child: GestureDetector(
      onTap: () => widget.actions.onOpenMedia?.call(i),
      child: Container(
        decoration: BoxDecoration(
          color: t.mediaPh,
          gradient: it.thumbnail == null ? orbitSwatch(it.swatch) : null,
          image: it.thumbnail == null
              ? null
              : DecorationImage(image: it.thumbnail!, fit: BoxFit.cover),
          borderRadius: BorderRadius.circular(4),
        ),
        child: it.isVideo
            ? Align(
                alignment: Alignment.bottomLeft,
                child: Container(
                  margin: const EdgeInsets.all(8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0x8C090C15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const OrbitIcon(
                        OrbitIcons.playCircle,
                        weight: OrbitIconWeight.fill,
                        size: 10.5,
                        color: Color(0xFFFFFFFF),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        it.durationLabel,
                        style: t.mono.style(
                          size: 10.5,
                          color: const Color(0xFFFFFFFF),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : null,
      ),
    ),
  );
}

// ------------------------------------------------------------ chat settings

class ChatSettingsModel {
  const ChatSettingsModel({
    required this.title,
    required this.avatar,
    this.loading = false,
    this.subtitle,
    this.isGroup = false,
    this.hasInfoPage = true,
    this.muted = false,
    this.muteChoices = const [
      (id: '8h', label: '8 hours'),
      (id: '1w', label: '1 week'),
      (id: 'always', label: 'Always'),
    ],
    this.disappearingLabel = 'Off',
    this.disappearingSeconds,
    this.disappearingChoices = const [
      (seconds: null, label: 'Off'),
      (seconds: 300, label: '5 minutes'),
      (seconds: 3600, label: '1 hour'),
      (seconds: 86400, label: '1 day'),
      (seconds: 604800, label: '1 week'),
      (seconds: 7776000, label: '90 days'),
    ],
    this.blocked = false,
    this.wallpaper,
    this.bubbleTint = HelixBubbleTint.theme,
    this.locked = false,
  });

  final bool loading;

  /// This chat's own wallpaper; null follows the one for all chats.
  final HelixWallpaper? wallpaper;

  /// The colour of your own bubbles in this chat.
  final HelixBubbleTint bubbleTint;

  /// The chat is locked.
  final bool locked;
  final String title;
  final String? subtitle;
  final HelixAvatarModel avatar;
  final bool isGroup;
  final bool hasInfoPage;
  final bool muted;
  final List<({String id, String label})> muteChoices;
  final String disappearingLabel;
  final int? disappearingSeconds;
  final List<({int? seconds, String label})> disappearingChoices;
  final bool blocked;
}

class ChatSettingsActions {
  const ChatSettingsActions({
    this.onOpenInfo,
    this.onOpenSharedMedia,
    this.onMute,
    this.onSetDisappearing,
    this.onClear,
    this.onBlock,
    this.onUnblock,
    this.onSetWallpaper,
    this.onSetBubbleTint,
    this.onSetLocked,
  });

  /// Gives the chat its own wallpaper; null goes back to the one for all
  /// chats. With it set, the page offers Wallpaper.
  final ValueChanged<HelixWallpaper?>? onSetWallpaper;

  /// Gives your bubbles in this chat a colour. With it set, the page offers
  /// Bubble colour.
  final ValueChanged<HelixBubbleTint>? onSetBubbleTint;

  /// Locks the chat, or unlocks it. With it set, the page offers Lock chat.
  final ValueChanged<bool>? onSetLocked;
  final VoidCallback? onOpenInfo;
  final VoidCallback? onOpenSharedMedia;

  /// Null unmutes.
  final ValueChanged<String?>? onMute;
  final ValueChanged<int?>? onSetDisappearing;
  final VoidCallback? onClear;
  final VoidCallback? onBlock;
  final VoidCallback? onUnblock;
}

/// `chat-settings`: the chat's picture and name, then Contact or Group
/// info, Media, Mute and Disappearing messages; then Clear chat and Block.
class ChatSettingsScreen extends StatelessWidget {
  const ChatSettingsScreen({
    super.key,
    required this.model,
    this.actions = const ChatSettingsActions(),
  });

  final ChatSettingsModel model;
  final ChatSettingsActions actions;

  @override
  Widget build(BuildContext context) {
    final m = model;
    final a = actions;
    if (m.loading) {
      return const OrbitPage(
        title: 'Chat settings',
        children: [SizedBox(height: 120), OrbitPageLoading()],
      );
    }
    return OrbitPage(
      title: 'Chat settings',
      children: [
        OrbitProfileHero(
          avatar: m.avatar,
          name: m.title,
          sub: m.subtitle ?? '',
        ),
        OrbitSection(
          rows: [
            if (m.hasInfoPage)
              m.isGroup
                  ? OrbitListRow(
                      icon: OrbitIcons.usersThree,
                      iconColor: 0,
                      title: 'Group info',
                      sub: 'Members, invite links and group settings',
                      end: OrbitRowEnd.chevron,
                      onTap: a.onOpenInfo,
                    )
                  : OrbitListRow(
                      icon: OrbitIcons.userCircle,
                      iconColor: 0,
                      title: 'Contact info',
                      sub: 'Name, number and safety number',
                      end: OrbitRowEnd.chevron,
                      onTap: a.onOpenInfo,
                    ),
            OrbitListRow(
              icon: OrbitIcons.images,
              iconColor: 2,
              title: 'Media, links and docs',
              end: OrbitRowEnd.chevron,
              onTap: a.onOpenSharedMedia,
            ),
            OrbitListRow(
              icon: OrbitIcons.bellSlash,
              iconColor: 4,
              title: 'Mute notifications',
              sub: m.muted ? 'Muted' : 'Off',
              end: OrbitRowEnd.chevron,
              onTap: () => showOrbitSheet(
                context,
                title: 'Mute notifications',
                items: [
                  for (final c in m.muteChoices)
                    OrbitMenuItem(
                      icon: OrbitIcons.bellSlash,
                      label: c.label,
                      onTap: () => a.onMute?.call(c.id),
                    ),
                  if (m.muted)
                    OrbitMenuItem(
                      icon: OrbitIcons.speakerHigh,
                      label: 'Unmute',
                      onTap: () => a.onMute?.call(null),
                    ),
                ],
              ),
            ),
            OrbitListRow(
              icon: OrbitIcons.timer,
              iconColor: 5,
              title: 'Disappearing messages',
              value: m.disappearingLabel,
              end: OrbitRowEnd.chevron,
              onTap: () => showOrbitSheet(
                context,
                title: 'Disappearing messages',
                items: [
                  for (final c in m.disappearingChoices)
                    OrbitMenuItem(
                      icon: OrbitIcons.timer,
                      label: c.label,
                      on: c.seconds == m.disappearingSeconds,
                      onTap: () => a.onSetDisappearing?.call(c.seconds),
                    ),
                ],
              ),
            ),
            if (a.onSetLocked != null)
              OrbitListRow(
                icon: OrbitIcons.lock,
                iconColor: 3,
                title: 'Lock chat',
                sub:
                    'Keeps it in Locked chats, behind your phone’s unlock. '
                    'Notifications show no name or text.',
                end: OrbitRowEnd.toggle,
                on: m.locked,
                onChanged: a.onSetLocked,
              ),
            if (a.onSetWallpaper != null)
              OrbitListRow(
                icon: OrbitIcons.palette,
                iconColor: 3,
                title: 'Wallpaper',
                value: m.wallpaper?.label ?? 'Same as all chats',
                end: OrbitRowEnd.chevron,
                onTap: () => showOrbitWallpaperSheet(
                  context,
                  current: m.wallpaper,
                  allowDefault: true,
                  onPick: a.onSetWallpaper!,
                ),
              ),
            if (a.onSetBubbleTint != null)
              OrbitListRow(
                icon: OrbitIcons.palette,
                iconColor: 1,
                title: 'Bubble colour',
                value: m.bubbleTint.label,
                end: OrbitRowEnd.chevron,
                onTap: () => showOrbitSheet(
                  context,
                  title: 'Bubble colour',
                  text: 'The colour of your own messages in this chat.',
                  items: [
                    for (final tint in HelixBubbleTint.values)
                      OrbitMenuItem(
                        icon: OrbitIcons.palette,
                        label: tint.label,
                        on: tint == m.bubbleTint,
                        onTap: () => a.onSetBubbleTint!(tint),
                      ),
                  ],
                ),
              ),
          ],
        ),
        OrbitSection(
          rows: [
            OrbitListRow(
              icon: OrbitIcons.eraser,
              title: 'Clear chat',
              danger: true,
              onTap: () => showOrbitDialog(
                context,
                title: 'Clear this chat?',
                text:
                    'All messages are removed from this device. The chat '
                    'stays in your list.',
                actions: [
                  const OrbitDialogAction('Cancel'),
                  OrbitDialogAction(
                    'Clear',
                    kind: OrbitButtonKind.danger,
                    onPressed: a.onClear,
                  ),
                ],
              ),
            ),
            if (!m.isGroup)
              m.blocked
                  ? OrbitListRow(
                      icon: OrbitIcons.prohibit,
                      title: 'Unblock ${m.title}',
                      onTap: a.onUnblock,
                    )
                  : OrbitListRow(
                      icon: OrbitIcons.prohibit,
                      title: 'Block ${m.title}',
                      danger: true,
                      onTap: () => showOrbitDialog(
                        context,
                        title: 'Block ${m.title}?',
                        text:
                            'They will not be able to message or call you, '
                            'and Orbit tells them that you blocked them. You '
                            'can unblock them here at any time.',
                        actions: [
                          const OrbitDialogAction('Cancel'),
                          OrbitDialogAction(
                            'Block',
                            kind: OrbitButtonKind.danger,
                            onPressed: a.onBlock,
                          ),
                        ],
                      ),
                    ),
          ],
        ),
      ],
    );
  }
}
