import 'dart:io';

import 'package:helix_remote_cli/v2.dart';

/// The v2 command line client: `dart run helix_remote_cli:helix_v2 help`.
Future<void> main(List<String> args) async {
  exit(await runHelixCli(args));
}
