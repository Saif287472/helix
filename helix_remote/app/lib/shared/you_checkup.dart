import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/engine/clock.dart';
import 'package:helix_remote/core/format/labels.dart';
import 'package:helix_remote/features/backup/application/backup_providers.dart';
import 'package:helix_remote/features/devices/application/devices_providers.dart';
import 'package:helix_remote/features/settings/application/account_providers.dart';
import 'package:helix_remote/features/settings/application/settings_providers.dart';

/// The You page's privacy checkup (`orbit/contracts/you.md`), in the order it
/// is drawn. It reads four features, so it lives here; Home reads it too, for
/// the dot on your avatar.
enum YouCheckKey { backup, devices, password, recovery, lock }

/// One check: whether it passes, and the line under its title.
@immutable
final class YouCheck {
  const YouCheck(this.key, {required this.ok, required this.text});

  final YouCheckKey key;
  final bool ok;

  /// Passing: "Backed up 5 hours ago". Failing: what is wrong ("No backup in
  /// the last 7 days").
  final String text;

  @override
  bool operator ==(Object other) =>
      other is YouCheck &&
      other.key == key &&
      other.ok == ok &&
      other.text == text;

  @override
  int get hashCode => Object.hash(key, ok, text);
}

/// The rules Review 1 set: backup when none in 7 days, devices when one has
/// not been used for 30 days, password when none is set, recovery when none
/// was made, app lock when it is off. A check whose facts have not come
/// passes, so nothing is flagged on a guess.
final youChecksProvider = Provider.autoDispose<List<YouCheck>>((ref) {
  final now = ref.watch(clockProvider)();
  final backup = ref.watch(backupSummaryProvider).value;
  final devices = ref.watch(deviceHealthProvider).value;
  final account = ref.watch(accountOverviewProvider);
  final lock = ref.watch(appLockViewProvider).value;

  final lastBackup = backup?.lastBackupAt;
  final recovery = backup?.lastRecoveryBackupAt;
  return [
    if (backup == null)
      const YouCheck(YouCheckKey.backup, ok: true, text: 'Checking…')
    else if (lastBackup == null)
      const YouCheck(YouCheckKey.backup, ok: false, text: 'No chat backup yet')
    else if (now.difference(lastBackup) > const Duration(days: 7))
      const YouCheck(
        YouCheckKey.backup,
        ok: false,
        text: 'No backup in the last 7 days',
      )
    else
      YouCheck(
        YouCheckKey.backup,
        ok: true,
        text: 'Backed up ${formatAgo(lastBackup, now).toLowerCase()}',
      ),
    if (devices == null)
      const YouCheck(YouCheckKey.devices, ok: true, text: 'Checking…')
    else if (devices.unused > 0)
      YouCheck(
        YouCheckKey.devices,
        ok: false,
        text: devices.unused == 1
            ? 'A device has not been used for 30 days'
            : '${devices.unused} devices have not been used for 30 days',
      )
    else
      YouCheck(
        YouCheckKey.devices,
        ok: true,
        text: switch (devices.count) {
          <= 1 => 'Only this device',
          2 => '2 devices, both used this month',
          final n => '$n devices, all used this month',
        },
      ),
    switch (account) {
      AsyncData(:final value) when value.hasPassword => const YouCheck(
        YouCheckKey.password,
        ok: true,
        text: 'Set. You can sign in on a new phone',
      ),
      AsyncData() => const YouCheck(
        YouCheckKey.password,
        ok: false,
        text: 'No password set',
      ),
      AsyncError() => const YouCheck(
        YouCheckKey.password,
        ok: true,
        text: 'Could not be checked. You may be offline',
      ),
      _ => const YouCheck(YouCheckKey.password, ok: true, text: 'Checking…'),
    },
    if (backup == null)
      const YouCheck(YouCheckKey.recovery, ok: true, text: 'Checking…')
    else if (recovery == null)
      const YouCheck(
        YouCheckKey.recovery,
        ok: false,
        text: 'No recovery backup yet',
      )
    else
      YouCheck(
        YouCheckKey.recovery,
        ok: true,
        text: 'Made ${formatAgo(recovery, now).toLowerCase()}',
      ),
    if (lock == null)
      const YouCheck(YouCheckKey.lock, ok: true, text: 'Checking…')
    else if (lock.enabled)
      YouCheck(
        YouCheckKey.lock,
        ok: true,
        text: 'On. Locks ${relockLabel(lock.relockAfterSeconds).toLowerCase()}',
      )
    else
      const YouCheck(YouCheckKey.lock, ok: false, text: 'App lock is off'),
  ];
});

/// Something in the checkup needs a moment: the amber dot on your avatar.
final youNeedsAttentionProvider = Provider.autoDispose<bool>(
  (ref) => ref.watch(youChecksProvider).any((c) => !c.ok),
);
