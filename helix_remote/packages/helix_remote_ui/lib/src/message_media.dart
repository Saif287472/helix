part of '../helix_remote_ui.dart';

String _mediaSemantic(HelixMediaItem item) {
  final base =
      item.semanticLabel ??
      (item.isVideo ? 'Video' : (item.isGif ? 'GIF' : 'Photo'));
  return switch (item.transfer) {
    HelixTransferState.done => base,
    HelixTransferState.notDownloaded =>
      '$base, not downloaded. Tap to download',
    HelixTransferState.downloading => '$base, downloading. Tap to cancel',
    HelixTransferState.uploading => '$base, uploading. Tap to cancel',
    HelixTransferState.failed => '$base, failed. Tap to retry',
  };
}

/// The round control that starts, cancels or retries a transfer, with a
/// progress ring while one runs. Decorative: its owner is the semantic node.
class _TransferGlyph extends StatelessWidget {
  const _TransferGlyph({
    required this.state,
    this.progress,
    this.size = 44,
    this.onDark = true,
  });
  final HelixTransferState state;
  final double? progress;
  final double size;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = onDark ? HelixScrimColors.onBackdrop : scheme.onPrimary;
    final bg = onDark ? HelixScrimColors.barrier : scheme.primary;
    final icon = switch (state) {
      HelixTransferState.notDownloaded => Icons.arrow_downward,
      HelixTransferState.downloading ||
      HelixTransferState.uploading => Icons.close,
      HelixTransferState.failed => Icons.refresh,
      HelixTransferState.done => Icons.play_arrow,
    };
    final running =
        state == HelixTransferState.downloading ||
        state == HelixTransferState.uploading;
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (running)
              Padding(
                padding: const EdgeInsets.all(3),
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 2.5,
                  color: fg,
                  backgroundColor: HelixScrimColors.onBackdropSubtle,
                ),
              ),
            Icon(icon, color: fg, size: size * .5),
          ],
        ),
      ),
    );
  }
}

/// Images and videos in a bubble: one large, two side by side, three as one
/// over two, four or more as a 2x2 grid with a "+N" on the last cell.
///
/// Items use the thumbnail the app provides; nothing is decoded at full size
/// (images are resized to the cell). The grid is [maxWidth] wide at most, so
/// bubbles of the same message count line up.
class HelixMediaGrid extends StatelessWidget {
  const HelixMediaGrid({
    super.key,
    required this.items,
    this.onTap,
    this.onTransferTap,
    this.overlay,
    this.maxWidth = 300,
  });

  final List<HelixMediaItem> items;
  final ValueChanged<int>? onTap;
  final ValueChanged<int>? onTransferTap;

  /// Drawn at the bottom end (the time pill of a caption-less media bubble).
  final Widget? overlay;
  final double maxWidth;

  static const _gap = 2.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final w = math.min(
        constraints.hasBoundedWidth ? constraints.maxWidth : maxWidth,
        maxWidth,
      );
      final layout = _layout(w);
      return SizedBox(
        width: w,
        height: layout.$2,
        child: ClipRRect(
          borderRadius: const BorderRadius.all(Radius.circular(10)),
          child: Stack(
            fit: StackFit.expand,
            children: [
              layout.$1,
              if (overlay != null)
                PositionedDirectional(end: 6, bottom: 6, child: overlay!),
            ],
          ),
        ),
      );
    },
  );

  Widget _cell(int i, {int more = 0}) => _MediaCell(
    item: items[i],
    more: more,
    onTap: onTap == null ? null : () => onTap!(i),
    onTransferTap: onTransferTap == null ? null : () => onTransferTap!(i),
  );

  (Widget, double) _layout(double w) {
    final n = items.length;
    if (n == 1) {
      final h = (w / items.first.aspectRatio).clamp(w * .5, w * 1.25);
      return (_cell(0), h.toDouble());
    }
    if (n == 2) {
      final side = (w - _gap) / 2;
      return (
        Row(
          children: [
            Expanded(child: _cell(0)),
            const SizedBox(width: _gap),
            Expanded(child: _cell(1)),
          ],
        ),
        side,
      );
    }
    if (n == 3) {
      final top = w * .6;
      final bottom = w * .4;
      return (
        Column(
          children: [
            SizedBox(height: top, child: _cell(0)),
            const SizedBox(height: _gap),
            Expanded(
              child: Row(
                children: [
                  Expanded(child: _cell(1)),
                  const SizedBox(width: _gap),
                  Expanded(child: _cell(2)),
                ],
              ),
            ),
          ],
        ),
        top + _gap + bottom,
      );
    }
    final half = (w - _gap) / 2;
    final extra = n - 4;
    return (
      Column(
        children: [
          Expanded(
            child: Row(
              children: [
                Expanded(child: _cell(0)),
                const SizedBox(width: _gap),
                Expanded(child: _cell(1)),
              ],
            ),
          ),
          const SizedBox(height: _gap),
          Expanded(
            child: Row(
              children: [
                Expanded(child: _cell(2)),
                const SizedBox(width: _gap),
                Expanded(child: _cell(3, more: extra)),
              ],
            ),
          ),
        ],
      ),
      half * 2 + _gap,
    );
  }
}

