import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:http/http.dart' as http;

final Ed25519 _ed = Ed25519();
final X25519 _x = X25519();

Future<Uint8List> _publicOf(KeyPair pair) async => Uint8List.fromList(
  (await pair.extractPublicKey() as SimplePublicKey).bytes,
);

Future<Uint8List> sign(SimpleKeyPair pair, List<int> message) async =>
    Uint8List.fromList((await _ed.sign(message, keyPair: pair)).bytes);

/// An account identity key (AIK), as a client would hold it.
final class TestAccount {
  TestAccount._(this.id, this.aik, this.publicKey);

  final String id;
  final SimpleKeyPair aik;
  final Uint8List publicKey;

  static Future<TestAccount> create({String? id}) async {
    final aik = await _ed.newKeyPair();
    return TestAccount._(id ?? Uuid.v7(), aik, await _publicOf(aik));
  }

  /// The same account id with a fresh AIK (recovery, replacement).
  Future<TestAccount> rotated() async {
    final aik = await _ed.newKeyPair();
    return TestAccount._(id, aik, await _publicOf(aik));
  }

  Future<TestDevice> newDevice({
    String name = 'Test phone',
    String? accountId,
  }) => TestDevice.create(this, name: name, accountId: accountId ?? id);
}

/// A device's keys: DIK (X25519), DSK (Ed25519), and its prekeys.
final class TestDevice {
  TestDevice._(
    this.account,
    this.accountId,
    this.id,
    this.name,
    this.dsk,
    this.dskPublic,
    this.dikPublic,
  );

  final TestAccount account;
  final String accountId;
  final String id;
  final String name;
  final SimpleKeyPair dsk;
  final Uint8List dskPublic;
  final Uint8List dikPublic;
  Session? session;
  int _nextPrekeyId = 1;

  static Future<TestDevice> create(
    TestAccount account, {
    required String name,
    required String accountId,
  }) async {
    final dsk = await _ed.newKeyPair();
    final dik = await _x.newKeyPair();
    return TestDevice._(
      account,
      accountId,
      Uuid.v7(),
      name,
      dsk,
      await _publicOf(dsk),
      await _publicOf(dik),
    );
  }

  Future<DeviceRegistration> registration({
    DateTime? at,
    bool badCertificate = false,
  }) async {
    final created = at ?? DateTime.now().toUtc();
    final body = deviceCertificateBody(
      accountId: accountId,
      deviceId: id,
      identityKey: dikPublic,
      signingKey: dskPublic,
      createdAt: created,
    );
    final certSig = await sign(
      account.aik,
      badCertificate ? [...body, 0] : body,
    );
    return DeviceRegistration(
      deviceId: id,
      name: name,
      platform: DevicePlatform.cli,
      identityKey: dikPublic,
      signingKey: dskPublic,
      certificate: DeviceCertificate(createdAt: created, signature: certSig),
      proof: await sign(dsk, body),
    );
  }

  Future<SignedPrekey> signedPrekey({
    int? id,
    bool badSignature = false,
  }) async {
    final key = await _publicOf(await _x.newKeyPair());
    final keyId = id ?? _nextPrekeyId++;
    final body = signedPrekeySignatureBody(keyId, key);
    return SignedPrekey(
      id: keyId,
      publicKey: key,
      signature: await sign(dsk, badSignature ? [...body, 1] : body),
    );
  }

  Future<List<OneTimePrekey>> oneTimePrekeys(int count) async => [
    for (var i = 0; i < count; i++)
      OneTimePrekey(
        id: _nextPrekeyId++,
        publicKey: await _publicOf(await _x.newKeyPair()),
      ),
  ];

  Future<PrekeyUpload> prekeys({int oneTime = 25}) async => PrekeyUpload(
    signedPrekey: await signedPrekey(),
    oneTimePrekeys: await oneTimePrekeys(oneTime),
  );

  String get bearer => session!.accessToken;
}

/// Response with decoded JSON (if any).
final class TestResponse {
  TestResponse(this.status, this.body, this.headers);

  final int status;
  final String body;
  final Map<String, String> headers;

  JsonReader get json => JsonReader.decode(body);

  String? get errorCode {
    if (body.isEmpty) return null;
    try {
      return ApiError.fromJson(json).code.wire;
    } on Object {
      return null;
    }
  }

  @override
  String toString() => 'TestResponse($status, $body)';
}

/// A tiny HTTP client for the route catalog.
final class TestApi {
  TestApi(this.base);

  final Uri base;
  final http.Client _client = http.Client();

  Future<TestResponse> call(
    ApiRoute route, {
    Map<String, String> params = const {},
    Map<String, Object?>? body,
    String? bearer,
    Map<String, String> query = const {},
    Map<String, String> headers = const {},
  }) async {
    final uri = base.replace(
      path: route.expand(params),
      queryParameters: query.isEmpty ? null : query,
    );
    final request = http.Request(route.method.name.toUpperCase(), uri)
      ..headers.addAll({
        if (body != null) 'content-type': 'application/json',
        if (bearer != null) 'authorization': 'Bearer $bearer',
        ...headers,
      });
    if (body != null) request.body = jsonEncode(body);
    final response = await http.Response.fromStream(
      await _client.send(request),
    );
    return TestResponse(response.statusCode, response.body, response.headers);
  }

  void close() => _client.close();
}

/// Deterministic test bytes.
Uint8List bytes(int length, [int seed = 1]) =>
    Uint8List.fromList([for (var i = 0; i < length; i++) (seed + i * 7) % 256]);
