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
  final String _filter = '';
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
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

  static const List<String> _sampleLogs = [
    '21:44:01 [INFO] WebSockets connection established from 104.28.14.2',
    '21:43:55 [OK] Database VACUUM INTO /backups/helix_20260924.db completed',
    '21:42:10 [INFO] Contact discovery phone hash Argon2id lookup (24ms)',
    '21:40:02 [WARN] SMS Gateway response balance check: \$48.50 remaining',
    '21:38:15 [INFO] Server display name updated to "Helix CipherNode Alpha"',
  ];

  List<String> get _visibleLines {
    List<String> baseLines;
    if (widget.logs.lines.isNotEmpty) {
      if (_isCleared && _clearedAtIndex <= widget.logs.lines.length) {
        baseLines = widget.logs.lines.sublist(_clearedAtIndex);
      } else {
        baseLines = widget.logs.lines;
      }
    } else {
      baseLines = _isCleared ? <String>[] : _sampleLogs;
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
              // Action Buttons Row (Pause Stream, Clear Logs, Copy Tail)
              Row(
                children: [
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
                      ? _buildEmptyState(context)
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

  Widget _buildEmptyState(BuildContext context) {
    final message = widget.logs.message;
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
          ],
        ),
      ),
    );
  }
}
