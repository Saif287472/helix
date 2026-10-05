import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/engine/helix_runtime.dart';
import 'package:helix_remote/core/engine/runtime_providers.dart';
import 'package:helix_remote/features/devices/application/devices_models.dart';
import 'package:helix_remote_api/v2.dart'
    show ApiException, NetworkException, SignedOutException;
import 'package:helix_remote_crypto/v2.dart'
    show CryptoV2Exception, LinkCode, Provisioning, Sha256Accumulator;
import 'package:helix_remote_engine/helix_remote_engine.dart'
    as engine
    show
        BackupException,
        BackupFailure,
        LinkProposal,
        NewDeviceLink,
        SignInException,
        SignInFailure;
import 'package:helix_remote_protocol/helix_remote_protocol.dart'
    show ErrorCode, SecurityEventKind;

/// The account's devices and the linking handshake, as plain values.
///
/// An interface so the pages and notifiers are tested with a fake; only
/// [EngineDevicesGateway] touches the engine. Methods that fail throw
/// whatever the engine and API throw, except the link methods, which throw
/// [LinkProblemException]; the notifiers turn both into sentences.
abstract interface class DevicesGateway {
  /// The device list, this device first, live.
  Stream<List<DeviceItem>> watch();

  /// Reads the list from the server.
  Future<void> refresh();

  Future<void> rename(String deviceId, String name);

  /// Revokes another device. [lost] records that it was lost or stolen.
  Future<void> revoke(String deviceId, {bool lost = false});

  /// Revokes every device but this one; returns how many.
  Future<int> revokeOthers();

  Future<List<SecurityEventItem>> securityEvents();

  /// Checks a scanned or pasted link code and describes it. Throws
  /// [LinkProblemException] (`notACode`, `otherServer`).
  Future<LinkRequest> inspectLink(String code);

  /// Approves the link: seals the account's keys to the new device.
  Future<void> approveLink(String code);

  /// The ids of this account's devices, read from the server: taken before an
  /// approval, so [sendHistoryToNewDevice] can tell which one is new.
  Future<Set<String>> deviceIds();

  /// Sends this device's history to the device(s) that are on the account now
  /// and were not in [knownBefore] (history transfers are never automatic).
  /// Returns the transfer id. Throws [LinkProblemException] (`notLinkedYet`
  /// when the new device has not finished joining, `offline`, `notAllowed`).
  Future<String> sendHistoryToNewDevice(Set<String> knownBefore);

  /// Starts linking **this** (new) device.
  Future<LinkSession> beginLink({String? deviceName});
}

final devicesGatewayProvider = Provider<DevicesGateway>(
  EngineDevicesGateway.new,
);

/// `482 913`: a short number derived from the link code, shown on both
/// devices. It does not secure anything by itself (the code is a bearer
/// secret) - it gives the person something to compare so they notice a code
/// that did not come from the device in front of them.
String linkCheckNumber(LinkCode code) {
  final hash = Sha256Accumulator()
    ..add(code.linkId.codeUnits)
    ..add(code.ephemeralKey);
  final bytes = hash.close();
  final value =
      ((bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3]) %
      1000000;
  final digits = value.toString().padLeft(6, '0');
  return '${digits.substring(0, 3)} ${digits.substring(3)}';
}

final class EngineDevicesGateway implements DevicesGateway {
  EngineDevicesGateway(this._ref);

  final Ref _ref;

  Future<HelixRuntime> get _runtime => _ref.read(runtimeProvider.future);

  @override
  Stream<List<DeviceItem>> watch() async* {
    final eng = (await _runtime).engine;
    yield* eng.devices.watch().map(
      (rows) => [
        for (final r in rows)
          DeviceItem(
            id: r.deviceId,
            name: r.name ?? '',
            platform: r.platform ?? '',
            isThisDevice: r.isThisDevice,
            lastActiveAt: r.lastActiveAt,
            linkedAt: r.linkedAt,
          ),
      ],
    );
  }

  @override
  Future<void> refresh() async {
    await (await _runtime).engine.devices.refresh();
  }

  @override
  Future<void> rename(String deviceId, String name) async {
    await (await _runtime).engine.devices.rename(deviceId, name);
  }

  @override
  Future<void> revoke(String deviceId, {bool lost = false}) async {
    await (await _runtime).engine.devices.revoke(deviceId, lost: lost);
  }

  @override
  Future<int> revokeOthers() async =>
      (await _runtime).engine.devices.revokeOthers();

  @override
  Future<List<SecurityEventItem>> securityEvents() async {
    final events = await (await _runtime).engine.devices.securityEvents();
    return [
      for (final e in events)
        SecurityEventItem(
          type: switch (e.kind) {
            SecurityEventKind.signedIn => SecurityEventType.signedIn,
            SecurityEventKind.deviceAdded => SecurityEventType.deviceAdded,
            SecurityEventKind.deviceRevoked => SecurityEventType.deviceRevoked,
            SecurityEventKind.passwordChanged =>
              SecurityEventType.passwordChanged,
            SecurityEventKind.recoveryUsed => SecurityEventType.recoveryUsed,
            SecurityEventKind.identityChanged =>
              SecurityEventType.identityChanged,
            SecurityEventKind.unknown => SecurityEventType.other,
          },
          at: e.at,
          deviceName: e.deviceName,
        ),
    ];
  }

