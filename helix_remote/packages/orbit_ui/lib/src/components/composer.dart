import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:orbit_ui/src/components/avatar.dart';
import 'package:orbit_ui/src/components/icon_button.dart';
import 'package:orbit_ui/src/icons/orbit_glyph.dart';
import 'package:orbit_ui/src/icons/orbit_icons.dart';
import 'package:orbit_ui/src/models/view_models.dart';
import 'package:orbit_ui/src/theme/motion.dart';
import 'package:orbit_ui/src/theme/orbit_metrics.dart';
import 'package:orbit_ui/src/theme/orbit_text.dart';
import 'package:orbit_ui/src/theme/orbit_tokens.dart';

/// Where a voice recording is.
enum OrbitRecording {
  /// Not recording.
  none,

  /// Holding the mic: "Slide to cancel", and the lock above to keep going.
  hold,

  /// Locked: the waveform so far, delete and send.
  locked,
}

/// What the composer's actions do. Everything is optional, so a preview can
/// pass only what it shows.
class OrbitComposerActions {
  const OrbitComposerActions({
    this.onSend,
    this.onMic,
    this.onAttach,
    this.onCamera,
    this.onEmoji,
    this.onCancelBanner,
    this.onCancelRecording,
    this.onSendRecording,
    this.onChanged,
    this.onMention,
    this.onPickMention,
    this.onTextChanged,
    this.onVoiceStart,
    this.onVoiceSlide,
    this.onVoiceLock,
    this.onVoiceEnd,
  });

  /// A person was picked from the mention list (their display name).
  final ValueChanged<String>? onMention;

  /// The same pick, with the whole person (the app inserts "@Name ").
  final ValueChanged<HelixPersonItem>? onPickMention;

  final ValueChanged<String>? onSend;

  /// A plain tap on the mic (not held).
  final VoidCallback? onMic;
  final VoidCallback? onAttach;
  final VoidCallback? onCamera;
  final VoidCallback? onEmoji;
  final VoidCallback? onCancelBanner;
  final VoidCallback? onCancelRecording;
  final VoidCallback? onSendRecording;
  final ValueChanged<String>? onChanged;

  /// The text or the cursor changed: the text and where the cursor is.
  final void Function(String text, int cursor)? onTextChanged;

  /// The mic was held long enough to record.
  final VoidCallback? onVoiceStart;

  /// The held finger moved: how far towards cancelling (sideways, 120px) and
  /// towards the lock (up, 80px), each 0..1.
  final void Function(double cancel, double lock)? onVoiceSlide;

  /// Slid onto the lock: keep recording hands-free.
  final VoidCallback? onVoiceLock;

  /// The hold ended: let go ([send] true) or slid away to cancel (false).
  final void Function({required bool send})? onVoiceEnd;
}

/// `.composer` (`css/screens.css`; `composer()` in
/// `js/screens/conversation.js`): the bottom of a chat.
///
/// `--surface` with a `--line-2` rule on top, 8px in and 26px at the bottom.
/// A reply or edit [banner] over a row of the field and the round button, 4px
/// apart and lined up at the bottom:
/// - the field is a 48px pill on `--field` (`--surface` with an
///   `--accent-line` edge while focused): emoji, the text (`--t-body`, line
///   height 1.4, up to 128px tall), attach, and the camera while empty;
/// - the button is the mic (`--inverse`) while empty, send (`--accent` with
///   `--glow`) with text, or a tick when editing (faded until there is text).
///
/// [recording] replaces the field with the recording strip; [disabled]
/// replaces the whole composer with the reason a message cannot be sent.
///
/// The 26px is paid to the screen edge, so the box adds the Android
/// navigation-bar inset below it: a phone with the three buttons would
/// otherwise draw them over the field.
class OrbitComposer extends StatefulWidget {
  const OrbitComposer({
    super.key,
    this.initialText = '',
    this.banner,
    this.recording = OrbitRecording.none,
    this.recordingTime = '0:07',
    this.recordingWave = const [],
    this.disabled,
    this.disabledIcon = false,
    this.emojiOpen = false,
    this.mentions = const [],
    this.attachKey,
    this.actions = const OrbitComposerActions(),
    this.controller,
    this.focusNode,
    this.enterSends = false,
  });

