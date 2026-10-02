import 'package:helix_remote_api/src/v2/transport/transport.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// The `keys` module: this device's prekeys and other accounts' bundles.
final class KeysClient {
  const KeysClient(this._t);

  final HelixTransport _t;

  /// Replaces the signed prekey (signature checked against the DSK).
  Future<void> setSignedPrekey(SignedPrekey prekey) =>
      _t.empty(Routes.setSignedPrekey, json: prekey.toJson());

  /// Uploads up to [AddOneTimePrekeysRequest.maxBatch] one-time prekeys.
  Future<KeyStatus> addOneTimePrekeys(List<OneTimePrekey> keys) {
    if (keys.length > AddOneTimePrekeysRequest.maxBatch) {
      throw ArgumentError.value(
        keys.length,
        'keys',
        'at most ${AddOneTimePrekeysRequest.maxBatch} per call',
      );
    }
    return _t.call(
      Routes.addOneTimePrekeys,
      KeyStatus.fromJson,
      json: AddOneTimePrekeysRequest(keys: keys).toJson(),
    );
  }

  Future<KeyStatus> status() => _t.call(Routes.keyStatus, KeyStatus.fromJson);

  /// Key bundles for [account] (`uuid` or `uuid@domain`): every active
  /// device, or only [devices]. Consumes one one-time prekey per device.
  Future<AccountKeys> accountKeys(
    String account, {
    Iterable<String> devices = const [],
  }) => _t.call(
    Routes.accountKeys,
    AccountKeys.fromJson,
    params: {'account': account},
    query: {if (devices.isNotEmpty) 'device': devices.toList()},
  );
}
