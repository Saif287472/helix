import 'package:helix_remote/features/backup/application/backup_models.dart';

/// Every sentence the backup pages say about a failure, in one place.
///
/// Nothing here names a key, a code, a host or an exception: the engine's
/// failures carry none of those, and this keeps it that way.

/// 2318 as "2,318", for "Restored 2,318 messages".
String messageCount(int n) =>
    '$n'.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

/// A short title for [problem], over [backupProblemText] (the restore step's
/// failed card).
String backupProblemTitle(BackupProblem problem) => switch (problem) {
  BackupProblem.noBackup => 'No backup was found',
  BackupProblem.wrongKey ||
  BackupProblem.accountMismatch => 'This backup could not be opened',
  BackupProblem.corrupt => 'The backup is damaged',
  BackupProblem.newerFormat => 'Update the app first',
  BackupProblem.rolledBack => 'An older backup was refused',
  BackupProblem.offline => 'You are offline',
  BackupProblem.conflict => 'Another device is backing up',
  BackupProblem.notAllowed => 'Helix refused it',
  BackupProblem.waitingForWifi => 'Waiting for Wi-Fi',
  _ => 'The restore did not finish',
};

String backupProblemText(BackupProblem problem) => switch (problem) {
  BackupProblem.noBackup =>
    'No backup was found for this account. Back up on your other phone '
        'first, then try again.',
  BackupProblem.wrongKey =>
    'This backup cannot be opened with your account. It may have been made '
        'before your account was reset, or the recovery secret is not the '
        'one it was made with.',
  BackupProblem.corrupt =>
    'The backup is damaged and cannot be read. Make a new one on a device '
        'that still has your chats.',
  BackupProblem.newerFormat =>
    'This backup was made by a newer version of Helix. Update the app and '
        'try again.',
  BackupProblem.rolledBack =>
    'The server returned an older backup than this phone already knows, so '
        'it was not used.',
  BackupProblem.accountMismatch => 'This backup belongs to another account.',
  BackupProblem.tooLarge =>
    'Your history is too large to back up, even after leaving out the '
        'oldest messages.',
  BackupProblem.cancelled => 'Stopped.',
  BackupProblem.offline =>
    'You are offline, or Helix cannot be reached. Check your connection and '
        'try again.',
  BackupProblem.conflict =>
    'Another device was backing up at the same time. Try again in a moment.',
  BackupProblem.weakSecret =>
    'That recovery secret is too weak to protect your backup. Use the one '
        'Helix makes for you.',
  BackupProblem.noOtherDevices =>
    'This is your only device. Sign in on another device first.',
  BackupProblem.incomplete =>
    'The transfer is incomplete: some of it did not arrive. Ask the other '
        'device to send it again.',
  BackupProblem.expired =>
    'The transfer is no longer available. Ask the other device to send it '
        'again.',
  BackupProblem.notAllowed =>
    'Helix would not take the backup. Check that you are still signed in on '
        'this phone, then try again.',
  BackupProblem.waitingForWifi =>
    'You were on mobile data and backups wait for Wi-Fi. Turn on backup over '
        'mobile data, or back up when you are on Wi-Fi.',
  BackupProblem.unknown => 'That did not work. Try again.',
};
