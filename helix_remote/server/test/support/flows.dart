import 'package:helix_remote_protocol/helix_remote_protocol.dart';

import 'harness.dart';
import 'test_client.dart';

const aliceNumber = '+8801711000001';
const bobNumber = '+8801711000002';

/// Adds a second device to [first]'s account through password sign-in.
Future<TestDevice> secondDevice(
  Harness h,
  TestDevice first,
  String number,
) async {
  final pw = PasswordSetup(
    kdf: const KdfParams(),
    salt: bytes(16),
    authKey: bytes(32, 9),
    wrappedIdentityKey: WrappedKey(nonce: bytes(12), ciphertext: bytes(48)),
  );
  await h.api.call(
    Routes.setPassword,
    bearer: first.bearer,
    body: SetPasswordRequest(password: pw).toJson(),
  );
  final step1 = PasswordSignInResponse.fromJson(
    (await h.api.call(
      Routes.passwordSignIn,
      body: PasswordSignInRequest(
        phoneNumber: number,
        authKey: pw.authKey,
      ).toJson(),
    )).json,
  );
  final device = await first.account.newDevice(name: 'Second');
  device.session = Session.fromJson(
    (await h.api.call(
      Routes.addDevice,
      body: AddDeviceRequest(
        device: await device.registration(),
        prekeys: await device.prekeys(),
        signInToken: step1.signInToken,
      ).toJson(),
    )).json,
  );
  return device;
}

Future<TestResponse> send(
  Harness h,
  TestDevice from,
  Map<String, List<String>> to, {
  String? id,
  bool ephemeral = false,
  bool urgent = true,
  int size = 64,
}) => h.api.call(
  Routes.sendMessage,
  bearer: from.bearer,
  body: SendMessageRequest(
    id: id ?? Uuid.v7(),
    recipients: [
      for (final e in to.entries)
        Recipient(
          account: e.key,
          devices: [
            for (final d in e.value)
              DevicePayload(device: d, payload: bytes(size, d.hashCode)),
          ],
        ),
    ],
    ephemeral: ephemeral,
    urgent: urgent,
  ).toJson(),
);

Future<MailboxPage> mailbox(Harness h, TestDevice d, {int after = 0}) async =>
    MailboxPage.fromJson(
      (await h.api.call(
        Routes.mailbox,
        bearer: d.bearer,
        query: {'after': '$after'},
      )).json,
    );

/// Retries [check] until it passes or [timeout] runs out (for effects that
/// land asynchronously, such as socket acks).
Future<void> eventually(
  Future<void> Function() check, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (true) {
    try {
      await check();
      return;
    } on Object {
      if (DateTime.now().isAfter(deadline)) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
}
