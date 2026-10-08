import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:helix_admin/src/features/logs/logs_controller.dart';
import 'package:helix_admin/src/session/admin_session_controller.dart';
import 'package:helix_admin/src/widgets/console_kit.dart';
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
        final shown = _logs.shown;
        final following = _logs.feed != LogFeed.paused;
        final Widget pane;
        if (_logs.loading && _logs.lines.isEmpty) {
          pane = const ConsoleLoading(label: 'Loading the log');
        } else if (_logs.error != null && _logs.lines.isEmpty) {
          pane = Center(
            child: ConsoleBanner(
              title: 'Something went wrong',
              message: _logs.error!,
              onRetry: _logs.load,
            ),
          );
        } else if (shown.isEmpty) {
          pane = Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.terminal,
                  size: 34,
                  color: HelixConsoleColors.textFaint,
                ),
                const SizedBox(height: 10),
                Text(
                  _logs.lines.isEmpty
                      ? 'No log lines yet'
                      : 'No lines match the filter',
                  style: const TextStyle(
                    fontSize: 13,
                    color: HelixConsoleColors.textMuted,
                  ),
                ),
                if (_logs.lines.isNotEmpty)
                  TextButton(
                    onPressed: () {
                      _filter.clear();
                      _logs.setFilter('');
                    },
                    child: const Text('Clear filter'),
                  ),
              ],
            ),
          );
        } else {
          // Newest at the bottom, and the view stays anchored there as new
          // lines arrive.
          pane = ListView.builder(
            reverse: true,
            itemCount: shown.length,
            itemBuilder: (context, index) =>
                _LogLine(entry: shown[shown.length - 1 - index]),
          );
        }
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(child: ConsoleHeading('Live Server Console')),
                  ConsolePill(
                    label: following ? 'Live streaming' : 'Stream paused',
                    tone: following ? ConsoleTone.ok : ConsoleTone.warn,
                    upper: true,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Expanded(
                child: ConsoleCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _logs.loading ? null : _logs.load,
                              style: ConsoleButtons.outlined,
                              child: const Text('Reload'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => _logs.setLive(!following),
                              style: ConsoleButtons.outlined,
                              child: Text(following ? 'Pause' : 'Follow live'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _copy,
                              style: ConsoleButtons.outlined,
                              child: const Text('Copy'),
                            ),
                          ),
                        ],
                      ),
                      if (following && _logs.feed == LogFeed.polling) ...[
                        const SizedBox(height: 8),
                        Text(
                          _logs.feedNote ?? 'Reloading every few seconds.',
                          style: const TextStyle(
                            fontSize: 11,
                            color: HelixConsoleColors.textMuted,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      TextField(
                        controller: _filter,
                        onChanged: _logs.setFilter,
                        style: const TextStyle(
                          fontSize: 13,
                          fontFamily: 'monospace',
                        ),
                        decoration: const InputDecoration(
                          hintText: 'Filter lines…',
                          isDense: true,
                          prefixIcon: Icon(
                            Icons.search,
                            size: 20,
                            color: HelixConsoleColors.textFaint,
                          ),
                        ),
                      ),
                      if (_logs.error != null && _logs.lines.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          _logs.error!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: HelixConsoleColors.danger,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: HelixConsoleColors.sunken,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: HelixConsoleColors.border,
                            ),
                          ),
                          child: pane,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// One line: the time in blue, the level in its colour, then the event.
class _LogLine extends StatelessWidget {
  const _LogLine({required this.entry});

  final LogEntry entry;

  @override
  Widget build(BuildContext context) {
    final parts = _split(entry);
    final tag = parts.level;
    final Color tagColor = switch (tag) {
      'error' => HelixConsoleColors.danger,
      'warn' || 'warning' => HelixConsoleColors.onWarn,
      _ => HelixConsoleColors.onOk,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: SelectableText.rich(
        TextSpan(
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 12.5,
            height: 1.4,
            color: HelixConsoleColors.textBody,
          ),
          children: [
            if (parts.time != null)
              TextSpan(
                text: '${parts.time} ',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: HelixConsoleColors.accent,
                ),
              ),
            if (tag != null)
              TextSpan(
                text: '[${tag.toUpperCase()}] ',
                style: TextStyle(fontWeight: FontWeight.w800, color: tagColor),
              ),
            TextSpan(text: parts.text),
          ],
        ),
      ),
    );
  }

  /// The server writes JSON objects: `ts`, `level`, `event` and fields. Any
  /// other line is shown as it is.
  static ({String? time, String? level, String text}) _split(LogEntry entry) {
    try {
      final json = jsonDecode(entry.raw);
      if (json is Map<String, Object?>) {
        final ts = DateTime.tryParse('${json['ts']}');
        final time = ts == null
            ? null
            : [
                ts.toLocal().hour,
                ts.toLocal().minute,
                ts.toLocal().second,
              ].map((n) => n.toString().padLeft(2, '0')).join(':');
        final event = '${json['event'] ?? ''}';
        final rest = [
          for (final e in json.entries)
            if (!const {'ts', 'level', 'event'}.contains(e.key))
              '${e.key}=${e.value}',
        ];
        return (
          time: time,
          level: entry.level,
          text: [event, ...rest].where((p) => p.isNotEmpty).join(' '),
        );
      }
    } on FormatException {
      // Plain text.
    }
    return (time: null, level: entry.level, text: entry.raw);
  }
}
