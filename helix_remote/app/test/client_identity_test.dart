import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/core/engine/helix_runtime.dart';
import 'package:helix_remote/core/platform/app_info.dart';
import 'package:helix_remote/core/platform/app_storage.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart'
    show EmptyPhoneBook, EngineConfig;
import 'package:helix_remote_protocol/helix_remote_protocol.dart'
    show DevicePlatform, HelixHeaders;

/// What the app calls itself to the server. `x-helix-client` is documented as
/// `<platform>/<app version>` for compatibility gating and support; the device
/// name belongs in the account's device list, not in every request.
void main() {
  late Directory tmp;
  late File dbFile;
  late SecureKeyStore keys;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('helix_client_identity');
    dbFile = File('${tmp.path}/helix.db');
    FlutterSecureStorage.setMockInitialValues({});
    keys = SecureKeyStore();
  });

  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } on FileSystemException {
      // A file still held by the test run is not worth failing for.
    }
  });

  test('the client name is the platform and the app version', () {
    expect(appClientName(DevicePlatform.android), 'android/$kAppVersion');
    expect(appClientName(DevicePlatform.windows), 'windows/$kAppVersion');
  });

  test(
    'a runtime sends it on every request and names the socket with it',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      final requests = <HttpRequest>[];
      server.listen((request) {
        requests.add(request);
        request.response
          ..headers.contentType = ContentType.json
          ..write('{"valid":false}');
        request.response.close();
      });

      final account = AppPaths.firstAccount;
      final runtime = await HelixRuntime.open(
        account: account,
        dbFile: dbFile,
        key: await keys.keyFor(account, dbFile),
        serverUrl: Uri.parse('http://127.0.0.1:${server.port}'),
        phoneBook: const EmptyPhoneBook(),
        config: const EngineConfig(
          deviceName: 'Pixel 9',
          platform: DevicePlatform.android,
        ),
        headless: true,
        keys: keys,
      );
      addTearDown(runtime.close);

      await runtime.api.identity.inviteLookup('HLX-AAAAAAAAAAAAAAAA');
      expect(requests, hasLength(1));
      expect(
        requests.single.headers.value(HelixHeaders.client),
        'android/$kAppVersion',
      );
      expect(
        requests.single.headers.value(HelixHeaders.client),
        isNot(contains('Pixel')),
        reason: 'the model names the device in the device list, not the client',
      );
      expect(runtime.api.realtime.clientName, 'android/$kAppVersion');
    },
  );
}
