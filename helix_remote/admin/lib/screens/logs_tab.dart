import 'package:flutter/material.dart';

class LogsTab extends StatelessWidget {
  const LogsTab({super.key, required this.logs, required this.onRefresh});

  final List<String> logs;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF08080C),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Live Server Console Logs (Last 100)',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: onRefresh,
                ),
              ],
            ),
            const Divider(),
            Expanded(
              child: logs.isEmpty
                  ? const Center(
                      child: Text(
                        'No logs available.',
                        style: TextStyle(color: Colors.white38),
                      ),
                    )
                  : ListView.builder(
                      itemCount: logs.length,
                      itemBuilder: (context, index) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text(
                            logs[index],
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 13,
                              color: Colors.greenAccent,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