  /// The field's text, when the caller owns it (to fill it for an edit,
  /// insert an emoji at the cursor, or save it as a draft); [initialText]
  /// is then ignored.
  final TextEditingController? controller;
  final FocusNode? focusNode;

  /// Enter sends (Shift+Enter always adds a line); otherwise Enter adds a
  /// line.
  final bool enterSends;

  /// People an "@" in a group can mention (`.mentions`): shown over the
  /// field while there are any.
  final List<HelixPersonItem> mentions;

  /// On the paperclip, so a window can hang the attach sheet above it.
  final GlobalKey? attachKey;

  final String initialText;
  final HelixComposerBannerModel? banner;
  final OrbitRecording recording;
  final String recordingTime;
  final List<int> recordingWave;

  /// Why nothing can be sent here, in place of the composer.
  final String? disabled;

  /// The reason starts with the "prohibited" sign (a block).
  final bool disabledIcon;
  final bool emojiOpen;
  final OrbitComposerActions actions;

  @override
  State<OrbitComposer> createState() => _OrbitComposerState();
}

class _OrbitComposerState extends State<OrbitComposer> {
  TextEditingController? _ownText;
  FocusNode? _ownFocus;
  final _micKey = GlobalKey(debugLabel: 'mic');

  TextEditingController get _text => widget.controller ?? _ownText!;
  FocusNode get _focus => widget.focusNode ?? _ownFocus!;

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) {
      _ownText = TextEditingController(text: widget.initialText);
    }
    if (widget.focusNode == null) _ownFocus = FocusNode();
    _text.addListener(_changed);
    _focus.addListener(_changed);
  }

  @override
  void didUpdateWidget(OrbitComposer old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      (old.controller ?? _ownText)?.removeListener(_changed);
      if (widget.controller == null) {
        _ownText ??= TextEditingController(text: widget.initialText);
      }
      _text.addListener(_changed);
    }
    if (old.focusNode != widget.focusNode) {
      (old.focusNode ?? _ownFocus)?.removeListener(_changed);
      if (widget.focusNode == null) _ownFocus ??= FocusNode();
      _focus.addListener(_changed);
    }
  }

  @override
  void dispose() {
    _text.removeListener(_changed);
    _focus.removeListener(_changed);
    _ownText?.dispose();
    _ownFocus?.dispose();
    super.dispose();
  }

  /// Enter sends when [OrbitComposer.enterSends]; Shift+Enter is a new line.
  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (!widget.enterSends || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final enter =
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;
    if (!enter || HardwareKeyboard.instance.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    if (_text.text.trim().isNotEmpty) widget.actions.onSend?.call(_text.text);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final w = widget;
    // A phone driven by the three navigation buttons draws that bar over the
    // bottom of every window, so the box - which is where a thumb reaches for
    // the field - rides above it, the way the dock does. `viewPadding` and not
    // `padding`: the app already lifts everything above the keyboard, and an
    // inset that moves with it would lift the field twice. With the emoji panel
    // open the composer is not the bottom strip and the panel pays for the bar.
    final navBar = w.emojiOpen ? 0.0 : MediaQuery.viewPaddingOf(context).bottom;
    final reason = w.disabled;
    if (reason != null) {
      final style = t.font.style(
        size: OrbitType.small,
        color: t.ink3,
        height: 1.45,
      );
      return Container(
        padding: EdgeInsets.fromLTRB(18, 14, 18, 30 + navBar),
        decoration: BoxDecoration(
          color: t.surface,
          border: Border(top: BorderSide(color: t.line2)),
        ),
        child: OrbitText.rich(
          TextSpan(
            children: [
              if (w.disabledIcon) ...[
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: OrbitIcon(
                    OrbitIcons.prohibit,
                    size: OrbitType.small,
                    color: t.ink3,
                  ),
                ),
                const TextSpan(text: ' '),
              ],
              TextSpan(text: reason),
            ],
          ),
          textAlign: TextAlign.center,
          style: style,
        ),
      );
    }

    final banner = w.banner;
    final row = switch (w.recording) {
      OrbitRecording.none => _typing(t),
      _ => _recording(t),
    };
    return Container(
      padding: EdgeInsets.fromLTRB(8, 8, 8, 26 + navBar),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border(top: BorderSide(color: t.line2)),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (banner != null && w.recording == OrbitRecording.none)
                _Banner(model: banner, onCancel: w.actions.onCancelBanner),
              if (w.mentions.isNotEmpty && w.recording == OrbitRecording.none)
                _Mentions(
                  people: w.mentions,
                  onPick: (p) {
                    w.actions.onPickMention?.call(p);
                    w.actions.onMention?.call(p.names.display);
                  },
                ),
              row,
            ],
          ),
          if (w.recording == OrbitRecording.hold)
            // `.lock-pill`: 12px from the right and 96px up from the bottom
            // edge, which the box's own 26px padding puts above the field -
            // measured from the field rather than from that edge, so on a
            // phone with navigation buttons the pill rises with the row
            // instead of settling against the bar.
            Positioned(right: 12 - 8, bottom: 96 - 26, child: _LockPill()),
        ],
      ),
    );
  }

  Widget _typing(OrbitTokens t) {
    final w = widget;
    final has = _text.text.trim().isNotEmpty;
    final editing = w.banner?.kind == HelixComposerBannerKind.edit;
    final focused = _focus.hasFocus;
    final text = t.font.style(size: OrbitType.body, color: t.ink);
    Widget fieldButton(OrbitGlyph icon, String tip, VoidCallback? on) =>
        OrbitIconButton(
          icon: icon,
          tooltip: tip,
          onPressed: on,
          size: 44,
          iconSize: 21,
          color: t.ink3,
          height: 46,
        );
    final field = Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: focused ? t.surface : t.field,
        border: Border.all(color: focused ? t.accentLine : Colors.transparent),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          fieldButton(
            w.emojiOpen ? OrbitIcons.keyboard : OrbitIcons.smiley,
            w.emojiOpen ? 'Keyboard' : 'Emoji',
            w.actions.onEmoji,
          ),
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 46, maxHeight: 128),
              // The 12px above and below are the input's own, so the whole
              // field height is what a finger (and a screen reader) gets.
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Focus(
                  canRequestFocus: false,
                  skipTraversal: true,
                  onKeyEvent: _key,
                  child: TextField(
                    controller: _text,
                    focusNode: _focus,
                    minLines: 1,
                    maxLines: 5,
                    keyboardType: TextInputType.multiline,
                    onChanged: (value) {
                      w.actions.onChanged?.call(value);
                      w.actions.onTextChanged?.call(
                        value,
                        _text.selection.baseOffset,
                      );
                    },
                    style: text,
                    cursorColor: t.accent,
                    cursorHeight: OrbitType.body * 1.2,
                    decoration:
                        InputDecoration.collapsed(
                          hintText: 'Message',
                          hintStyle: text.copyWith(color: t.ink4),
                        ).copyWith(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 12,
                          ),
                        ),
                  ),
                ),
              ),
            ),
          ),
          KeyedSubtree(
            key: w.attachKey,
            child: fieldButton(
              OrbitIcons.paperclip,
              'Attach',
              w.actions.onAttach,
            ),
          ),
          if (!has)
            fieldButton(OrbitIcons.camera, 'Camera', w.actions.onCamera),
        ],
      ),
    );
    final Widget action;
    if (editing) {
      action = Opacity(
        opacity: has ? 1 : 0.45,
        child: _RoundButton(
          icon: OrbitIcons.check,
          weight: OrbitIconWeight.bold,
          tooltip: 'Save edit',
          color: t.accent,
          ink: t.onAccent,
          glow: true,
          onPressed: has ? () => w.actions.onSend?.call(_text.text) : null,
        ),
      );
    } else if (has) {
      action = _RoundButton(
        icon: OrbitIcons.paperPlaneTilt,
        weight: OrbitIconWeight.fill,
        tooltip: 'Send',
        color: t.accent,
        ink: t.onAccent,
        glow: true,
        onPressed: () => w.actions.onSend?.call(_text.text),
      );
    } else {
      action = _mic(
        _RoundButton(
          icon: OrbitIcons.microphone,
          weight: OrbitIconWeight.fill,
          tooltip: 'Record a voice message',
          color: t.inverse,
          ink: t.onInverse,
          glow: true,
          onPressed: _holds ? null : w.actions.onMic,
        ),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: field),
        const SizedBox(width: 4),
        action,
      ],
    );
  }

  Widget _recording(OrbitTokens t) {
    final w = widget;
    final locked = w.recording == OrbitRecording.locked;
    final strip = Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.only(left: 14, right: 8),
      decoration: BoxDecoration(
        color: t.field,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          const _RecDot(),
          const SizedBox(width: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 42),
            child: Text(
              w.recordingTime,
              style: t.mono.style(size: 14, weight: 600, color: t.ink),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: locked
                ? SizedBox(
                    height: 24,
                    child: CustomPaint(
                      painter: _RecWave(w.recordingWave, t.danger),
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      OrbitIcon(
                        OrbitIcons.caretLeft,
                        weight: OrbitIconWeight.bold,
                        size: OrbitType.caption,
                        color: t.ink3,
                      ),
                      const SizedBox(width: 4),
                      OrbitText(
                        'Slide to cancel',
                        style: t.font.style(
                          size: OrbitType.caption,
                          color: t.ink3,
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (locked) ...[
          OrbitIconButton(
            icon: OrbitIcons.trash,
            tooltip: 'Delete recording',
            tone: OrbitIconButtonTone.danger,
            onPressed: w.actions.onCancelRecording,
          ),
          const SizedBox(width: 4),
        ],
        Expanded(child: strip),
        const SizedBox(width: 4),
        locked
            ? _RoundButton(
                icon: OrbitIcons.paperPlaneTilt,
                weight: OrbitIconWeight.fill,
                tooltip: 'Send recording',
                color: t.accent,
                ink: t.onAccent,
                glow: true,
                onPressed: w.actions.onSendRecording,
              )
            : _mic(
                Transform.scale(
                  scale: 1.18,
                  child: _RoundButton(
                    icon: OrbitIcons.microphone,
                    weight: OrbitIconWeight.fill,
                    tooltip: 'Release to send',
                    color: t.danger,
                    ink: t.onAccent,
                    glow: true,
                    onPressed: _holds ? null : w.actions.onSendRecording,
                  ),
                ),
              ),
      ],
    );
  }

  /// The caller records voice by holding the mic.
  bool get _holds => widget.actions.onVoiceStart != null;

  /// The mic, held to record: one gesture from the press to the release,
  /// kept across the switch from the field to the recording strip.
  Widget _mic(Widget button) {
    final a = widget.actions;
    if (!_holds) return button;
    return _MicGesture(
      key: _micKey,
      onTap: a.onMic,
      onStart: a.onVoiceStart!,
      onSlide: a.onVoiceSlide,
      onLock: a.onVoiceLock,
      onEnd: a.onVoiceEnd,
      child: button,
    );
  }
}

/// Hold the mic to record (the prototype's 220ms), slide 120px towards the
/// start to cancel or 80px up onto the lock to keep going hands-free, and
/// let go to send. A shorter press is a tap.
class _MicGesture extends StatefulWidget {
  const _MicGesture({
    super.key,
    required this.onStart,
    required this.child,
    this.onTap,
    this.onSlide,
    this.onLock,
    this.onEnd,
  });

  final VoidCallback? onTap;
  final VoidCallback onStart;
  final void Function(double cancel, double lock)? onSlide;
  final VoidCallback? onLock;
  final void Function({required bool send})? onEnd;
  final Widget child;

  static const cancelDistance = 120.0;
  static const lockDistance = 80.0;

  @override
  State<_MicGesture> createState() => _MicGestureState();
}

class _MicGestureState extends State<_MicGesture> {
  var _origin = Offset.zero;
  var _started = false;
  var _settled = false;

  /// The hold is over: [send] unless it already ended (cancelled, locked).
  void _finish({required bool send}) {
    if (_started && !_settled) widget.onEnd?.call(send: send);
    _started = false;
    _settled = false;
  }

  void _move(Offset to) {
    if (_settled) return;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final delta = to - _origin;
    final towardsStart = rtl ? delta.dx : -delta.dx;
    final cancel = (towardsStart / _MicGesture.cancelDistance).clamp(0.0, 1.0);
    final lock = (-delta.dy / _MicGesture.lockDistance).clamp(0.0, 1.0);
    widget.onSlide?.call(cancel, lock);
    if (cancel >= 1) {
      _settled = true;
      widget.onEnd?.call(send: false);
    } else if (lock >= 1) {
      _settled = true;
      widget.onLock?.call();
    }
  }

  @override
  Widget build(BuildContext context) => Listener(
    // The system took the touch away (a permission prompt): the hold is
    // over, and nothing is sent.
    onPointerCancel: (_) => _finish(send: false),
    child: RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: {
        TapGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
              () => TapGestureRecognizer(debugOwner: this),
              (r) => r.onTap = widget.onTap,
            ),
        LongPressGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
              () => LongPressGestureRecognizer(
                duration: const Duration(milliseconds: 220),
                debugOwner: this,
              ),
              (r) => r
                ..onLongPressStart = (d) {
                  _origin = d.globalPosition;
                  _started = true;
                  _settled = false;
                  widget.onStart();
                }
                ..onLongPressMoveUpdate = ((d) => _move(d.globalPosition))
                ..onLongPressEnd = ((_) => _finish(send: true)),
            ),
      },
      child: widget.child,
    ),
  );
}

