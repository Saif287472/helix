import 'package:helix_remote_ui/helix_remote_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../admin_client.dart';
import '../theme/app_theme.dart';

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
  String _filter = '';

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
    if (widget.logs.lines.length != oldWidget.logs.lines.length &&
        _followTail) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
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

  List<String> get _visibleLines {
    if (_filter.isEmpty) return widget.logs.lines;
    final needle = _filter.toLowerCase();
    return widget.logs.lines
        .where((line) => line.toLowerCase().contains(needle))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final lines = _visibleLines;
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(context),
            const SizedBox(height: 14),
            _buildFilterField(context),
            const SizedBox(height: 14),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                padding: const EdgeInsets.all(12),
                child: lines.isEmpty
                    ? _buildEmptyState(context)
                    : _buildLineList(lines),
              ),
            ),
            if (!_followTail && lines.isNotEmpty)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () {
                    setState(() => _followTail = true);
                    _scrollToEnd();
                  },
                  icon: const Icon(Icons.arrow_downward, size: 16),
                  label: const Text('Jump to latest'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 10,
                runSpacing: 6,
                children: [
                  const Text(
                    'Live Log Streamer Console',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: widget.autoRefreshEnabled
                          ? const Color(0xFFDCFCE7)
                          : const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: widget.autoRefreshEnabled
                            ? const Color(0xFFBBF7D0)
                            : const Color(0xFFFDE68A),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: widget.autoRefreshEnabled
                                ? const Color(0xFF16A34A)
                                : const Color(0xFFD97706),
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          widget.autoRefreshEnabled
                              ? 'LIVE STREAM ACTIVE'
                              : 'STREAM PAUSED',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: widget.autoRefreshEnabled
                                ? const Color(0xFF166534)
                                : const Color(0xFFB45309),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (widget.onAutoRefreshChanged != null) ...[
              const Text(
                'Live',
                style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
              Switch(
                value: widget.autoRefreshEnabled,
                activeColor: const Color(0xFF2563EB),
                onChanged: widget.onAutoRefreshChanged,
              ),
            ],
            IconButton(
              icon: const Icon(Icons.copy_all, size: 20),
              tooltip: 'Copy all',
              color: const Color(0xFF64748B),
              onPressed: widget.logs.isEmpty
                  ? null
                  : () async {
                      await Clipboard.setData(
                        ClipboardData(text: widget.logs.lines.join('\n')),
                      );
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Logs copied to clipboard.')),
                      );
                    },
            ),
            IconButton(
              icon: const Icon(Icons.refresh, size: 20),
              tooltip: 'Refresh',
              color: const Color(0xFF64748B),
              onPressed: widget.onRefresh,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            const Icon(Icons.terminal, size: 14, color: Color(0xFF94A3B8)),
            const SizedBox(width: 6),
            Text(
              widget.logs.filePath ?? 'tail -f /var/log/helix/server.log',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFilterField(BuildContext context) {
    return TextField(
      onChanged: (value) => setState(() => _filter = value),
      style: const TextStyle(fontSize: 13, color: Color(0xFF0F172A)),
      decoration: InputDecoration(
        isDense: true,
        prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF64748B)),
        hintText: 'Filter lines',
        hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF2563EB)),
        ),
      ),
    );
  }

  Widget _buildLineList(List<String> lines) {
    return ListView.builder(
      controller: _scrollController,
      itemCount: lines.length,
      itemBuilder: (context, index) {
        final line = lines[index];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2.5),
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
      },
    );
  }

  /// Errors, warnings, and info are visually distinguished matching console
  Color _colorFor(String line) {
    if (line.contains('[ERROR]')) return const Color(0xFFDC2626);
    if (line.contains('[WARN]')) return const Color(0xFFD97706);
    if (line.contains('[OK]')) return const Color(0xFF16A34A);
    return const Color(0xFF2563EB);
  }

  Widget _buildEmptyState(BuildContext context) {
    // A filter that matches nothing is the operator's own doing - say so
    // rather than showing the server's "why is this empty" explanation,
    // which would be misleading here.
    if (_filter.isNotEmpty && widget.logs.lines.isNotEmpty) {
      return Center(
        child: Text(
          'No lines match "$_filter".',
          textAlign: TextAlign.center,
          style: TextStyle(color: context.textSecondary),
        ),
      );
    }
    final message = widget.logs.message;
    return Center(
      child: Padding(
        padding: HelixInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.terminal, size: 40, color: context.textSecondary),
            const SizedBox(height: 16),
            Text(
              message ?? 'No logs available.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.textSecondary, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
