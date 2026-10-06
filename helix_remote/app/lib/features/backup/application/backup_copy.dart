import 'package:helix_remote/features/backup/application/backup_models.dart';

/// Every sentence the backup pages say about a failure, in one place.
///
/// Nothing here names a key, a code, a host or an exception: the engine's
/// failures carry none of those, and this keeps it that way.
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
    'The backup did not run. If you are on mobile data, turn on backup over '
        'mobile data or connect to Wi-Fi.',
  BackupProblem.unknown => 'That did not work. Try again.',
};
