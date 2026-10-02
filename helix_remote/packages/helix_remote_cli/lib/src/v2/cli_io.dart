import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Everything the CLI reads from and writes to the outside world, so tests
/// run whole commands without a terminal.
abstract interface class CliIo {
  /// Environment variables (never printed).
  Map<String, String> get env;

  void out(String line);

  void err(String line);

  /// The next line of input, or null at the end. With [secret] the line is
  /// not echoed to the terminal. [prompt] goes to stderr.
  Future<String?> readLine(String prompt, {bool secret = false});

  /// Completes when the user interrupts (Ctrl-C).
  Future<void> get interrupted;
}

/// The real terminal.
final class ConsoleIo implements CliIo {
  ConsoleIo() {
    _lines = stdin
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_onLine, onDone: _onDone);
    ProcessSignal.sigint.watch().first.then((_) => _interrupted.complete());
  }

  late final StreamSubscription<String> _lines;
  final List<String> _buffer = [];
  final List<Completer<String?>> _waiting = [];
  bool _done = false;
  final Completer<void> _interrupted = Completer<void>();

  @override
  Map<String, String> get env => Platform.environment;

  @override
  void out(String line) => stdout.writeln(line);

  @override
  void err(String line) => stderr.writeln(line);

  @override
  Future<void> get interrupted => _interrupted.future;

  void _onLine(String line) {
    if (_waiting.isNotEmpty) {
      _waiting.removeAt(0).complete(line);
    } else {
      _buffer.add(line);
    }
  }

  void _onDone() {
    _done = true;
    for (final waiting in _waiting) {
      waiting.complete(null);
    }
    _waiting.clear();
  }

  @override
  Future<String?> readLine(String prompt, {bool secret = false}) async {
    stderr.write('$prompt: ');
    var echo = true;
    if (secret && stdin.hasTerminal) {
      echo = stdin.echoMode;
      stdin.echoMode = false;
    }
    try {
      if (_buffer.isNotEmpty) return _buffer.removeAt(0);
      if (_done) return null;
      final next = Completer<String?>();
      _waiting.add(next);
      return await next.future;
    } finally {
      if (secret && stdin.hasTerminal) {
        stdin.echoMode = echo;
        stderr.writeln();
      }
    }
  }

  Future<void> close() => _lines.cancel();
}

/// In-memory I/O for tests.
class BufferIo implements CliIo {
  BufferIo({
    Map<String, String> env = const {},
    Iterable<String> input = const [],
  }) : env = {...env},
       _input = [...input];

  @override
  final Map<String, String> env;

  final List<String> _input;
  final List<String> stdoutLines = [];
  final List<String> stderrLines = [];
  final List<String> prompts = [];

  /// Everything printed, for "no secret appears" assertions.
  String get everything =>
      [...stdoutLines, ...stderrLines, ...prompts].join('\n');

  @override
  void out(String line) => stdoutLines.add(line);

  @override
  void err(String line) => stderrLines.add(line);

  @override
  Future<String?> readLine(String prompt, {bool secret = false}) async {
    prompts.add(prompt);
    return _input.isEmpty ? null : _input.removeAt(0);
  }

  @override
  Future<void> get interrupted => Completer<void>().future;
}