  @override
  Future<LinkRequest> inspectLink(String code) async {
    final LinkCode link;
    try {
      link = LinkCode.parse(code.trim());
    } on CryptoV2Exception {
      throw const LinkProblemException(LinkProblem.notACode);
    }
    final runtime = await _runtime;
    if (link.serverOrigin != runtime.serverUrl.origin) {
      throw const LinkProblemException(LinkProblem.otherServer);
    }
    return LinkRequest(
      serverHost: Uri.parse(link.serverOrigin).host,
      check: linkCheckNumber(link),
      accountKeyCode: await _ownKeyCode(runtime),
    );
  }

  /// This account's key code, from the public half of the account key that
  /// this device holds (the new device shows the same code, computed from what
  /// the approval carries). Only the public key is read.
  Future<String?> _ownKeyCode(HelixRuntime runtime) async {
    try {
      final identity = await runtime.db.cryptoDao.identityKeys();
      return identity == null ? null : Provisioning.keyCode(identity.aikPublic);
    } on Object {
      return null;
    }
  }

  @override
  Future<void> approveLink(String code) async {
    try {
      await (await _runtime).engine.devices.approveLink(code.trim());
    } on engine.SignInException catch (e) {
      throw LinkProblemException(
        e.reason == engine.SignInFailure.linkExpired
            ? LinkProblem.expired
            : LinkProblem.notACode,
      );
    } on ApiException catch (e) {
      throw LinkProblemException(switch (e.code) {
        ErrorCode.expired || ErrorCode.notFound => LinkProblem.expired,
        _ when e.isRetryable => LinkProblem.offline,
        _ => LinkProblem.notAllowed,
      });
    } on NetworkException {
      throw const LinkProblemException(LinkProblem.offline);
    } on SignedOutException {
      throw const LinkProblemException(LinkProblem.notAllowed);
    }
  }

  @override
  Future<Set<String>> deviceIds() async {
    try {
      final devices = (await _runtime).engine.devices;
      await devices.refresh();
      return {for (final d in await devices.list()) d.deviceId};
    } on NetworkException {
      throw const LinkProblemException(LinkProblem.offline);
    } on ApiException catch (e) {
      throw LinkProblemException(
        e.isRetryable ? LinkProblem.offline : LinkProblem.notAllowed,
      );
    }
  }

  @override
  Future<String> sendHistoryToNewDevice(Set<String> knownBefore) async {
    try {
      final eng = (await _runtime).engine;
      await eng.devices.refresh();
      final fresh = [
        for (final d in await eng.devices.list())
          if (!d.isThisDevice && !knownBefore.contains(d.deviceId)) d.deviceId,
      ];
      if (fresh.isEmpty) {
        throw const LinkProblemException(LinkProblem.notLinkedYet);
      }
      return await eng.backup.sendHistory(devices: fresh);
    } on engine.BackupException catch (e) {
      throw LinkProblemException(switch (e.failure) {
        engine.BackupFailure.noOtherDevices => LinkProblem.notLinkedYet,
        engine.BackupFailure.offline => LinkProblem.offline,
        _ => LinkProblem.notAllowed,
      });
    } on NetworkException {
      throw const LinkProblemException(LinkProblem.offline);
    } on ApiException catch (e) {
      throw LinkProblemException(
        e.isRetryable ? LinkProblem.offline : LinkProblem.notAllowed,
      );
    }
  }

  @override
  Future<LinkSession> beginLink({String? deviceName}) async {
    try {
      final link = await (await _runtime).engine.account.beginLink(
        deviceName: deviceName,
      );
      return _EngineLinkSession(link);
    } on NetworkException {
      throw const LinkProblemException(LinkProblem.offline);
    } on ApiException catch (e) {
      throw LinkProblemException(
        e.isRetryable ? LinkProblem.offline : LinkProblem.notAllowed,
      );
    }
  }
}

final class _EngineLinkSession implements LinkSession {
  _EngineLinkSession(this._link);

  final engine.NewDeviceLink _link;

  @override
  String get code => _link.code;

  @override
  String get check => linkCheckNumber(LinkCode.parse(_link.code));

  @override
  DateTime get expiresAt => _link.expiresAt;

  @override
  Future<void> complete({required LinkConfirm confirm}) async {
    try {
      await _link.complete(
        confirm: (engine.LinkProposal proposal) => confirm(
          LinkProposalView(
            phoneMask: proposal.phoneMask,
            helixName: proposal.helixName,
            keyCode: proposal.fingerprint,
          ),
        ),
      );
    } on engine.SignInException catch (e) {
      throw LinkProblemException(switch (e.reason) {
        engine.SignInFailure.linkExpired => LinkProblem.expired,
        engine.SignInFailure.linkDeclined => LinkProblem.declined,
        engine.SignInFailure.untrustedAccountKey => LinkProblem.untrusted,
        _ => LinkProblem.notAllowed,
      });
    } on NetworkException {
      throw const LinkProblemException(LinkProblem.offline);
    } on ApiException catch (e) {
      throw LinkProblemException(
        e.isRetryable ? LinkProblem.offline : LinkProblem.notAllowed,
      );
    }
  }

  @override
  void cancel() => _link.cancel();
}
