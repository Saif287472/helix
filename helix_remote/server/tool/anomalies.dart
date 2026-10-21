// Shows the apps' anomaly reports as they arrive: the `client_anomaly` lines
// of the server's log, one readable block each.
//
//   dart run tool/anomalies.dart <log file>     follow the file (HELIX_LOG_FILE)
//   dart run tool/anomalies.dart <log file> --all   print what it holds, then follow
//   <server output> | dart run tool/anomalies.dart  read lines from a pipe
//
// Lines are already redacted by the server. Nothing is written anywhere.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final all = args.contains('--all');
  final path = args.where((a) => !a.startsWith('--')).firstOrNull;
  if (path == null) {
    await stdin
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .forEach(_show);
    return;
  }
  await _follow(File(path), fromStart: all);
}

/// Reads [file] as it grows; a rotation (the file shrinks or is replaced)
/// starts again at its beginning.
Future<void> _follow(File file, {required bool fromStart}) async {
  stdout.writeln('Watching ${file.path} for app anomalies (Ctrl+C to stop).');
  var offset = fromStart || !file.existsSync() ? 0 : file.lengthSync();
  var partial = '';
  while (true) {
    if (file.existsSync()) {
      final length = file.lengthSync();
      if (length < offset) offset = 0;
      if (length > offset) {
        final raf = file.openSync();
        try {
          raf.setPositionSync(offset);
          final bytes = raf.readSync(length - offset);
          offset = length;
          final text = partial + utf8.decode(bytes, allowMalformed: true);
          final lines = text.split('\n');
          partial = lines.removeLast();
          lines.forEach(_show);
        } finally {
          raf.closeSync();
        }
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
}

void _show(String line) {
  if (!line.contains('client_anomaly')) return;
  final Object? decoded;
  try {
    decoded = jsonDecode(line);
  } on FormatException {
    return;
  }
  if (decoded is! Map || decoded['event'] != 'client_anomaly') return;
  final entry = decoded;
  String text(String key) => '${entry[key] ?? ''}';
  final device = text('device_id');
  final short = device.length > 6
      ? '…${device.substring(device.length - 6)}'
      : device;
  final at = DateTime.tryParse(text('at'))?.toLocal();
  final when = at == null
      ? text('ts')
      : '${at.year}-${_two(at.month)}-${_two(at.day)} '
            '${_two(at.hour)}:${_two(at.minute)}:${_two(at.second)}';
  final build = entry['debug'] == true ? 'debug' : 'release';
  stdout.writeln(
    '\n$when  ${text('kind').toUpperCase()}  ${text('where')}\n'
    '  ${text('platform')} ${text('app_version')} $build · device $short',
  );
  final message = text('message');
  if (message.isNotEmpty) stdout.writeln('  $message');
  final fields = entry['fields'];
  if (fields is Map && fields.isNotEmpty) {
    stdout.writeln(
      '  ${[for (final e in fields.entries) '${e.key}=${e.value}'].join('  ')}',
    );
  }
  final stack = text('stack');
  if (stack.isNotEmpty) {
    for (final l in stack.split('\n').take(12)) {
      stdout.writeln('    $l');
    }
  }
}

String _two(int n) => n.toString().padLeft(2, '0');
