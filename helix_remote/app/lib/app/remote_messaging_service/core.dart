part of '../remote_messaging_service.dart';

mixin RemoteMessagingCore on RemoteMessagingServiceBase {
  bool get readReceiptsEnabled => _readReceiptsEnabled;
  RemotePrivacySettings get privacySettings => _privacySettings;
  RemoteCapabilityRegistry get capabilities =>
      RemoteCapabilityRegistry.current();
  Stream<RemoteSyncChange> get changes => _changeController.stream;

  Future<void> setupAccount({
    required RemoteAccount account,
    required RemoteDevice device,
  }) async {
    db.upsertAccount(account);
    db.upsertDevice(account.accountId, device);
    _accountId = account.accountId;
    _username = account.username;
    _displayName = account.username;
    _deviceId = device.deviceId;
    _emitChange(const RemoteSyncChange(areas: {RemoteSyncChangeArea.devices}));
  }

  void setCryptoKeys({
    required Uint8List devicePrivateKey,
    required Uint8List devicePublicKey,
  }) {
    _devicePrivateKey = devicePrivateKey;
    _devicePublicKey = devicePublicKey;
  }

  void setReadReceiptsEnabled(bool enabled) {
    _readReceiptsEnabled = enabled;
  }

  void verifyDevice({required String accountId, required String deviceId}) {
    final device = db
        .getDevices(accountId)
        .where((candidate) => candidate.deviceId == deviceId);
    if (device.isEmpty) {
      throw StateError('Remote device verification failed: unknown device');
    }

    final current = device.first;
    db.upsertDevice(
      accountId,
      RemoteDevice(
        deviceId: current.deviceId,
        deviceName: current.deviceName,
        deviceSigningPublicKey: current.deviceSigningPublicKey,
        deviceAgreementPublicKey: current.deviceAgreementPublicKey,
        createdAt: current.createdAt,
        status: 'Verified',
      ),
    );
    _emitChange(const RemoteSyncChange(areas: {RemoteSyncChangeArea.devices}));
  }

  String? get currentAccountId => _accountId;
  String? get currentUsername => _username;
  String? get currentDisplayName =>
      _displayName?.isNotEmpty == true ? _displayName : _username;
  void setDisplayName(String name) => _displayName = name;

  @override
  void _emitChange(RemoteSyncChange change) {
    if (!_changeController.isClosed) {
      _changeController.add(change);
    }
  }

  Future<void> dispose() async {
    await _syncChangeSub.cancel();
    await _changeController.close();
  }

  @override
  String _requireAccountId() {
    final accountId = _accountId;
    if (accountId == null) {
      throw StateError('Remote messaging account is not set up');
    }
    return accountId;
  }

  @override
  String _requireDeviceId() {
    final deviceId = _deviceId;
    if (deviceId == null) {
      throw StateError('Remote messaging device is not set up');
    }
    return deviceId;
  }
}