/// `.send-btn`: the 48px round button, a 21px icon, `--glow` under it.
class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.weight,
    required this.tooltip,
    required this.color,
    required this.ink,
    required this.onPressed,
    this.glow = false,
  });

  final OrbitGlyph icon;
  final OrbitIconWeight weight;
  final String tooltip;
  final Color color;
  final Color ink;
  final VoidCallback? onPressed;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    return Tooltip(
      message: tooltip,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        label: tooltip,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: glow ? t.glow : null,
          ),
          child: Material(
            color: color,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onPressed,
              splashFactory: NoSplash.splashFactory,
              child: Center(
                child: OrbitIcon(icon, weight: weight, size: 21, color: ink),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `.cp-banner`: what a reply or edit is about. 8px 4px 8px 12px in, corner
/// 14, `--field` with a 3px `--accent` edge on the left (`--cyan` when
/// editing); the title at weight 640 in `--accent-ink` (`--cyan-ink`) with
/// its bold icon, the text in `--ink-3` on one line, `--t-caption`; a 40px ×
/// to cancel. 8px over the field.
class _Banner extends StatelessWidget {
  const _Banner({required this.model, this.onCancel});

  final HelixComposerBannerModel model;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final edit = model.kind == HelixComposerBannerKind.edit;
    final ink = edit ? t.cyanInk : t.accentInk;
    final small = t.font.style(size: OrbitType.caption, color: t.ink3);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(9, 8, 4, 8),
          decoration: BoxDecoration(
            color: t.field,
            border: Border(
              left: BorderSide(color: edit ? t.cyan : t.accent, width: 3),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        OrbitIcon(
                          edit
                              ? OrbitIcons.pencilSimple
                              : OrbitIcons.arrowBendUpLeft,
                          weight: OrbitIconWeight.bold,
                          size: OrbitType.caption,
                          color: ink,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: OrbitText(
                            model.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: small.copyWith(
                              color: ink,
                              fontWeight: FontWeight.w600,
                              fontVariations: const [
                                FontVariation('wght', 640),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (model.text.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: OrbitText(
                          model.text,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          style: small,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              OrbitIconButton(
                icon: OrbitIcons.x,
                tooltip: edit ? 'Cancel edit' : 'Cancel reply',
                onPressed: onCancel,
                size: 40,
                iconSize: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// `.rec-dot`: the 10px `--danger` dot, blinking every second unless the
/// system asks to reduce motion.
class _RecDot extends StatefulWidget {
  const _RecDot();

  @override
  State<_RecDot> createState() => _RecDotState();
}

class _RecDotState extends State<_RecDot> with SingleTickerProviderStateMixin {
  late final _blink = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final run = OrbitMotion.allowed(context);
    if (run && !_blink.isAnimating) _blink.repeat();
    if (!run && _blink.isAnimating) _blink.reset();
  }

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    return AnimatedBuilder(
      animation: _blink,
      builder: (context, _) {
        final v = _blink.isAnimating ? _blink.value : 0.0;
        final o = v < 0.5
            ? 1 - 0.75 * Curves.ease.transform(v * 2)
            : 0.25 + 0.75 * Curves.ease.transform((v - 0.5) * 2);
        return Opacity(
          opacity: o,
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: t.danger, shape: BoxShape.circle),
          ),
        );
      },
    );
  }
}

/// The recording's waveform: 24 bars in `--danger` at 55%.
class _RecWave extends CustomPainter {
  const _RecWave(this.samples, this.color);

  final List<int> samples;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const bars = 24;
    final w = (size.width - (bars - 1) * 2) / bars;
    final paint = Paint()..color = color.withValues(alpha: 0.55);
    for (var i = 0; i < bars; i++) {
      final v = samples.isEmpty
          ? 60
          : samples[(i / bars * samples.length).floor()];
      final h = size.height * math.max(12, (v / 255 * 100).round()) / 100;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(i * (w + 2), (size.height - h) / 2, w, h),
          const Radius.circular(2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_RecWave old) =>
      old.samples != samples || old.color != color;
}

/// `.lock-pill`: slide up to lock. A 48px wide pill (`--surface`, a
/// `--line` edge, `--shadow-float`), 10px in: an open lock and a bold caret
/// rising every 1.2s, in `--ink-3`.
class _LockPill extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    return Tooltip(
      message: 'Slide up to lock',
      child: Container(
        width: 48,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: t.surface,
          border: Border.all(color: t.line),
          borderRadius: BorderRadius.circular(24),
          boxShadow: t.shadowFloat,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            OrbitIcon(OrbitIcons.lockSimpleOpen, size: 18, color: t.ink3),
            const SizedBox(height: 6),
            OrbitIcon(
              OrbitIcons.caretUp,
              weight: OrbitIconWeight.bold,
              size: 14,
              color: t.ink3,
            ),
          ],
        ),
      ),
    );
  }
}

/// `.mentions`: who an "@" can name. A card (corner 14, `--surface`, a
/// `--line` edge, `--shadow-float`) 4px in and 8px over the field; 52px rows,
/// 12px in, a 34px picture 10px before the name (weight 560, `--t-small`)
/// and their number or ~name in mono 10.5px.
class _Mentions extends StatelessWidget {
  const _Mentions({required this.people, this.onPick});

  final List<HelixPersonItem> people;
  final ValueChanged<HelixPersonItem>? onPick;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border.all(color: t.line),
        borderRadius: BorderRadius.circular(14),
        boxShadow: t.shadowFloat,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: Column(
          children: [
            for (final p in people)
              Semantics(
                button: true,
                child: InkWell(
                  onTap: () => onPick?.call(p),
                  hoverColor: t.field,
                  splashFactory: NoSplash.splashFactory,
                  child: SizedBox(
                    height: 52,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          OrbitAvatar(avatar: p.avatar, size: 34),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                OrbitText(
                                  p.names.display,
                                  style: t.font.style(
                                    size: OrbitType.small,
                                    weight: 560,
                                    color: t.ink,
                                  ),
                                ),
                                OrbitText(
                                  p.names.secondary ?? '',
                                  style: t.mono.style(
                                    size: 10.5,
                                    color: t.ink3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
