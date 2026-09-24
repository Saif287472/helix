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
      color: HelixColorTokens.cFF08080C,
      child: Padding(
        padding: HelixInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(context),
            const SizedBox(height: 12),
            _buildFilterField(context),
            const Divider(),
            Expanded(
              child: lines.isEmpty
                  ? _buildEmptyState(context)
                  : _buildLineList(lines),
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
            const Expanded(
              child: Text(
                'Live Server Console Logs',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            if (widget.onAutoRefreshChanged != null) ...[
              Text(
                'Live',
                style: TextStyle(fontSize: 12, color: context.textSecondary),
              ),
              Switch(
                value: widget.autoRefreshEnabled,
                onChanged: widget.onAutoRefreshChanged,
              ),
            ],
            IconButton(
              icon: const Icon(Icons.copy_all),
              tooltip: 'Copy all',
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
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
              onPressed: widget.onRefresh,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: widget.autoRefreshEnabled ? const Color(0xFF059669) : Colors.grey,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              widget.logs.filePath ?? 'tail -f /var/log/helix/server.log',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: context.textFaint,
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
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        isDense: true,
        prefixIcon: const Icon(Icons.search, size: 18),
        hintText: 'Filter lines',
        hintStyle: TextStyle(color: context.textSecondary, fontSize: 13),
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
          padding: HelixInsets.symmetric(vertical: 4),
          child: SelectableText(
            line,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              color: _colorFor(line),
            ),
          ),
        );
      },
    );
  }

  /// Errors and warnings are worth spotting at a glance in a wall of
  /// green monospace.
  Color _colorFor(String line) {
    if (line.contains('[ERROR]')) return HelixColorTokens.cFFFF6B6B;
    if (line.contains('[WARN]')) return HelixColorTokens.cFFFFC107;
    return Colors.greenAccent;
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
