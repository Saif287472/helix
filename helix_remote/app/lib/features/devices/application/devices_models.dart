import 'package:flutter/foundation.dart' show immutable;

/// One of this account's devices.
@immutable
final class DeviceItem {
  const DeviceItem({
    required this.id,
    required this.name,
    required this.platform,
    required this.isThisDevice,
    this.lastActiveAt,
    this.linkedAt,
  });

  final String id;

  /// What the device calls itself; empty when it never said.
  final String name;

  /// `android`, `windows`, ... as the server records it.
  final String platform;
  final bool isThisDevice;
  final DateTime? lastActiveAt;
  final DateTime? linkedAt;

  @override
  bool operator ==(Object other) =>
      other is DeviceItem &&
      other.id == id &&
      other.name == name &&
      other.platform == platform &&
      other.isThisDevice == isThisDevice &&
      other.lastActiveAt == lastActiveAt &&
      other.linkedAt == linkedAt;

  @override
  int get hashCode =>
      Object.hash(id, name, platform, isThisDevice, lastActiveAt, linkedAt);
}

/// What kind of entry the account's security log holds.
enum SecurityEventType {
  signedIn,
  deviceAdded,
  deviceRevoked,
  passwordChanged,
  recoveryUsed,
  identityChanged,
  other,
}

@immutable
final class SecurityEventItem {
  const SecurityEventItem({
    required this.type,
    required this.at,
    this.deviceName,
  });

  final SecurityEventType type;
  final DateTime at;
  final String? deviceName;
}

/// Why a link could not be approved or completed.
enum LinkProblem {
  /// The text is not a Helix link code.
  notACode,

  /// The code was made for a different server than this device is on.
  otherServer,

  /// The code ran out (they last ten minutes) or was cancelled.
  expired,

  /// The person on the new device said the account was not theirs (or let the
  /// question time out). Nothing was kept.
  declined,

  /// The new device is not on the account yet, so there is nobody to send
  /// the history to.
  notLinkedYet,

  /// The approval did not check out (not signed by a device of the account it
  /// names). Nothing was kept.
  untrusted,

  /// The person did not pass the phone's own lock check.
  notConfirmed,
  offline,
  notAllowed,
  unknown,
}

final class LinkProblemException implements Exception {
  const LinkProblemException(this.problem);

  final LinkProblem problem;

  @override
  String toString() => 'LinkProblemException(${problem.name})';
}

/// What an approver is shown before it approves: enough to notice a code that
/// was not made by a device in front of them.
@immutable
final class LinkRequest {
  const LinkRequest({
    required this.serverHost,
    required this.check,
    this.accountKeyCode,
  });

  final String serverHost;

  /// A short number both devices show, to compare: `482 913`.
  final String check;

  /// This account's key code (`a1b2 c3d4 e5f6 a7b8 c9d0`): the new device
  /// shows the same code before it keeps anything, so the person can see it
  /// is joining *their* account. Null when this device cannot read it.
  final String? accountKeyCode;
}

/// What an approval offers the **new** device, shown before anything is kept:
/// the account as the approving device states it, and the key code to compare
/// with that device.
@immutable
final class LinkProposalView {
  const LinkProposalView({
    required this.keyCode,
    this.phoneMask,
    this.helixName,
  });

  /// The account's phone number, masked (`+88017*****01`); null when the
  /// account has none.
  final String? phoneMask;

  /// `anna.k` (without the `~`); null when the account has none.
  final String? helixName;

  /// `a1b2 c3d4 e5f6 a7b8 c9d0`: the account key's short form.
  final String keyCode;
}

/// What a link can ask the person on the new device: keep these keys or not.
typedef LinkConfirm = Future<bool> Function(LinkProposalView proposal);

/// A link in progress on the **new** device: the code to show and a way to
/// wait for the approval.
abstract interface class LinkSession {
  /// The text of the QR code.
  String get code;

  /// The same `482 913` the approving device will show.
  String get check;

  /// The code stops working at this time.
  DateTime get expiresAt;

  /// Waits for an approval, asks [confirm] (the approval is checked first, and
  /// nothing is kept yet) and, only on a yes, signs this device in. A no or an
  /// error leaves the device empty. Throws [LinkProblemException] (`expired`,
  /// `declined`, ...).
  Future<void> complete({required LinkConfirm confirm});

  void cancel();
}