class _MediaCell extends StatelessWidget {
  const _MediaCell({
    required this.item,
    required this.more,
    this.onTap,
    this.onTransferTap,
  });
  final HelixMediaItem item;
  final int more;
  final VoidCallback? onTap;
  final VoidCallback? onTransferTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final thumb = item.thumbnail;
    final done = item.transfer == HelixTransferState.done;
    final tap = done ? onTap : onTransferTap;
    final Widget picture = thumb == null
        ? ColoredBox(
            color: scheme.surfaceContainerHighest,
            child: Center(
              child: Icon(
                item.isVideo ? Icons.videocam_outlined : Icons.image_outlined,
                color: scheme.onSurfaceVariant,
              ),
            ),
          )
        : Image(
            image: ResizeImage.resizeIfNeeded(480, null, thumb),
            fit: BoxFit.cover,
            gaplessPlayback: true,
            excludeFromSemantics: true,
            errorBuilder: (_, _, _) => ColoredBox(
              color: scheme.surfaceContainerHighest,
              child: Icon(
                Icons.broken_image_outlined,
                color: scheme.onSurfaceVariant,
              ),
            ),
          );
    return Semantics(
      button: true,
      image: true,
      label: _mediaSemantic(item),
      onTap: tap,
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: tap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              picture,
              if (!done)
                Center(
                  child: _TransferGlyph(
                    state: item.transfer,
                    progress: item.progress,
                  ),
                )
              else if (item.isVideo)
                const Center(
                  child: _TransferGlyph(state: HelixTransferState.done),
                ),
              if (item.isVideo && item.durationLabel != null && done)
                PositionedDirectional(
                  start: 6,
                  bottom: 6,
                  child: _OverlayChip(
                    icon: Icons.videocam,
                    label: item.durationLabel!,
                  ),
                ),
              if (item.isGif && done)
                const PositionedDirectional(
                  start: 6,
                  bottom: 6,
                  child: _OverlayChip(label: 'GIF'),
                ),
              if (more > 0)
                ColoredBox(
                  color: HelixScrimColors.barrier,
                  child: Center(
                    child: Text(
                      '+$more',
                      textScaler: TextScaler.noScaling,
                      style: const TextStyle(
                        color: HelixScrimColors.onBackdrop,
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OverlayChip extends StatelessWidget {
  const _OverlayChip({this.icon, required this.label});
  final IconData? icon;
  final String label;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      color: HelixScrimColors.barrier,
      borderRadius: BorderRadius.all(Radius.circular(10)),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: HelixScrimColors.onBackdrop),
            const SizedBox(width: 2),
          ],
          Text(
            label,
            textScaler: TextScaler.noScaling,
            style: const TextStyle(
              color: HelixScrimColors.onBackdrop,
              fontSize: 11,
              height: 1.2,
            ),
          ),
        ],
      ),
    ),
  );
}

/// A file in a bubble: type glyph, name, size and kind, with the transfer
/// control when the file is not on this device yet.
class HelixDocumentTile extends StatelessWidget {
  const HelixDocumentTile({
    super.key,
    required this.content,
    this.onTap,
    this.onTransferTap,
  });

  final HelixDocumentContent content;
  final VoidCallback? onTap;
  final VoidCallback? onTransferTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = content;
    final done = c.transfer == HelixTransferState.done;
    final tap = done ? onTap : onTransferTap;
    final detail = [
      if (c.sizeLabel.isNotEmpty) c.sizeLabel,
      if (c.typeLabel.isNotEmpty) c.typeLabel,
    ].join(' · ');
    return Semantics(
      button: true,
      label:
          'Document ${c.name}${detail.isEmpty ? '' : ', $detail'}'
          '${done ? '' : ', tap to download'}',
      onTap: tap,
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: tap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: HelixChatMetrics.minTarget + 8,
              minWidth: 200,
            ),
            child: DecoratedBox(
              decoration: const BoxDecoration(
                color: HelixScrimColors.shadowSoft,
                borderRadius: BorderRadius.all(Radius.circular(8)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    done
                        ? Icon(
                            Icons.insert_drive_file,
                            size: 36,
                            color: scheme.primary,
                          )
                        : _TransferGlyph(
                            state: c.transfer,
                            progress: c.progress,
                            size: 40,
                            onDark: false,
                          ),
                    const SizedBox(width: HelixSpace.xs),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            c.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              color: scheme.onSurface,
                            ),
                          ),
                          if (detail.isNotEmpty)
                            Text(
                              detail,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: HelixChatColors.metaText,
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
      ),
    );
  }
}

