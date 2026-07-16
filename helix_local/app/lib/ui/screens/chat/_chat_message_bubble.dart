part of 'chat_screen.dart';

// ---------------------------------------------------------------------------
// Message bubble
// ---------------------------------------------------------------------------

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.peerInitial,
    required this.peerDisplayName,
    required this.showAvatar,
    required this.groupedWithPrevious,
    required this.groupedWithNext,
    required this.showMeta,
    required this.onLongPress,
    required this.onReplySwipe,
    required this.isSearchHit,
    this.replySource,
    this.onQuoteTap,
    this.searchQuery = '',
  });

  final ChatMessage message;
  final String peerInitial;
  final String peerDisplayName;
  final bool showAvatar;
  final bool groupedWithPrevious;
  final bool groupedWithNext;
  final bool showMeta;
  final ChatMessage? replySource;
  final VoidCallback onLongPress;
  final VoidCallback onReplySwipe;
  final VoidCallback? onQuoteTap;
  final String searchQuery;
  final bool isSearchHit;

  @override
  Widget build(BuildContext context) {
    if (message.isSystem) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Center(
          child: Text(
            message.text,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontStyle: FontStyle.italic,
              color: Theme.of(context).colorScheme.onSurface.withAlpha(140),
            ),
          ),
        ),
      );
    }

    final isLocal = message.origin == MessageOrigin.local;
    final bubbleColor = isSearchHit
        ? Theme.of(context).colorScheme.tertiaryContainer
        : (isLocal
              ? HelixTheme.localBubbleColor(context)
              : HelixTheme.remoteBubbleColor(context));
    final textColor = isLocal
        ? HelixTheme.localBubbleTextColor(context)
        : HelixTheme.remoteBubbleTextColor(context);

    final timeStr =
        '${message.timestamp.hour.toString().padLeft(2, '0')}:'
        '${message.timestamp.minute.toString().padLeft(2, '0')}';
    final screenWidth = MediaQuery.sizeOf(context).width;
    final bubbleMaxWidth = math.min(
      screenWidth * (screenWidth < 700 ? 0.78 : 0.54),
      560.0,
    );

    Widget bubbleContent;
    if (message.isFile) {
      bubbleContent = _FileBubbleContent(
        message: message,
        textColor: textColor,
        timeStr: timeStr,
        isLocal: isLocal,
        showMeta: showMeta,
      );
    } else {
      bubbleContent = _TextBubbleContent(
        message: message,
        textColor: textColor,
        timeStr: timeStr,
        isLocal: isLocal,
        showMeta: showMeta,
        replySource: replySource,
        replySourceName: replySource == null
            ? null
            : (replySource!.origin == MessageOrigin.local
                  ? 'You'
                  : peerDisplayName),
        onQuoteTap: onQuoteTap,
        searchQuery: searchQuery,
      );
    }

    final bubble = Container(
      constraints: BoxConstraints(maxWidth: bubbleMaxWidth),
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(!isLocal && groupedWithPrevious ? 6 : 14),
          topRight: Radius.circular(isLocal && groupedWithPrevious ? 6 : 14),
          bottomLeft: isLocal
              ? const Radius.circular(14)
              : Radius.circular(groupedWithNext ? 6 : 4),
          bottomRight: isLocal
              ? Radius.circular(groupedWithNext ? 6 : 4)
              : const Radius.circular(14),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(12),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: bubbleContent,
    );

    final reactionsRow = message.hasReactions
        ? _ReactionsRow(message: message, isLocal: isLocal)
        : null;

    final column = Column(
      crossAxisAlignment: isLocal
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        bubble,
        if (reactionsRow != null) ...[const SizedBox(height: 4), reactionsRow],
      ],
    );

    final row = Padding(
      padding: EdgeInsets.only(
        top: groupedWithPrevious ? 1 : 3,
        bottom: groupedWithNext ? 1 : 3,
      ),
      child: Row(
        mainAxisAlignment: isLocal
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isLocal) ...[
            SizedBox(
              width: 28,
              child: showAvatar
                  ? CircleAvatar(
                      radius: 12,
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.primaryContainer,
                      child: Text(
                        peerInitial,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Theme.of(
                            context,
                          ).colorScheme.onPrimaryContainer,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            const SizedBox(width: 6),
          ],
          column,
        ],
      ),
    );

    return Semantics(
      button: true,
      label: isLocal ? 'Sent message' : 'Received message',
      child: GestureDetector(
        onLongPress: onLongPress,
        onHorizontalDragEnd: (details) {
          if (details.primaryVelocity != null &&
              details.primaryVelocity! > 200) {
            HapticFeedback.lightImpact();
            onReplySwipe();
          }
        },
        child: row,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Text bubble content — markdown + tappable links + search highlight
// ---------------------------------------------------------------------------

class _TextBubbleContent extends StatelessWidget {
  const _TextBubbleContent({
    required this.message,
    required this.textColor,
    required this.timeStr,
    required this.isLocal,
    required this.showMeta,
    this.replySource,
    this.replySourceName,
    this.onQuoteTap,
    this.searchQuery = '',
  });

  final ChatMessage message;
  final Color textColor;
  final String timeStr;
  final bool isLocal;
  final bool showMeta;
  final ChatMessage? replySource;
  final String? replySourceName;
  final VoidCallback? onQuoteTap;
  final String searchQuery;

  bool get _hasMarkdown => _kMdPattern.hasMatch(message.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 12, 8),
      child: Column(
        crossAxisAlignment: isLocal
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Quoted reply preview
          if (replySource != null) ...[
            GestureDetector(
              onTap: onQuoteTap,
              child: Container(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                margin: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(25),
                  borderRadius: BorderRadius.circular(6),
                  border: Border(
                    left: BorderSide(
                      color: theme.colorScheme.primary,
                      width: 3,
                    ),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (replySourceName != null)
                      Text(
                        replySourceName!,
                        style: TextStyle(
                          color: textColor.withAlpha(220),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    Text(
                      replySource!.isDeleted ? '(deleted)' : replySource!.text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: textColor.withAlpha(200),
                        fontSize: 12,
                        fontStyle: replySource!.isDeleted
                            ? FontStyle.italic
                            : FontStyle.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          // Message body
          if (message.isDeleted)
            Text(
              'This message was deleted.',
              style: TextStyle(
                color: textColor.withAlpha(160),
                fontSize: 14,
                fontStyle: FontStyle.italic,
              ),
            )
          else if (_hasMarkdown)
            _MarkdownBody(text: message.text, textColor: textColor)
          else
            _LinkableText(
              text: message.text,
              textColor: textColor,
              searchQuery: searchQuery,
            ),
          if (showMeta) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (message.editedAt != null && !message.isDeleted)
                  Text(
                    'edited · ',
                    style: TextStyle(
                      color: textColor.withAlpha(130),
                      fontSize: 10,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                Text(
                  timeStr,
                  style: TextStyle(
                    color: textColor.withAlpha(160),
                    fontSize: 10,
                  ),
                ),
                if (isLocal) ...[
                  const SizedBox(width: 4),
                  DeliveryIcon(status: message.deliveryStatus, size: 12),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Markdown body with code-block copy button
// ---------------------------------------------------------------------------

class _MarkdownBody extends StatelessWidget {
  const _MarkdownBody({required this.text, required this.textColor});

  final String text;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    final baseStyle = TextStyle(color: textColor, fontSize: 14.5, height: 1.35);
    final sheet = MarkdownStyleSheet(
      p: baseStyle,
      strong: baseStyle.copyWith(fontWeight: FontWeight.w700),
      em: baseStyle.copyWith(fontStyle: FontStyle.italic),
      code: baseStyle.copyWith(
        fontFamily: 'monospace',
        backgroundColor: Colors.black.withAlpha(30),
      ),
      codeblockDecoration: BoxDecoration(
        color: Colors.black.withAlpha(30),
        borderRadius: BorderRadius.circular(6),
      ),
    );

    return MarkdownBody(
      data: text,
      styleSheet: sheet,
      builders: {'code': _CodeBlockBuilder()},
      onTapLink: (_, href, _) {
        if (href != null) {
          launchUrl(Uri.parse(href), mode: LaunchMode.externalApplication);
        }
      },
    );
  }
}

class _CodeBlockBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final code = element.textContent;
    return Stack(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 10, 40, 10),
          child: SelectableText(
            code,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: IconButton(
            icon: const Icon(Icons.copy, size: 16),
            tooltip: 'Copy code',
            visualDensity: VisualDensity.compact,
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Copied'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Linkable text with URL tapping + search highlight
// ---------------------------------------------------------------------------

class _LinkableText extends StatelessWidget {
  const _LinkableText({
    required this.text,
    required this.textColor,
    this.searchQuery = '',
  });

  final String text;
  final Color textColor;
  final String searchQuery;

  @override
  Widget build(BuildContext context) {
    final baseStyle = TextStyle(color: textColor, fontSize: 14.5, height: 1.35);
    final urlMatches = _kUrlPattern.allMatches(text).toList();
    final highlightColor = Theme.of(context).colorScheme.primary.withAlpha(80);

    final spans = <InlineSpan>[];
    int cursor = 0;

    for (final urlMatch in urlMatches) {
      if (urlMatch.start > cursor) {
        spans.addAll(
          _highlightedSpans(
            text.substring(cursor, urlMatch.start),
            baseStyle,
            searchQuery,
            highlightColor,
          ),
        );
      }
      final url = urlMatch.group(0)!;
      spans.add(
        TextSpan(
          text: url,
          style: baseStyle.copyWith(
            color: Theme.of(context).colorScheme.primary,
            decoration: TextDecoration.underline,
          ),
          recognizer: TapGestureRecognizer()
            ..onTap = () =>
                launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
        ),
      );
      cursor = urlMatch.end;
    }

    if (cursor < text.length) {
      spans.addAll(
        _highlightedSpans(
          text.substring(cursor),
          baseStyle,
          searchQuery,
          highlightColor,
        ),
      );
    }

    if (spans.isEmpty) {
      return Text(text, style: baseStyle);
    }

    return SelectableText.rich(TextSpan(children: spans));
  }

  List<InlineSpan> _highlightedSpans(
    String segment,
    TextStyle base,
    String query,
    Color highlight,
  ) {
    if (query.isEmpty) return [TextSpan(text: segment, style: base)];

    final spans = <InlineSpan>[];
    final lower = segment.toLowerCase();
    final lowerQ = query.toLowerCase();
    int start = 0;
    int idx;
    while ((idx = lower.indexOf(lowerQ, start)) != -1) {
      if (idx > start) {
        spans.add(TextSpan(text: segment.substring(start, idx), style: base));
      }
      spans.add(
        TextSpan(
          text: segment.substring(idx, idx + query.length),
          style: base.copyWith(backgroundColor: highlight),
        ),
      );
      start = idx + query.length;
    }
    if (start < segment.length) {
      spans.add(TextSpan(text: segment.substring(start), style: base));
    }
    return spans;
  }
}

// ---------------------------------------------------------------------------
// File bubble content
// ---------------------------------------------------------------------------

class _FileBubbleContent extends ConsumerWidget {
  const _FileBubbleContent({
    required this.message,
    required this.textColor,
    required this.timeStr,
    required this.isLocal,
    required this.showMeta,
  });

  final ChatMessage message;
  final Color textColor;
  final String timeStr;
  final bool isLocal;
  final bool showMeta;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isImage = message.isImage;
    final hasFile = message.localFilePath != null;
    final ephemeralBytes = message.isEphemeral && message.fileId != null
        ? ref.read(ephemeralMediaServiceProvider).getMedia(message.fileId!)
        : null;
    final hasEphemeralBytes = ephemeralBytes != null;
    final inProgress = message.transferProgress != null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Column(
        crossAxisAlignment: isLocal
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isImage && (hasFile || hasEphemeralBytes))
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: hasFile
                  ? GestureDetector(
                      onTap: () =>
                          _openLightbox(context, message.localFilePath!),
                      child: Image.file(
                        File(message.localFilePath!),
                        width: 200,
                        height: 200,
                        fit: BoxFit.cover,
                      ),
                    )
                  : GestureDetector(
                      onTap: () => _openMemoryLightbox(context, ephemeralBytes),
                      child: Image.memory(
                        ephemeralBytes!,
                        width: 200,
                        height: 200,
                        fit: BoxFit.cover,
                      ),
                    ),
            )
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _fileIcon(message.mimeType),
                  size: 32,
                  color: textColor.withAlpha(200),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        message.fileName ?? 'File',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (message.fileSize != null)
                        Text(
                          message.isEphemeral &&
                                  !inProgress &&
                                  !hasEphemeralBytes
                              ? 'Media expired from RAM'
                              : _formatFileSize(message.fileSize!),
                          style: TextStyle(
                            color: textColor.withAlpha(160),
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          if (message.isEphemeral)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.shield_outlined,
                    size: 12,
                    color: textColor.withAlpha(180),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Private · RAM-only',
                    style: TextStyle(
                      fontSize: 10,
                      color: textColor.withAlpha(180),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          if (inProgress)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(
                value: message.transferProgress,
                backgroundColor: textColor.withAlpha(40),
                valueColor: AlwaysStoppedAnimation<Color>(
                  textColor.withAlpha(200),
                ),
              ),
            ),
          if (hasFile && !inProgress && !isImage)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: TextButton.icon(
                onPressed: () => _openFile(context, message),
                icon: Icon(_openIcon(message.mimeType), size: 14),
                label: Text(_openLabel(message.mimeType)),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  minimumSize: Size.zero,
                ),
              ),
            ),
          if (hasEphemeralBytes &&
              !inProgress &&
              !isImage &&
              (message.mimeType?.startsWith('audio/') ?? false))
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: TextButton.icon(
                onPressed: () => _openEphemeralAudio(
                  context,
                  ephemeralBytes,
                  message.fileName ?? 'Audio',
                ),
                icon: const Icon(Icons.play_circle_outline, size: 14),
                label: const Text('Play'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  minimumSize: Size.zero,
                ),
              ),
            ),
          if (showMeta) ...[
            const SizedBox(height: 4),
            Text(
              timeStr,
              style: TextStyle(color: textColor.withAlpha(160), fontSize: 10),
            ),
          ],
        ],
      ),
    );
  }

  IconData _fileIcon(String? mime) {
    if (mime == null) return Icons.insert_drive_file_outlined;
    if (mime.startsWith('image/')) return Icons.image_outlined;
    if (mime.startsWith('audio/')) return Icons.audiotrack_outlined;
    if (mime.startsWith('video/')) return Icons.videocam_outlined;
    if (mime == 'application/pdf') return Icons.picture_as_pdf_outlined;
    return Icons.insert_drive_file_outlined;
  }

  IconData _openIcon(String? mime) {
    if (mime?.startsWith('audio/') ?? false) return Icons.play_circle_outline;
    if (mime?.startsWith('video/') ?? false) return Icons.play_circle_outline;
    return Icons.open_in_new;
  }

  String _openLabel(String? mime) {
    if (mime?.startsWith('audio/') ?? false) return 'Play';
    if (mime?.startsWith('video/') ?? false) return 'Play';
    return 'Open';
  }

  void _openFile(BuildContext context, ChatMessage message) {
    final path = message.localFilePath!;
    final mime = message.mimeType ?? '';
    final name = message.fileName ?? 'File';

    if (mime.startsWith('audio/')) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              AudioPlayerScreen.fromFile(filePath: path, title: name),
        ),
      );
    } else if (mime.startsWith('video/')) {
      if (Platform.isWindows) {
        OpenFile.open(path);
      } else {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => VideoPlayerScreen(filePath: path, title: name),
          ),
        );
      }
    } else {
      OpenFile.open(path);
    }
  }

  void _openEphemeralAudio(
    BuildContext context,
    Uint8List bytes,
    String title,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AudioPlayerScreen.fromBytes(bytes: bytes, title: title),
      ),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  void _openLightbox(BuildContext context, String path) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (ctx) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            actions: [
              IconButton(
                icon: const Icon(Icons.open_in_new),
                tooltip: 'Open image',
                onPressed: () => OpenFile.open(path),
              ),
            ],
          ),
          body: InteractiveViewer(
            minScale: 0.8,
            maxScale: 5,
            child: Center(child: Image.file(File(path))),
          ),
        ),
      ),
    );
  }

  void _openMemoryLightbox(BuildContext context, Uint8List bytes) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (ctx) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
          ),
          body: InteractiveViewer(
            minScale: 0.8,
            maxScale: 5,
            child: Center(child: Image.memory(bytes)),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reactions row
// ---------------------------------------------------------------------------

class _ReactionsRow extends StatelessWidget {
  const _ReactionsRow({required this.message, required this.isLocal});
  final ChatMessage message;
  final bool isLocal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chips = message.reactions.entries.map((entry) {
      final emoji = entry.key;
      final count = entry.value.length;
      final isMine = entry.value.contains(MessageOrigin.local);
      return Container(
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isMine
              ? theme.colorScheme.primary.withAlpha(40)
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: isMine
              ? Border.all(color: theme.colorScheme.primary.withAlpha(120))
              : null,
        ),
        child: Text(
          count > 1 ? '$emoji $count' : emoji,
          style: const TextStyle(fontSize: 14),
        ),
      );
    }).toList();

    return Row(
      mainAxisAlignment: isLocal
          ? MainAxisAlignment.end
          : MainAxisAlignment.start,
      children: chips,
    );
  }
}
