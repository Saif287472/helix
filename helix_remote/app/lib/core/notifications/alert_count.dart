import 'dart:convert';
import 'dart:io';

import 'package:helix_remote/core/platform/app_storage.dart';

/// How many messages an account's notification has announced since it was
/// last cleared.
///
/// Kept in the account's folder, not in memory, because two isolates raise
/// the one notification: the push isolate for a wake-up and the running app
/// while it is in the background. Each used to count only its own run, and
/// whichever posted last replaced the other's number with its own (two wake-ups
/// of two messages said "2 new messages" over four). The notification is
/// replaced by id, so the number it shows has to be the sum, wherever it was
/// counted. Clearing the notification (the chats came on screen, the account
/// was removed) starts it again from nothing.
final class AlertCountStore {
  const AlertCountStore({Future<File> Function(String account)? fileOf})
    : _fileOf = fileOf ?? AppPaths.alertCountFile;

  final Future<File> Function(String account) _fileOf;

  /// Adds [arrived] to [account]'s count and returns the new total. A count
  /// that cannot be stored is the number of this pass alone, which is what the
  /// notification said before it was kept.
  Future<int> add(String account, int arrived) async {
    var total = arrived;
    try {
      final file = await _fileOf(account);
      total += await _read(file);
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode({'n': total}));
    } on Object {
      // The notification still goes up with what this pass knows.
    }
    return total;
  }

  /// Forgets [account]'s count: its notification is gone.
  Future<void> reset(String account) async {
    try {
      final file = await _fileOf(account);
      if (await file.exists()) await file.delete();
    } on Object {
      // Nothing stored, or nowhere to store it.
    }
  }

  Future<int> _read(File file) async {
    try {
      final json = jsonDecode(await file.readAsString());
      final n = json is Map ? json['n'] : null;
      return n is int && n > 0 ? n : 0;
    } on Object {
      return 0;
    }
  }
}
