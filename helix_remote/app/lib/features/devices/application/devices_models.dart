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
  const LinkRequest({required this.serverHost, required this.check});

  final String serverHost;

  /// A short number both devices show, to compare: `482 913`.
  final String check;
}

/// A link in progress on the **new** device: the code to show and a way to
/// wait for the approval.
abstract interface class LinkSession {
  /// The text of the QR code.
  String get code;

  /// The same `482 913` the approving device will show.
  String get check;

  /// The code stops working at this time.
  DateTime get expiresAt;

  /// Waits for an approval and signs this device in. Throws
  /// [LinkProblemException] (`expired`, ...).
  Future<void> complete();

  void cancel();
}
