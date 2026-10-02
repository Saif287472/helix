/// A command line: `helix_v2 [--option value]… <command> [args…]`.
///
/// Options may appear anywhere. Flags (see [booleanFlags]) take no value.
/// `--option=value` works too.
final class CliArgs {
  CliArgs._(this.command, this.positional, this.options, this.flags);

  /// Options that never take a value.
  static const booleanFlags = {
    'json',
    'replace',
    'show',
    'lost',
    'help',
    'all',
  };

  factory CliArgs.parse(List<String> args) {
    final options = <String, String>{};
    final flags = <String>{};
    final positional = <String>[];
    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      if (arg == '-h') {
        flags.add('help');
      } else if (arg.startsWith('--') && arg.length > 2) {
        final eq = arg.indexOf('=');
        final name = eq < 0 ? arg.substring(2) : arg.substring(2, eq);
        if (booleanFlags.contains(name)) {
          flags.add(name);
        } else if (eq >= 0) {
          options[name] = arg.substring(eq + 1);
        } else if (i + 1 < args.length) {
          options[name] = args[++i];
        } else {
          throw CliUsageError('--$name needs a value');
        }
      } else {
        positional.add(arg);
      }
    }
    return CliArgs._(
      positional.isEmpty ? null : positional.first,
      positional.isEmpty ? const [] : positional.sublist(1),
      options,
      flags,
    );
  }

  final String? command;

  /// What follows the command.
  final List<String> positional;
  final Map<String, String> options;
  final Set<String> flags;

  bool flag(String name) => flags.contains(name);

  String? option(String name) => options[name];
}

/// A mistake in how the CLI was called (exit code 2).
final class CliUsageError implements Exception {
  CliUsageError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A failure with a message that is safe to print (exit code 1).
final class CliError implements Exception {
  CliError(this.message);

  final String message;

  @override
  String toString() => message;
}
