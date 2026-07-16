abstract final class _RemoteStringValue {
  const _RemoteStringValue(this.value);

  final String value;

  @override
  String toString() => value;

  @override
  bool operator ==(Object other) =>
      other.runtimeType == runtimeType &&
      other is _RemoteStringValue &&
      other.value == value;

  @override
  int get hashCode => Object.hash(runtimeType, value);
}

final class AccountId extends _RemoteStringValue {
  const AccountId(super.value);
}

final class DeviceId extends _RemoteStringValue {
  const DeviceId(super.value);
}

final class RemoteSigningPublicKey extends _RemoteStringValue {
  const RemoteSigningPublicKey(super.value);
}

final class RemoteAgreementPublicKey extends _RemoteStringValue {
  const RemoteAgreementPublicKey(super.value);
}
