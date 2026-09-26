import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../admin_client.dart';

class LogsTab extends StatefulWidget {
  const LogsTab({
    super.key,
    required this.logs,
    required this.onRefresh,
    this.autoRefreshEnabled = false,
    this.onAutoRefreshChanged,
  });

  final ServerLogs logs;
  final VoidCallback onRefresh;

  /// Whether the shell is polling for new lines on a timer. Owned above
  /// this widget so the poll keeps running while other tabs are open.
  final bool autoRefreshEnabled;
  final ValueChanged<bool>? onAutoRefreshChanged;

  @override
  State<LogsTab> createState() => _LogsTabState();
}

class _LogsTabState extends State<LogsTab> {
  final _scrollController = ScrollController();
  final _filterController = TextEditingController();

  /// Case-insensitive substring filter over the visible lines.
  ///
  /// Was a `final String _filter = ''`, which made the whole filtering branch
  /// of [_visibleLines] unreachable and left the console with no way to find
  /// an error among thousands of lines. Restored rather than deleted: the
  /// filtering logic was still here, only frozen.
  String _filter = '';
  bool _isCleared = false;
  int _clearedAtIndex = 0;

  /// Whether new lines should pull the view to the bottom. Turned off as
  /// soon as the operator scrolls up, so reading back through history
  /// isn't yanked away every time the poll lands.
  bool _followTail = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _filterController.addListener(_onFilterChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
  }

  void _onFilterChanged() {
    final next = _filterController.text;
    if (next == _filter) return;
    setState(() => _filter = next);
  }