/// A voice note (or audio file): play/pause, waveform with a played portion,
/// time, and the speed chip.
class HelixAudioBubbleBody extends StatelessWidget {
  const HelixAudioBubbleBody({
    super.key,
    required this.content,
    required this.outgoing,
    this.onToggle,
    this.onSpeed,
    this.onSeek,
    this.onTransferTap,
  });

  final HelixAudioContent content;
  final bool outgoing;
  final VoidCallback? onToggle;
  final VoidCallback? onSpeed;
  final ValueChanged<double>? onSeek;
  final VoidCallback? onTransferTap;

  static String speedLabel(double speed) =>
      speed == speed.roundToDouble() ? '${speed.round()}x' : '${speed}x';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = content;
    final done = c.transfer == HelixTransferState.done;
    final kind = c.isVoiceNote ? 'Voice message' : (c.title ?? 'Audio');
    final shownTime = c.playing || c.progress > 0
        ? (c.positionLabel ?? c.durationLabel)
        : c.durationLabel;
    final leading = done
        ? Semantics(
            button: true,
            label: c.playing ? 'Pause $kind' : 'Play $kind, ${c.durationLabel}',
            onTap: onToggle,
            child: ExcludeSemantics(
              child: GestureDetector(
                onTap: onToggle,
                behavior: HitTestBehavior.opaque,
                child: SizedBox.square(
                  dimension: HelixChatMetrics.minTarget,
                  child: Center(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: SizedBox.square(
                        dimension: 40,
                        child: Icon(
                          c.playing ? Icons.pause : Icons.play_arrow,
                          color: scheme.onPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          )
        : Semantics(
            button: true,
            label: switch (c.transfer) {
              HelixTransferState.notDownloaded => '$kind, tap to download',
              HelixTransferState.failed => '$kind failed, tap to retry',
              _ => '$kind, tap to cancel',
            },
            onTap: onTransferTap,
            child: ExcludeSemantics(
              child: GestureDetector(
                onTap: onTransferTap,
                behavior: HitTestBehavior.opaque,
                child: SizedBox.square(
                  dimension: HelixChatMetrics.minTarget,
                  child: Center(
                    child: _TransferGlyph(
                      state: c.transfer,
                      progress: c.transferProgress,
                      size: 40,
                      onDark: false,
                    ),
                  ),
                ),
              ),
            ),
          );

    final wave = Semantics(
      slider: true,
      label: '$kind position',
      value: '${(c.progress * 100).round()} percent',
      increasedValue: '${((c.progress + .1).clamp(0.0, 1.0) * 100).round()}',
      decreasedValue: '${((c.progress - .1).clamp(0.0, 1.0) * 100).round()}',
      onIncrease: onSeek == null
          ? null
          : () => onSeek!((c.progress + .1).clamp(0.0, 1.0)),
      onDecrease: onSeek == null
          ? null
          : () => onSeek!((c.progress - .1).clamp(0.0, 1.0)),
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, box) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: onSeek == null
                ? null
                : (d) => onSeek!(_fraction(context, d.localPosition.dx, box)),
            onHorizontalDragUpdate: onSeek == null
                ? null
                : (d) => onSeek!(_fraction(context, d.localPosition.dx, box)),
            child: SizedBox(
              height: 32,
              child: CustomPaint(
                size: Size(box.maxWidth, 32),
                painter: _WaveformPainter(
                  samples: c.waveform,
                  progress: c.progress,
                  active: scheme.primary,
                  idle: HelixChatColors.waveformIdle,
                  rtl: Directionality.of(context) == TextDirection.rtl,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 280),
      child: Row(
        children: [
          leading,
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                wave,
                Row(
                  children: [
                    if (!outgoing && !c.played && c.isVoiceNote)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 4),
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    Text(
                      shownTime,
                      style: const TextStyle(
                        fontSize: 12,
                        color: HelixChatColors.metaText,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (c.isVoiceNote && done && (c.playing || c.speed != 1))
            Semantics(
              button: true,
              label: 'Playback speed ${speedLabel(c.speed)}',
              onTap: onSpeed,
              child: ExcludeSemantics(
                child: GestureDetector(
                  onTap: onSpeed,
                  behavior: HitTestBehavior.opaque,
                  child: SizedBox(
                    width: HelixChatMetrics.minTarget,
                    height: HelixChatMetrics.minTarget,
                    child: Center(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: scheme.secondaryContainer,
                          borderRadius: const BorderRadius.all(
                            Radius.circular(12),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          child: Text(
                            speedLabel(c.speed),
                            textScaler: TextScaler.noScaling,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: scheme.onSecondaryContainer,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  double _fraction(BuildContext context, double dx, BoxConstraints box) {
    final f = (dx / math.max(1, box.maxWidth)).clamp(0.0, 1.0);
    return Directionality.of(context) == TextDirection.rtl ? 1 - f : f;
  }
}

class _WaveformPainter extends CustomPainter {
  const _WaveformPainter({
    required this.samples,
    required this.progress,
    required this.active,
    required this.idle,
    required this.rtl,
  });

  final Uint8List? samples;
  final double progress;
  final Color active;
  final Color idle;
  final bool rtl;

  @override
  void paint(Canvas canvas, Size size) {
    const bars = HelixChatMetrics.waveformBars;
    final slot = size.width / bars;
    final barW = math.max(1.5, slot * .55);
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = barW;
    final data = samples;
    for (var i = 0; i < bars; i++) {
      double level;
      if (data == null || data.isEmpty) {
        // A calm deterministic placeholder rather than a flat line.
        level = .25 + .2 * ((i * 7) % 5) / 4;
      } else {
        final from = (i * data.length / bars).floor();
        final to = math.max(from + 1, ((i + 1) * data.length / bars).ceil());
        var peak = 0;
        for (var j = from; j < to && j < data.length; j++) {
          if (data[j] > peak) peak = data[j];
        }
        level = peak / 255;
      }
      final h = math.max(3.0, level * size.height);
      final x = rtl ? size.width - (i + .5) * slot : (i + .5) * slot;
      paint.color = (i + .5) / bars <= progress ? active : idle;
      canvas.drawLine(
        Offset(x, (size.height - h) / 2),
        Offset(x, (size.height + h) / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.progress != progress ||
      !identical(old.samples, samples) ||
      old.active != active ||
      old.idle != idle ||
      old.rtl != rtl;
}

/// A static location: a placeholder map tile (the UI package draws no map)
/// with the place name and address.
class HelixLocationCard extends StatelessWidget {
  const HelixLocationCard({super.key, required this.content, this.onTap});
  final HelixLocationContent content;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = content;
    return Semantics(
      button: true,
      label:
          'Location${c.label.isEmpty ? '' : ', ${c.label}'}'
          '${c.address.isEmpty ? '' : ', ${c.address}'}',
      onTap: onTap,
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: onTap,
          child: SizedBox(
            width: 240,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.all(Radius.circular(8)),
                  child: SizedBox(
                    height: 110,
                    width: double.infinity,
                    child: ColoredBox(
                      color: HelixNeutralColors.subtle,
                      child: Center(
                        child: Icon(
                          Icons.location_on,
                          size: 40,
                          color: scheme.error,
                        ),
                      ),
                    ),
                  ),
                ),
                if (c.label.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      c.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                if (c.address.isNotEmpty)
                  Text(
                    c.address,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: HelixChatColors.metaText,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A shared contact card.
class HelixContactCard extends StatelessWidget {
  const HelixContactCard({super.key, required this.content, this.onTap});
  final HelixContactContent content;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = content;
    return Semantics(
      button: true,
      label:
          'Contact ${c.name}${c.detail.isEmpty ? '' : ', ${c.detail}'}'
          '${c.onHelix ? ', on Helix' : ''}',
      onTap: onTap,
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: 220,
              minHeight: HelixChatMetrics.minTarget + 8,
            ),
            child: Row(
              children: [
                HelixAvatar(
                  model: HelixAvatarModel(
                    name: c.name,
                    colorIndex: HelixAvatarModel.colorIndexFor(c.name),
                  ),
                ),
                const SizedBox(width: HelixSpace.xs),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        c.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface,
                        ),
                      ),
                      if (c.detail.isNotEmpty)
                        Text(
                          c.detail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: HelixChatColors.metaText,
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
    );
  }
}

/// The link card under a text message: picture, title, description, host.
class HelixLinkPreviewCard extends StatelessWidget {
  const HelixLinkPreviewCard({super.key, required this.preview, this.onTap});
  final HelixLinkPreview preview;
  final VoidCallback? onTap;

  static String hostOf(String url) {
    final uri = Uri.tryParse(url.contains('://') ? url : 'https://$url');
    final host = uri?.host ?? '';
    return host.isEmpty ? url : host.replaceFirst(RegExp(r'^www\.'), '');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final p = preview;
    return Semantics(
      link: true,
      button: true,
      label: 'Link preview, ${p.title ?? hostOf(p.url)}',
      onTap: onTap,
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: onTap,
          child: SizedBox(
            width: double.infinity,
            child: ClipRRect(
              borderRadius: const BorderRadius.all(Radius.circular(8)),
              child: ColoredBox(
                color: HelixScrimColors.shadowSoft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (p.image != null)
                      AspectRatio(
                        aspectRatio: 1.91,
                        child: Image(
                          image: ResizeImage.resizeIfNeeded(
                            600,
                            null,
                            p.image!,
                          ),
                          fit: BoxFit.cover,
                          excludeFromSemantics: true,
                          errorBuilder: (_, _, _) =>
                              ColoredBox(color: scheme.surfaceContainerHighest),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (p.title != null)
                            Text(
                              p.title!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: scheme.onSurface,
                              ),
                            ),
                          if (p.description != null)
                            Text(
                              p.description!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          Text(
                            hostOf(p.url),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: HelixChatColors.metaText,
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
      ),
    );
  }
}

/// The body of a bubble that has no content: deleted for everyone,
/// "couldn't decrypt" (with an optional "Ask to resend"), "needs a newer
/// version" (with an optional "Update"), or an expired disappearing message.
class HelixPlaceholderBody extends StatelessWidget {
  const HelixPlaceholderBody({
    super.key,
    required this.kind,
    required this.outgoing,
    this.onAction,
  });

  final HelixPlaceholderKind kind;
  final bool outgoing;

  /// "Ask to resend" for undecryptable, "Update Helix" for unsupported.
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final icon = switch (kind) {
      HelixPlaceholderKind.deleted => Icons.block,
      HelixPlaceholderKind.undecryptable => Icons.lock_outline,
      HelixPlaceholderKind.unsupported => Icons.system_update_alt,
      HelixPlaceholderKind.expired => Icons.timer_off_outlined,
    };
    final actionLabel = switch (kind) {
      HelixPlaceholderKind.undecryptable => 'Ask to resend',
      HelixPlaceholderKind.unsupported => 'Update Helix',
      _ => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: HelixChatColors.metaText),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                _placeholderText(kind, outgoing),
                style: const TextStyle(
                  fontSize: 15,
                  fontStyle: FontStyle.italic,
                  color: HelixChatColors.metaText,
                ),
              ),
            ),
          ],
        ),
        if (actionLabel != null && onAction != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              foregroundColor: scheme.primary,
              padding: const EdgeInsets.symmetric(horizontal: 4),
            ),
            child: Text(actionLabel),
          ),
      ],
    );
  }
}

/// A view-once photo or video: shows "Tap to view" until opened, then
/// "Opened". The picture itself is never in the bubble.
class HelixViewOnceTile extends StatelessWidget {
  const HelixViewOnceTile({
    super.key,
    required this.content,
    required this.outgoing,
    this.onTap,
  });
  final HelixViewOnceContent content;
  final bool outgoing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = content;
    final what = c.isVideo ? 'Video' : 'Photo';
    final status = c.opened ? 'Opened' : (outgoing ? 'Sent' : 'Tap to view');
    final canTap = !c.opened && !outgoing;
    return Semantics(
      button: canTap,
      label: 'View once $what, $status',
      onTap: canTap ? onTap : null,
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: canTap ? onTap : null,
          behavior: HitTestBehavior.opaque,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: HelixChatMetrics.minTarget,
              minWidth: 160,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: c.opened
                          ? HelixChatColors.metaText
                          : scheme.primary,
                      width: 2,
                    ),
                  ),
                  child: SizedBox.square(
                    dimension: 32,
                    child: Icon(
                      c.opened ? Icons.check : Icons.looks_one_outlined,
                      size: 18,
                      color: c.opened
                          ? HelixChatColors.metaText
                          : scheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: HelixSpace.xs),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        what,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface,
                        ),
                      ),
                      Text(
                        status,
                        style: const TextStyle(
                          fontSize: 12,
                          color: HelixChatColors.metaText,
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
    );
  }
}
