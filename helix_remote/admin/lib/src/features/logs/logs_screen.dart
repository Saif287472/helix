import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:helix_admin/src/features/logs/logs_controller.dart';
import 'package:helix_admin/src/session/admin_session_controller.dart';
import 'package:helix_admin/src/widgets/dialogs.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// The server's log: the recent tail, a filter, and a live feed over the
/// admin WebSocket (polling where a socket is not possible). Lines are
/// redacted by the server; nothing is stored here.
class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key, required this.adminContext, this.pollInterval});

  final AdminContext adminContext;
  final Duration? pollInterval;

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  late final LogsController _logs;
  final _filter = TextEditingController();

  @override
  void initState() {
    super.initState();
    _logs = LogsController(
      widget.adminContext,
      pollInterval: widget.pollInterval ?? const Duration(seconds: 3),
    )..load();
  }

  @override
  void dispose() {
    _logs.dispose();
    _filter.dispose();
    super.dispose();
  }

  Future<void> _copy() async {
    final text = _logs.shown.map((l) => l.raw).join('\n');
    if (text.isEmpty) {
      showMessage(context, 'There are no lines to copy.');
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) showMessage(context, 'Copied ${_logs.shown.length} lines.');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _logs,
      builder: (context, _) {
        final scheme = Theme.of(context).colorScheme;
        final shown = _logs.shown;
        final Widget body;
        if (_logs.loading && _logs.lines.isEmpty) {
          body = const Center(child: HelixSkeleton(width: 180, height: 24));
        } else if (_logs.error != null && _logs.lines.isEmpty) {
          body = HelixErrorState(message: _logs.error!, onRetry: _logs.load);
        } else if (shown.isEmpty) {
          body = HelixEmptyState(
            icon: Icons.article_outlined,
            title: _logs.lines.isEmpty
                ? 'No log lines yet'
                : 'No lines match the filter',
            action: _logs.lines.isEmpty
                ? null
                : TextButton(
                    onPressed: () {
                      _filter.clear();
                      _logs.setFilter('');
                    },
                    child: const Text('Clear filter'),
                  ),
          );
        } else {
          // Newest at the bottom, and the view stays anchored there as new
          // lines arrive.
          body = ListView.builder(
            reverse: true,
            padding: const EdgeInsets.symmetric(
              horizontal: HelixSpace.md,
              vertical: HelixSpace.xs,
            ),
            itemCount: shown.length,
            itemBuilder: (context, index) {
              final entry = shown[shown.length - 1 - index];
              return _LogLine(entry: entry);
            },
          );
        }
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                HelixSpace.md,
                HelixSpace.sm,
                HelixSpace.xs,
                0,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _filter,
                      onChanged: _logs.setFilter,
                      decoration: const InputDecoration(
                        labelText: 'Filter lines',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.filter_list),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Reload log',
                    icon: const Icon(Icons.refresh),
                    onPressed: _logs.loading ? null : _logs.load,
                  ),
                  IconButton(
                    tooltip: 'Copy shown lines',
                    icon: const Icon(Icons.copy),
                    onPressed: _copy,
                  ),
                ],
              ),
            ),
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: HelixSpace.md,
              ),
              title: const Text('Follow live'),
              subtitle: Text(switch (_logs.feed) {
                LogFeed.paused => 'Showing the last lines; not updating.',
                LogFeed.live => 'New lines appear as they are written.',
                LogFeed.polling => _logs.feedNote ?? 'Reloading.',
              }),
              value: _logs.feed != LogFeed.paused,
              onChanged: _logs.setLive,
            ),
            if (_logs.error != null && _logs.lines.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: HelixSpace.md),
                child: Text(
                  _logs.error!,
                  style: TextStyle(color: scheme.error),
                ),
              ),
            const Divider(height: 1),
            Expanded(child: body),
          ],
        );
      },
    );
  }
}

class _LogLine extends StatelessWidget {
  const _LogLine({required this.entry});

  final LogEntry entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = entry.isError
        ? scheme.error
        : entry.isWarning
        ? HelixStatusColors.onCautionContainer
        : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(
        entry.raw,
        style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: color),
      ),
    );
  }
}