  @override
  void didUpdateWidget(LogsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.logs.lines.length != oldWidget.logs.lines.length) {
      if (_followTail) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
      }
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _filterController.removeListener(_onFilterChanged);
    _filterController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    // A small tolerance keeps "following" true through the sub-pixel
    // wobble that momentum scrolling leaves behind at the very bottom.
    final atBottom = position.pixels >= position.maxScrollExtent - 32;
    if (atBottom != _followTail) {
      setState(() => _followTail = atBottom);
    }
  }

  void _scrollToEnd() {
    if (!_scrollController.hasClients) return;
    _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
  }

  List<String> get _visibleLines {
    List<String> baseLines;
    if (widget.logs.lines.isNotEmpty) {
      if (_isCleared && _clearedAtIndex <= widget.logs.lines.length) {
        baseLines = widget.logs.lines.sublist(_clearedAtIndex);
      } else {
        baseLines = widget.logs.lines;
      }
    } else {
      // An empty console is reported as empty. The server sends a `message`
      // explaining *why* it has nothing (no log sink, no file, nothing logged
      // yet) and `_buildEmptyState` shows that verbatim - substituting sample
      // lines here hid the one piece of text that helps the operator.
      baseLines = const <String>[];
    }

    if (_filter.isEmpty) return baseLines;
    final needle = _filter.toLowerCase();
    return baseLines
        .where((line) => line.toLowerCase().contains(needle))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final lines = _visibleLines;
    final isPaused = !widget.autoRefreshEnabled;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header Row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Live Server Console',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F172A),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isPaused ? const Color(0xFFFFFBEB) : const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isPaused ? const Color(0xFFFDE68A) : const Color(0xFFA7F3D0),
                ),
              ),
              child: Text(
                isPaused ? 'STREAM PAUSED' : 'LIVE STREAMING...',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isPaused ? const Color(0xFFD97706) : const Color(0xFF059669),
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Main Console Card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Action Buttons Row (Refresh, Pause Stream, Clear Logs, Copy Tail)
              Row(
                children: [
                  OutlinedButton.icon(
                    key: const Key('logs_refresh_button'),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF334155),
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      minimumSize: Size.zero,
                    ),
                    onPressed: () {
                      // Always available: with the stream paused, a failed
                      // poll is otherwise indistinguishable from an idle
                      // server and there is no way to retry.
                      widget.onRefresh();
                    },
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Refresh', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton(
                    key: const Key('logs_stream_toggle_button'),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF334155),
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      minimumSize: Size.zero,
                    ),
                    onPressed: () {
                      if (widget.onAutoRefreshChanged != null) {
                        widget.onAutoRefreshChanged!(!widget.autoRefreshEnabled);
                      }
                    },
                    child: Text(
                      widget.autoRefreshEnabled ? 'Pause Stream' : 'Resume Stream',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF334155),
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      minimumSize: Size.zero,
                    ),
                    onPressed: () {
                      setState(() {
                        _isCleared = true;
                        _clearedAtIndex = widget.logs.lines.length;
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Console log display cleared')),
                      );
                    },
                    child: const Text('Clear Logs', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF334155),
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      minimumSize: Size.zero,
                    ),
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      final content = lines.join('\n');
                      await Clipboard.setData(ClipboardData(text: content));
                      if (!mounted) return;
                      messenger.showSnackBar(
                        const SnackBar(content: Text('Log tail copied to clipboard')),
                      );
                    },
                    child: const Text('Copy Tail', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Filter field
              TextField(
                controller: _filterController,
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Filter lines…',
                  hintStyle: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF94A3B8),
                  ),
                  prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF94A3B8)),
                  suffixIcon: _filter.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear, size: 18, color: Color(0xFF94A3B8)),
                          tooltip: 'Clear filter',
                          onPressed: _filterController.clear,
                        ),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Log Streamer Window (Fixed height ~320px matching demo image)
              SizedBox(
                height: 320,
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: lines.isEmpty
                      ? (_filter.isNotEmpty
                            ? _buildFilterMissState()
                            : _buildEmptyState(context))
                      : ListView.builder(
                          controller: _scrollController,
                          itemCount: lines.length,
                          itemBuilder: (context, index) {
                            return _buildFormattedLine(lines[index]);
                          },
                        ),
                ),
              ),

              if (!_followTail && lines.isNotEmpty) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () {
                      setState(() => _followTail = true);
                      _scrollToEnd();
                    },
                    icon: const Icon(Icons.arrow_downward, size: 14),
                    label: const Text('Jump to latest', style: TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  String _formatTimeLocal(String timeStr) {
    final dt = DateTime.tryParse(timeStr);
    if (dt != null) {
      final local = dt.toLocal();
      final h = local.hour.toString().padLeft(2, '0');
      final m = local.minute.toString().padLeft(2, '0');
      final s = local.second.toString().padLeft(2, '0');
      return '$h:$m:$s';
    }
    return timeStr;
  }

  Widget _buildFormattedLine(String line) {
    final match = RegExp(r'^(\d{4}-\d{2}-\d{2}T[\d:\.Z]+|\d{2}:\d{2}:\d{2})\s*(\[[A-Z]+\])?\s*(.*)$').firstMatch(line);
    if (match != null) {
      final timeStr = match.group(1) ?? '';
      final tagStr = match.group(2) ?? '';
      final msgStr = match.group(3) ?? '';
      final localTime = _formatTimeLocal(timeStr);

      Color tagColor = const Color(0xFF2563EB);
      if (tagStr.contains('OK')) tagColor = const Color(0xFF059669);
      if (tagStr.contains('WARN')) tagColor = const Color(0xFFD97706);
      if (tagStr.contains('ERROR')) tagColor = const Color(0xFFDC2626);

      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3.0),
        child: SelectableText.rich(
          TextSpan(
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5, height: 1.4),
            children: [
              TextSpan(text: '$localTime ', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2563EB))),
              if (tagStr.isNotEmpty)
                TextSpan(text: '$tagStr ', style: TextStyle(fontWeight: FontWeight.bold, color: tagColor)),
              TextSpan(text: msgStr, style: const TextStyle(color: Color(0xFF334155))),
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.0),
      child: SelectableText(
        line,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 12.5,
          color: _colorFor(line),
          height: 1.4,
        ),
      ),
    );
  }

  Color _colorFor(String line) {
    if (line.contains('[ERROR]')) return const Color(0xFFDC2626);
    if (line.contains('[WARN]')) return const Color(0xFFD97706);
    if (line.contains('[OK]')) return const Color(0xFF059669);
    return const Color(0xFF2563EB);
  }

  /// Shown when a filter matches nothing.
  ///
  /// Deliberately separate from [_buildEmptyState]: a filter miss means the
  /// server *did* return lines and they simply did not match, so the
  /// server's "no log source" explanation and the file path would both be
  /// misleading here - it would read as though the server had nothing to say.
  Widget _buildFilterMissState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.filter_alt_off, size: 36, color: Color(0xFF94A3B8)),
            const SizedBox(height: 12),
            Text(
              'No lines match "$_filter"',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontSize: 13,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _filterController.clear,
              child: const Text('Clear filter', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final message = widget.logs.message;
    // `source` distinguishes "nothing logged yet" from "this server cannot
    // write a log file at all", and `filePath` tells the operator which file
    // is being tailed. Both are sent by the server on every response.
    final source = widget.logs.source;
    final sourceLabel = switch (source) {
      'file' => 'Reading from log file',
      'memory' => 'Reading from in-memory buffer',
      'none' => 'No log source available',
      _ => 'Log source: $source',
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.terminal, size: 36, color: Color(0xFF94A3B8)),
            const SizedBox(height: 12),
            Text(
              message ?? 'No logs available.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF64748B), height: 1.5, fontSize: 13),
            ),
            const SizedBox(height: 10),
            Text(
              sourceLabel,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (widget.logs.filePath != null &&
                widget.logs.filePath!.isNotEmpty) ...[
              const SizedBox(height: 4),
              SelectableText(
                widget.logs.filePath!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
